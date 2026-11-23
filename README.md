# MCP Agent Gateway Automation

An end-to-end, governed AI agent on Google Cloud's Agent Platform:

- an **IT-helpdesk MCP server** (FastMCP) hosted privately on **Cloud Run**,
- an **ADK agent** that uses those tools, deployed to **Agent Runtime** with **Agent Identity**,
- **Agent Registry** to catalogue the agent and MCP server,
- **Agent Gateway** to control the agent's outbound traffic, with tool-level ALLOW/DENY policies.

Everything is automated with PowerShell scripts that run in order (`01` → `07`).

```
                       ┌──────────────── Agent Registry ────────────────┐
                       │  helpdesk-agent   helpdesk-mcp (4 tools)       │
                       └───────────────▲────────────────────▲───────────┘
                                       │ "is it registered?" │
 user ─► helpdesk-agent ──egress──► Agent Gateway ──────────► Cloud Run: helpdesk-mcp (/mcp)
        (Agent Runtime,             ├ IAP authz (Agent Identity + IAM)   search_kb          ✅
         Agent Identity)            └ tool policy: ALLOW 3 tools          get_ticket_status  ✅
                                                                          create_ticket      ✅ (human approval)
                                                                          delete_ticket      ❌ 403 at gateway
```

Security is enforced in three places:

| Layer | Control |
|---|---|
| Agent code | `tool_filter` exposes only 3 tools; `create_ticket` needs human approval (`require_confirmation=True`) |
| Cloud Run | Service is private (`--no-allow-unauthenticated`); callers need `roles/run.invoker` and a Google ID token |
| Agent Gateway | Only registered destinations are reachable; the ALLOW policy permits 3 MCP tools, so `delete_ticket` returns 403 even if the agent tries it |

---

## Repository layout

| Path | What it is |
|---|---|
| `mcp-server/server.py` | FastMCP server with 4 annotated tools (2 read-only, 1 write, 1 destructive) and a `/health` route |
| `mcp-server/test_client.py` | Connectivity test: ping, list tools, call 3 tools |
| `mcp-server/Dockerfile` | Container image for Cloud Run |
| `agent/helpdesk_agent/` | ADK agent: `McpToolset` over streamable HTTP, automatic Cloud Run ID token, tool filtering, human-in-the-loop |
| `agent/helpdesk_agent/.env.example` | Template for local agent settings |
| `agent/deploy_agent.py` | Deploys the agent to Agent Runtime with Agent Identity and (optionally) the gateway binding |
| `agent/my_first_agent/` | Minimal "hello world" ADK agent |
| `config/*.tpl` | Templates for the gateway, IAP authz extension and authz policies (`${VARS}` are filled in by the scripts) |
| `config/toolspec.json` | Tool spec used for manual Agent Registry registration |
| `scripts/00-config.ps1` | **Your settings**, dot-sourced by every other script |
| `scripts/01…07-*.ps1` | One script per step (see below) |
| `scripts/99-cleanup.ps1` | Deletes everything the lab created |
| `scripts/check-permissions.ps1` | Read-only check of your IAM permissions for every step |
| `build/` | Generated YAML (created by the scripts; git-ignored) |

---

## Prerequisites

