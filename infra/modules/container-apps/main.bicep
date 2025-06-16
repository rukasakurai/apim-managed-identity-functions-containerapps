// Container Apps Module - Independent lifecycle (Future implementation)
targetScope = 'resourceGroup'

@description('The name prefix for Container Apps resources')
param resourcePrefix string = 'myapp'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod)')
param environmentName string = 'dev'

@description('The clientId of the Entra app registration for the Container App')
param containerAppAppId string

@description('Container image to deploy')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceToken = '${resourcePrefix}-${environmentName}-${uniqueSuffix}'

// Resource names
var containerAppName = '${resourceToken}-ca'
var containerAppEnvName = '${resourceToken}-env'
var logAnalyticsWorkspaceName = '${resourceToken}-logs'

// Tags
var tags = {
  'azd-env-name': environmentName
  environment: environmentName
  project: resourcePrefix
  component: 'container-apps'
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'containerapp'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: []
      registries: []
    }
    template: {
      containers: [
        {
          name: 'main'
          image: containerImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: environmentName
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Outputs
@description('The name of the Container App')
output containerAppName string = containerApp.name

@description('The hostname of the Container App')
output containerAppHostName string = containerApp.properties.configuration.ingress.fqdn

@description('The resource ID of the Container App')
output containerAppId string = containerApp.id

@description('The principal ID of the Container App managed identity')
output containerAppPrincipalId string = containerApp.identity.principalId

@description('The Container App URL')
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
