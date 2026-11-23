# Agent Gateway - egress (agent -> tools / MCP servers / APIs)
# Only destinations registered in this Agent Registry are reachable through the gateway.
# (name comes from the command's positional argument; schema: lib/googlecloudsdk/schemas/networkservices/v1/AgentGateway.yaml)
description: "Day 2 lab egress gateway (${PREFIX})"
protocols:
- MCP
googleManaged:
  governedAccessPath: AGENT_TO_ANYWHERE
registries:
- ${REGISTRY_PATH}
