// Main Bicep template for Azure Function (Flex Consumption) and API Management (Standard v2)
// Target deployment scope
targetScope = 'resourceGroup'

// Parameters
@description('The name prefix for all resources')
param resourcePrefix string = 'myapp'

@description('The Azure region where resources will be deployed')
param location string = 'japaneast'

@description('The environment name (dev, test, prod)')
param environmentName string = 'dev'

@description('Publisher email for API Management service')
param publisherEmail string

@description('Publisher name for API Management service')
param publisherName string

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceToken = '${resourcePrefix}-${environmentName}-${uniqueSuffix}'

// Resource names
var functionAppName = '${resourceToken}-func'
var hostingPlanName = '${resourceToken}-plan'
var storageAccountName = replace('${resourceToken}storage', '-', '')
var apimServiceName = '${resourceToken}-apim'

// Tags
var tags = {
  'azd-env-name': environmentName
  environment: environmentName
  project: resourcePrefix
}

// Storage Account for Azure Function
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
  }
}

// Blob container for function app deployments
resource deploymentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/deployments'
  properties: {
    publicAccess: 'None'
  }
}

// App Service Plan (Flex Consumption)
resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true // Required for Linux (Python runtime)
  }
}

// Azure Function App (Python on Flex Consumption)
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'function'
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    reserved: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deployments'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'AzureWebJobsStorage'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.11'
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

// API Management Service (Standard v2)
resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimServiceName
  location: location
  tags: union(tags, {
    'azd-service-name': 'apim'
  })
  sku: {
    name: 'StandardV2'
    capacity: 1
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

// Outputs
@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The hostname of the Function App')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The resource ID of the Function App')
output functionAppId string = functionApp.id

@description('The principal ID of the Function App system-assigned managed identity')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('The name of the API Management service')
output apimServiceName string = apimService.name

@description('The gateway URL of the API Management service')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('The management API URL of the API Management service')
output apimManagementUrl string = apimService.properties.managementApiUrl

@description('The resource ID of the API Management service')
output apimServiceId string = apimService.id

@description('The principal ID of the API Management system-assigned managed identity')
output apimPrincipalId string = apimService.identity.principalId

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id
