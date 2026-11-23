"""Connectivity test for the Helpdesk MCP server.

  python test_client.py                                   # local server or `gcloud run services proxy`
  python test_client.py https://<service>.run.app/mcp --token <ID_TOKEN>   # direct to Cloud Run

Get a token for direct calls with:
  gcloud auth print-identity-token
"""

import argparse
import asyncio

from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport


async def main(url: str, token: str | None) -> None:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    async with Client(StreamableHttpTransport(url, headers=headers)) as client:
        await client.ping()
        print(f"[ok] connected to {url}")

        tools = await client.list_tools()
        print(f"[ok] {len(tools)} tools:")
        for t in tools:
            a = t.annotations
            print(f"   - {t.name:<18} readOnly={getattr(a, 'readOnlyHint', None)} "
                  f"destructive={getattr(a, 'destructiveHint', None)}")

        r = await client.call_tool("search_kb", {"query": "vpn keeps dropping"})
        print("[ok] search_kb ->", r.content[0].text[:80], "...")

        r = await client.call_tool("get_ticket_status", {"ticket_id": "INC-1001"})
        print("[ok] get_ticket_status ->", r.content[0].text)

        r = await client.call_tool("create_ticket", {"summary": "Day 2 test ticket", "priority": "low"})
        print("[ok] create_ticket ->", r.content[0].text)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("url", nargs="?", default="http://127.0.0.1:8080/mcp")
    p.add_argument("--token", help="Google ID token (for direct calls to a private Cloud Run service)")
    a = p.parse_args()
    asyncio.run(main(a.url, a.token))
