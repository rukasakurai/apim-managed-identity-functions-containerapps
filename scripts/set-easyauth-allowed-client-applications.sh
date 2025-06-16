#!/bin/bash
# This script fetches the APIM managed identity client ID and updates the Function App's Easy Auth allowedClientApplications
# Updated to use the latest Azure Web Apps REST API version: 2024-11-01
echo "Running set-easyauth-allowed-client-applications.sh script..."

set -e

# Required environment variables:
#   AZURE_RESOURCE_GROUP - the resource group name
#   apimServiceName      - the APIM resource name
#   functionAppName   - the Function App resource name

if [[ -z "$AZURE_RESOURCE_GROUP" || -z "$apimServiceName" || -z "$functionAppName" ]]; then
  echo "ERROR: AZURE_RESOURCE_GROUP, apimServiceName, and functionAppName must be set."
  exit 1
fi

# Get APIM principalId (objectId of managed identity)
echo "Getting APIM principal ID..."
APIM_PRINCIPAL_ID=$(az resource show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$apimServiceName" \
  --resource-type "Microsoft.ApiManagement/service" \
  --query "identity.principalId" -o tsv)

if [ -z "$APIM_PRINCIPAL_ID" ]; then
  echo "ERROR: Could not retrieve APIM principal ID"
  echo "Resource group: $AZURE_RESOURCE_GROUP"
  echo "APIM service name: $apimServiceName"
  exit 1
fi

echo "APIM principal ID: $APIM_PRINCIPAL_ID"

# Get APIM clientId (appId of service principal)
echo "Getting APIM client ID..."
APIM_CLIENT_ID=$(az ad sp show --id "$APIM_PRINCIPAL_ID" --query appId -o tsv)

if [ -z "$APIM_CLIENT_ID" ]; then
  echo "ERROR: Could not retrieve APIM client ID"
  echo "Principal ID: $APIM_PRINCIPAL_ID"
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

# Method 1: Try the direct resource approach
AUTH_CONFIG_EXISTS=$(az resource show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$functionAppName/authsettingsV2" \
  --resource-type "Microsoft.Web/sites/config" \
  --query "name" -o tsv 2>/dev/null || echo "")

if [ -z "$AUTH_CONFIG_EXISTS" ]; then
  echo "Direct resource query failed. Trying webapp auth show..."
  
  # Method 2: Try using az webapp auth show
  AUTH_CONFIG_EXISTS=$(az webapp auth show \
    --name "$functionAppName" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "platform.enabled" -o tsv 2>/dev/null || echo "")
  
  if [ "$AUTH_CONFIG_EXISTS" = "true" ]; then
    echo "Auth config found via webapp auth show"
    USE_WEBAPP_AUTH_UPDATE=true
  else
    echo "WARNING: Easy Auth appears to be disabled or not accessible"
    echo "Checking if we can access it via REST API..."
    
    # Method 3: Try REST API approach
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    REST_RESPONSE=$(az rest \
      --method GET \
      --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$functionAppName/config/authsettingsV2?api-version=2024-11-01" \
      --query "properties.platform.enabled" -o tsv 2>/dev/null || echo "")
    
    if [ "$REST_RESPONSE" = "true" ]; then
      echo "Auth config found via REST API"
      USE_REST_API_UPDATE=true
    else
      echo "ERROR: Cannot access authsettingsV2 config through any method"
      echo "Please verify Easy Auth is properly configured"
      exit 1
    fi
  fi
else
  echo "Auth config verified via direct resource query: $AUTH_CONFIG_EXISTS"
  USE_RESOURCE_UPDATE=true
fi

# Update Easy Auth settings using the method that worked for detection
echo "Updating allowedClientApplications..."

if [ "$USE_RESOURCE_UPDATE" = "true" ]; then
  echo "Using az resource update method..."
  az resource update \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$functionAppName/authsettingsV2" \
    --resource-type "Microsoft.Web/sites/config" \
    --set properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications="[\"$APIM_CLIENT_ID\"]"
  
elif [ "$USE_REST_API_UPDATE" = "true" ]; then
  echo "Using REST API method..."
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  
  # Get current config
  CURRENT_CONFIG=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$functionAppName/config/authsettingsV2?api-version=2024-11-01")
  
  # Update the config with jq to add allowedClientApplications
  UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq ".properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications = [\"$APIM_CLIENT_ID\"]")
  
  # Apply the update
  az rest \
    --method PUT \
    --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$functionAppName/config/authsettingsV2?api-version=2024-11-01" \
    --body "$UPDATED_CONFIG"
    
else
  echo "ERROR: No valid update method available"
  exit 1
fi

if [ $? -eq 0 ]; then
  echo "Successfully updated allowedClientApplications for $functionAppName."
else
  echo "ERROR: Failed to update allowedClientApplications"
  exit 1
fi
