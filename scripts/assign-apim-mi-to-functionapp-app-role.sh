echo "Running assign-apim-mi-to-functionapp-app-role.sh script..."

az ad app update --id "$FUNC_EASYAUTH_APP_ID"  --app-roles @approle.json

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
