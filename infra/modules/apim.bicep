// APIM Module - Independent lifecycle
targetScope = 'resourceGroup'

@description('The name prefix for APIM resources')
param resourcePrefix string = 'myapp'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod)')
param environmentName string = 'dev'

@description('Publisher email for API Management service')
param publisherEmail string

@description('Publisher name for API Management service')
param publisherName string

@description('APIM SKU name')
param skuName string = 'StandardV2'

@description('APIM SKU capacity')
param skuCapacity int = 1

@description('Log Analytics workspace resource ID for APIM diagnostics')
@minLength(1)
param logAnalyticsWorkspaceId string

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceToken = '${resourcePrefix}-${environmentName}-${uniqueSuffix}'
var apimServiceName = '${resourceToken}-apim'

// Tags
var tags = {
  'azd-env-name': environmentName
  environment: environmentName
  project: resourcePrefix
  component: 'apim'
}

// API Management Service (Standard v2)
resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimServiceName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'None'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'true'
    }
  }
}

// NOTE: Using 2021-05-01-preview for diagnosticSettings because we need:
// - logAnalyticsDestinationType = 'Dedicated' for resource-specific tables
// - Newer categories like WebSocketConnectionLogs
// GA (2016-09-01) lacks these capabilities.
resource apimGatewayDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${resourceToken}-apim-gateway-logs'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    // Explicitly route to resource-specific ("Dedicated") tables (e.g. ApiManagementGatewayLogs)
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'WebSocketConnectionLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// APIM Product for backend services
resource backendProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apimService
  name: 'backend-services'
  properties: {
    displayName: 'Backend Services'
    description: 'Product for backend services (Functions, Container Apps, etc.)'
    terms: ''
    subscriptionRequired: false
    state: 'published'
  }
}

// Outputs
@description('The name of the API Management service')
output apimServiceName string = apimService.name

@description('The resource ID of the API Management service')
output apimServiceId string = apimService.id

@description('The principal ID of the APIM managed identity')
output apimPrincipalId string = apimService.identity.principalId

@description('The gateway URL of the API Management service')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('The management API URL of the API Management service')
output apimManagementUrl string = apimService.properties.managementApiUrl

@description('The backend product ID')
output backendProductId string = backendProduct.id
