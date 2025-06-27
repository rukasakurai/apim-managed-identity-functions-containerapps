#!/bin/bash
# set-easyauth-allowed-client-applications.sh
# This script updates both Function App and Container App Easy Auth allowedClientApplications with the APIM managed identity client ID
# The APIM principal ID (object ID) is provided from Bicep output, and this script converts it to the client ID (app ID)
# Updated to use stable Azure REST API versions: Web Apps 2023-12-01, Container Apps 2024-03-01

# Source shared logging configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logging.sh"

log_section "Easy Auth Configuration Script Starting"
log_info "Using Azure REST API stable versions: Web Apps 2023-12-01, Container Apps 2024-03-01"

set -e

# =========================
# SECTION 1: Prerequisites & Dependency Checks
# =========================

# Check for required dependencies
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Please install jq first."
    log_error "Install with: apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    exit 1
fi

log_info "All required dependencies are available"

# Required environment variables:
#   AZURE_RESOURCE_GROUP - the resource group name
#   functionAppName      - the Function App resource name (required)
#   websocketAppName     - the Container App resource name (required)
#   apimPrincipalId      - the APIM managed identity principal ID (from Bicep output)

REQUIRED_VARS=(AZURE_RESOURCE_GROUP functionAppName websocketAppName apimPrincipalId)
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        log_error "Required variable $VAR is not set. Please export or set it before running this script."
        if [ "$VAR" = "apimPrincipalId" ]; then
            log_error "This should be the principal ID (object ID) from the APIM Bicep output."
        fi
        exit 1
    fi
done

log_info "All required environment variables are set"

# =========================
# SECTION 2: APIM Client ID Resolution
# =========================
log_section "APIM Client ID Resolution"

log_info "APIM principal ID: $apimPrincipalId"

# Get APIM clientId (appId of service principal) from the provided principal ID
log_info "Getting APIM client ID from principal ID..."
APIM_CLIENT_ID=$(az ad sp show --id "$apimPrincipalId" --query appId -o tsv)

if [ -z "$APIM_CLIENT_ID" ]; then
  log_error "Could not retrieve APIM client ID"
  log_error "Principal ID: $apimPrincipalId"
  exit 1
fi

log_success "APIM clientId resolved: $APIM_CLIENT_ID"

# Get subscription ID (used by both functions)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
log_info "Using subscription: $SUBSCRIPTION_ID"

# =========================
# HELPER FUNCTIONS
# =========================

# Function to check if a resource exists
check_resource_exists() {
  local resource_name="$1"
  local resource_type="$2"
  local resource_group="$3"
  
  log_info "Verifying $resource_type exists..."
  local exists=$(az resource show \
    --resource-group "$resource_group" \
    --name "$resource_name" \
    --resource-type "$resource_type" \
    --query "name" -o tsv 2>/dev/null || echo "")
      if [ -z "$exists" ]; then
    log_error "$resource_type '$resource_name' not found in resource group '$resource_group'"
    return 1
  fi
  
  log_success "$resource_type verified: $exists"
  return 0
}

# =========================
# SECTION 3: Function App Easy Auth Configuration
# =========================

