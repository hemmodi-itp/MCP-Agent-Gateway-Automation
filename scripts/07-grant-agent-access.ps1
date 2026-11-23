# Step 7 - authorise the deployed agent's identity:
#   (a) Cloud Run: roles/run.invoker on the MCP service
#   (b) Gateway egress: a Unified Access Policy (V2) allowing it to reach REGISTERED destinations
#       (org/folder-level - documented here, run by an org admin)
. "$PSScriptRoot\00-config.ps1"
$ErrorActionPreference = "Stop"
if (-not $ENGINE_ID -or -not $ORG_ID) { throw "Set `$ENGINE_ID and `$ORG_ID in 00-config.ps1" }

$PROJECT_NUMBER = gcloud projects describe $PROJECT_ID --format="value(projectNumber)"
$AGENT_PRINCIPAL = "principal://agents.global.org-$ORG_ID.system.id.goog/resources/aiplatform/projects/$PROJECT_NUMBER/locations/$REGION/reasoningEngines/$ENGINE_ID"
Write-Host "Agent principal: $AGENT_PRINCIPAL"
Write-Host "(Compare with the identity shown on the deployment's details page - use that if it differs.)"

Write-Host "`n=== (a) Cloud Run invoker ==="
gcloud run services add-iam-policy-binding $MCP_SERVICE --region=$REGION `
  --member=$AGENT_PRINCIPAL --role="roles/run.invoker"

Write-Host "`n=== (b) Egress Unified Access Policy (V2) - needs an ORG or FOLDER admin ==="
# `gcloud iam access-policies create` only accepts --organization or --folder (not --project),
# so a project-level user can't run this. While the IAP extension is in DRY_RUN, the gateway
# only LOGS what this policy would decide; tool-level ALLOW/DENY policies still enforce.
# To enforce identity checks, an org/folder admin runs (rules in a JSON file):
#   gcloud iam access-policies create <name> --organization=$ORG_ID --location=global `
#     --display-name="Helpdesk agent egress" --details-rules=rules.json
#   with a rule: effect ALLOW, principals [$AGENT_PRINCIPAL],
#     permission iap.googleapis.com/resources.egressViaIAP,
#     condition (iap.googleapis.com): destination.is_registered == true
#   then binds it to the project with `gcloud iam policy-bindings create ... --policy-kind=ACCESS`.
Write-Host "Skipped - see the comments in this script for the org-admin command."
