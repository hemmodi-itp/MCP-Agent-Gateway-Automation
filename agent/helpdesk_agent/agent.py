"""ADK helpdesk agent that uses the Helpdesk MCP server's tools.

Config (env vars or agent/helpdesk_agent/.env):
  MCP_SERVER_URL   http://127.0.0.1:8080/mcp (local / `gcloud run services proxy`)
                   or https://<service>-<hash>.<region>.run.app/mcp (direct to Cloud Run)
  MCP_AUTH_TOKEN   optional static bearer token (e.g. from `gcloud auth print-identity-token`)
  AGENT_MODEL      model ID (default: gemini-flash-latest)
  MODEL_LOCATION   Agent Platform location for model calls, e.g. "global" (only used when
                   GOOGLE_GENAI_USE_VERTEXAI=TRUE). Needed because newer models such as
                   gemini-4-hydrogen are served from `global`, while the agent runs in us-central1.

When MCP_SERVER_URL is a *.run.app URL and no MCP_AUTH_TOKEN is set, a Google ID
token is fetched automatically for the Cloud Run service (works with a service
account / runtime identity; on a laptop use the proxy or MCP_AUTH_TOKEN instead).
"""

import os
import time
from urllib.parse import urlparse

from google.adk.agents import LlmAgent
from google.adk.models import Gemini
from google.adk.tools.mcp_tool import McpToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StreamableHTTPConnectionParams

MCP_SERVER_URL = os.getenv("MCP_SERVER_URL", "http://127.0.0.1:8080/mcp")
MODEL_ID = os.getenv("AGENT_MODEL", "gemini-flash-latest")
MODEL_LOCATION = os.getenv("MODEL_LOCATION")
_USE_AGENT_PLATFORM = os.getenv("GOOGLE_GENAI_USE_VERTEXAI", "").lower() in ("true", "1")

# Agent Platform + explicit location -> pin the model client to that location.
# Otherwise (e.g. local Gemini API key) just pass the model name.
MODEL = (
    Gemini(model=MODEL_ID, client_kwargs={"enterprise": True, "location": MODEL_LOCATION})
    if _USE_AGENT_PLATFORM and MODEL_LOCATION
    else MODEL_ID
)

_token_cache: dict[str, float | str] = {"token": "", "exp": 0.0}


def _auth_headers(_ctx=None) -> dict[str, str]:
    """Called by ADK before MCP requests - returns the Authorization header."""
    static = os.getenv("MCP_AUTH_TOKEN")
    if static:
        return {"Authorization": f"Bearer {static}"}

    host = urlparse(MCP_SERVER_URL).hostname or ""
    if not host.endswith(".run.app"):
        return {}  # local server or authenticated proxy - no token needed

    if time.time() < float(_token_cache["exp"]):
        return {"Authorization": f"Bearer {_token_cache['token']}"}

    import google.auth.transport.requests
    from google.oauth2 import id_token

    audience = f"https://{host}"
    token = id_token.fetch_id_token(google.auth.transport.requests.Request(), audience)
    _token_cache.update(token=token, exp=time.time() + 50 * 60)  # ID tokens live 60 min
    return {"Authorization": f"Bearer {token}"}


def _connection() -> StreamableHTTPConnectionParams:
    # timeout=30: a scaled-to-zero Cloud Run MCP server needs ~12-15 s to cold start; with a
    # shorter timeout ADK drops the toolset for that turn ("tool not available").
    return StreamableHTTPConnectionParams(url=MCP_SERVER_URL, timeout=30, sse_read_timeout=300)


# Least privilege: only the tools this agent needs. delete_ticket is never exposed.

# 1) Read-only tools - run freely.
read_tools = McpToolset(
    connection_params=_connection(),
    header_provider=_auth_headers,
    tool_filter=["search_kb", "get_ticket_status"],
)

# 2) Write tools - HARD guardrail: ADK pauses before every call and waits for a
#    human approve/reject. The model cannot skip this (unlike a prompt instruction).
#    require_confirmation also accepts a callable that gets the tool's arguments,
#    e.g.  require_confirmation=lambda priority="medium": priority == "high"
write_tools = McpToolset(
    connection_params=_connection(),
    header_provider=_auth_headers,
    tool_filter=["create_ticket"],
    require_confirmation=True,
)

tools = [read_tools, write_tools]
instruction = (
    "You are Intuitive's internal IT helpdesk assistant.\n"
    "- For how-to questions, call search_kb first and answer in short numbered steps.\n"
    "- For ticket questions, call get_ticket_status.\n"
    "- When the user wants a ticket, call create_ticket. The system will ask a human "
    "to approve it. If it is rejected, say no ticket was created.\n"
    "- Repeat the ticket ID back after a ticket is created.\n"
    "- Never ask for or reveal passwords. Politely decline non-IT questions."
)

# 3) GATEWAY DEMO ONLY (GATEWAY_DEMO_EXPOSE_DELETE=true): deliberately expose delete_ticket
#    so the agent CAN try it - and Agent Gateway's tool ALLOW policy must block it (403).
#    This shows the gateway enforcing even when the agent's own code is too permissive.
if os.getenv("GATEWAY_DEMO_EXPOSE_DELETE", "").lower() == "true":
    tools.append(McpToolset(
        connection_params=_connection(),
        header_provider=_auth_headers,
        tool_filter=["delete_ticket"],
    ))
    instruction += (
        "\n- If the user asks to delete a ticket, call delete_ticket and report exactly "
        "what the system returned (including any error)."
    )

root_agent = LlmAgent(
    name="helpdesk_agent",
    model=MODEL,
    description="Internal IT helpdesk agent backed by the Helpdesk MCP server.",
    instruction=instruction,
    tools=tools,
)