# Function to update Function App Easy Auth allowed client applications
update_function_app_auth() {
  local app_name="$1"
  local resource_group="$2"
  local client_id="$3"
  local subscription_id="$4"
  
  log_section "Updating Function App: $app_name"
  
  # Check if Function App exists
  if ! check_resource_exists "$app_name" "Microsoft.Web/sites" "$resource_group"; then
    return 1
  fi
  
  # Check if Easy Auth is enabled
  log_info "Checking Easy Auth status..."
  local auth_enabled=$(az webapp auth show \
    --name "$app_name" \
    --resource-group "$resource_group" \
    --query "enabled" -o tsv 2>/dev/null || echo "false")
  
  if [ "$auth_enabled" != "true" ]; then
    log_error "Easy Auth is not enabled for Function App '$app_name'"
    log_error "Please enable Easy Auth first before running this script"
    return 1
  fi
  
  log_success "Easy Auth is enabled"
  
  # Check if Azure AD provider is configured
  log_info "Checking Azure AD provider configuration..."
  local aad_provider_enabled=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.Web/sites/$app_name/config/authsettingsV2?api-version=2023-12-01" \
    --query "properties.identityProviders.azureActiveDirectory.enabled" -o tsv 2>/dev/null || echo "false")
  
  if [ "$aad_provider_enabled" != "true" ]; then
    log_error "Azure Active Directory provider is not enabled for Function App '$app_name'"
    log_error "Please configure Azure AD authentication first"
    return 1
  fi
  
  log_success "Azure AD provider is enabled"
  
  # Create backup of current configuration
  log_info "Creating configuration backup..."
  local backup_config=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.Web/sites/$app_name/config/authsettingsV2?api-version=2023-12-01")
    log_success "Configuration backed up successfully"
  
  # Update allowed client applications
  if update_allowed_client_applications "$backup_config" "$client_id" "$app_name" "$resource_group" "$subscription_id" "function"; then
    log_success "Successfully updated Function App '$app_name'"
    return 0
  else
    log_error "Failed to update Function App '$app_name'"
    return 1
  fi
}

# =========================
# SECTION 4: Container App Easy Auth Configuration
# =========================

# Function to update Container App Easy Auth allowed client applications
update_container_app_auth() {
  local app_name="$1"
  local resource_group="$2"
  local client_id="$3"
  local subscription_id="$4"
  
  log_section "Updating Container App: $app_name"
  
  # Check if Container App exists
  if ! check_resource_exists "$app_name" "Microsoft.App/containerApps" "$resource_group"; then
    return 1
  fi
    log_info "Checking Container App authentication configuration..."
  
  # Get Container App auth configuration with better error handling
  log_info "Fetching authentication configuration..."
  local auth_config_raw=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.App/containerApps/$app_name/authConfigs/current?api-version=2024-03-01" 2>&1)
  
  if [ $? -ne 0 ]; then
    log_error "Failed to retrieve authentication configuration"
    log_error "Error: $auth_config_raw"
    return 1
  fi
  
  local auth_config="$auth_config_raw"
  
  # Debug: Show the full auth config structure (first 50 lines)
  log_info "Debug: Full authentication configuration structure:"
  echo "$auth_config" | jq '.' | head -50
    # Check if authentication is enabled
  local auth_enabled=$(echo "$auth_config" | jq -r '.properties.platform.enabled // false')
  local auth_platform_exists=$(echo "$auth_config" | jq -r '.properties.platform // empty')
  
  # Debug: Show platform configuration
  log_info "Debug: Platform configuration:"
  echo "$auth_config" | jq '.properties.platform // {}'
  
  if [ "$auth_enabled" != "true" ] && [ -z "$auth_platform_exists" ]; then
    log_error "Authentication is not enabled for Container App '$app_name'"
    log_error "Please enable authentication first before running this script"
    log_info "Current platform config:"
    echo "$auth_config" | jq '.properties.platform // {}'
    return 1
  fi
  
  log_success "Authentication platform is configured"
    # Check if Azure AD provider is configured
  log_info "Checking Azure AD provider configuration..."
  
  # Container Apps may have different structure - check multiple possible paths
  local aad_provider_enabled=$(echo "$auth_config" | jq -r '.properties.identityProviders.azureActiveDirectory.enabled // false')
  local aad_registration_exists=$(echo "$auth_config" | jq -r '.properties.identityProviders.azureActiveDirectory.registration.clientId // empty')
  
  # Debug: Log the actual auth config structure for troubleshooting
  log_info "Debug: Auth config structure for Azure AD provider:"
  echo "$auth_config" | jq '.properties.identityProviders.azureActiveDirectory // {}' | head -20
    # Check if AAD is configured (either enabled=true OR registration exists)
  if [ "$aad_provider_enabled" != "true" ] && [ -z "$aad_registration_exists" ]; then
    log_error "Azure Active Directory provider is not properly configured for Container App '$app_name'"
    log_error "Either enabled should be true or registration.clientId should exist"
    log_info "Current AAD provider config:"
    echo "$auth_config" | jq '.properties.identityProviders.azureActiveDirectory // {}'
    log_info "Please ensure Azure AD authentication is properly configured for the Container App"
    return 1
  fi
  
  # Log what we found
  if [ "$aad_provider_enabled" = "true" ]; then
    log_success "Azure AD provider is enabled"
  elif [ -n "$aad_registration_exists" ]; then
    log_success "Azure AD provider registration found (clientId: ${aad_registration_exists:0:8}...)"
  fi
  
  log_success "Azure AD provider is enabled"
  log_info "Configuration backed up successfully"
  
  # Update allowed client applications for Container App
  if update_allowed_client_applications_container_app "$auth_config" "$client_id" "$app_name" "$resource_group" "$subscription_id"; then
    log_success "Successfully updated Container App '$app_name'"
    return 0
  else
    log_error "Failed to update Container App '$app_name'"
    return 1
  fi
}

