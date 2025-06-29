# apim-managed-identity-functions-containerapps

> ⚠️ **Warning**: This repository is for demonstration purposes only and should not be considered production-ready. It is designed to showcase concepts and patterns for integrating Azure Functions with API Management using managed identities. Before using any code or configurations in a production environment, please review and adapt them according to your organization's security, compliance, and operational requirements.

> **Note**: Container Apps integration is currently work in progress. The infrastructure modules exist but are not yet integrated into the main deployment pipeline. The current implementation focuses on APIM + Azure Functions integration.

This repository demonstrates how to securely expose Azure Functions and other backends behind Azure API Management (APIM) using managed identities and Microsoft Entra ID authentication. It provides a **modular, lifecycle-aware solution** for:

- **Independent deployment** of APIM and backend services
- **Flexible integration** patterns for connecting backends to shared APIM instances
- **Secure authentication** using Entra ID app registrations and managed identities
- **Automated setup** with infrastructure-as-code (Bicep) and deployment scripts
- **Extensible architecture** ready for future backend types

## Deployment Scenarios

This repository supports multiple deployment patterns. See [DEPLOYMENT-SCENARIOS.md](./docs/DEPLOYMENT-SCENARIOS.md) for detailed scenarios.

## Quick Start

### Create App Registrations for Azure Function Authentication and for Azure Container Apps Authentication

Before running `azd up`, you must create a Microsoft Entra ID app registration for your Azure Function and Azure Container Apps authentication.

1. **Create an App Registration**

   - Go to [Azure Portal > Microsoft Entra ID > App registrations](https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade).
   - Click **New registration**.
   - Enter a name (e.g., `my-functionapp-auth`, `my-containerapp-auth`).
   - Leave the default account type: **Accounts in this organizational directory only (Single tenant)**.
   - Leave Redirect URI blank.
   - Click **Register**.

2. **Configure**: Expose an API → Set Application ID URI to `api://{client-id}`
3. **Copy**: Copy the client ID. When running `azd up`, you will be prompted for it

> **Why needed**: For JWT authentication between APIM and Functions/ContainerApps.

### Provision & Deploy

- **Docker Desktop** must be running before `azd up`
- Verify with: `docker --version`

> **Note**: The websocket-app service requires Docker for containerization. If Docker isn't running, deployment will fail with "Docker daemon is not running" error.

```sh
azd up
```

> **Note**: The `azd up` command typically takes around 5 to 10 minutes to complete, depending on your network speed and the complexity of the resources being provisioned.

### Manually Configure the Azure Container Apps Authentication

The current Bicep deployment does **not** set up a working Easy Auth for Azure Container Apps. You must **delete** any Easy Auth configuration created by the Bicep deployment and manually configure authentication in the Azure Portal.

### Manually Configure Allowed Client Applications for Azure Function Authentication and for Azure Container Apps Authentication

> **Note**: The automation script (`scripts/set-easyauth-allowed-client-applications.sh`) is not working and not included in the azure.yaml, so you must manually configure the **Allowed client applications** for Easy Auth on your Azure Function and Azure Container App. This is required to allow your API Management (APIM) instance (using its managed identity) to call the Azure Function and Azure Container App when Easy Auth is enabled with only allowing requests from specific client applications.

1. **Obtain the Client ID of the APIM Managed Identity**

   - Go to [Azure Portal > API Management > Your APIM instance > Identity](https://portal.azure.com/).
   - Under **System assigned managed identity**, copy the **Object (principal) ID**
   - Go to your Enterprise Application section of Entra and search for the copied Object ID, and get the Client ID

2. **Set Allowed Client Applications in Azure Function Authentication**
   - Go to [Azure Portal > Your Function App / Container App > Authentication](https://portal.azure.com/).
   - Click on your authentication provider (e.g., **Microsoft** under **Identity providers**).
   - Under **Access control** (or **Advanced settings**), find the **Allowed client applications** field.
   - Paste the **Client ID** of your APIM managed identity into the list.
   - Save your changes.

### Test hello-function

#### Test the Azure Function endpoint (should fail):

```sh
curl "https://$(azd env get-values | grep functionAppName | cut -d'=' -f2 | tr -d '"').azurewebsites.net/api/hello"
```

#### Test the Azure API Management endpoint (should work):

```sh
curl "https://$(azd env get-values | grep apimServiceName | cut -d'=' -f2 | tr -d '"').azure-api.net/hello-api/hello"
```

or test from the APIs section of the Azure API Management resource in Azure Portal

### Test websocket-app

Install wscat to test WebSocket connections:

```bash
npm install -g wscat
```

#### Test the Azure Container App endpoint (should fail):

```sh
wscat -c "wss://$(azd env get-values | grep websocketAppFqdn | cut -d'=' -f2 | tr -d '"')"
```

Expected response: `error: Unexpected server response: 401`

#### Test the Azure API Management endpoint (should work):

```sh
wscat -c "https://$(azd env get-values | grep apimServiceName | cut -d'=' -f2 | tr -d '"').azure-api.net/wss"
```

After connecting, enter

```
{"type": "ping", "timestamp": "2024-01-01T12:00:00Z"}
```

## Cleanup

```sh
azd down --force --purge
```

> **Note**: The `azd down --force --purge` command can take about 20 minutes to complete.

## Troubleshooting

If you encounter issues during deployment or testing, please refer to [`troubleshooting.md`](./docs/troubleshooting.md)

## Contributing

We welcome [Issues](../../issues) and [Pull Requests](../../pulls)! No guarantee of acceptance - this is a demo repository. See [Contributing Guidelines](CONTRIBUTING.md).
