#!/bin/bash
# This script fetches the APIM managed identity client ID and updates the Function App's Easy Auth allowedClientApplications
echo "Running set-easyauth-allowed-client-applications.sh script..."

set -e

# Required environment variables:
#   RESOURCE_GROUP - the resource group name
#   APIM_NAME      - the APIM resource name
#   FUNCTION_APP   - the Function App resource name

if [[ -z "$RESOURCE_GROUP" || -z "$APIM_NAME" || -z "$FUNCTION_APP" ]]; then
  echo "ERROR: RESOURCE_GROUP, APIM_NAME, and FUNCTION_APP must be set."
  exit 1
fi

# Get APIM principalId (objectId of managed identity)
APIM_PRINCIPAL_ID=$(az resource show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APIM_NAME" \
  --resource-type "Microsoft.ApiManagement/service" \
  --query "identity.principalId" -o tsv)

# Get APIM clientId (appId of service principal)
APIM_CLIENT_ID=$(az ad sp show --id "$APIM_PRINCIPAL_ID" --query appId -o tsv)

echo "APIM clientId: $APIM_CLIENT_ID"

# Patch Easy Auth settings to allow only APIM clientId
az resource update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FUNCTION_APP/authsettingsV2" \
  --resource-type "Microsoft.Web/sites/config" \
  --set properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications="[$APIM_CLIENT_ID]"

echo "Updated allowedClientApplications for $FUNCTION_APP."
