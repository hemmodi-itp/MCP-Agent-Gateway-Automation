# ALLOW policy for the egress gateway. Once ANY allow policy exists, every request that
# matches none of its rules is DENIED ("RBAC: access denied") - and the gateway carries ALL
# of the agent's outbound traffic, not just MCP. So it needs two rules:
#
#  Rule 1 - MCP tool allow-list: tools/list + tools/call for ONLY these three tools.
#           delete_ticket is not listed -> denied (403) at the gateway.
#           MATCH_BASE_PROTOCOL_METHODS keeps MCP handshake methods (initialize, ping...) working.
#  Rule 2 - the agent's own Google API calls (Agent Platform sessions + Gemini model, logging,
#           telemetry...). Narrow this to specific hosts once you've seen them in the gateway logs.
name: ${PREFIX}-allow-tools
target:
  resources:
  - "${GATEWAY_PATH}"
policyProfile: REQUEST_AUTHZ
httpRules:
- to:
    operations:
    - mcp:
        baseProtocolMethodsOption: MATCH_BASE_PROTOCOL_METHODS
        methods:
        - name: "tools/list"
        - name: "tools/call"
          params:
          - exact: "search_kb"
          - exact: "get_ticket_status"
          - exact: "create_ticket"
- to:
    operations:
    - hosts:
      - suffix: ".googleapis.com"
action: ALLOW
