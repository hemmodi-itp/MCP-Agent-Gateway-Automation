# Step 4 - Agent Registry: see the auto-registered MCP server, register one manually, register an agent.
. "$PSScriptRoot\00-config.ps1"

$t = Get-GcloudTrack "agent-registry"
$gc = @($t) | Where-Object { $_ }   # "" -> GA

Write-Host "=== A) Auto-registered by Cloud Run (--functional-type=mcp-server) ==="
& gcloud @gc agent-registry mcp-servers list --project=$PROJECT_ID --location=$REGION

Write-Host "`n=== B) Google-managed MCP servers (auto-registered, global) ==="
& gcloud @gc agent-registry mcp-servers list --project=$PROJECT_ID --location=global --limit=10

Write-Host "`n=== C) Manual registration - how you'd register an EXTERNAL / other-project MCP server ==="
$url = gcloud run services describe $MCP_SERVICE --region=$REGION --format="value(status.url)"
# --mcp-server-spec-content accepts inline JSON or a .json file - but gcloud only treats the value
# as a file if the path has NO spaces (regex ^\S*\.json$). Our folder path has spaces, so run from
# the config folder and pass the relative name.
Push-Location (Join-Path $LAB "config")
try {
  & gcloud @gc agent-registry services create "$MCP_SERVICE-manual" `
    --project=$PROJECT_ID --location=$REGION `
    --display-name="Helpdesk MCP (manual)" `
    --mcp-server-spec-type=tool-spec `
    --mcp-server-spec-content=toolspec.json `
    --interfaces="url=$url/mcp,protocolBinding=jsonrpc"
} finally { Pop-Location }

Write-Host "`n=== D) Register an agent (REST-style, no spec) ==="
# After step 06 you can point this at the Agent Runtime endpoint instead. Runtime agents are auto-registered.
& gcloud @gc agent-registry services create "$AGENT_NAME-entry" `
  --project=$PROJECT_ID --location=$REGION `
  --display-name="Helpdesk agent (manual entry)" `
  --agent-spec-type=no-spec `
  --interfaces="url=https://example.invalid/helpdesk,protocolBinding=http-json"

Write-Host "`n=== E) Inspect ==="
& gcloud @gc agent-registry mcp-servers list --project=$PROJECT_ID --location=$REGION --format="table(name.basename(), displayName)"
# The registry projects each Service into a read-only McpServer with a GENERATED id - look it up by display name.
$mcpId = & gcloud @gc agent-registry mcp-servers list --project=$PROJECT_ID --location=$REGION `
  --filter="displayName='Helpdesk MCP (manual)'" --format="value(name.basename())"
& gcloud @gc agent-registry mcp-servers describe $mcpId --project=$PROJECT_ID --location=$REGION
& gcloud @gc agent-registry agents list --project=$PROJECT_ID --location=$REGION

Write-Host "`nAlso check the console: Agent Platform > Govern > Agent Registry (agents, MCP servers, tools)."
# Update tools later:  gcloud agent-registry services update <name> --location=$REGION --mcp-server-spec-content=<file>
# Delete:              gcloud agent-registry services delete <name> --location=$REGION
