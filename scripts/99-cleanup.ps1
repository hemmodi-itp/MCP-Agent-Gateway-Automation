# Cleanup - deletes everything this lab created (asks before each delete).
. "$PSScriptRoot\00-config.ps1"

$pol = @(Get-GcloudTrack "network-security authz-policies") | Where-Object { $_ }
$ext = @(Get-GcloudTrack "service-extensions authz-extensions") | Where-Object { $_ }
$gw  = @(Get-GcloudTrack "network-services agent-gateways") | Where-Object { $_ }
$reg = @(Get-GcloudTrack "agent-registry") | Where-Object { $_ }

gcloud iam policy-bindings delete $PREFIX-agent-egress-binding --project=$PROJECT_ID --location=global
gcloud iam access-policies delete $PREFIX-agent-egress --project=$PROJECT_ID --location=global
foreach ($p in "$PREFIX-allow-tools","$PREFIX-deny-prompts","$PREFIX-iap-policy") {
  & gcloud @pol network-security authz-policies delete $p --location=$REGION --project=$PROJECT_ID
}
& gcloud @ext service-extensions authz-extensions delete $PREFIX-iap-authz --location=$REGION --project=$PROJECT_ID
& gcloud @gw network-services agent-gateways delete $GATEWAY --location=$REGION --project=$PROJECT_ID
& gcloud @reg agent-registry services delete "$MCP_SERVICE-manual" --location=$REGION --project=$PROJECT_ID
& gcloud @reg agent-registry services delete "$AGENT_NAME-entry" --location=$REGION --project=$PROJECT_ID
gcloud run services delete $MCP_SERVICE --region=$REGION --project=$PROJECT_ID
gcloud storage rm --recursive $STAGING_BUCKET
Write-Host "Delete the Agent Runtime deployment in the console: Agent Platform > Deployments > $AGENT_NAME > Delete"
