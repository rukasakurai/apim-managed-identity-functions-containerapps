#!/bin/bash
# This script removes app role assignments using the Microsoft Graph API v1.0 (stable version)

echo "Running cleanup-app-roles.sh script..."

# Check if required environment variables are set
if [ -z "$functionAuthAppId" ]; then
    echo "Warning: functionAuthAppId not set. Skipping app role cleanup."
    exit 0
fi

if [ -z "$apimPrincipalId" ]; then
    echo "Warning: apimPrincipalId not set. Skipping app role assignment cleanup."
    exit 0
fi

echo "Cleaning up app role assignments for APIM managed identity..."

# Get the app role assignment ID
ASSIGNMENT_ID=$(az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments" \
  --query "value[?resourceId=='$(az ad sp show --id $functionAuthAppId --query id -o tsv)'].id" \
  -o tsv 2>/dev/null)

# Delete the app role assignment if it exists
if [ -n "$ASSIGNMENT_ID" ]; then
    echo "Removing app role assignment: $ASSIGNMENT_ID"
    az rest --method DELETE \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments/$ASSIGNMENT_ID"
    echo "App role assignment removed successfully"
else
    echo "No app role assignment found to remove"
fi

# Note: We do NOT remove the app role definition from the Function App's app registration
# because the app registration is manually created and might be reused
echo "App role definition left intact on app registration (manual cleanup required if desired)"
echo "Cleanup completed"
