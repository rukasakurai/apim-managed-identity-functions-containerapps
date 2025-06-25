#!/bin/bash
# This script removes app role assignments using the Microsoft Graph API v1.0 (stable version)

# Source shared logging configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logging.sh"

log_section "App Role Cleanup Script Starting"

# Check if required environment variables are set
if [ -z "$functionAuthAppId" ]; then
    log_warning "functionAuthAppId not set. Skipping app role cleanup."
    exit 0
fi

if [ -z "$apimPrincipalId" ]; then
    log_warning "apimPrincipalId not set. Skipping app role assignment cleanup."
    exit 0
fi

log_info "Cleaning up app role assignments for APIM managed identity..."

# Get the app role assignment ID
log_info "Getting app role assignment ID..."
ASSIGNMENT_ID=$(az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments" \
  --query "value[?resourceId=='$(az ad sp show --id $functionAuthAppId --query id -o tsv)'].id" \
  -o tsv 2>/dev/null)

# Delete the app role assignment if it exists
if [ -n "$ASSIGNMENT_ID" ]; then
    log_info "Removing app role assignment: $ASSIGNMENT_ID"
    az rest --method DELETE \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments/$ASSIGNMENT_ID"
    log_success "App role assignment removed successfully"
else
    log_info "No app role assignment found to remove"
fi

# Note: We do NOT remove the app role definition from the Function App's app registration
# because the app registration is manually created and might be reused
echo "App role definition left intact on app registration (manual cleanup required if desired)"
echo "Cleanup completed"
