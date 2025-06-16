echo "Running assign-apim-mi-to-functionapp-app-role.sh script..."

# Generate a new GUID for the app role
APP_ROLE_GUID=$(uuidgen)
echo "Generated app role GUID: $APP_ROLE_GUID"

# Create a temporary app role file from template with the generated GUID
# The template contains PLACEHOLDER_GUID which gets substituted with a real GUID
TEMP_APPROLE_FILE=$(mktemp)
TEMPLATE_FILE="../infra/function-app-roles.template.json"
sed "s/PLACEHOLDER_GUID/$APP_ROLE_GUID/g" "$TEMPLATE_FILE" > "$TEMP_APPROLE_FILE"

az ad app update --id "$FUNC_EASYAUTH_APP_ID"  --app-roles @"$TEMP_APPROLE_FILE"

# Clean up temporary file
rm "$TEMP_APPROLE_FILE"

ROLE_ID=$(az ad sp show --id $FUNC_EASYAUTH_APP_ID --query "appRoles[?value=='access_as_application'].id" -o tsv)

# create the assignment with Microsoft Graph via az rest
az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$APIM_MI_CLIENTID/appRoleAssignments" \
  --body '{
      "principalId":"'$APIM_MI_CLIENTID'",
      "resourceId":"'"$(az ad sp show --id $FUNC_EASYAUTH_APP_ID --query id -o tsv)"'",
      "appRoleId":"'$ROLE_ID'"
    }' \
  --headers "Content-Type=application/json"
