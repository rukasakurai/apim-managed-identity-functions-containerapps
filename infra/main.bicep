// Main orchestration template - supports modular deployment
targetScope = 'resourceGroup'

// Common parameters
@description('The name prefix for all resources')
param resourcePrefix string = 'myapp'

@description('The Azure region where resources will be deployed')
param location string = 'japaneast'

@description('The environment name (dev, test, prod)')
param environmentName string = 'dev'

// APIM parameters
@description('Deploy APIM service')
param deployApim bool = true

@description('Publisher email for API Management service')
param publisherEmail string = ''

@description('Publisher name for API Management service')
param publisherName string = ''

@description('Existing APIM service name (if not deploying new)')
param existingApimServiceName string = ''

// Functions parameters
@description('Deploy Azure Functions')
param deployFunctions bool = true

@description('The clientId of the Entra app registration for the Function App')
param functionAuthAppId string

// Integration parameters
@description('Integrate Functions with APIM')
param integrateFunctionsWithApim bool = true

// WebSocket App parameters
@description('Deploy WebSocket App')
param deployWebsocketApp bool = true

@description('WebSocket application port')
param websocketPort int = 8080

// Variables
var apimServiceName = deployApim ? apimModule.outputs.apimServiceName : existingApimServiceName

// Deploy APIM module
module apimModule 'modules/apim/main.bicep' = if (deployApim) {
  name: 'apim-deployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    environmentName: environmentName
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Deploy Functions module
module functionsModule 'modules/functions/main.bicep' = if (deployFunctions) {
  name: 'functions-deployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    environmentName: environmentName
    functionAuthAppId: functionAuthAppId
  }
}

// Integrate Functions with APIM
module functionsApimIntegration 'modules/apim-backend-integration/main.bicep' = if (integrateFunctionsWithApim && deployFunctions && (deployApim || existingApimServiceName != '')) {
  name: 'functions-apim-integration'
  params: {
    apimServiceName: apimServiceName
    backendType: 'function'
    backendResourceId: functionsModule.outputs.functionAppId
    backendHostname: functionsModule.outputs.functionAppHostName
    backendApiPath: '/api'
    apimApiPath: 'hello-api'
    apiDisplayName: 'Hello Function API'
    backendAppId: functionAuthAppId
    backendName: 'hello-function'
  }
}

// Deploy platform module (provisions Log Analytics workspace)
module platformModule 'modules/platform/main.bicep' = {
  name: 'platform-deployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
  }
}

// Deploy WebSocket App module
module websocketAppModule 'modules/container-apps/main.bicep' = if (deployWebsocketApp) {
  name: 'websocket-app-deployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    environmentName: environmentName
    resourceToken: uniqueString(resourceGroup().id)
    tags: {}
    logAnalyticsWorkspaceCustomerId: platformModule.outputs.logAnalyticsWorkspaceCustomerId
    logAnalyticsWorkspaceSharedKey: platformModule.outputs.logAnalyticsWorkspaceKey
    containerRegistryId: platformModule.outputs.acrResourceId
    containerRegistryName: platformModule.outputs.acrName
    websocketPort: websocketPort
  }
}

// Outputs
@description('APIM Service Name')
output apimServiceName string = deployApim ? apimModule.outputs.apimServiceName : existingApimServiceName

@description('APIM Gateway URL')
output apimGatewayUrl string = deployApim
  ? apimModule.outputs.apimGatewayUrl
  : reference(resourceId('Microsoft.ApiManagement/service', existingApimServiceName), '2024-05-01').properties.gatewayUrl

@description('APIM Service ID')
output apimServiceId string = deployApim
  ? apimModule.outputs.apimServiceId
  : resourceId('Microsoft.ApiManagement/service', existingApimServiceName)

@description('APIM Principal ID')
output apimPrincipalId string = deployApim
  ? apimModule.outputs.apimPrincipalId
  : reference(resourceId('Microsoft.ApiManagement/service', existingApimServiceName), '2024-05-01', 'Full').identity.principalId

@description('Function App Name')
output functionAppName string = deployFunctions ? functionsModule.outputs.functionAppName : ''

@description('Function App Hostname')
output functionAppHostName string = deployFunctions ? functionsModule.outputs.functionAppHostName : ''

@description('Function App ID')
output functionAppId string = deployFunctions ? functionsModule.outputs.functionAppId : ''

@description('Function App Principal ID')
output functionAppPrincipalId string = deployFunctions ? functionsModule.outputs.functionAppPrincipalId : ''

@description('Function API URL through APIM')
output functionApiUrl string = integrateFunctionsWithApim ? functionsApimIntegration.outputs.apiUrl : ''

@description('Storage Account Name')
output storageAccountName string = deployFunctions ? functionsModule.outputs.storageAccountName : ''

@description('Storage Account ID')
output storageAccountId string = deployFunctions ? functionsModule.outputs.storageAccountId : ''

@description('Function Backend Name in APIM')
output functionBackendName string = integrateFunctionsWithApim ? functionsApimIntegration.outputs.backendName : ''

@description('Function API Name in APIM')
output functionApiName string = integrateFunctionsWithApim ? functionsApimIntegration.outputs.apiName : ''

@description('Resource Group ID')
output resourceGroupId string = resourceGroup().id

@description('Function App App ID for Easy Auth')
output functionAuthAppId string = functionAuthAppId

@description('WebSocket App Name')
output websocketAppName string = deployWebsocketApp ? websocketAppModule.outputs.websocketAppName : ''

@description('WebSocket App FQDN')
output websocketAppFqdn string = deployWebsocketApp ? websocketAppModule.outputs.websocketAppFqdn : ''

@description('WebSocket App URL')
output websocketAppUrl string = deployWebsocketApp ? websocketAppModule.outputs.websocketAppUrl : ''

@description('Azure Container Registry endpoint for azd')
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = platformModule.outputs.acrLoginServer

@description('ACR resource id')
output acrResourceId string = platformModule.outputs.acrResourceId
