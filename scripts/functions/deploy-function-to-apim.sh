#!/bin/bash

# Deploy Azure Function to existing APIM instance
echo "Deploying Azure Function to APIM..."

# Check if APIM service exists
APIM_SERVICE_NAME=${APIM_SERVICE_NAME}
if [ -z "$APIM_SERVICE_NAME" ]; then
    echo "Error: APIM_SERVICE_NAME environment variable not set"
    exit 1
fi

RESOURCE_GROUP_NAME=${AZURE_RESOURCE_GROUP}
if [ -z "$RESOURCE_GROUP_NAME" ]; then
    echo "Error: AZURE_RESOURCE_GROUP environment variable not set"
    exit 1
fi

FUNCTION_APP_ID=${FUNCTION_APP_ID}
if [ -z "$FUNCTION_APP_ID" ]; then
    echo "Error: FUNCTION_APP_ID environment variable not set"
    exit 1
fi

FUNCTION_APP_HOSTNAME=${FUNCTION_APP_HOSTNAME}
if [ -z "$FUNCTION_APP_HOSTNAME" ]; then
    echo "Error: FUNCTION_APP_HOSTNAME environment variable not set"
    exit 1
fi

FUNC_EASYAUTH_APP_ID=${FUNC_EASYAUTH_APP_ID}
if [ -z "$FUNC_EASYAUTH_APP_ID" ]; then
    echo "Error: FUNC_EASYAUTH_APP_ID environment variable not set"
    exit 1
fi

# Deploy the function app code first
echo "Deploying function app code..."
azd deploy function

if [ $? -ne 0 ]; then
    echo "Error: Function app deployment failed"
    exit 1
fi

# Configure APIM backend integration
echo "Configuring APIM backend integration..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file "./infra/modules/apim-backend-integration/main.bicep" \
  --parameters apimServiceName="$APIM_SERVICE_NAME" \
               backendType="function" \
               backendResourceId="$FUNCTION_APP_ID" \
               backendHostname="$FUNCTION_APP_HOSTNAME" \
               apimApiPath="hello-api" \
               apiDisplayName="Hello Function API" \
               backendAppId="$FUNC_EASYAUTH_APP_ID" \
               backendName="hello-function"

if [ $? -ne 0 ]; then
    echo "Error: APIM backend integration deployment failed"
    exit 1
fi

echo "Function deployment to APIM completed successfully"
