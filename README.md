# apim-managed-identity-functions-containerapps

## Prerequisites

Before running `azd up`, you must create an Entra ID (Azure AD) app registration for your Azure Function authentication.

### Steps

1. **Create an App Registration**

   - Go to [Azure Portal > Microsoft Entra ID > App registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade).
   - Click **New registration**.
   - Enter a name (e.g., `my-functionapp-auth`).
   - Leave the default account type: **Accounts in this organizational directory only (Single tenant)**.
   - Leave Redirect URI blank.
   - Click **Register**.

2. **Copy the Application (client) ID**

   - After registration, go to the app’s overview page.
   - Copy the **Application (client) ID**.

3. **Run `azd up`**
   - When prompted for the `functionAppAppId` parameter, paste the Application (client) ID you copied above.

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

3. **Test the Azure API Management endpoint**

After deployment, test the API Management endpoint:

```sh
curl "https://$APIM_SERVICE_NAME.azure-api.net/hello-api/hello"
```

Or, if you have the APIM endpoint URL from deployment:

```sh
curl "$helloApiUrl"
```

**Expected Response:** `Hello, world!`

### One-liner for quick testing:

If you are using `azd`, you can fetch the APIM endpoint URL from your environment outputs:

```sh
curl "https://$(azd env get-values | grep apimServiceName | cut -d'=' -f2 | tr -d '"').azure-api.net/hello-api/hello"
```

> **Note:** The APIM endpoint path is `/hello-api/hello`.