# =========================
# SECTION 5: Client Application Update Utilities
# =========================

# Common function to update allowed client applications for Function Apps
update_allowed_client_applications() {
  local backup_config="$1"
  local client_id="$2"
  local app_name="$3"
  local resource_group="$4"
  local subscription_id="$5"
  local app_type="$6"
  
  log_info "Checking existing allowedClientApplications..."
  
  # Get existing allowed client applications
  local existing_clients=$(echo "$backup_config" | jq -r '.properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications // []')
  
  log_info "Existing allowed client applications: $existing_clients"
  
  # Check if client ID is already in the list
  if echo "$existing_clients" | jq -e --arg client_id "$client_id" 'index($client_id)' > /dev/null; then
    log_warning "Client ID '$client_id' is already in allowedClientApplications list"
    log_info "No update needed"
    return 0
  fi
  
  log_info "Adding client ID to allowedClientApplications..."
  
  # Merge client ID with existing clients (avoid duplicates)
  local updated_clients=$(echo "$existing_clients" | jq --arg client_id "$client_id" '. + [$client_id] | unique')
  
  log_info "Updated allowed client applications: $updated_clients"
  
  # Update the configuration with merged client list
  local updated_config=$(echo "$backup_config" | jq --argjson clients "$updated_clients" '.properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications = $clients')
  
  # Apply the update using REST API
  log_info "Applying configuration update..."
  local update_result=$(az rest \
    --method PUT \
    --url "https://management.azure.com/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.Web/sites/$app_name/config/authsettingsV2?api-version=2023-12-01" \
    --body "$updated_config" 2>&1)
  
  if [ $? -eq 0 ]; then
    log_success "Successfully updated allowedClientApplications for $app_name"
    
    # Verify the update
    log_info "Verifying configuration update..."
    local verification=$(az rest \
      --method GET \
      --url "https://management.azure.com/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.Web/sites/$app_name/config/authsettingsV2?api-version=2023-12-01" \
      --query "properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications" -o json)
    
    if echo "$verification" | jq -e --arg client_id "$client_id" 'index($client_id)' > /dev/null; then
      log_success "Verification successful: Client ID is present in allowedClientApplications"
      return 0
    else
      log_warning "Verification failed: Client ID not found in updated configuration"
      log_info "Current allowedClientApplications: $verification"
      return 1
    fi
  else
    log_error "Failed to update allowedClientApplications"
    log_error "Error details: $update_result"
    log_info "Configuration backup is available for manual restoration if needed"
    return 1
  fi
}

