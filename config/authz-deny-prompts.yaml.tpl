# Explicit DENY example: block MCP prompts entirely.
name: ${PREFIX}-deny-prompts
target:
  resources:
  - "${GATEWAY_PATH}"
policyProfile: REQUEST_AUTHZ
httpRules:
- to:
    operations:
    - mcp:
        methods:
        - name: "prompts"
action: DENY
