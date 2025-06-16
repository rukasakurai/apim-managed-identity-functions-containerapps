# apim-managed-identity-functions-containerapps

## Quick Start

### Create App Registration for Azure Function Authentication

Before running `azd up`, you must create an Entra ID (Azure AD) app registration for your Azure Function authentication.

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

### Provision & Deploy

```sh
azd up
```

### Manually Configure Allowed Client Applications for Azure Functions Authentication

If the automation script (`scripts/set-easyauth-allowed-client-applications.sh`) is not working, you can manually configure the **Allowed client applications** for Azure App Service Authentication (Easy Auth) on your Azure Function. This is required to allow your API Management (APIM) instance (using its managed identity) to call the Azure Function when App Service Authentication is enabled.

1. **Obtain the Client ID of the APIM Managed Identity**

   - Go to [Azure Portal > API Management > Your APIM instance > Identity](https://portal.azure.com/).
   - Under **System assigned managed identity** or **User assigned managed identities**, copy the **Object (principal) ID**
   - Go to your Enterprise Application section of Entra and search for the copied Object ID, and get the Client ID

2. **Set Allowed Client Applications in Azure Function Authentication**
   - Go to [Azure Portal > Function App > Your Function App > Authentication](https://portal.azure.com/).
   - Click on your authentication provider (e.g., **Microsoft** under **Identity providers**).
   - Under **Access control** (or **Advanced settings**), find the **Allowed client applications** field.
   - Paste the **Client ID** of your APIM managed identity into the list.
   - Save your changes.

### Test

#### Test the Azure Function

After deployment, test the function:

```sh
curl "https://$FUNCTION_APP_NAME.azurewebsites.net/api/hello?code=$MASTER_KEY"
```

or

```sh
curl "https://$(azd env get-values | grep "functionAppName" | cut -d'=' -f2 | tr -d '"').azurewebsites.net/api/hello"
```

**Expected Response:** Error (Not `Hello, world!`)

#### Test the Azure API Management endpoint

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
