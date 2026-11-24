# Lab 04: Mark IQ – Fabric IQ Ontology

Microsoft Fabric – give Mark a governed business vocabulary with a **Fabric IQ ontology**: entity types, relationships, metrics, and rules, bound to live OneLake data and materialized as a graph.

## 🎯 Mission Brief

Mark v1 knows tables. Mark v2 knows measures. Neither knows **the business**: that a customer *places* sales orders, that a sales order *contains* order lines, that an order line *references* a product, that "F100241" is how people name an order, or that "open order" means *Pending*.

In this lab you capture that knowledge once, in a Fabric IQ **ontology** named `retail_ontology`, and then build **Mark IQ**, a data agent that combines:

- **`retail_ontology`**: authoritative source for business entities, relationships, identifiers, and rules, queried as a graph.
- **`sm_retail`**: authoritative source for governed DAX measures and every monetary value.

You finish by running the same benchmark used in Lab 03 against Mark v1, Mark v2, and Mark IQ. In Lab 05 the same ontology is consumed outside Fabric through MCP.

## 🔎 Goals

By completing this lab, you will:

1. Understand the Fabric IQ ontology building blocks.
2. Generate `retail_ontology` from `sm_retail`.
3. Model the entity types, keys, and properties with business names.
4. Bind the entity types directly to the `db_retail` SQL database.
5. Configure and verify relationship types in the graph.
6. Review the generated metrics and add business rules.
7. Explore the ontology with the built-in **ontology agent**.
8. Create **Mark IQ** with ontology and semantic-model sources and explicit source routing.
9. Validate with a self-checking test pack and compare all three Mark versions.

---

## 1. Fabric IQ ontology in five minutes

### a. Building blocks

| Concept | What it is | In this lab |
|---|---|---|
| **Entity type** | A business concept, not a table | `CustomerEntity`, `SalesOrderEntity`, `OrderLineEntity`, `ProductEntity` |
| **Property** | An attribute of an entity type | `OrderNumber`, `OrderStatus`, `ProductName` |
| **Entity type key** | Uniquely identifies an instance (string or integer) | `CustomerId`, `OrderId`, `OrderId` + `OrderLineNumber`, `ProductID` |
| **Data binding** | Connects an entity type to OneLake data | `db_retail` tables |
| **Relationship type** | A named, directed business link | `customerPlacedSalesOrder`, `salesOrderContainsLine`, `lineReferencesProduct` |
| **Metric** | A business calculation, generated from DAX measures | `Total Sales`, `Total Order Value`, … |
| **Rule** | Business logic written in natural language and linked to ontology elements | "An open order is a SalesOrderEntity whose OrderStatus is Pending." |
| **Graph** | The materialized instances and edges, queried with GQL | The child Graph item of `retail_ontology` |
| **Ontology agent** | Built-in agent in the ontology editor with **Plan** and **Act** modes | Used to review and query `retail_ontology` |

### b. Version architecture

| Version | Sources | Primary role |
|---|---|---|
| Mark v1 | `db_retail` SQL database | Raw-SQL baseline and transactional lookup |
| Mark v2 | `sm_retail` semantic model | Governed DAX measures and analytics |
| Mark IQ | `retail_ontology` + `sm_retail` | Business entities, relationships, and rules, plus governed measures |

### c. Important facts about the current release

> [!IMPORTANT]
> - **Ontology is in preview.** The data agent itself is generally available.
> - The **new ontology experience** is the default for new ontology items. The old experience retires on **January 31, 2027**. If your ontology shows a banner about the old experience, use the banner's option to create a copy in the new experience, then reconnect any agents to the copy and recreate rules manually.
> - A data agent **doesn't work with an ontology that uses semantic models for binding**. Generate Ontology 
creates semantic-model bindings, so in section 4 you rebind every entity type to the `db_retail` SQL database. `sm_retail` stays connected to Mark IQ as a separate source for measures.
> - Entity type keys must be **string or integer** columns. Parameterized `decimal(p,s)` columns can surface as strings in the graph, so don't use ontology properties for money. Monetary answers come from `sm_retail`.

---

## 2. Verify prerequisites

### a. Tenant settings

A Fabric administrator must enable (see Lab 01, section 0):

- **Users can create ontology (preview) items**
- **Users can create Fabric items**
- The Fabric data agent tenant settings (Copilot and Azure OpenAI Service)

