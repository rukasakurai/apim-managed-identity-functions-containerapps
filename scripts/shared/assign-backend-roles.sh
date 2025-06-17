#!/bin/bash

# Generic script for assigning backend roles to APIM managed identity

BACKEND_TYPE=$1

if [ -z "$BACKEND_TYPE" ]; then
    echo "Usage: $0 <backend_type>"
    echo "backend_type: function, containerapp"
    exit 1
fi

if [ "$BACKEND_TYPE" != "function" ] && [ "$BACKEND_TYPE" != "containerapp" ]; then
    echo "Error: Invalid backend type: $BACKEND_TYPE"
    echo "Valid types: function, containerapp"
    exit 1
fi

echo "Assigning APIM managed identity roles for backend type: $BACKEND_TYPE"

# Get the subscription ID and resource group from environment variables or azd env
SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
RESOURCE_GROUP_NAME=${AZURE_RESOURCE_GROUP}
APIM_PRINCIPAL_ID=${APIM_PRINCIPAL_ID}

if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: AZURE_SUBSCRIPTION_ID environment variable not set"
    exit 1
fi

if [ -z "$RESOURCE_GROUP_NAME" ]; then
    echo "Error: AZURE_RESOURCE_GROUP environment variable not set"
    exit 1
fi

if [ -z "$APIM_PRINCIPAL_ID" ]; then
    echo "Error: APIM_PRINCIPAL_ID environment variable not set"
    exit 1
fi

case $BACKEND_TYPE in
    "function")
        echo "Processing Azure Functions backend..."
        
        # Get the function app resource ID
        FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
        if [ -z "$FUNCTION_APP_NAME" ]; then
            echo "Error: FUNCTION_APP_NAME environment variable not set"
            exit 1
        fi
        
        # Assign the APIM managed identity to the Function App's app registration role
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        "$SCRIPT_DIR/../assign-apim-mi-to-functionapp-app-role.sh"
        
        if [ $? -ne 0 ]; then
            echo "Error: Failed to assign APIM managed identity to Function App app role"
            exit 1
        fi
        
        echo "Function backend role assignment completed"
        ;;
    "containerapp")
        echo "Processing Container Apps backend..."
        # Container Apps-specific role assignment logic will go here
        echo "Container Apps backend processing not yet implemented"
        ;;
    *)
        echo "Error: Unknown backend type: $BACKEND_TYPE"
        exit 1
        ;;
esac

echo "Backend role assignment completed successfully"