# Function to update allowed client applications for Container Apps
update_allowed_client_applications_container_app() {
  local auth_config="$1"
  local client_id="$2"
  local app_name="$3"
  local resource_group="$4"
  local subscription_id="$5"
  
  log_info "Checking existing allowedClientApplications..."
  
  # Get existing allowed client applications
  local existing_clients=$(echo "$auth_config" | jq -r '.properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications // []')
  
  log_info "Existing allowed client applications: $existing_clients"
  
  # Check if client ID is already in the list
  if echo "$existing_clients" | jq -e --arg client_id "$client_id" 'index($client_id)' > /dev/null; then
    log_warning "Client ID '$client_id' is already in allowedClientApplications list"
    log_info "No update needed"
    return 0
  fi
  
  log_info "Adding client ID to allowedClientApplications..."
  
  # Merge client ID with existing clients (avoid duplicates)
  local updated_clients=$(echo "$existing_clients" | jq --arg client_id "$client_id" '. + [$client_id] | unique')
  
  log_info "Updated allowed client applications: $updated_clients"
  
  # Update the configuration with merged client list
  local updated_config=$(echo "$auth_config" | jq --argjson clients "$updated_clients" '.properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications = $clients')
  
  # Apply the update using REST API
  log_info "Applying configuration update..."
  local update_result=$(az rest \
    --method PUT \
    --url "https://management.azure.com/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.App/containerApps/$app_name/authConfigs/current?api-version=2024-03-01" \
    --body "$updated_config" 2>&1)
  
  if [ $? -eq 0 ]; then
    log_success "Successfully updated allowedClientApplications for $app_name"
    
    # Verify the update
    log_info "Verifying configuration update..."
    local verification=$(az rest \
      --method GET \
      --url "https://management.azure.com/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.App/containerApps/$app_name/authConfigs/current?api-version=2024-03-01" \
      --query "properties.identityProviders.azureActiveDirectory.validation.jwtClaimChecks.allowedClientApplications" -o json)
    
    if echo "$verification" | jq -e --arg client_id "$client_id" 'index($client_id)' > /dev/null; then
      log_success "Verification successful: Client ID is present in allowedClientApplications"
      return 0
    else
      log_warning "Verification failed: Client ID not found in updated configuration"
      log_info "Current allowedClientApplications: $verification"
      return 1
    fi
  else
    log_error "Failed to update allowedClientApplications"
    log_error "Error details: $update_result"
    log_info "Configuration backup is available for manual restoration if needed"
    return 1
  fi
}

# =========================
# SECTION 6: Function App Configuration Update
# =========================

# Initialize counters
SUCCESS_COUNT=0
TOTAL_COUNT=2  # Both Function App and Container App are required

log_section "Function App Easy Auth Update"

# Update Function App (required)
if update_function_app_auth "$functionAppName" "$AZURE_RESOURCE_GROUP" "$APIM_CLIENT_ID" "$SUBSCRIPTION_ID"; then
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
fi

# =========================
# SECTION 7: Container App Configuration Update
# =========================

log_section "Container App Easy Auth Update"

# Update Container App (required)
if update_container_app_auth "$websocketAppName" "$AZURE_RESOURCE_GROUP" "$APIM_CLIENT_ID" "$SUBSCRIPTION_ID"; then
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
fi

# =========================
# SECTION 8: Summary & Completion
# =========================
log_section "Configuration Update Summary"
log_info "Total apps processed: $TOTAL_COUNT"
log_info "Successfully updated: $SUCCESS_COUNT"
log_info "Failed updates: $((TOTAL_COUNT - SUCCESS_COUNT))"

if [ $SUCCESS_COUNT -eq $TOTAL_COUNT ]; then
  log_success "Both applications updated successfully!"
  log_success "APIM client ID '$APIM_CLIENT_ID' has been added to allowedClientApplications for:"
  log_info "  - Function App: $functionAppName"
  log_info "  - Container App: $websocketAppName"
  exit 0
else
  log_error "Some applications failed to update. Please check the error messages above."
  log_info "Function App: $functionAppName"
  log_info "Container App: $websocketAppName"
  exit 1
fi

# =========================
# END OF SCRIPT
# =========================
