# Step 1 - point gcloud at your project, enable APIs, create the Python venv.
. "$PSScriptRoot\00-config.ps1"
$ErrorActionPreference = "Stop"

gcloud config set project $PROJECT_ID
gcloud config set run/region $REGION

Write-Host "`n[apis] enabling (takes 1-3 min) ..."
gcloud services enable `
  aiplatform.googleapis.com run.googleapis.com cloudbuild.googleapis.com `
  artifactregistry.googleapis.com agentregistry.googleapis.com apphub.googleapis.com `
  iam.googleapis.com iap.googleapis.com compute.googleapis.com `
  networkservices.googleapis.com networksecurity.googleapis.com `
  cloudresourcemanager.googleapis.com logging.googleapis.com `
  --project=$PROJECT_ID

Write-Host "`n[venv] $VENV"
if (-not (Test-Path $PY)) { python -m venv $VENV }
& $PY -m pip install -q --upgrade pip
& $PY -m pip install -q "fastmcp>=2.13,<3" "google-adk[mcp]>=2.14" "google-cloud-aiplatform[agent_engines,adk]" google-auth requests

Write-Host "`n[check]"
gcloud services list --enabled --filter="name:(agentregistry OR aiplatform OR run OR networkservices)" --format="value(name)"
& $PY -c "import fastmcp, google.adk; print('fastmcp', fastmcp.__version__, '| adk', google.adk.__version__)"
Write-Host "`nNext: gcloud auth application-default login   (once), then 02-deploy-mcp-cloudrun.ps1"
