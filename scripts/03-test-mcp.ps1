# Step 3 - test connectivity to the private Cloud Run MCP server.
#   A) direct call with a Google ID token     (automatic)
#   C) negative test without a token -> 403   (automatic)
#   B) through `gcloud run services proxy`    (run by hand in a 2nd window - see the end)
. "$PSScriptRoot\00-config.ps1"

$client = Join-Path $LAB "mcp-server\test_client.py"
$url = gcloud run services describe $MCP_SERVICE --region=$REGION --format="value(status.url)"

Write-Host "=== A) Direct call with a Google ID token ==="
$token = gcloud auth print-identity-token
& $PY -W ignore $client "$url/mcp" --token $token

Write-Host "`n=== C) Negative test: no token -> expect 403 ==="
try {
  Invoke-WebRequest "$url/mcp" -Method Post -UseBasicParsing -Body "{}" -ContentType "application/json" | Out-Null
  Write-Host "  !! request succeeded without a token - service is public"
} catch { Write-Host "  -> HTTP $($_.Exception.Response.StatusCode.value__)" }

Write-Host "`n=== B) Proxy test - run these yourself ==="
Write-Host "Window 2:  gcloud run services proxy $MCP_SERVICE --region=$REGION --port=8080"
Write-Host "Window 1:  & `"$PY`" -W ignore `"$client`" http://127.0.0.1:8080/mcp"
