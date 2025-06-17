#!/bin/bash
# This script updates the Function App's Easy Auth allowedClientApplications with the APIM managed identity client ID
# The APIM principal ID (object ID) is provided from Bicep output, and this script converts it to the client ID (app ID)
# Updated to use stable Azure Web Apps REST API version: 2023-12-01
echo "Running set-easyauth-allowed-client-applications.sh script..."

set -e

# Check for required dependencies
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed. Please install jq first."
    echo "Install with: apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    exit 1
fi

# Required environment variables:
#   AZURE_RESOURCE_GROUP - the resource group name
#   functionAppName      - the Function App resource name
#   apimPrincipalId    - the APIM managed identity principal ID (from Bicep output)

if [[ -z "$AZURE_RESOURCE_GROUP" || -z "$functionAppName" ]]; then
  echo "ERROR: AZURE_RESOURCE_GROUP and functionAppName must be set."
  exit 1
fi

# Accept apimPrincipalId as an argument if not set as env var
if [[ -z "$apimPrincipalId" ]]; then
  if [[ -n "$1" ]]; then
    apimPrincipalId="$1"
  else
    echo "ERROR: apimPrincipalId must be set as an environment variable or provided as the first argument."
    echo "This should be the principal ID (object ID) from the APIM Bicep output."
    exit 1
  fi
fi

echo "APIM principal ID: $apimPrincipalId"

# Get APIM clientId (appId of service principal) from the provided principal ID
echo "Getting APIM client ID from principal ID..."
APIM_CLIENT_ID=$(az ad sp show --id "$apimPrincipalId" --query appId -o tsv)

if [ -z "$APIM_CLIENT_ID" ]; then
  echo "ERROR: Could not retrieve APIM client ID"
  echo "Principal ID: $apimPrincipalId"
  exit 1
fi

echo "APIM clientId: $APIM_CLIENT_ID"

# Check if Function App exists
echo "Verifying Function App exists..."
FUNCTION_APP_EXISTS=$(az resource show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$functionAppName" \
  --resource-type "Microsoft.Web/sites" \
  --query "name" -o tsv 2>/dev/null)

if [ -z "$FUNCTION_APP_EXISTS" ]; then
  echo "ERROR: Function App '$functionAppName' not found in resource group '$AZURE_RESOURCE_GROUP'"
  exit 1
fi

echo "Function App verified: $FUNCTION_APP_EXISTS"

# Check if authsettingsV2 config exists using different approaches
echo "Checking if authsettingsV2 config exists..."

# Primary method: Use az webapp auth show (most reliable)
echo "Checking Easy Auth status..."
AUTH_ENABLED=$(az webapp auth show \
  --name "$functionAppName" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query "enabled" -o tsv 2>/dev/null || echo "false")

if [ "$AUTH_ENABLED" != "true" ]; then
  echo "ERROR: Easy Auth is not enabled for Function App '$functionAppName'"
  echo "Please enable Easy Auth first before running this script"
  exit 1
fi

echo "Easy Auth is enabled. Checking Azure AD provider configuration..."

# Check if Azure AD provider is configured
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
AAD_PROVIDER_ENABLED=$(az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$functionAppName/config/authsettingsV2?api-version=2023-12-01" \
  --query "properties.identityProviders.azureActiveDirectory.enabled" -o tsv 2>/dev/null || echo "false")

if [ "$AAD_PROVIDER_ENABLED" != "true" ]; then
  echo "ERROR: Azure Active Directory provider is not enabled for Function App '$functionAppName'"
  echo "Please configure Azure AD authentication first"
  exit 1
fi

echo "Azure AD provider is enabled. Creating configuration backup..."

# Create backup of current configuration
BACKUP_CONFIG=$(az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$functionAppName/config/authsettingsV2?api-version=2023-12-01")

echo "Configuration backed up successfully."

# Update Easy Auth settings with array merging
echo "Checking existing allowedClientApplications..."

# Get existing allowed client applications
EXISTING_CLIENTS=$(echo "$BACKUP_CONFIG" | jq -r '.properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications // []')

echo "Existing allowed client applications: $EXISTING_CLIENTS"

# Check if APIM client ID is already in the list
if echo "$EXISTING_CLIENTS" | jq -e --arg client_id "$APIM_CLIENT_ID" 'index($client_id)' > /dev/null; then
  echo "APIM client ID '$APIM_CLIENT_ID' is already in allowedClientApplications list"
  echo "No update needed."
  exit 0
fi

echo "Adding APIM client ID to allowedClientApplications..."

# Merge APIM client ID with existing clients (avoid duplicates)
UPDATED_CLIENTS=$(echo "$EXISTING_CLIENTS" | jq --arg client_id "$APIM_CLIENT_ID" '. + [$client_id] | unique')

echo "Updated allowed client applications: $UPDATED_CLIENTS"

# Update the configuration with merged client list
UPDATED_CONFIG=$(echo "$BACKUP_CONFIG" | jq --argjson clients "$UPDATED_CLIENTS" '.properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications = $clients')

# Apply the update using REST API
echo "Applying configuration update..."
UPDATE_RESULT=$(az rest \
  --method PUT \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$functionAppName/config/authsettingsV2?api-version=2023-12-01" \
  --body "$UPDATED_CONFIG" 2>&1)

if [ $? -eq 0 ]; then
  echo "Successfully updated allowedClientApplications for $functionAppName."
  
  # Verify the update
  echo "Verifying configuration update..."
  VERIFICATION=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$functionAppName/config/authsettingsV2?api-version=2023-12-01" \
    --query "properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications" -o json)
  
  if echo "$VERIFICATION" | jq -e --arg client_id "$APIM_CLIENT_ID" 'index($client_id)' > /dev/null; then
    echo "✅ Verification successful: APIM client ID is present in allowedClientApplications"
  else
    echo "⚠️  Verification failed: APIM client ID not found in updated configuration"
    echo "Current allowedClientApplications: $VERIFICATION"
  fi
else
  echo "ERROR: Failed to update allowedClientApplications"
  echo "Error details: $UPDATE_RESULT"
  echo ""
  echo "💾 Configuration backup is available for manual restoration if needed"
  echo "Backup: $BACKUP_CONFIG"
  exit 1
fi
