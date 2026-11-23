# Step 2 - build & deploy the MCP server to Cloud Run (private) and auto-register it in Agent Registry.
. "$PSScriptRoot\00-config.ps1"
$ErrorActionPreference = "Stop"

$src = Join-Path $LAB "mcp-server"
Write-Host "[deploy] $MCP_SERVICE from $src (Cloud Build, ~3-5 min)"

# --functional-type=mcp-server  -> Cloud Run auto-registers the service as an MCP server in Agent Registry (Preview, beta track)
# --no-allow-unauthenticated    -> callers need roles/run.invoker + a Google ID token
gcloud beta run deploy $MCP_SERVICE `
  --source=$src `
  --region=$REGION `
  --functional-type=mcp-server `
  --no-allow-unauthenticated `
  --memory=512Mi --max-instances=2 `
  --project=$PROJECT_ID

$me  = gcloud config get-value account
$url = gcloud run services describe $MCP_SERVICE --region=$REGION --format="value(status.url)"

Write-Host "`n[iam] letting $me invoke the service"
gcloud run services add-iam-policy-binding $MCP_SERVICE --region=$REGION `
  --member="user:$me" --role="roles/run.invoker" | Out-Null

Write-Host "`n[done] MCP endpoint: $url/mcp"
Write-Host "Unauthenticated test (should be 403):"
# Note: Cloud Run reserves paths ending in "z" (e.g. /healthz) and returns 404 for them - test /health instead.
try { Invoke-WebRequest "$url/health" -UseBasicParsing | Out-Null; Write-Host "  !! got 200 - service is public" }
catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -eq 403) { Write-Host "  -> 403 (good: private)" } else { Write-Host "  -> $code (unexpected - check the service)" }
}
Write-Host "Next: 03-test-mcp.ps1"
