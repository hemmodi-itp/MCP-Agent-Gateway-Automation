# Wire the IAP extension into the gateway (identity-based authentication/authorization).
name: ${PREFIX}-iap-policy
target:
  resources:
  - "${GATEWAY_PATH}"
policyProfile: REQUEST_AUTHZ
action: CUSTOM
customProvider:
  authzExtension:
    resources:
    - "projects/${PROJECT_ID}/locations/${REGION}/authzExtensions/${PREFIX}-iap-authz"
