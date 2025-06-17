# Deployment Scenarios

This repository now supports multiple deployment scenarios to accommodate different lifecycle management needs.

## Architecture Overview

The infrastructure is now modular with the following components:

- **APIM Module** (`infra/modules/apim/`): API Management service that can be deployed independently
- **Functions Module** (`infra/modules/functions/`): Azure Functions that can be deployed independently
- **Container Apps Module** (`infra/modules/container-apps/`): Future support for Container Apps
- **APIM Backend Integration Module** (`infra/modules/apim-backend-integration/`): Connects any backend to APIM

## Deployment Scenarios

### 1. Full Deployment (Default)

Deploy everything together - APIM, Functions, and integration:

```bash
# Standard deployment
azd up

# Or explicitly with parameters
azd provision --parameters deployApim=true deployFunctions=true integrateFunctionsWithApim=true
```

### 2. APIM-Only Deployment

Deploy only the APIM service (useful for platform teams setting up shared infrastructure):

```bash
azd provision --parameters deployApim=true deployFunctions=false integrateFunctionsWithApim=false
```

### 3. Functions with Existing APIM

Deploy Functions and integrate them with an existing APIM service:

```bash
# Set the existing APIM service name
export EXISTING_APIM_NAME="your-existing-apim-service-name"

azd provision --parameters deployApim=false deployFunctions=true integrateFunctionsWithApim=true existingApimServiceName=$EXISTING_APIM_NAME
```

### 4. Functions-Only Deployment

Deploy only the Functions without APIM integration:

```bash
azd provision --parameters deployApim=false deployFunctions=true integrateFunctionsWithApim=false
```

### 5. Integration-Only Deployment

Connect existing Functions to existing APIM (useful for connecting services deployed separately):

```bash
# Requires existing APIM and Functions to be available
azd provision --parameters deployApim=false deployFunctions=false integrateFunctionsWithApim=true existingApimServiceName="your-apim-name"
```

## Module Parameters

### APIM Module Parameters

- `resourcePrefix`: Name prefix for resources
- `location`: Azure region
- `environmentName`: Environment name (dev/test/prod)
- `publisherEmail`: APIM publisher email
- `publisherName`: APIM publisher name
- `skuName`: APIM SKU (default: StandardV2)
- `skuCapacity`: APIM capacity (default: 1)

### Functions Module Parameters

- `resourcePrefix`: Name prefix for resources
- `location`: Azure region
- `environmentName`: Environment name
- `functionAuthAppId`: Entra ID app registration client ID

### APIM Backend Integration Parameters

- `apimServiceName`: Name of the APIM service
- `backendType`: Type of backend (function/containerapp)
- `backendResourceId`: Resource ID of the backend
- `backendHostname`: Hostname of the backend
- `backendApiPath`: API path prefix (default: /api)
- `apimApiPath`: Path in APIM (e.g., hello-api)
- `apiDisplayName`: Display name for the API
- `backendAppId`: Backend app registration ID
- `backendName`: Identifier for the backend

## Future Enhancements

### Container Apps Support

The infrastructure is ready for Container Apps. To add support:

1. Implement authentication for Container Apps
2. Update the main orchestration template to include Container Apps module
3. Create Container Apps-specific deployment scripts

### Example for Container Apps:

```bash
# Future: Deploy Container Apps with APIM
azd provision --parameters deployApim=true deployContainerApps=true integrateContainerAppsWithApim=true
```

## Migration from Monolithic to Modular

To migrate from the old monolithic deployment:

1. **Backup your current deployment**
2. **Deploy new modular APIM**: Use APIM-only deployment
3. **Deploy Functions separately**: Use Functions with existing APIM
4. **Verify functionality**: Test all endpoints
5. **Clean up old resources**: Remove the monolithic deployment

## Best Practices

1. **Platform Teams**: Deploy APIM once, share across teams
2. **Application Teams**: Deploy backends independently, integrate with shared APIM
3. **Environment Separation**: Use different parameter files for dev/test/prod
4. **Resource Naming**: Use consistent naming conventions across modules
5. **Security**: Ensure proper RBAC assignments between APIM and backends
