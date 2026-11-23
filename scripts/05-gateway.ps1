# Step 5 - Agent Gateway (egress) + authentication (IAP / Agent Identity) + tool-level policies.
. "$PSScriptRoot\00-config.ps1"

$gw  = @(Get-GcloudTrack "network-services agent-gateways") | Where-Object { $_ }
$ext = @(Get-GcloudTrack "service-extensions authz-extensions") | Where-Object { $_ }
$pol = @(Get-GcloudTrack "network-security authz-policies") | Where-Object { $_ }

Write-Host "=== A) Create the egress gateway (bound to this project's Agent Registry) ==="
$f = Expand-Template "gateway-egress.yaml"; Get-Content $f
& gcloud @gw network-services agent-gateways import $GATEWAY --source=$f --location=$REGION --project=$PROJECT_ID
& gcloud @gw network-services agent-gateways describe $GATEWAY --location=$REGION --project=$PROJECT_ID

Write-Host "`n=== B) Authentication: IAP authz extension (checks Agent Identity vs IAM) - DRY_RUN ==="
$f = Expand-Template "iap-authz-extension.yaml"
& gcloud @ext service-extensions authz-extensions import $PREFIX-iap-authz --source=$f --location=$REGION --project=$PROJECT_ID
$f = Expand-Template "authz-iap-custom.yaml"
& gcloud @pol network-security authz-policies import $PREFIX-iap-policy --source=$f --location=$REGION --project=$PROJECT_ID

Write-Host "`n=== C) Tool-level policies (max 4 authz policies per egress gateway) ==="
$f = Expand-Template "authz-allow-mcp-tools.yaml"; Get-Content $f
& gcloud @pol network-security authz-policies import $PREFIX-allow-tools --source=$f --location=$REGION --project=$PROJECT_ID
$f = Expand-Template "authz-deny-prompts.yaml"
& gcloud @pol network-security authz-policies import $PREFIX-deny-prompts --source=$f --location=$REGION --project=$PROJECT_ID

Write-Host "`n=== D) Verify ==="
& gcloud @pol network-security authz-policies list --location=$REGION --project=$PROJECT_ID
Write-Host "`nGateway path for step 06:  $GATEWAY_PATH"
