#!/bin/bash
# This script creates app roles and assigns them using the Microsoft Graph API v1.0 (stable version)
echo "Running assign-apim-mi-to-functionapp-app-role.sh script..."

# Generate a new GUID for the app role (cross-platform compatible)
if command -v uuidgen &> /dev/null; then
    # Linux/macOS
    APP_ROLE_GUID=$(uuidgen)
elif command -v powershell.exe &> /dev/null; then
    # Windows with PowerShell
    APP_ROLE_GUID=$(powershell.exe -Command "[System.Guid]::NewGuid().ToString()")
else
    # No GUID generation tool available
    echo "ERROR: No GUID generation tool available (uuidgen or PowerShell)"
    echo "Please ensure either uuidgen is installed or PowerShell is available"
    exit 1
fi

echo "Generated app role GUID: $APP_ROLE_GUID"

# Create a temporary app role file from template with the generated GUID
# The template contains PLACEHOLDER_GUID which gets substituted with a real GUID
TEMP_APPROLE_FILE=$(mktemp)
TEMPLATE_FILE="$(dirname "$0")/../infra/function-app-roles.template.json"

# Verify template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "ERROR: Template file not found at: $TEMPLATE_FILE"
    echo "Current working directory: $(pwd)"
    echo "Script location: $(dirname "$0")"
    exit 1
fi

sed "s/PLACEHOLDER_GUID/$APP_ROLE_GUID/g" "$TEMPLATE_FILE" > "$TEMP_APPROLE_FILE"

# Check if app role already exists before updating
EXISTING_ROLE_ID=$(az ad sp show --id $functionAuthAppId --query "appRoles[?value=='access_as_application'].id" -o tsv 2>/dev/null)

if [ -n "$EXISTING_ROLE_ID" ]; then
    echo "App role 'access_as_application' already exists (ID: $EXISTING_ROLE_ID). Skipping app role creation."
else    echo "Creating app role 'access_as_application'..."
    az ad app update --id "$functionAuthAppId"  --app-roles @"$TEMP_APPROLE_FILE"
    
    if [ $? -eq 0 ]; then
        echo "App role created successfully"
    else
        echo "ERROR: Failed to create app role"
        rm "$TEMP_APPROLE_FILE"
        exit 1
    fi
fi

# Clean up temporary file
rm "$TEMP_APPROLE_FILE"

ROLE_ID=$(az ad sp show --id $functionAuthAppId --query "appRoles[?value=='access_as_application'].id" -o tsv)

if [ -z "$ROLE_ID" ]; then
    echo "ERROR: Could not find app role 'access_as_application' in the app registration"
    exit 1
fi

echo "Found app role ID: $ROLE_ID"

# Check if the app role assignment already exists
EXISTING_ASSIGNMENT=$(az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments" \
  --query "value[?resourceId=='$(az ad sp show --id $functionAuthAppId --query id -o tsv)' && appRoleId=='$ROLE_ID'].id" \
  -o tsv 2>/dev/null)

if [ -n "$EXISTING_ASSIGNMENT" ]; then
    echo "App role assignment already exists (ID: $EXISTING_ASSIGNMENT). Skipping creation."
else    echo "Creating new app role assignment..."    # Create the assignment with Microsoft Graph via az rest
    az rest --method POST \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments" \      --body '{
          "principalId":"'$apimPrincipalId'",
          "resourceId":"'"$(az ad sp show --id $functionAuthAppId --query id -o tsv)"'",
          "appRoleId":"'$ROLE_ID'"
        }' \
      --headers "Content-Type=application/json"
    
    if [ $? -eq 0 ]; then
        echo "App role assignment created successfully"
    else
        echo "ERROR: Failed to create app role assignment"
        exit 1
    fi
fi

echo "App role assignment process completed"
