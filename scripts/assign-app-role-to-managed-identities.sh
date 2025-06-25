#!/bin/bash
# assign-app-role-to-managed-identities.sh
# This script creates app roles and assigns them to managed identities using the Microsoft Graph API v1.0 (stable version)

# Source shared logging configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/logging.sh"

# Parse command line arguments
VERBOSE=false
for arg in "$@"; do
    case $arg in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
    esac
done

log_section "App Role Assignment Script Starting"
log_info "Using Microsoft Graph API v1.0 (stable version)"

# =========================
# SECTION 1: Prerequisites & Variable Checks
# =========================
REQUIRED_VARS=(functionAuthAppId containerAppsAuthAppId apimPrincipalId)
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        log_error "Required variable $VAR is not set. Please export or set it before running this script."
        exit 1
    fi
done

log_info "All required variables are set"

# =========================
# HELPER FUNCTIONS
# =========================

# Function to generate GUID cross-platform
generate_guid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    elif command -v powershell.exe &> /dev/null; then
        powershell.exe -Command "[System.Guid]::NewGuid().ToString()"
    else
        log_error "No GUID generation tool available (uuidgen or PowerShell)"
        log_error "Please ensure either uuidgen is installed or PowerShell is available"
        exit 1
    fi
}

# Function to create app role for a given app registration
create_app_role() {
    local app_id="$1"
    local app_name="$2"
    
    log_info "Processing app role creation for $app_name..."
    
    # Generate a new GUID for the app role
    local app_role_guid
    app_role_guid=$(generate_guid)
    if [ "$VERBOSE" = true ]; then
        log_info "Generated app role GUID: $app_role_guid"
    fi
    
    # Create a temporary app role file from template with the generated GUID
    local temp_approle_file
    temp_approle_file=$(mktemp)
    local template_file="$(dirname "$0")/../infra/app-role.template.json"
    
    # Verify template file exists
    if [ ! -f "$template_file" ]; then
        log_error "Template file not found at: $template_file"
        log_error "Current working directory: $(pwd)"
        log_error "Script location: $(dirname "$0")"
        exit 1
    fi
    
    sed "s/PLACEHOLDER_GUID/$app_role_guid/g" "$template_file" > "$temp_approle_file"
    
    # Check if app role already exists before updating
    local existing_role_id
    existing_role_id=$(az ad sp show --id "$app_id" --query "appRoles[?value=='access_as_application'].id" -o tsv 2>/dev/null)
    
    if [ -n "$existing_role_id" ]; then
        log_warning "App role 'access_as_application' already exists for $app_name. Skipping creation."
        if [ "$VERBOSE" = true ]; then
            log_info "Existing role ID: $existing_role_id"
        fi
    else
        log_info "Creating app role 'access_as_application' for $app_name..."
        az ad app update --id "$app_id" --app-roles @"$temp_approle_file" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "$app_name app role created successfully"
        else
            log_error "Failed to create $app_name app role"
            rm "$temp_approle_file"
            exit 1
        fi
    fi
    
    # Clean up temporary file
    rm "$temp_approle_file"
}

# Function to assign app role to APIM managed identity
assign_app_role_to_apim() {
    local app_id="$1"
    local app_name="$2"
    
    log_info "Processing app role assignment for $app_name..."
    
    # Get the role ID
    local role_id
    role_id=$(az ad sp show --id "$app_id" --query "appRoles[?value=='access_as_application'].id" -o tsv)
    
    if [ -z "$role_id" ]; then
        log_error "Could not find app role 'access_as_application' in the $app_name registration"
        exit 1
    fi
    
    if [ "$VERBOSE" = true ]; then
        log_info "Found $app_name role ID: $role_id"
    fi
    
    # Check if the app role assignment already exists
    local existing_assignment
    existing_assignment=$(az rest --method GET \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments" \
      --query "value[?resourceId=='$(az ad sp show --id $app_id --query id -o tsv)' && appRoleId=='$role_id'].id" \
      -o tsv 2>/dev/null)
    
    if [ -n "$existing_assignment" ]; then
        log_warning "$app_name role assignment already exists. Skipping creation."
        if [ "$VERBOSE" = true ]; then
            log_info "Existing assignment ID: $existing_assignment"
        fi
    else
        log_info "Creating new $app_name role assignment..."
        local assignment_result
        assignment_result=$(az rest --method POST \
          --url "https://graph.microsoft.com/v1.0/servicePrincipals/$apimPrincipalId/appRoleAssignments" \
          --body '{
              "principalId":"'$apimPrincipalId'",
              "resourceId":"'"$(az ad sp show --id $app_id --query id -o tsv)"'",
              "appRoleId":"'$role_id'"
            }' \
          --headers "Content-Type=application/json" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            log_success "$app_name role assignment created successfully"
            if [ "$VERBOSE" = true ]; then
                echo "$assignment_result" | jq '.'
            fi
        else
            log_error "Failed to create $app_name role assignment"
            exit 1
        fi
    fi
}

# =========================
# SECTION 2: Function App Setup
# =========================
log_section "Function App Role Management"
create_app_role "$functionAuthAppId" "Function App"
assign_app_role_to_apim "$functionAuthAppId" "Function App"

# =========================
# SECTION 3: Container App Setup
# =========================
log_section "Container App Role Management"
create_app_role "$containerAppsAuthAppId" "Container App"
assign_app_role_to_apim "$containerAppsAuthAppId" "Container App"

# =========================
# END OF SCRIPT
# =========================
log_section "Script Completed"
log_success "App role assignment process completed successfully"
