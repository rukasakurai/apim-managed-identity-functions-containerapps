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

@description('The clientId of the Entra app registration for the Function App')
param functionAppAppId string

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
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          // value: appInsights.properties.InstrumentationKey
          // Application Insights is commented out
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          // value: appInsights.properties.ConnectionString
          // Application Insights is commented out
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          // value: '~3'
          // Application Insights is commented out
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
  dependsOn: [
    // appInsights // Application Insights is commented out
    // hostingPlan // Removed unnecessary dependsOn
    // storageAccount // Removed unnecessary dependsOn
  ]
}

// Authentication settings for the Function App (Entra app registration)
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
          // jwtClaimChecks.allowedClientApplications will be set post-provision
        }
      }
    }
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

// Role assignment to allow APIM to invoke Functions using managed identity
resource apimToFunctionRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: functionApp
  name: guid(functionApp.id, apimService.id, 'Website Contributor')
  properties: {
    principalId: apimService.identity.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'de139f84-1756-47ae-9be6-808fbbe84772'
    ) // Website Contributor role
    principalType: 'ServicePrincipal'
  }
}

// Backend configuration for the Azure Function
resource functionBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apimService
  name: 'function-backend'
  properties: {
    description: 'Backend for Azure Function App'
    url: 'https://${functionApp.properties.defaultHostName}/api'
    protocol: 'http'
    resourceId: '${environment().resourceManager}${functionApp.id}'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
  dependsOn: [
    apimToFunctionRoleAssignment
  ]
}

// API definition for the Function App
resource functionApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apimService
  name: 'hello-function-api'
  properties: {
    displayName: 'Hello Function API'
    description: 'API for Azure Function hello world endpoint'
    serviceUrl: 'https://${functionApp.properties.defaultHostName}/api'
    path: 'hello-api'
    protocols: ['https']
    subscriptionRequired: false // Disable subscription key requirement
    apiType: 'http'
  }
}

// Operation for the hello endpoint
resource helloOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: functionApi
  name: 'hello-get'
  properties: {
    displayName: 'Get Hello World'
    method: 'GET'
    urlTemplate: '/hello'
    description: 'Returns hello world message from Azure Function'
    responses: [
      {
        statusCode: 200
        description: 'Success'
        representations: [
          {
            contentType: 'text/plain'
          }
        ]
      }
    ]
  }
}

// Policy for the hello operation to use the function backend
resource helloOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: helloOperation
  name: 'policy'
  properties: {
    value: '<policies>\n  <inbound>\n    <authentication-managed-identity resource="api://${functionAppAppId}" output-token-variable-name="accessToken" />\n    <set-header name="Authorization" exists-action="override">\n      <value>@("Bearer " + context.Variables["accessToken"])</value>\n    </set-header>\n    <set-backend-service backend-id="function-backend" />\n  </inbound>\n  <backend><base /></backend>\n  <outbound><base /></outbound>\n  <on-error><base /></on-error>\n</policies>'
  }
  dependsOn: [
    functionBackend
  ]
}

// API Management Product for publishing the API (open access, no subscription required)
resource apimProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apimService
  name: 'open-product'
  properties: {
    displayName: 'Open Product'
    description: 'Product for public/open APIs (no subscription required)'
    terms: ''
    subscriptionRequired: false
    state: 'published'
  }
}

// Add the API to the product (correct parent and name)
resource apiProduct 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: apimProduct
  name: functionApi.name
}

// Application Insights for monitoring
/*
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourceToken}-ai'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    WorkspaceResourceId: '' // Not using Log Analytics workspace
  }
}
*/

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

@description('The URL to access the hello API through APIM')
output helloApiUrl string = '${apimService.properties.gatewayUrl}/hello-api/hello'

@description('The name of the Function API in APIM')
output functionApiName string = functionApi.name

@description('The name of the Function backend in APIM')
output functionBackendName string = functionBackend.name

@description('The resource ID of the resource group')
output RESOURCE_GROUP_ID string = resourceGroup().id

@description('The Application (client) ID of the Function App’s app-registration for Easy Auth')
output FUNC_EASYAUTH_APP_ID string = functionAppAppId

@description('The principal ID of the APIM system-assigned managed identity (use as APIM_MI_CLIENTID; for clientId, use Azure CLI post-deployment)')
output APIM_MI_CLIENTID string = apimService.identity.principalId
