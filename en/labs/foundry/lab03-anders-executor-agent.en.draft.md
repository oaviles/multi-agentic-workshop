# Lab 03: Anders – Executor Agent

Azure AI Foundry – configure, run, and test **Anders**, the executor agent of Contoso Retail’s multi-agent architecture.

## 🎯 Mission Brief

Anders is the **executor agent** of Contoso Retail’s multi-agent architecture. Its role is to receive operational action requests — such as generating and publishing order reports — and execute them by interacting with external services such as the Azure Function `FxContosoRetail`.

For Anders to interact with the Contoso Retail API, we will define an **OpenAPI Tool** that allows the agent to automatically discover and invoke the Function App endpoints based on its OpenAPI specification. The Function App `FxContosoRetail` **already includes** OpenAPI and decorated endpoints in the base code.

## 🔎 Goals

By completing this lab you will:

1. Verify OpenAPI support in the Azure Function `FxContosoRetail`.
2. Redeploy the Function App.
3. Verify the OpenAPI specification.
4. Understand, configure, run, and test the Anders agent.
5. Publish Anders so Copilot Studio can consume it.

## Prerequisites

### Tools on your machine

| Tool | Description | Download |
|---|---|---|
| **.NET 10 SDK** | Build and run the Function App and the Anders agent | [Download](https://dotnet.microsoft.com/download/dotnet/8.0) |
| **Azure CLI** | Authenticate to Azure, deploy resources, and assign RBAC roles | [Install](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| **Azure Functions Core Tools** | Publish the Function App to Azure (recommended option) | [Install](https://learn.microsoft.com/azure/azure-functions/functions-run-local#install-the-azure-functions-core-tools) |
| **PowerShell** | Run deployment scripts | Windows: included · macOS/Linux: [Install PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) |
| **Git** | Clone the workshop repository | [Download](https://git-scm.com/downloads) |

> [!TIP]
> On **macOS**, you can install the tools using Homebrew:
> ```bash
> brew install dotnet-sdk azure-cli azure-functions-core-tools@4 powershell git
> ```

### Azure infrastructure

- Have completed the **infrastructure setup** described in [Foundry Setup](codespaces-setup.md)
- Have noted **all values generated during the infrastructure deployment** (resource names, URLs, suffix, AI Foundry endpoint, etc.)
- Have identified these 2 Fabric Warehouse values (used in the updated setup):
    - `FabricWarehouseSqlEndpoint`
    - `FabricWarehouseDatabase`

### RBAC permissions

Your user needs the **Cognitive Services User** role on the AI Services resource to be able to create and run agents. Since your user is **Owner of the tenant**, you can assign the role to yourself.

Run the following commands (replace `{suffix}` with your 5-character suffix):

```powershell
# 1. Get your user name (UPN)
$upn = az account show --query "user.name" -o tsv

# 2. Get the AI Services resource name (if you don't remember it)
az cognitiveservices account list --resource-group rg-contoso-retail --query "[].name" -o tsv

# 3. Assign the Cognitive Services User role
az role assignment create `
    --assignee $upn `
    --role "Cognitive Services User" `
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-contoso-retail/providers/Microsoft.CognitiveServices/accounts/ais-contosoretail-{suffix}"
```

> [!NOTE]
> RBAC propagation may take up to 1 minute. Wait before continuing with the lab.

---

## 1. Verify the OpenAPI specification

Once deployed, verify that the OpenAPI endpoints are available.

### a. Get the JSON specification

Open in a browser or with `curl`:

```
https://func-contosoretail-<suffix>.azurewebsites.net/api/openapi/v3.json
```

You should see a JSON with the OpenAPI structure describing the `HelloWorld`, `OrdersReporter`, and `SqlExecutor` endpoints, including the request/response schemas.

### b. Explore the Swagger UI

Navigate to:

```
https://func-contosoretail-<suffix>.azurewebsites.net/api/swagger/ui
```

From the Swagger UI interface you can explore the endpoints and test them interactively.

> [!IMPORTANT]
> The OpenAPI specification documents the API and serves as a reference to understand which parameters to send and what response to expect. The Anders agent will use this information indirectly through the Function Tool that we will define in the next step.

---

## 2. Understand the Anders agent

The Anders agent implementation lives under `en/labs/foundry/code/agents/AndersAgent/ms-foundry/` and is built on these packages:

| Package | Role |
|---|---|
| `Azure.AI.Projects` | Foundry project client |
| `Azure.AI.Projects.Agents` | Agent administration: versions, definitions and tools |
| `Azure.AI.Extensions.OpenAI` | Conversations and the Responses API |

The programming model uses **named and versioned agents**, **conversations**, and the **Responses API**: a single call to `CreateResponse()` returns the agent output directly, with no polling loop.

Open the file `en/labs/foundry/code/agents/AndersAgent/ms-foundry/Program.cs` and note that it is organized into **3 phases**:

### a. Phase 1 — Download the OpenAPI specification

```csharp
var openApiSpecUrl = $"{functionAppBaseUrl}/openapi/v3.json";
var openApiSpec = await httpClient.GetStringAsync(openApiSpecUrl);
```

The program downloads the OpenAPI specification from the Function App **at runtime**. This means that if the API changes (new endpoints, new parameters), the agent automatically detects it when restarted.

### b. Phase 2 — Verify existing agent or create a new one

This phase has two key parts:

**Existing agent detection:**

Before creating a new version, the program checks whether the agent already exists by calling `GetAgent`. If it finds one, it asks the user whether they want to keep the existing agent or overwrite it with a new version. This avoids unnecessary proliferation of agent versions during iterative development.

**Agent definition with OpenAPI tool (protocol method):**

```csharp
var agentDefinitionJson = new
{
    definition = new
    {
        kind = "prompt",
        model = modelDeployment,
        instructions = andersInstructions,
        tools = new object[]
        {
            new
            {
                type = "openapi",
                openapi = new
                {
                    name = "ContosoRetailAPI",
                    description = "API de Contoso Retail...",
                    spec = openApiSpecJson,
                    auth = new { type = "anonymous" }
                }
            }
        }
    }
};
```

Since the `OpenApiAgentTool` types are internal in SDK 1.2.x, the tool definition is built as an anonymous object and serialized via `BinaryContent`. The `kind = "prompt"` field is required by the API to indicate a prompt-based agent.

**System prompt (instructions):**

The system prompt includes the exact JSON schema that Anders must build when invoking the API:

```json
{
  "customerName": "Customer Name",
  "startDate": "YYYY-MM-DD",
  "endDate": "YYYY-MM-DD",
  "orders": [
    {
      "orderNumber": "order code",
      "orderDate": "YYYY-MM-DD",
      "orderLineNumber": 1,
      "productName": "product name",
      "brandName": "brand name",
      "categoryName": "category name",
      "quantity": 1.0,
      "unitPrice": 0.00,
      "lineTotal": 0.00
    }
  ]
}
```

> [!TIP]
> Including the schema in the instructions is a good practice when the agent must construct complex payloads. Although the OpenAPI specification already describes the schema, reinforcing it in the system prompt significantly reduces formatting errors.

**Agent reuse:**

```csharp
try
{
    existingAgent = projectClient.Agents.GetAgent(agentName);
    // Ask the user whether they want to overwrite or keep it
}
catch (ClientResultException ex) when (ex.Status == 404)
{
    // Agent not found — create a new one
}
```

Before creating a new agent version, the program attempts to retrieve the existing agent by name. If it finds one, it asks the user to confirm whether they want to overwrite it. This avoids creating unnecessary versions in Foundry when restarting the application.

### c. Phase 3 — Interactive chat with the Responses API

```csharp
ProjectConversation conversation = projectClient.OpenAI.Conversations.CreateProjectConversation();
ProjectResponsesClient responseClient = projectClient.OpenAI.GetProjectResponsesClientForAgent(
    defaultAgent: agentName,
    defaultConversationId: conversation.Id);

ResponseResult response = responseClient.CreateResponse(input);
Console.WriteLine(response.GetOutputText());
```

The interaction pattern is straightforward:
1. A `ProjectConversation` is created (the conversation context)
2. A `ProjectResponsesClient` is obtained, bound to the agent and the conversation
3. Each user message is sent via `CreateResponse()`, which returns the output **synchronously** — without the need for a polling loop
4. The response text is extracted using `GetOutputText()`

> [!NOTE]
> **What happens during a response call?** When the model decides it needs to call the API, Foundry automatically executes the HTTP call using the OpenAPI specification. The result is sent back to the model, which formulates the final response to the user. All of this happens within the single `CreateResponse()` call — the code simply receives the completed response.

**Cleanup on exit:**

When the user types `exit`, the chat loop ends. The agent **persists** in Foundry and is automatically reused on the next execution.

---

## 5. Configure, run, and test Anders

### a. Configure `appsettings.json`

Open the file `en/labs/foundry/code/agents/AndersAgent/ms-foundry/appsettings.json` and replace the values with those from your environment:

```json
{
  "FoundryProjectEndpoint": "<YOUR-AI-FOUNDRY-PROJECT-ENDPOINT>",
  "ModelDeploymentName": "gpt-deployment",
  "FunctionAppBaseUrl": "https://func-contosoretail-<suffix>.azurewebsites.net/api"
}
```

> [!NOTE]
> **Where do I find these values?**
> - **FoundryProjectEndpoint**: The `AI Foundry Endpoint` from the deployment output.
> - **ModelDeploymentName**: `gpt-deployment` (name of the deployment created by the Bicep).
> - **FunctionAppBaseUrl**: The URL of your Function App + `/api`.

### b. Build and run

```powershell
cd /workspaces/multi-agentic-workshop/en/labs/foundry/code/agents/AndersAgent/ms-foundry
dotnet build
```

Make sure there are no build errors. Then run:

```powershell
dotnet run
```

You will see in the console that the agent checks whether a version already exists in Foundry. If it finds one, it will ask whether you want to keep it or overwrite it. If it does not exist, a new agent is created automatically.

### c. Inspect the agent in Azure AI Foundry

**Before interacting with Anders**, go to the portal to inspect what was created:

1. Open [Microsoft Foundry](https://ai.azure.com) and navigate to your project
2. Ensure to be in the New Foundry Experience (Top Bar Toggle)
3. In the side menu, select **Agents**
4. Find the **"Anders"** agent and click it

Observe two key things:

- **System prompt (instructions):** You will see the full instructions given to the agent, including the JSON schema. This is what guides its behavior when deciding when and how to invoke the API.
- **Tools:** You will see **ContosoRetailAPI** listed as an OpenAPI tool. You can expand it to see the full specification with the `ordersReporter` endpoint, the request/response schemas, and the anonymous authentication configuration.

> [!TIP]
> The system prompt and the tools are the two pillars that determine what an agent can do and how it does it. Understanding this relationship is key to designing effective agents.

### d. Test the agent

Back in the console, test it first with a greeting:

```
You: Hi Anders, what can you do?
```

Anders should respond explaining that it can generate order reports. 


Now, go to [Microsoft Foundry](https://ai.azure.com) and try Anders from Microsoft Foundry in the Agent playground. Then try with real data (paste everything on a single line):

```
You: Generate a report for Izabella Celma (period: January 1–31, 2026). Order ORD-CID-069-001 (2026-01-04): Sport-100 Helmet Black, Contoso Outdoor, Helmets, 6x$34.99=$209.94 | HL Road Frame Red 62, Contoso Outdoor, Road Frames, 10x$1431.50=$14315.00 | Long-Sleeve Logo Jersey S, Contoso Outdoor, Jerseys, 8x$49.99=$399.92. Order ORD-CID-069-003 (2026-01-08): HL Road Frame Black 58, Contoso Outdoor, Road Frames, 3x$1431.50=$4294.50 | HL Road Frame Red 44, Contoso Outdoor, Road Frames, 7x$1431.50=$10020.50. Order ORD-CID-069-002 (2026-01-17): HL Road Frame Red 62, Contoso Outdoor, Road Frames, 2x$1431.50=$2863.00 | LL Road Frame Black 60, Contoso Outdoor, Road Frames, 4x$337.22=$1348.88.
```

What happens internally:
1. Anders analyzes the message and decides it needs to call the `ordersReporter` endpoint
2. **Foundry executes the HTTP call** automatically to the Function App with the structured data according to the schema
3. The Function App generates the HTML report, uploads it to Blob Storage, and returns the URL
4. Foundry sends the result back to the model
5. Anders formulates its response and presents the URL to the user

Open the report URL in the browser to verify that it was generated correctly.

Now try a simpler case — a single order with two products:

```
You: Generate a report for Marco Rivera (period: February 5–10, 2026). Order ORD-CID-112-001 (2026-02-07): Mountain Bike Socks M, Contoso Outdoor, Socks, 3x$9.50=$28.50 | Water Bottle 30oz, Contoso Outdoor, Bottles and Cages, 1x$6.99=$6.99.
```

> [!NOTE]
> Typing `exit` only ends the conversation. The agent **persists** in Foundry and is automatically reused on the next execution.

---

## 6. Publish Anders so Copilot Studio can consume it

In Lab 8 you will connect Anders from **Copilot Studio** as an external agent. Copilot Studio invokes Foundry agents using the **Activity Protocol** (the Azure Bot Service protocol), but an agent that was just created in the project **only exposes the Responses API protocol** by default. If you try to connect it as-is, Copilot Studio returns an error such as:

> `connectorRequestFailure … HTTP 400. Agent Anders endpoint does not support activity. Please update the agent endpoint to support this protocol.`

To enable the Activity Protocol you must **publish** Anders to Microsoft 365 and Teams from the Foundry portal:

### a. Select **Publish → Teams and Microsoft 365 Copilot**

In the Microsoft Foundry portal, open the **Anders** agent and click **Publish → Teams and Microsoft 365 Copilot**.

### b. Fill in the required metadata

Fill in the required metadata (Name, version, description, developer).

### c. Choose the **Just you** scope and publish

Under **Publish options → Direct publish**, choose the **Just you** scope (no admin approval required) and click **Publish**.

When you publish, Foundry creates an **Azure Bot Service** resource and enables the `activity` protocol on the agent endpoint — exactly what Copilot Studio needs.

> [!IMPORTANT]
> **Required permissions.** Publishing creates an Azure Bot Service, so your user needs the **Azure Bot Service Contributor** role (or Contributor/Owner) on the resource group; Foundry roles do not grant this permission. Also register the provider once:
>
> ```bash
> az provider register --namespace Microsoft.BotService
> ```

> [!NOTE]
> The agent can expose **both** protocols at once (Responses **and** Activity): enabling Activity does not break the SDK/portal interaction used by the rest of the workshop.

### d. Optionally automate publishing (no portal)

Publishing from the portal is a UI shortcut over the Foundry REST API. To skip the manual steps, run the script with **PowerShell** to enable the `activity` protocol directly on the agent endpoint. The default Codespaces terminal is **bash**, so invoke it with `pwsh`:

```bash
cd /workspaces/multi-agentic-workshop/en/labs/foundry
pwsh ./setup/enable-activity-protocol.ps1 -Suffix <suffix>
```

> [!NOTE]
> The script uses the Foundry **preview** REST API (`api-version=v1`). It enables `activity` while keeping `responses` and the `Entra` scheme that Copilot Studio uses. If your tenant additionally requires the Azure Bot Service, use the portal publish described above (needs the **Azure Bot Service Contributor** role).

---

## Troubleshooting (Just in case Azure Storage issues generating report)

### Storage Account blocked by policy (error 503)

In subscriptions with strict Azure policies, the Storage Account backing the Function App may have its **public network access disabled** automatically after provisioning. This prevents the Functions host from reaching its own storage, causing a persistent **503 (Site Unavailable)** error — even though the app reports as `Running` and `Enabled`.

**Symptoms:**
- The Function App appears as `Running` in the Azure Portal and CLI
- All network access restrictions show "Allow all"
- Every HTTP request to any endpoint returns 503 after a ~60-second timeout

**Diagnosis:**
```powershell
az storage account show --name stcontosoretail<suffix> --resource-group rg-contoso-retail --query "publicNetworkAccess" -o tsv
```

If it returns `Disabled`, that is the root cause.

**Solution:**

A convenience script is included in the repository:

```powershell
cd /workspaces/multi-agentic-workshop/en/labs/foundry/setup
pwsh unlock-storage.ps1
```

The script automatically detects the suffix from the Function App. If you need to force it, it also accepts `-Suffix` or `-FunctionAppName`.

This script enables public network access on the Storage Account and restarts the Function App. See [unlock-storage.ps1](setup/unlock-storage.ps1) for details.

---

## Mission Complete

Anders receives operational action requests — such as generating and publishing order reports — and executes them by interacting with the Azure Function `FxContosoRetail`.

Continue with [Lab 8 — Anders — Enterprise Knowledge powered by Foundry IQ](lab04-anders-foundryiq.en.md).
