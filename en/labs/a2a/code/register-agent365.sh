#!/usr/bin/env bash
#
# Register the deployed Anne Agent in the Microsoft Agent 365 registry.
#
# This uses the Microsoft Graph beta Agent Registry API. It registers an
# existing Entra Agent Identity Blueprint; it does not turn the Container App
# managed identity or the A2A Agent Card into an Agent Identity Blueprint.
#
# Prerequisites:
#   * An Agent Identity Blueprint created with the Agent 365 CLI (`a365 setup`)
#   * Agent Registry Administrator assigned to the signed-in operator
#   * A Graph token containing AgentInstance.ReadWrite.All
#   * curl and jq
#
# Required environment variables:
#   AGENT365_BLUEPRINT_APP_ID  Agent Identity Blueprint application (client) ID
#   AGENT365_OWNER_OBJECT_ID   Entra object ID of the registration owner
#
# Agent Card discovery (choose one):
#   AGENT365_AGENT_CARD_URL    Full URL to /.well-known/agent-card.json
#   PUBLIC_BASE_URL            Base URL of the deployed Container App
#
# Authentication:
#   AGENT365_GRAPH_TOKEN       Pre-acquired Graph token (recommended), or
#   AGENT365_GRAPH_TOKEN_FILE  File containing a pre-acquired Graph token, or
#                              an `az login` session is used as a fallback
#
# Usage:
#   ./register-agent365.sh --dry-run
#   ./register-agent365.sh
#
set -euo pipefail

GRAPH_ROOT="${AGENT365_GRAPH_ROOT:-https://graph.microsoft.com}"
REGISTRATION_PATH="/beta/agentRegistry/agentInstances"
DISPLAY_NAME="${AGENT_NAME:-Anne Agent}"
BLUEPRINT_APP_ID="${AGENT365_BLUEPRINT_APP_ID:-}"
OWNER_OBJECT_ID="${AGENT365_OWNER_OBJECT_ID:-}"
AGENT_CARD_URL="${AGENT365_AGENT_CARD_URL:-}"
GRAPH_TOKEN="${AGENT365_GRAPH_TOKEN:-}"
GRAPH_TOKEN_FILE="${AGENT365_GRAPH_TOKEN_FILE:-}"
unset AGENT365_GRAPH_TOKEN
OUTPUT_PATH="${AGENT365_REGISTRATION_OUTPUT:-}"
DRY_RUN=false

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: ./register-agent365.sh [--dry-run] [--help]

Registers an existing Entra Agent Identity Blueprint in Microsoft Agent 365.

Required:
  AGENT365_BLUEPRINT_APP_ID  Blueprint application (client) ID
  AGENT365_OWNER_OBJECT_ID   Registration owner's Entra object ID

Agent Card URL:
  AGENT365_AGENT_CARD_URL, or PUBLIC_BASE_URL from which the URL is derived

Authentication:
  AGENT365_GRAPH_TOKEN_FILE, AGENT365_GRAPH_TOKEN, or an authenticated Azure CLI
  session. The token must contain AgentInstance.ReadWrite.All and the user must
  have the Agent Registry Administrator role. A token file avoids exposing the
  token through the script process environment.

Optional:
  AGENT_NAME                     Display name (default: Anne Agent)
  AGENT365_REGISTRATION_OUTPUT   File in which to save the Graph response
  AGENT365_GRAPH_ROOT            Graph root URL (default: public Graph)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v jq >/dev/null 2>&1 || fail "jq is required."

guid_pattern='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
[[ "$BLUEPRINT_APP_ID" =~ $guid_pattern ]] || fail \
  "AGENT365_BLUEPRINT_APP_ID must be the Agent Identity Blueprint application ID, not the Container App principal ID."
[[ "$OWNER_OBJECT_ID" =~ $guid_pattern ]] || fail \
  "AGENT365_OWNER_OBJECT_ID must be the Entra object ID of a user who will own the registration."

if [[ -z "$AGENT_CARD_URL" ]]; then
  [[ -n "${PUBLIC_BASE_URL:-}" ]] || fail \
    "Set AGENT365_AGENT_CARD_URL or PUBLIC_BASE_URL to the deployed Container App URL."
  AGENT_CARD_URL="${PUBLIC_BASE_URL%/}/.well-known/agent-card.json"
