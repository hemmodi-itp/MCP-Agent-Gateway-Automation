# Checks your EFFECTIVE permissions on the project (direct + group + inherited roles)
# for every Day 2 step, using Cloud Resource Manager testIamPermissions. Read-only.
param([string]$Project = "itp-ai-garage-space")

$token = gcloud auth print-access-token
$uri = "https://cloudresourcemanager.googleapis.com/v1/projects/${Project}:testIamPermissions"

$checks = [ordered]@{
  "Enable APIs (Cloud Run)"           = "serviceusage.services.enable"
  "Cloud Run: deploy"                 = "run.services.create"
  "Cloud Run: grant invoker"          = "run.services.setIamPolicy"
  "Cloud Run: deploy as SA"           = "iam.serviceAccounts.actAs"
  "Cloud Build: build from source"    = "cloudbuild.builds.create"
  "Artifact Registry: create repo"    = "artifactregistry.repositories.create"
  "Storage: source upload bucket"     = "storage.buckets.create"
  "Agent Registry: list MCP servers"  = "agentregistry.mcpServers.list"
  "Agent Registry: list agents"       = "agentregistry.agents.list"
  "Agent Gateway: create"             = "networkservices.agentGateways.create"
  "Gateway: authz policies"           = "networksecurity.authzPolicies.create"
  "Gateway: authz extensions"         = "networkservices.authzExtensions.create"
  "Agent Runtime: deploy agent"       = "aiplatform.reasoningEngines.create"
  "Gemini models: predict"            = "aiplatform.endpoints.predict"
  "Project IAM: grant roles"          = "resourcemanager.projects.setIamPolicy"
}

"{0,-36} {1,-42} {2}" -f "STEP", "PERMISSION", "RESULT"
"{0,-36} {1,-42} {2}" -f "----", "----------", "------"
foreach ($k in $checks.Keys) {
  $perm = $checks[$k]
  $body = @{ permissions = @($perm) } | ConvertTo-Json
  try {
    $r = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/json" `
         -Headers @{ Authorization = "Bearer $token" }
    $res = if ($r.permissions -contains $perm) { "YES" } else { "missing" }
  } catch {
    $res = "n/a (unknown permission name)"
  }
  "{0,-36} {1,-42} {2}" -f $k, $perm, $res
}
