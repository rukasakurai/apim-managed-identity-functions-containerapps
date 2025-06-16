# apim-managed-identity-functions-containerapps

> ⚠️ **Warning**: This repository is for demonstration purposes only and should not be considered production-ready. It is designed to showcase concepts and patterns for integrating Azure Functions with API Management using managed identities. Before using any code or configurations in a production environment, please review and adapt them according to your organization's security, compliance, and operational requirements.

This repository demonstrates how to securely expose Azure Functions and other backends behind Azure API Management (APIM) using managed identities and Microsoft Entra ID authentication. It provides a **modular, lifecycle-aware solution** for:

- **Independent deployment** of APIM and backend services (Azure Functions, Container Apps)
- **Flexible integration** patterns for connecting backends to shared APIM instances
- **Secure authentication** using Entra ID app registrations and managed identities
- **Automated setup** with infrastructure-as-code (Bicep) and deployment scripts
- **Extensible architecture** ready for future backend types

## Architecture Overview

The solution uses a **modular approach** that separates concerns and supports independent lifecycle management:

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   APIM Module       │    │  Functions Module   │    │ Container Apps      │
│   (Platform Team)   │    │  (App Team A)       │    │ (App Team B)        │
│                     │    │                     │    │                     │
│ • Gateway           │    │ • Function App      │    │ • Container App     │
│ • Policies          │    │ • Storage Account   │    │ • Environment       │
│ • Products          │    │ • App Service Plan  │    │ • Log Analytics     │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
           │                           │                           │
           └───────────────────────────┼───────────────────────────┘
                                       │
                    ┌─────────────────────┐
                    │ APIM Integration    │
                    │ Module              │
                    │                     │
                    │ • Backend Config    │
                    │ • API Definitions   │
                    │ • Auth Policies     │
                    └─────────────────────┘
```

### Key Benefits

- **Independent Lifecycles**: APIM and backends can be deployed, updated, and managed separately
- **Team Autonomy**: Platform teams manage APIM, application teams manage their backends
- **Reusability**: Single APIM instance can serve multiple backend services
- **Extensibility**: Easy to add new backend types (Container Apps, AKS, etc.)
- **Flexibility**: Support various deployment scenarios

The solution is ideal for scenarios where you want to:

- **Share APIM across teams/projects** while maintaining backend independence
- **Scale backend services independently** without affecting the API gateway
- **Use different deployment cadences** for platform vs. application components
- **Support multiple backend technologies** behind a unified API gateway
- **Implement enterprise API governance** with centralized APIM management

## Deployment Scenarios

This repository supports multiple deployment patterns. See [DEPLOYMENT-SCENARIOS.md](./DEPLOYMENT-SCENARIOS.md) for detailed scenarios.

### Quick Examples

#### 1. Full Deployment (Default)

```bash
azd up
```

#### 2. APIM-Only (Platform Setup)

```bash
azd provision --parameters deployApim=true deployFunctions=false integrateFunctionsWithApim=false
```

#### 3. Functions with Existing APIM

```bash
azd provision --parameters deployApim=false deployFunctions=true integrateFunctionsWithApim=true existingApimServiceName="your-apim-name"
```

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