fi
[[ "$AGENT_CARD_URL" == https://* ]] || fail "The deployed Agent Card URL must use HTTPS."

log "Validating A2A Agent Card at $AGENT_CARD_URL"
agent_card="$(curl --fail --silent --show-error --location "$AGENT_CARD_URL")" || fail \
  "Could not retrieve the Agent Card. Deploy the Container App and verify public ingress first."

card_name="$(jq -er '.name | select(type == "string" and length > 0)' <<<"$agent_card")" || fail \
  "Agent Card does not contain a valid name."
a2a_endpoint="$(jq -er \
  '.supportedInterfaces[0].url // .url | select(type == "string" and length > 0)' \
  <<<"$agent_card")" || fail "Agent Card does not advertise an A2A endpoint URL."
[[ "$a2a_endpoint" == https://* ]] || fail "The advertised A2A endpoint must use HTTPS: $a2a_endpoint"

payload="$(jq -n \
  --arg display_name "$DISPLAY_NAME" \
  --arg owner_id "$OWNER_OBJECT_ID" \
  --arg blueprint_id "$BLUEPRINT_APP_ID" \
  '{
    ownerIds: [$owner_id],
    displayName: $display_name,
    agentIdentityBlueprintId: $blueprint_id
  }')"

printf 'Agent Card name : %s\n' "$card_name"
printf 'A2A endpoint    : %s\n' "$a2a_endpoint"
printf 'Registry name   : %s\n' "$DISPLAY_NAME"
printf 'Blueprint app ID: %s\n' "$BLUEPRINT_APP_ID"
printf 'Owner object ID : %s\n' "$OWNER_OBJECT_ID"

if [[ "$DRY_RUN" == true ]]; then
  log "Dry run: registration request"
  printf 'POST %s%s\n' "$GRAPH_ROOT" "$REGISTRATION_PATH"
  jq . <<<"$payload"
  printf '\nNo registry changes were made.\n'
  exit 0
fi

if [[ -n "$GRAPH_TOKEN_FILE" ]]; then
  [[ -f "$GRAPH_TOKEN_FILE" ]] || fail "AGENT365_GRAPH_TOKEN_FILE does not exist."
  GRAPH_TOKEN="$(<"$GRAPH_TOKEN_FILE")"
fi

if [[ -z "$GRAPH_TOKEN" ]]; then
  command -v az >/dev/null 2>&1 || fail \
    "Set AGENT365_GRAPH_TOKEN or install Azure CLI and run az login."
  az account show >/dev/null 2>&1 || fail \
    "Set AGENT365_GRAPH_TOKEN or authenticate first with az login --allow-no-subscriptions."

  log "Acquiring a Microsoft Graph token from the Azure CLI session"
  GRAPH_TOKEN="$(az account get-access-token \
    --resource "$GRAPH_ROOT" \
    --query accessToken \
    --output tsv)" || fail "Azure CLI could not acquire a Microsoft Graph token."
fi
[[ -n "$GRAPH_TOKEN" ]] || fail "Microsoft Graph returned an empty access token."

response_file="$(mktemp)"
auth_header_file="$(mktemp)"
chmod 600 "$response_file" "$auth_header_file"
printf 'Authorization: Bearer %s\n' "$GRAPH_TOKEN" >"$auth_header_file"
unset GRAPH_TOKEN
trap 'rm -f "$response_file" "$auth_header_file"' EXIT

log "Registering the Agent Identity Blueprint in Microsoft Agent 365"
http_status="$(curl --silent --show-error \
  --output "$response_file" \
  --write-out '%{http_code}' \
  --request POST \
  --header "@$auth_header_file" \
  --header 'Content-Type: application/json' \
  --data "$payload" \
  "$GRAPH_ROOT$REGISTRATION_PATH")" || fail "Microsoft Graph request failed before receiving a response."

case "$http_status" in
  200|201)
    registration_id="$(jq -r '.id // empty' "$response_file")"
    [[ -n "$registration_id" ]] || fail \
      "Graph returned HTTP $http_status without a registration ID: $(cat "$response_file")"
    log "Agent registered successfully"
    printf 'Registration ID: %s\n' "$registration_id"
    ;;
  409)
    log "Agent is already registered"
    jq . "$response_file"
    ;;
  401)
    fail "Graph rejected the token. Acquire a token for $GRAPH_ROOT with AgentInstance.ReadWrite.All."
    ;;
  403)
    fail "Registration is forbidden. Grant AgentInstance.ReadWrite.All and assign the Agent Registry Administrator role, then wait for propagation. Response: $(cat "$response_file")"
    ;;
  *)
    fail "Registration failed with HTTP $http_status: $(cat "$response_file")"
    ;;
esac

if [[ -n "$OUTPUT_PATH" ]]; then
  jq . "$response_file" >"$OUTPUT_PATH"
  printf 'Graph response saved to %s\n' "$OUTPUT_PATH"
fi

cat <<EOF

Registration adds the Agent Identity Blueprint to Agent 365 inventory. The A2A
endpoint remains hosted by Azure Container Apps and is not copied into this
Graph registration payload. Verify the inventory entry in:
https://admin.cloud.microsoft/#/agents/all
EOF