References: [Ontology prerequisites](https://learn.microsoft.com/en-us/fabric/iq/ontology/tutorial-0-introduction) and [Fabric data agent tenant settings](https://learn.microsoft.com/en-us/fabric/data-science/data-agent-tenant-settings).

### b. Workspace and permissions

Confirm that:

- `sm_retail` and `db_retail` are in a Fabric workspace other than **My workspace**, on an F2 or higher capacity.
- You have **Read** and **Build** permissions on `sm_retail`.
- `sm_retail` has its four tables, three active relationships, and the Lab 01 measures with descriptions.
- Mark v1 and Mark v2 still exist unchanged.

---

## 3. Generate `retail_ontology` from `sm_retail`

If you already generated `retail_ontology` from `sm_retail` in the new experience, open it and continue to section 4.

1. In the workspace, open `sm_retail`.
2. In the ribbon (or the **...** menu), select **Generate Ontology**.
   > [!WARNING]
   >
   > In some cases "Generate Ontology" ribbon is not enable, in this case, you need to turn on this feature in the Fabric Administrator.
   >
   > Navigate to: OneLake catalog → Govern → Configurations → Tenant settings 
   >  
   > Find and enable these settings.
   >
   > Review step 2 "Verify prerequiments" above.
   > References: [Ontology prerequisites](https://learn.microsoft.com/en-us/fabric/iq/ontology/tutorial-0-introduction) and [Fabric data agent tenant settings](https://learn.microsoft.com/en-us/fabric/data-science/data-agent-tenant-settings).

3. Select the current workspace and enter the name `retail_ontology`.
4. Select **Create** and wait for the ontology to open.

Generate Ontology creates:

- An **entity type** for each table.
- **Properties** and **data bindings** for the columns.
- **Relationship types** that follow the model relationships.
- **Metrics** from the DAX measures.

You still need to review the entity keys (especially multi-column keys), confirm the relationship bindings, and rename entities to business names. That's the work of the next sections.

If **Generate Ontology** or the **Ontology (preview)** item isn't available, check the tenant settings in section 2.

---

## 4. Model and bind the entity types

### a. Rename the entity types

Generated entity types use the table names. Rename them to business names. The `Entity` suffix avoids GQL reserved words such as `ORDER` and `PRODUCT`, and makes it clear that prompts refer to ontology entities rather than physical tables.

| Generated name | Business name | Description to enter |
|---|---|---|
| `customer` | `CustomerEntity` | A retail customer that can place zero or more sales orders. |
| `orders` | `SalesOrderEntity` | A purchase transaction placed by one customer. Users refer to it by OrderNumber. |
| `orderline` | `OrderLineEntity` | A uniquely identified line within a sales order that records one product and its quantity. |
| `product` | `ProductEntity` | A sellable item from the retail product catalog. |

For each entity type:

1. Select it in the Explorer and select **Open details** (or **View entity type details**).
2. Select **... > Rename**, enter the business name, and save.
3. Enter the description.

If any entity type wasn't generated, select **Home > + Add > Entity type**, enter the business name, and select **Add**.

### b. Define keys and properties

| Entity type | Entity type key | Properties to keep |
|---|---|---|
| `CustomerEntity` | `CustomerId` | `CustomerId`, `FirstName`, `LastName`, `CustomerTypeId`, `CustomerRelationshipTypeId`, `IsActive`, `PrimaryEmail` |
| `SalesOrderEntity` | `OrderId` | `OrderId`, `OrderNumber`, `CustomerId`, `OrderDate`, `OrderStatus`, `SalesChannelId`, `PaymentMethod` |
| `OrderLineEntity` | `OrderId` + `OrderLineNumber` | `OrderId`, `OrderLineNumber`, `ProductID`, `Quantity` |
| `ProductEntity` | `ProductID` | `ProductID`, `ProductName`, `ProductNumber`, `BrandName`, `CategoryName`, `ProductStatus` |

> [!IMPORTANT]
> - `orders[OrderId]` is an internal UUID. `orders[OrderNumber]` (for example `F100241`) is what users type. Use `OrderId` as the key and keep `OrderNumber` as a property.
> - `OrderLineNumber` repeats across orders (every order has a line 1), so `OrderLineEntity` needs the composite key `OrderId` + `OrderLineNumber`.
> - Don't add the money columns (`SubTotal`, `TaxAmount`, `OrderTotal`, `UnitPrice`, `LineTotal`, `DiscountAmount`, `ListPrice`, `StandardCost`) as properties. They're governed in `sm_retail`.
> - Several `product` columns in the source have a trailing space in their name (`ProductCategoryID `, `ListPrice `, `StandardCost `, `Weight `). Leave them out of the binding.

### c. Rebind each entity type to `db_retail`

Replace the generated semantic-model bindings with SQL database bindings so the data agent can query the ontology.

For each entity type:

1. Select **...** next to the entity type and select **Bind data** (or use the **Configure** tab).
2. If a binding to `sm_retail` exists, remove it.
3. Select **+** next to **Data sources** and select **OneLake catalog**.
4. Select the `db_retail` SQL database, expand **dbo**, select the source table, and select **Select**:

   | Entity type | Source table |
   |---|---|
   | `CustomerEntity` | `dbo.customer` |
   | `SalesOrderEntity` | `dbo.orders` |
   | `OrderLineEntity` | `dbo.orderline` |
   | `ProductEntity` | `dbo.product` |

5. Under **Entity type** > **Properties**, map each property from section 4b to its source column.
6. Set the entity type key to the column (or columns) from section 4b.
7. Select **Create** (or **Save**) and confirm that the entity type updated successfully.
8. Open the entity's **Instances** view and confirm that rows load.

<details>
<summary>Fallback: the composite key editor accepts only one column</summary>

Create a view in `db_retail` with a single-column key, and bind `OrderLineEntity` to it:

```sql
CREATE VIEW dbo.v_orderline_ontology AS
SELECT
    CONCAT(OrderId, '-', OrderLineNumber) AS OrderLineKey,
    OrderId,
    OrderLineNumber,
    ProductID,
    Quantity
FROM dbo.orderline;
```

Use `OrderLineKey` as the key, and use `v_orderline_ontology` as the mapping table for `salesOrderContainsLine` and `lineReferencesProduct`.
</details>

<details>
<summary>Fallback: <code>db_retail</code> isn't selectable in the OneLake catalog</summary>

Copy the four tables into a managed Lakehouse and bind to it instead:

1. Create a Lakehouse named `lh_retail_iq`.
2. Use **Get data > New data pipeline** (or **Copy data**) to copy `dbo.customer`, `dbo.orders`, `dbo.orderline`, and `dbo.product` from `db_retail` to `lh_retail_iq` as new managed tables, with overwrite behavior.
3. In the `product` mapping, rename the destination columns to remove trailing spaces (`ProductCategoryID`, `ListPrice`, `StandardCost`, `Weight`).
4. Run the pipeline, refresh the Lakehouse explorer, and confirm that the four tables contain rows.
5. Bind each entity type to its `lh_retail_iq` table, using the same keys and properties.
</details>

---

## 5. Configure relationship types

### a. Target relationships

| Relationship type | Origin | Target | Mapping table | Origin match | Target match |
|---|---|---|---|---|---|
| `customerPlacedSalesOrder` | `CustomerEntity` | `SalesOrderEntity` | `orders` | `CustomerId` | `OrderId` |
| `salesOrderContainsLine` | `SalesOrderEntity` | `OrderLineEntity` | `orderline` | `OrderId` | `OrderId` + `OrderLineNumber` |
| `lineReferencesProduct` | `OrderLineEntity` | `ProductEntity` | `orderline` | `OrderId` + `OrderLineNumber` | `ProductID` |

Relationship types are **directed**. Use verb names that read from origin to target. A property named `CustomerId` on `SalesOrderEntity` doesn't create an edge by itself; the relationship binding materializes the edge.

### b. Review generated relationships

Generate Ontology usually creates relationships in the model direction (many side to one side), for example `orders → customer`. Renaming a relationship changes only its label, not its direction. For each target relationship:

- If a generated relationship already has the right origin and target, rename it and check its binding.
- If it points the opposite way, delete it and create the target relationship.

### c. Create a relationship type

Repeat for each row of the table in 5a:

1. Select **Home > + Add > Relationship type** (or select the origin entity type and add a relationship).
2. Set **Origin entity type**, **Relationship name**, and **Target entity type**.
3. Bind it to the `db_retail` mapping table from the table above.
4. Map the origin key columns and the target key columns.
5. Select **Save** and confirm **Successfully updated the relationship type**.
6. On the canvas, confirm that the arrow starts at the origin and points to the target.

The complete business path is:

```text
CustomerEntity --customerPlacedSalesOrder--> SalesOrderEntity --salesOrderContainsLine--> OrderLineEntity --lineReferencesProduct--> ProductEntity
```

Remove duplicate relationships between the same entity types only after the new one returns data.

---

## 6. Review metrics and add business rules

### a. Review the generated metrics

Open an entity type, select **Open details**, and review its **Metrics** section. Generate Ontology created them from the `sm_retail` DAX measures, such as `Total Sales`, `Total Order Value`, and `Average Order Value`.

Keep them: they document the business meaning of each KPI for ontology consumers (the ontology agent in this lab and MCP clients in Lab 05). Mark IQ still calculates monetary results through `sm_retail`, which remains the single governed calculation engine.

> [!NOTE]
> If Mark IQ later reports that it can't query the ontology even though every entity type is bound to `db_retail`, the metrics may still reference the semantic model. Remove the metrics from `retail_ontology` and retest; the measures stay governed in `sm_retail`.

### b. Add business rules

Rules capture business logic in natural language and link it to ontology elements. They aren't executed against data and don't trigger actions; they give every agent that reads the ontology the same definitions.

For each rule, select **Home > + Add > Rule**, enter the **Name** and **Definition**, link the elements under **Linked ontology elements** with **+ Add**, and select **Create**.

| Name | Definition | Linked elements |
|---|---|---|
| `OrderIdentifier` | Users identify a sales order by its OrderNumber, for example F100241. OrderId is an internal identifier and is never shown as the order reference. | `SalesOrderEntity`, `OrderNumber`, `OrderId` |
| `OpenOrder` | An open order is a SalesOrderEntity whose OrderStatus is Pending. Completed and Cancelled orders are closed. | `SalesOrderEntity`, `OrderStatus` |
| `VipCustomer` | A VIP customer is a CustomerEntity whose CustomerRelationshipTypeId is VIP. | `CustomerEntity`, `CustomerRelationshipTypeId` |
| `RevenueGrain` | Total Sales is measured at order-line grain and Total Order Value at order-header grain. They are not interchangeable; always state the grain. | `SalesOrderEntity`, `OrderLineEntity`, `salesOrderContainsLine` |
| `PurchaseHistory` | What a customer bought is found by traversing customerPlacedSalesOrder, then salesOrderContainsLine, then lineReferencesProduct. | `CustomerEntity`, `customerPlacedSalesOrder`, `salesOrderContainsLine`, `lineReferencesProduct` |

> [!NOTE]
> The ontology MCP server exposes rules to external agents (Lab 05). For the data agent, repeat the critical rules in the Mark IQ instructions (section 9) so the behavior doesn't depend on rule support in a preview feature.

---

## 7. Refresh and validate the graph

### a. Refresh

Schema changes trigger graph ingestion automatically, but run a manual refresh after you finish all renames and bindings. New source rows also require a manual refresh.

1. In the workspace, locate the **Graph** child item of `retail_ontology`.
2. Select **... > Schedule > Refresh now** and wait for completion.
3. Return to `retail_ontology` and confirm that every entity type's **Instances** view loads rows.
4. Confirm that no entity types remain with the old names (`customer`, `orders`, `orderline`, `product`).

### b. Build checks

Run these queries in the `db_retail` query editor and compare them with the graph.

| Check | Query | Pass rule |
|---|---|---|
| C1 Row counts | `SELECT 'customer' t, COUNT(*) n FROM dbo.customer UNION ALL SELECT 'orders', COUNT(*) FROM dbo.orders UNION ALL SELECT 'orderline', COUNT(*) FROM dbo.orderline UNION ALL SELECT 'product', COUNT(*) FROM dbo.product;` | Reference counts for C9 |
| C2 Customer key unique | `SELECT CustomerId FROM dbo.customer GROUP BY CustomerId HAVING COUNT(*) > 1;` | 0 rows |
| C3 Order key unique | `SELECT OrderId FROM dbo.orders GROUP BY OrderId HAVING COUNT(*) > 1;` | 0 rows |
| C4 Product key unique | `SELECT ProductID FROM dbo.product GROUP BY ProductID HAVING COUNT(*) > 1;` | 0 rows |
| C5 Order line key unique | `SELECT OrderId, OrderLineNumber FROM dbo.orderline GROUP BY OrderId, OrderLineNumber HAVING COUNT(*) > 1;` | 0 rows |
| C6 Orders without customer | `SELECT COUNT(*) FROM dbo.orders o LEFT JOIN dbo.customer c ON c.CustomerId = o.CustomerId WHERE c.CustomerId IS NULL;` | 0 |
| C7 Lines without order | `SELECT COUNT(*) FROM dbo.orderline l LEFT JOIN dbo.orders o ON o.OrderId = l.OrderId WHERE o.OrderId IS NULL;` | 0 |
| C8 Lines without product | `SELECT COUNT(*) FROM dbo.orderline l LEFT JOIN dbo.product p ON p.ProductID = l.ProductID WHERE p.ProductID IS NULL;` | 0 |
| C9 Graph node counts | Count the instances of each entity type in the graph (Fabric Graph query builder or the ontology agent). | Each count equals C1 for its table |
| C10 Graph edge counts | Count the edges of the three relationship types. | `customerPlacedSalesOrder` = orders count; `salesOrderContainsLine` = orderline count; `lineReferencesProduct` = orderline count (C6–C8 pass) |

Don't test agents until C1–C10 pass. Most agent failures come from the build, not the agent.

### c. Traversal checks

1. Find `CustomerEntity` `CID-069` and traverse `customerPlacedSalesOrder`: its sales orders appear.
2. Find the `SalesOrderEntity` whose `OrderNumber` is `F100241` and traverse `salesOrderContainsLine`: only its lines appear.
3. Traverse `lineReferencesProduct` from those lines: the expected products appear.
4. Search for `CID-999999`: nothing is returned.

Traverse in the configured direction. A query that walks `customerPlacedSalesOrder` backward from a sales order might return no data even when the relationship is valid.

---

## 8. Explore with the ontology agent

The ontology editor includes a built-in **ontology agent** for the ontology you have open. It starts in **Plan** mode, which explains and proposes without changing anything. **Act** mode applies changes.

1. In `retail_ontology`, select **Home > Ontology agent**.
2. In **Plan** mode, ask:
   - `Review this ontology. List any entity type without a key, without a data binding, or without a description.`
   - `Which products were sold in the sales order whose OrderNumber is F100241?`
   - `Which open orders do VIP customers have? Return OrderNumber, OrderDate, and the customer name.`
3. Check the last answer against `db_retail`:

   ```sql
   SELECT o.OrderNumber, o.OrderDate, c.FirstName, c.LastName
   FROM dbo.orders o JOIN dbo.customer c ON c.CustomerId = o.CustomerId
   WHERE c.CustomerRelationshipTypeId = 'VIP' AND o.OrderStatus = 'Pending'
   ORDER BY o.OrderDate;
   ```

   The agent can only answer it correctly by applying the `OpenOrder` and `VipCustomer` rules. Neither "open" nor "VIP" is a column value the user typed.
4. If the review lists gaps, switch to **Act**, ask the agent to fix one specific gap (for example, `Add a description to OrderLineEntity`), and review the change before keeping it.

---

## 9. Create the agents

### a. Ontology-only test agent

Create this agent first to isolate ontology problems from source routing.

1. Select **+ New item > Data agent** and name it `Mark Ontology Test`.
2. Select **Add Ontology**, search for `retail_ontology`, and select **Add**.
3. Confirm that the four entity types appear in the explorer.
4. In **Agent instructions**, add:

   ```markdown
   Support group by in GQL.
   ```

   This line is the documented workaround for aggregation queries over an ontology source.

### b. Mark IQ

1. Select **+ New item > Data agent** and name it `Mark IQ`.
2. Add `retail_ontology` as a data source.
3. Add `sm_retail` as a second data source and select the `customer`, `orders`, `orderline`, and `product` tables.
4. Set the data source descriptions. The agent uses them to choose a source:

   | Source | Description |
   |---|---|
   | `sm_retail` | `Governed source for all monetary values, totals, averages, percentages, rankings, trends, and named measures (Total Sales, Total Order Value, Total Discount Amount, Discount % of Sales, Tax % of Sales, Order Count, Average Order Value). Use it for every number calculated from sales data.` |
   | `retail_ontology` | `Business entities (CustomerEntity, SalesOrderEntity, OrderLineEntity, ProductEntity), their relationships, and business rules such as open orders and VIP customers. Use it to identify entities and traverse relationships. Not for monetary totals, sums, averages, or percentages.` |

   If the explorer doesn't let you edit a description, put the same text at the start of the agent instructions under `# Source routing`.

5. Open **Agent instructions** and add:

```markdown
# Role
You are Mark IQ, the Contoso Retail data agent grounded in the retail_ontology Fabric IQ ontology and the sm_retail semantic model.

# Source routing
- Use retail_ontology to identify customers, sales orders, order lines, and products, to traverse their relationships, and to apply business definitions.
- Use sm_retail for totals, counts, averages, percentages, rankings, trends, monetary values, and every question that names a measure.
- When a question needs both, first use retail_ontology to resolve the entities (for example the customer or the order), then use sm_retail to calculate the numbers for exactly those entities.
- Never sum, average, or divide properties from retail_ontology. Ratios such as Discount % of Sales come from the sm_retail measure.
- If a question names a raw column such as LineTotal, DiscountAmount, or OrderTotal, use the corresponding governed measure in sm_retail and state its name.

# Business rules (mirrors retail_ontology rules)
- Users identify orders by OrderNumber (for example F100241). OrderId is internal; don't show it as the order reference.
- An open order has OrderStatus Pending. Completed and Cancelled orders are closed.
- A VIP customer has CustomerRelationshipTypeId VIP.
- Total Sales is order-line grain; Total Order Value is order-header grain. They are not interchangeable; state the grain when both appear.

# Response behavior
- State the source and measures used.
- Preserve requested identifiers, filters, and date ranges.
- Use tables for multi-row results.
- Don't invent entities, relationships, or values. If nothing matches, say so.
- Explain ambiguity and the interpretation you chose.

# Ontology query behavior
Support group by in GQL.
```

---

## 10. Self-checking test pack

Run the reference queries in `db_retail` first and save the results. Start a new chat for each question and copy it exactly.

### a. Ontology tests (`Mark Ontology Test`)

Pass rule: the agent returns exactly the IDs in the reference query and doesn't invent rows.

| ID | Question | Reference query (`db_retail`) |
|---|---|---|
| O1 | Which sales orders were placed by customer CID-069? Return OrderNumber, OrderDate, and OrderStatus. | `SELECT OrderNumber, OrderDate, OrderStatus FROM dbo.orders WHERE CustomerId = 'CID-069' ORDER BY OrderNumber;` |
| O2 | Which products were sold in order F100241? Return ProductID and ProductName. | `SELECT DISTINCT p.ProductID, p.ProductName FROM dbo.orders o JOIN dbo.orderline l ON l.OrderId = o.OrderId JOIN dbo.product p ON p.ProductID = l.ProductID WHERE o.OrderNumber = 'F100241' ORDER BY p.ProductID;` |
| O3 | Which customer placed order F100241? | `SELECT c.CustomerId, c.FirstName, c.LastName FROM dbo.orders o JOIN dbo.customer c ON c.CustomerId = o.CustomerId WHERE o.OrderNumber = 'F100241';` |
| O4 | Is there a customer with ID CID-999999? | `SELECT COUNT(*) FROM dbo.customer WHERE CustomerId = 'CID-999999';` (expected 0) |
| O5 | How many open orders does each VIP customer have? | `SELECT c.CustomerId, COUNT(*) n FROM dbo.orders o JOIN dbo.customer c ON c.CustomerId = o.CustomerId WHERE c.CustomerRelationshipTypeId = 'VIP' AND o.OrderStatus = 'Pending' GROUP BY c.CustomerId ORDER BY c.CustomerId;` |

### b. Semantic model tests (`Mark IQ`)

Pass rule: the value matches the reference and the agent's steps show it analyzed `sm_retail`.

| ID | Question | Reference query (`db_retail`) |
|---|---|---|
| S1 | What is the Total Sales for all order lines? | `SELECT SUM(LineTotal) FROM dbo.orderline;` |
| S2 | What is the Total Order Value for all orders? | `SELECT SUM(OrderTotal) FROM dbo.orders;` It must differ from S1, and the agent must not treat them as interchangeable. |
| S3 | What is the Average Order Value for customer CID-069? | `SELECT AVG(OrderTotal) FROM dbo.orders WHERE CustomerId = 'CID-069';` |
| S4 | Show Order Count by year. | `SELECT YEAR(OrderDate) y, COUNT(*) n FROM dbo.orders GROUP BY YEAR(OrderDate) ORDER BY y;` |
| S5 | Show Total Discount Amount by product category. | `SELECT p.CategoryName, SUM(l.DiscountAmount) d FROM dbo.orderline l JOIN dbo.product p ON p.ProductID = l.ProductID GROUP BY p.CategoryName ORDER BY p.CategoryName;` |

### c. Hybrid tests (`Mark IQ`)

Pass rule: the entities match the reference and the money matches the reference through `sm_retail`.

| ID | Question | Reference query (`db_retail`) |
|---|---|---|
| H1 | Which customer placed order F100241, and what is its Total Order Value? | `SELECT c.CustomerId, o.OrderTotal FROM dbo.orders o JOIN dbo.customer c ON c.CustomerId = o.CustomerId WHERE o.OrderNumber = 'F100241';` |
| H2 | For customer CID-069, which products did they buy, and what was the Total Sales for each product? | `SELECT p.ProductName, SUM(l.LineTotal) s FROM dbo.orders o JOIN dbo.orderline l ON l.OrderId = o.OrderId JOIN dbo.product p ON p.ProductID = l.ProductID WHERE o.CustomerId = 'CID-069' GROUP BY p.ProductName ORDER BY p.ProductName;` |
| H3 | What is the Total Order Value of the open orders of VIP customers? | `SELECT SUM(o.OrderTotal) FROM dbo.orders o JOIN dbo.customer c ON c.CustomerId = o.CustomerId WHERE c.CustomerRelationshipTypeId = 'VIP' AND o.OrderStatus = 'Pending';` |

H3 is the Fabric IQ showcase: the business definitions come from the ontology and the number comes from the governed measure. Ask H3 to Mark v1 and Mark v2 as well and compare.

### d. Scoring

| Test | Passed? | Notes |
|---|---|---|
| C1–C10 (build) | | |
| O1–O5 (ontology) | | |
| S1–S5 (semantic model) | | |
| H1–H3 (hybrid) | | |

A test fails if a value differs from the reference, the agent invents a row, or it uses the wrong source.

---

## 11. Run the three-version benchmark

Mark IQ doesn't need to call both sources for every question. The data agent orchestrator selects the source that best fits the request, so seeing only `sm_retail` for a metric question is expected.

Start a new chat for each agent and ask the Lab 03 questions in order:

| ID | Question | Expected Mark IQ routing |
|---|---|---|
| Q1 | **What are the orders from Omar Bennett? Return OrderNumber, OrderDate, OrderStatus, and Total Order Value.** | Ontology to resolve the customer, semantic model for `Total Order Value` |
| Q2 | **What products were included in order F100241? Return product name, quantity, unit price, line total, discount amount, and tax amount.** | Semantic model (monetary values) |
| Q3 | **What did Omar Bennett buy? Group the result by order and include the product details.** | Ontology preferred; semantic model is also valid |
| Q4 | **For customer CID-069, show Order Count, Total Order Subtotal, Total Order Tax, Total Order Value, and Average Order Value between July 1, 2019 and May 31, 2021.** | Semantic model |
| Q5 | **Show the top 5 products by Total Sales, including Total Quantity and Total Discount Amount.** | Semantic model |
| Q6 | **Show Total Sales, Total Discount Amount, Discount % of Sales, and Tax % of Sales by product category.** | Semantic model |
| Q7 | **Show Order Count, Customer Count, Total Order Value, and Average Order Value by year.** | Semantic model |
| Q8 | **Compare Total Sales from order lines with Total Order Value from order headers. Explain why they may differ.** | Semantic model, with the grain explanation from the business rules |
| Q9 | **Which VIP customers have open orders, and what is the Total Order Value of those orders?** | Ontology for "VIP" and "open", semantic model for the value |

### Comparison worksheet

| Question | Mark v1 | Mark v2 | Mark IQ | Values agree | Relationships correct | Business terms understood | Best answer |
|---|---|---|---|---|---|---|---|
| Q1 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q2 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q3 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q4 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q5 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q6 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q7 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q8 |  |  |  | Yes/No | Yes/No | Yes/No |  |
| Q9 |  |  |  | Yes/No | Yes/No | Yes/No |  |

Investigate disagreements by checking filters and date boundaries, relationship direction and bindings, order-header versus order-line grain, governed measure versus raw column, and the source Mark IQ selected. Don't declare Mark IQ better because it's newer: the winning answer must be accurate, reproducible, and grounded in the intended source.

---

## 12. Troubleshooting

### "There's content here I can't work with"

The ontology definitions exist, but instances or edges aren't queryable. In `Mark Ontology Test`, run these from simplest to most complex and stop at the first failure:

| Step | Prompt | If it fails, check |
|---|---|---|
| 1 | `Return CustomerId, FirstName, and LastName for CustomerEntity CID-069.` | `CustomerEntity` binding to `dbo.customer` and `CustomerId` key |
| 2 | `Return OrderId, OrderNumber, OrderDate, and OrderStatus for the SalesOrderEntity whose OrderNumber is F100241.` | `SalesOrderEntity` binding, `OrderId` key, `OrderNumber` property |
| 3 | `Return ProductID, ProductName, BrandName, and CategoryName for five ProductEntity instances.` | `ProductEntity` binding; columns with trailing spaces left out |
| 4 | `Traverse customerPlacedSalesOrder from CustomerEntity CID-069 and return OrderNumber.` | Mapping `orders[CustomerId]` → origin, `orders[OrderId]` → target |
| 5 | `Traverse salesOrderContainsLine from the SalesOrderEntity with OrderNumber F100241 and return the OrderLineEntity keys.` | Composite target key mapping |
| 6 | `Traverse lineReferencesProduct from those OrderLineEntity instances and return ProductName.` | Mapping `orderline[ProductID]` → `ProductEntity[ProductID]` |

### The agent can't query the ontology at all

- Confirm that no entity type, relationship type, or metric still binds to `sm_retail` (data agents don't support semantic-model bindings in an ontology).
- Confirm that the ontology is in the new experience.

### The agent still uses old labels (`orders`, `orderline`, `product`)

1. Refresh the Graph item (section 7a).
2. Open **Open in Fabric Graph > Query builder** from an entity's details and confirm the node types `CustomerEntity`, `SalesOrderEntity`, `OrderLineEntity`, and `ProductEntity`.
3. In the agent, remove `retail_ontology` as a source, save, add it again, and clear the chat.
4. If the labels stay stale, create a clean ontology named `retail_ontology_v2` with **+ New item > Ontology (preview)**, add the entity types with their final names from the start, bind them to `db_retail` (section 4c), and add the relationships (section 5). You can also ask the ontology agent in **Act** mode to create them, then review its plan.

---

## 13. Publish Mark IQ

After the test pack and benchmark pass:

1. Select **Publish**.
2. Use a description such as:

   `Contoso Retail agent grounded in the retail_ontology Fabric IQ ontology (entities, relationships, business rules) and the governed sm_retail measures.`

3. Publish Mark IQ separately from Mark v1 and Mark v2. Keep the previous versions until the comparison is complete.

---

## Current preview limitations

- Ontology, Graph, the ontology agent, and the ontology MCP server are in preview. The old ontology experience retires on January 31, 2027.
- Data agents don't work with an ontology that uses semantic-model bindings.
- New source rows require a manual graph refresh.
- Entity type keys must be string or integer; parameterized decimals can surface as strings.
- Rules are descriptive. They aren't executed and the new experience doesn't integrate directly with Activator.
- Data agent responses are capped at 25 rows and 25 columns, with up to five data sources per agent.

Review the current documentation before delivering this lab:

- [What is ontology?](https://learn.microsoft.com/en-us/fabric/iq/ontology/overview)
- [Generate an ontology from semantic models](https://learn.microsoft.com/en-us/fabric/iq/ontology/how-to-generate-from-semantic-models)
- [Bind data to an ontology](https://learn.microsoft.com/en-us/fabric/iq/ontology/how-to-bind-data)
- [Use rules in an ontology](https://learn.microsoft.com/en-us/fabric/iq/ontology/how-to-use-rules)
- [Create a data agent with an ontology](https://learn.microsoft.com/en-us/fabric/iq/ontology/how-to-create-data-agent)
- [Agent integration options for ontology](https://learn.microsoft.com/en-us/fabric/iq/ontology/concepts-agent-integration)

---

## Mission Complete

You now have three comparable Mark implementations:

- **Mark v1** – raw SQL baseline.
- **Mark v2** – governed semantic-model analytics.
- **Mark IQ** – business entities, relationships, and rules from Fabric IQ, with governed measures for every number.

The business knowledge you wrote into Mark v1's prompts now lives in a governed ontology that any agent can reuse. Continue to [Lab 05 - Mark everywhere: Fabric IQ through MCP](lab05-mark-fabric-iq-mcp.en.md) to consume it outside Fabric.
