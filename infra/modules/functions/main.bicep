// Azure Functions Module - Independent lifecycle
targetScope = 'resourceGroup'

@description('The name prefix for Function resources')
param resourcePrefix string = 'myapp'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod)')
param environmentName string = 'dev'

@description('The clientId of the Entra app registration for the Function App')
param functionAppAppId string

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceToken = '${resourcePrefix}-${environmentName}-${uniqueSuffix}'

// Resource names
var functionAppName = '${resourceToken}-func'
var hostingPlanName = '${resourceToken}-plan'
var storageAccountName = replace('${resourceToken}storage', '-', '')

// Tags
var tags = {
  'azd-env-name': environmentName
  environment: environmentName
  project: resourcePrefix
  component: 'functions'
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
    reserved: true
  }
}

// Azure Function App
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

// Authentication settings for the Function App
resource funcAuth 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: functionApp
  name: 'authsettingsV2'
  properties: {
    globalValidation: {
      requireAuthentication: true
    }
    platform: {
      enabled: true
    }
    identityProviders: {
      azureActiveDirectory: {
        registration: {
          clientId: functionAppAppId
          openIdIssuer: 'https://sts.windows.net/${tenant().tenantId}/'
        }
        validation: {
          allowedAudiences: [
            '${functionAppAppId}'
          ]
        }
      }
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

@description('The principal ID of the Function App managed identity')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The storage account name')
output storageAccountName string = storageAccount.name

@description('The storage account resource ID')
output storageAccountId string = storageAccount.id
