# apim-managed-identity-functions-containerapps

## Quick Start

1. **Provision & Deploy**

```sh
azd up
```

2. **Test the Azure Function**

After deployment, test the function:

```sh
curl "https://$FUNCTION_APP_NAME.azurewebsites.net/api/hello?code=$MASTER_KEY"
```

**Expected Response:** `Hello, world!`

### One-liner for quick testing:

```sh
curl "https://$(azd env get-values | grep "functionAppName" | cut -d'=' -f2 | tr -d '"').azurewebsites.net/api/hello?code=$(az functionapp keys list --name $(azd env get-values | grep "functionAppName" | cut -d'=' -f2 | tr -d '"') --resource-group $(azd env get-values | grep "AZURE_RESOURCE_GROUP" | cut -d'=' -f2 | tr -d '"') --query "masterKey" -o tsv)"
```
