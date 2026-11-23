"""Deploy the ADK helpdesk agent to Agent Runtime with the Agent Platform SDK.

  python deploy_agent.py --project P --region us-central1 --mcp-url https://<svc>.run.app/mcp
  python deploy_agent.py ... --gateway projects/P/locations/us-central1/agentGateways/helpdesk-gw

--gateway binds the agent's outbound (egress) traffic to Agent Gateway. That requires
AGENT_IDENTITY, which this script always uses. Run from the day2-lab/agent folder.
"""

import argparse
import os
import sys

import vertexai
from vertexai import agent_engines, types


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--project", required=True)
    p.add_argument("--region", default="us-central1")
    p.add_argument("--mcp-url", required=True, help="https://<service>.run.app/mcp")
    p.add_argument("--gateway", help="projects/<p>/locations/<r>/agentGateways/<name>")
    p.add_argument("--model", default="gemini-4-hydrogen")
    p.add_argument("--model-location", default="global",
                   help="where the model is served (newer models: global)")
    p.add_argument("--display-name", default="helpdesk-agent")
    p.add_argument("--update", help="existing resource name to update instead of create")
    p.add_argument("--staging-bucket", required=True,
                   help="gs://bucket the SDK uploads the packaged agent to")
    p.add_argument("--expose-delete", action="store_true",
                   help="gateway demo: expose delete_ticket so the gateway policy must block it")
    a = p.parse_args()
    if a.expose_delete:
        os.environ["GATEWAY_DEMO_EXPOSE_DELETE"] = "true"
        print("[demo] delete_ticket exposed to the agent - Agent Gateway must block it")

    # The agent object is built at import time and serialized as-is for deployment,
    # so set the cloud settings BEFORE importing it (the local .env is not used here).
    os.environ["MCP_SERVER_URL"] = a.mcp_url
    os.environ["AGENT_MODEL"] = a.model
    os.environ["MODEL_LOCATION"] = a.model_location
    os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "TRUE"
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from helpdesk_agent.agent import root_agent

    client = vertexai.Client(project=a.project, location=a.region)
    app = agent_engines.AdkApp(agent=root_agent)

    config: dict = {
        "display_name": a.display_name,
        "description": "Day 2 lab - IT helpdesk agent using MCP tools on Cloud Run",
        "requirements": [
            "google-cloud-aiplatform[agent_engines,adk]",
            "google-adk[mcp]>=2.14",
            "google-auth",
            "requests",
            # used by the SDK to serialize the agent - listed explicitly to avoid the
            # "requirements are missing" warning and keep versions consistent
            "cloudpickle",
            "pydantic",
        ],
        "extra_packages": ["helpdesk_agent"],
        "staging_bucket": a.staging_bucket,
        "env_vars": {
            "MCP_SERVER_URL": a.mcp_url,
            "AGENT_MODEL": a.model,
            "MODEL_LOCATION": a.model_location,
            # Use Agent Platform (Vertex) models with the runtime's identity - never an API key.
            # (Overrides the local .env, which points at the Gemini API for laptop testing.)
            "GOOGLE_GENAI_USE_VERTEXAI": "TRUE",
            # Agent Identity tokens are bound to the agent's mTLS certificate by default.
            # Cloud Run (*.run.app) can't verify a cert-bound token over plain TLS -> 401
            # "access token could not be verified". Google's Agent Gateway + Agent Runtime
            # guide sets this to False; it lets the agent present an unbound token.
            # Trade-off: an unbound token could be replayed if stolen - keep tools least-privilege.
            "GOOGLE_API_PREVENT_AGENT_TOKEN_SHARING_FOR_GCP_SERVICES": "False",
        },
        # Agent Identity = per-agent SPIFFE identity; required for Agent Gateway binding
        "identity_type": types.IdentityType.AGENT_IDENTITY,
    }
    if a.gateway:
        config["agent_gateway_config"] = {
            "agent_to_anywhere_config": {"agent_gateway": a.gateway}
        }
        print(f"[gateway] egress bound to {a.gateway}")

    print("[deploy] packaging and deploying - this takes ~5-10 minutes ...")
    if a.update:
        remote = client.agent_engines.update(name=a.update, agent=app, config=config)
    else:
        remote = client.agent_engines.create(agent=app, config=config)

    name = remote.api_resource.name
    print(f"[done] {name}")
    print("Test it: console > Agent Platform > Deployments > helpdesk-agent > Playground")
    print("Agent identity principal is shown on the deployment's details page "
          "(needed for scripts/07-grant-agent-access.ps1).")


if __name__ == "__main__":
    main()
