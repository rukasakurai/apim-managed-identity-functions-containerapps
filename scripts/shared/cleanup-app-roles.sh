#!/bin/bash

# Cleanup script for Entra ID app roles and assignments
echo "Cleaning up Entra ID app roles and assignments..."

# Get environment variables
SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
RESOURCE_GROUP_NAME=${AZURE_RESOURCE_GROUP}

if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: AZURE_SUBSCRIPTION_ID environment variable not set"
    exit 1
fi

if [ -z "$RESOURCE_GROUP_NAME" ]; then
    echo "Error: AZURE_RESOURCE_GROUP environment variable not set"
    exit 1
fi

# Call the existing cleanup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/../cleanup-app-roles.sh"

if [ -f "$CLEANUP_SCRIPT" ]; then
    echo "Running existing cleanup script..."
    "$CLEANUP_SCRIPT"
    
    if [ $? -ne 0 ]; then
        echo "Warning: Cleanup script returned non-zero exit code"
    fi
else
    echo "No existing cleanup script found. Manual cleanup may be required."
fi

echo "Cleanup completed"
