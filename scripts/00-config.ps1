# ===== Day 2 lab config - EDIT THESE, then every script dot-sources this file =====
$PROJECT_ID   = "itp-ai-garage-space"      # shared company project
$REGION       = "us-central1"
$PREFIX       = "hem"                      # keeps your resources apart from colleagues' in the shared project
$MCP_SERVICE  = "$PREFIX-helpdesk-mcp"     # Cloud Run service name
$GATEWAY      = "$PREFIX-helpdesk-gw"      # Agent Gateway name
$AGENT_NAME   = "$PREFIX-helpdesk-agent"
$ORG_ID       = "203589767236"             # intuitive.ai org (gcloud projects get-ancestors); part of the agent principal
$ENGINE_ID    = "1984263620757815296"      # from step 06 (reasoningEngines/<id>)

# Python venv on a SHORT path (long Windows paths break some packages' DLLs)
$VENV = "$env:LOCALAPPDATA\gcp-day2-venv"
$PY   = "$VENV\Scripts\python.exe"

# ---- derived - don't edit ----
$LAB   = Split-Path $PSScriptRoot -Parent
$BUILD = Join-Path $LAB "build"
New-Item -ItemType Directory -Force $BUILD | Out-Null
$REGISTRY_PATH = "//agentregistry.googleapis.com/projects/$PROJECT_ID/locations/$REGION"
$GATEWAY_PATH  = "projects/$PROJECT_ID/locations/$REGION/agentGateways/$GATEWAY"
$STAGING_BUCKET = "gs://$PROJECT_ID-$PREFIX-agent-staging"   # where the SDK uploads the packaged agent

function Get-GcloudTrack([string]$Group) {
    # Some Agent Platform commands are GA, others still beta/alpha - pick the first that exists.
    foreach ($t in @("", "beta", "alpha")) {
        $gcArgs = @($t) + ($Group -split " ") + @("--help") | Where-Object { $_ }
        & gcloud @gcArgs *> $null
        if ($LASTEXITCODE -eq 0) { return $t }
    }
    throw "gcloud has no '$Group' command in GA/beta/alpha. Run: gcloud components update"
}

function Expand-Template([string]$Name) {
    # config/<Name>.tpl  ->  build/<Name>  with ${VARS} substituted
    $src = Join-Path $LAB "config\$Name.tpl"
    $out = Join-Path $BUILD $Name
    $text = Get-Content $src -Raw
    foreach ($v in "PROJECT_ID","REGION","GATEWAY","GATEWAY_PATH","REGISTRY_PATH","MCP_SERVICE","PREFIX") {
        $text = $text.Replace("`${$v}", (Get-Variable $v).Value)
    }
    Set-Content -Path $out -Value $text -Encoding utf8
    return $out
}

if ($PROJECT_ID -eq "your-project-id") { throw "Edit scripts\00-config.ps1 first (PROJECT_ID)." }
