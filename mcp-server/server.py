"""IT Helpdesk MCP server - Day 2 lab.

Four tools with MCP annotations so Agent Gateway policies can tell them apart:
  search_kb          read-only
  get_ticket_status  read-only
  create_ticket      write
  delete_ticket      write + destructive   (the one we will DENY via policy)

Runs over streamable HTTP at  http://<host>:<PORT>/mcp  (Cloud Run sets PORT).
"""

import logging
import os
import uuid
from datetime import datetime, timezone

from fastmcp import FastMCP
from mcp.types import ToolAnnotations
from starlette.requests import Request
from starlette.responses import JSONResponse

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("helpdesk-mcp")

mcp = FastMCP("IT Helpdesk MCP Server")

KB = {
    "password": "Reset at https://myaccount.example.com > Security > Reset password. "
                "MFA is required. Locked out? Call IT on ext. 4357.",
    "vpn": "1) Quit the VPN client 2) Check internet 3) Reconnect with the 'Corp-Global' "
           "profile 4) Still failing? Reinstall from the Software Center.",
    "laptop": "New laptops: sign in with company SSO, let Intune finish enrolment (~20 min), "
              "then install apps from the Software Center.",
    "software": "Request software via the IT portal > Software request. "
                "Licensed apps need manager approval.",
}

# In-memory "ticket system" (resets when the container restarts - fine for a lab)
TICKETS: dict[str, dict] = {
    "INC-1001": {"summary": "VPN drops every 10 minutes", "priority": "high", "status": "in_progress"},
}


@mcp.tool(annotations=ToolAnnotations(title="Search knowledge base", readOnlyHint=True))
def search_kb(query: str) -> str:
    """Search the IT knowledge base (topics: password, vpn, laptop, software)."""
    log.info("search_kb query=%r", query)
    q = query.lower()
    hits = [text for topic, text in KB.items() if topic in q]
    return "\n".join(hits) if hits else "No article found. Suggest raising a ticket."


@mcp.tool(annotations=ToolAnnotations(title="Get ticket status", readOnlyHint=True))
def get_ticket_status(ticket_id: str) -> dict:
    """Get the status of an IT ticket, e.g. INC-1001."""
    log.info("get_ticket_status id=%s", ticket_id)
    t = TICKETS.get(ticket_id.upper())
    return {"ticket_id": ticket_id.upper(), **t} if t else {"error": f"{ticket_id} not found"}


@mcp.tool(annotations=ToolAnnotations(title="Create ticket", readOnlyHint=False, destructiveHint=False))
def create_ticket(summary: str, priority: str = "medium") -> dict:
    """Create an IT ticket. priority: low | medium | high."""
    tid = f"INC-{uuid.uuid4().int % 9000 + 1000}"
    TICKETS[tid] = {
        "summary": summary,
        "priority": priority,
        "status": "open",
        "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    log.info("create_ticket id=%s", tid)
    return {"ticket_id": tid, **TICKETS[tid]}


@mcp.tool(annotations=ToolAnnotations(title="Delete ticket", readOnlyHint=False, destructiveHint=True))
def delete_ticket(ticket_id: str) -> dict:
    """Permanently delete an IT ticket."""
    log.info("delete_ticket id=%s", ticket_id)
    removed = TICKETS.pop(ticket_id.upper(), None)
    return {"deleted": bool(removed), "ticket_id": ticket_id.upper()}


# /health, not /healthz: Cloud Run reserves URL paths ending in "z" and answers 404 itself.
@mcp.custom_route("/health", methods=["GET"])
async def health(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})


if __name__ == "__main__":
    # host 0.0.0.0 is required on Cloud Run.
    # stateless_http=True: no in-memory MCP sessions, so any Cloud Run instance can serve any
    #   request (with stateful sessions, a request landing on another instance fails with
    #   "Session not found"). It also means the client doesn't open the GET notification stream.
    # json_response=True: plain JSON replies instead of an SSE stream - simpler through proxies.
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8080")),
        stateless_http=True,
        json_response=True,
    )
