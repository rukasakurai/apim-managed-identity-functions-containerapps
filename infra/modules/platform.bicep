// Provision Log Analytics workspace for monitoring
@description('The name prefix for all resources')
param resourcePrefix string

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

var logAnalyticsWorkspaceName = '${take(resourcePrefix, 20)}-log-${uniqueString(resourceGroup().id)}'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Provision Azure Container Registry (ACR)
var acrName = toLower(replace('${take(resourcePrefix, 20)}acr${uniqueString(resourceGroup().id)}', '-', ''))

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    // Enable admin user for development or troubleshooting only. Disable in production for better security.
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// Outputs for use by other modules
@description('Log Analytics workspace resource id')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('Log Analytics workspace customer id (GUID)')
output logAnalyticsWorkspaceCustomerId string = logAnalytics.properties.customerId

@description('Log Analytics workspace shared key')
@secure()
output logAnalyticsWorkspaceKey string = logAnalytics.listKeys().primarySharedKey

@description('ACR login server')
output acrLoginServer string = containerRegistry.properties.loginServer

@description('ACR resource id')
output acrResourceId string = containerRegistry.id

@description('ACR name')
output acrName string = containerRegistry.name