- **Windows + PowerShell 5.1 or later** (the scripts are PowerShell)
- **Python 3.12+**
- **Google Cloud SDK** with beta and alpha components
- A GCP project where you can enable APIs, deploy Cloud Run and Agent Runtime, and create network-security resources. Run `scripts\check-permissions.ps1 -Project <id>` to verify.
- For step 07(b), an **organization or folder admin** (Unified Access Policies can't be created at project level)

> Agent Registry, Agent Gateway and some Cloud Run agent features are **Preview**. The scripts pick the GA, beta or alpha `gcloud` track automatically, but flags may change. If a command fails, check `gcloud <command> --help`.

### One-time tooling

```powershell
winget install Google.CloudSDK            # then open a NEW terminal
gcloud init                                # sign in, pick your project
gcloud auth application-default login      # credentials for Python / ADK
gcloud components install beta alpha
```

---

## 1. Configure

Edit `scripts/00-config.ps1`:

```powershell
$PROJECT_ID = "your-project-id"
$REGION     = "us-central1"
$PREFIX     = "yourname"          # keeps your resources apart in a shared project
$ORG_ID     = ""                  # gcloud projects get-ancestors <project-id>  (type = organization)
$ENGINE_ID  = ""                  # filled in after step 06 (reasoningEngines/<id>)
```

The Python virtual environment is created at `%LOCALAPPDATA%\gcp-day2-venv`. The short path is deliberate: very long Windows paths stop some packages from loading their DLLs.

---

## 2. Run locally first (no cloud needed)

```powershell
cd scripts
.\01-setup-project.ps1              # enables APIs + creates the venv (only the venv part is needed for local)

$py = "$env:LOCALAPPDATA\gcp-day2-venv\Scripts\python.exe"
cd ..\mcp-server
& $py server.py                     # terminal 1 -> http://localhost:8080/mcp
& $py test_client.py                # terminal 2
```

Expected: `[ok] 4 tools`, then 3 successful tool calls.

**Chat with the agent locally:**

```powershell
cd ..\agent\helpdesk_agent
copy .env.example .env              # then edit: pick Option A (Vertex/ADC) or Option B (GOOGLE_API_KEY)
cd ..
& "$env:LOCALAPPDATA\gcp-day2-venv\Scripts\adk.exe" web     # open http://localhost:8000, choose helpdesk_agent
```

Try these prompts:
- *"My VPN keeps dropping"* → calls `search_kb`
- *"What's the status of INC-1001?"* → calls `get_ticket_status`
- *"Raise a ticket: laptop fan is noisy"* → asks you to approve, then calls `create_ticket`

---

## 3. Deploy to Google Cloud (step by step)

Run each script from the `scripts` folder, in order.

| Step | Command | What it does |
|---|---|---|
| 01 | `.\01-setup-project.ps1` | Sets the gcloud project and region, enables ~13 APIs, creates the venv |
| 02 | `.\02-deploy-mcp-cloudrun.ps1` | Builds and deploys the MCP server to Cloud Run as a **private** service. `--functional-type=mcp-server` auto-registers it in Agent Registry. Grants you `run.invoker` and checks that an unauthenticated call gets 403 |
| 03 | `.\03-test-mcp.ps1` | Tests (A) a direct call with an ID token, (C) a call with no token (expect 403), and prints the commands for (B) the `gcloud run services proxy` test |
| 04 | `.\04-registry.ps1` | Lists the auto-registered MCP server, registers one manually from `toolspec.json`, registers an agent entry, and describes them |
| 05 | `.\05-gateway.ps1` | Creates the egress **Agent Gateway**, the IAP authz extension (in `DRY_RUN`) and the tool ALLOW / prompt DENY policies |
| 06 | `.\06-deploy-agent.ps1` | Deploys the ADK agent to **Agent Runtime** with Agent Identity, with egress bound to the gateway (~5–10 min). Copy the `reasoningEngines/<id>` into `$ENGINE_ID` in `00-config.ps1` |
| 07 | `.\07-grant-agent-access.ps1` | Grants the agent's identity `run.invoker` on the MCP service. Prints the org-admin command for the egress Unified Access Policy |

### Options for step 06

```powershell
.\06-deploy-agent.ps1                         # SDK deploy WITH gateway binding (default)
.\06-deploy-agent.ps1 -NoGateway              # without the gateway, to compare behaviour
.\06-deploy-agent.ps1 -AdkCli                 # plain `adk deploy agent_engine` (no gateway)
.\06-deploy-agent.ps1 -Model gemini-flash-latest
.\06-deploy-agent.ps1 -Update projects/.../reasoningEngines/<id>   # update in place
.\06-deploy-agent.ps1 -ExposeDelete           # gateway demo (see below)
```

### Test the deployed agent

Open the console: **Agent Platform → Deployments → `<prefix>-helpdesk-agent` → Playground**.

**Gateway enforcement demo:** redeploy with `-ExposeDelete`. The agent can then *try* `delete_ticket`, and the gateway's ALLOW policy must block it with 403, even though the agent's own code allows the tool.

---

## How the pieces are configured

**Agent settings** (`agent/helpdesk_agent/.env` locally, set by `deploy_agent.py` when deployed):

| Variable | Purpose |
|---|---|
| `GOOGLE_GENAI_USE_VERTEXAI` | `TRUE` = Agent Platform models with ADC; `FALSE` = Gemini API with `GOOGLE_API_KEY` |
| `GOOGLE_CLOUD_PROJECT` / `GOOGLE_CLOUD_LOCATION` | Needed when `GOOGLE_GENAI_USE_VERTEXAI=TRUE` |
| `MCP_SERVER_URL` | `http://127.0.0.1:8080/mcp` (local or proxy) or `https://<svc>.run.app/mcp` |
| `MCP_AUTH_TOKEN` | Optional static bearer token. If unset and the URL is `*.run.app`, an ID token is fetched automatically |
| `AGENT_MODEL` | Model ID (default `gemini-flash-latest`) |
| `MODEL_LOCATION` | Where the model is served, e.g. `global` for newer models |

**Gateway policies** live in `config/*.tpl`. The scripts expand them into `build/`. To change which tools are allowed, edit the `params` list in `config/authz-allow-mcp-tools.yaml.tpl` and re-run step 05.

**IAP enforcement** starts in `DRY_RUN` (logging only). To enforce it, remove `iamEnforcementMode: "DRY_RUN"` from `config/iap-authz-extension.yaml.tpl` after the org-level access policy from step 07 is in place.

---

## Cleanup

```powershell
.\99-cleanup.ps1
```

This deletes the authz policies, the extension, the gateway, the registry entries, the Cloud Run service and the staging bucket, asking before each one. Delete the Agent Runtime deployment in the console.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `403` calling Cloud Run | Expected without a token. With one: check that the caller has `roles/run.invoker` |
| `401 access token could not be verified` from the deployed agent | Agent Identity tokens are cert-bound. `deploy_agent.py` sets `GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES=False` for this reason |
| Agent says "tool not available" on the first call | Cloud Run cold start (~12–15 s). The toolset timeout is 30 s, so retry once |
| `Session not found` from the MCP server | The server must run with `stateless_http=True` (it does) when Cloud Run scales past one instance |
| `/healthz` returns 404 | Cloud Run reserves paths ending in `z`; use `/health` |
| `RBAC: access denied` for Google APIs after step 05 | Once an ALLOW policy exists, everything else is denied. Rule 2 in the allow policy permits `*.googleapis.com` |
| DLL load errors in Python | Use the venv at the short `%LOCALAPPDATA%` path |
| `gcloud has no '<group>' command` | `gcloud components update` and `gcloud components install beta alpha` |

---

## Security notes

- Never commit `.env` files, `build/`, `.adk/` session databases or service-account keys. They are listed in `.gitignore`.
- The deployed agent uses its **Agent Identity**, never an API key.
- The MCP server's ticket store is in memory (it resets on restart) and its knowledge base is sample data. Treat it as a demo.
