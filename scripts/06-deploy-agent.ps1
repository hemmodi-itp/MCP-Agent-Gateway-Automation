# Step 6 - deploy the ADK agent to Agent Runtime, egress bound to Agent Gateway.
#   .\06-deploy-agent.ps1            -> SDK deploy WITH gateway binding (Agent Identity)
#   .\06-deploy-agent.ps1 -NoGateway -> SDK deploy without the gateway (compare behaviour)
#   .\06-deploy-agent.ps1 -AdkCli    -> plain `adk deploy agent_engine` (ADK CLI way, no gateway)
param([switch]$NoGateway, [switch]$AdkCli, [string]$Model = "gemini-4-hydrogen", [string]$Update = "", [switch]$ExposeDelete)
. "$PSScriptRoot\00-config.ps1"
$ErrorActionPreference = "Stop"

$url = gcloud run services describe $MCP_SERVICE --region=$REGION --format="value(status.url)"
$agentDir = Join-Path $LAB "agent"

if ($AdkCli) {
    # ADK CLI reads agent/helpdesk_agent/.env - put MCP_SERVER_URL=$url/mcp there first
    & "$VENV\Scripts\adk.exe" deploy agent_engine `
        --project=$PROJECT_ID --region=$REGION `
        --display_name=$AGENT_NAME `
        (Join-Path $agentDir "helpdesk_agent")
    return
}

# Staging bucket for the SDK's upload (create once, same region as the agent)
# (try/catch: with ErrorActionPreference=Stop, PowerShell 5.1 turns gcloud's stderr into an exception)
$bucketExists = $true
try { gcloud storage buckets describe $STAGING_BUCKET --format="value(name)" *> $null; if ($LASTEXITCODE -ne 0) { $bucketExists = $false } }
catch { $bucketExists = $false }
if (-not $bucketExists) {
    Write-Host "[bucket] creating $STAGING_BUCKET"
    gcloud storage buckets create $STAGING_BUCKET --project=$PROJECT_ID --location=$REGION --uniform-bucket-level-access
    if ($LASTEXITCODE -ne 0) { throw "Could not create $STAGING_BUCKET" }
}

Push-Location $agentDir
try {
    # Build the optional args with += (an `if` returning a 1-item array unwraps to a string,
    # and splatting a string passes it one character at a time).
    $extra = @()
    if (-not $NoGateway) { $extra += @("--gateway", $GATEWAY_PATH) }
    if ($Update)         { $extra += @("--update", $Update) }
    if ($ExposeDelete)   { $extra += "--expose-delete" }
    & $PY -W ignore deploy_agent.py --project $PROJECT_ID --region $REGION --mcp-url "$url/mcp" `
        --display-name $AGENT_NAME --model $Model --staging-bucket $STAGING_BUCKET @extra
    if ($LASTEXITCODE -ne 0) { throw "Deploy failed - see the error above." }
} finally { Pop-Location }

Write-Host "`nVerify the gateway binding (null = not bound):"
Write-Host "  console > Agent Platform > Deployments > $AGENT_NAME > Details > Agent Gateway"
Write-Host "Then set `$ENGINE_ID in 00-config.ps1 and run 07-grant-agent-access.ps1"
