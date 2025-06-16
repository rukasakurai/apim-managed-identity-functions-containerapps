# apim-managed-identity-functions-containerapps

> ⚠️ **Warning**: This repository is for demonstration purposes only and should not be considered production-ready. It is designed to showcase concepts and patterns for integrating Azure Functions with API Management using managed identities. Before using any code or configurations in a production environment, please review and adapt them according to your organization's security, compliance, and operational requirements.

This repository demonstrates how to securely expose Azure Functions behind Azure API Management (APIM) using managed identities and Microsoft Entra ID authentication. It provides an end-to-end solution for:

- Deploying an Azure Function (Python) with Bicep infrastructure-as-code
- Integrating API Management (APIM) as a secure gateway to the function
- Enabling authentication using Entra ID app registrations
- Assigning and configuring managed identities and app roles for secure, identity-based access
- Automating setup with scripts for role assignment and Easy Auth configuration

The solution is ideal for scenarios where you want to:

- Protect Azure Functions from direct public access
- Use APIM as a secure, authenticated entry point
- Leverage managed identities for secure, passwordless communication between APIM and Azure Functions
- Automate infrastructure and security configuration with Bicep and scripts

The repository includes all necessary Bicep templates, scripts, and documentation to provision, configure, and test the integration end-to-end.

## Quick Start

### Create App Registration for Azure Function Authentication

Before running `azd up`, you must create a Microsoft Entra ID app registration for your Azure Function authentication.

1. **Create an App Registration**

   - Go to [Azure Portal > Microsoft Entra ID > App registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade).
   - Click **New registration**.
   - Enter a name (e.g., `my-functionapp-auth`).
   - Leave the default account type: **Accounts in this organizational directory only (Single tenant)**.
   - Leave Redirect URI blank.
   - Click **Register**.

2. **Configure**: Expose an API → Set Application ID URI to `api://{client-id}`
3. **Cppy**: Copy the client ID. When running `azd up`, you will be prompted for it

> **Why needed**: For JWT authentication between APIM and Functions.

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

#### Test the Azure Function (should fail):

```sh
curl "https://$(azd env get-values | grep functionAppName | cut -d'=' -f2 | tr -d '"').azurewebsites.net/api/hello"
```

**Expected Response:** Error (Not `Hello, world!`)

#### Test the Azure API Management endpoint (should work):

```sh
curl "https://$(azd env get-values | grep apimServiceName | cut -d'=' -f2 | tr -d '"').azure-api.net/hello-api/hello"
```

or test from the APIs section of the Azure API Management resource in Azure Portal

## Troubleshooting

If you encounter issues during deployment or testing, please refer to [`troubleshooting.md`](./troubleshooting.md)

## Contributing

We welcome [Issues](../../issues) and [Pull Requests](../../pulls)! No guarantee of acceptance - this is a demo repository. See [Contributing Guidelines](CONTRIBUTING.md).
