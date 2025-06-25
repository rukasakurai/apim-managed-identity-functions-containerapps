// Container Apps module for WebSocket application deployment
// Implements Azure best practices with managed identity, logging, and security

targetScope = 'resourceGroup'

@description('The name prefix for all resources')
param resourcePrefix string

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod)')
param environmentName string

@description('Resource token for unique resource naming')
param resourceToken string = uniqueString(resourceGroup().id)

@description('Tags to apply to all resources')
param tags object = {}

@description('Log Analytics workspace customer id (GUID) for monitoring')
param logAnalyticsWorkspaceCustomerId string

@description('Log Analytics workspace shared key for monitoring')
@secure()
param logAnalyticsWorkspaceSharedKey string

@description('WebSocket application port')
param websocketPort int = 8080

@description('The name of the Azure Container Registry')
param containerRegistryName string

@description('The name of the user-assigned identity')
param acaIdentityName string = '${environmentName}-aca-identity'

@description('The client ID of the Entra app registration for Container Apps Easy Auth')
param containerAppsAuthAppId string

// Variables for resource naming
// Ensure names stay within Azure limits (32 chars for Container Apps)
var shortResourceToken = take(resourceToken, 6) // Use only first 6 chars of resource token
var containerAppEnvironmentName = '${take(resourcePrefix, 10)}-cae-${shortResourceToken}'
var websocketAppName = '${take(resourcePrefix, 10)}-ws-${shortResourceToken}'
// Use base image for initial deployment - update after building custom image
var containerImageName = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

resource userAssignedManagedIdentityForContainerApp 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (!empty(acaIdentityName)) {
  name: acaIdentityName
  location: location
}
// Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvironmentName
  location: location
  tags: union(tags, {
    'azd-env-name': environmentName
  })
  properties: {
    // Log Analytics configuration for monitoring
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspaceCustomerId
        sharedKey: logAnalyticsWorkspaceSharedKey
      }
    }

    // Zone redundancy for high availability in production
    zoneRedundant: environmentName == 'prod'

    // Workload profiles for different performance requirements
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// WebSocket Container App
resource websocketApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: websocketAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'websocket-app'
    'azd-env-name': environmentName
  })
  // It is critical that the identity is granted ACR pull access before the app is created
  // otherwise the container app will throw a provision error
  // This also forces us to use an user assigned managed identity since there would no way to
  // provide the system assigned identity with the ACR pull access before the app is created
  dependsOn: [
    acrPullRoleAssignment
  ]

  // Managed Identity configuration
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: !empty(acaIdentityName) ? { '${userAssignedManagedIdentityForContainerApp.id}': {} } : null
  }

  properties: {
    // Environment reference
    environmentId: containerAppEnvironment.id

    // Workload profile
    workloadProfileName: 'Consumption' // Application configuration
    configuration: {
      // Active revisions mode - single for simple deployments
      activeRevisionsMode: 'Single'

      // Maximum inactive revisions to keep
      maxInactiveRevisions: 3

      // Container registry configuration for ACR access
      registries: [
        {
          server: '${containerRegistryName}.azurecr.io'
          identity: userAssignedManagedIdentityForContainerApp.id
        }
      ]

      // Ingress configuration for WebSocket traffic
      ingress: {
        external: true
        targetPort: websocketPort
        allowInsecure: false // Force HTTPS in production

        // Traffic distribution (100% to latest revision)
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]

        // Additional port mappings for health checks
        additionalPortMappings: [
          {
            external: false
            targetPort: 8081
            exposedPort: 8081
          }
        ]
      }
    }

    // Application template
    template: {
      // Scaling configuration
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          // HTTP scaling rule for WebSocket connections
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '30'
              }
            }
          }
        ]
      }

      // Container configuration
      containers: [
        {
          name: 'websocket-app'
          image: containerImageName

          // Resource requirements
          resources: {
            cpu: json('0.25') // 0.25 CPU cores
            memory: '0.5Gi' // 512MB memory
          }

          // Environment variables
          env: [
            {
              name: 'WEBSOCKET_PORT'
              value: string(websocketPort)
            }
            {
              name: 'WEBSOCKET_HOST'
              value: '0.0.0.0'
            }
            {
              name: 'ENVIRONMENT'
              value: environmentName
            }
          ]

          // Health probes
          probes: [
            // Liveness probe
            {
              type: 'Liveness'
              tcpSocket: {
                port: websocketPort
              }
              initialDelaySeconds: 30
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
            // Readiness probe
            {
              type: 'Readiness'
              tcpSocket: {
                port: websocketPort
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
            }
          ]
        }
      ]

      // Graceful termination
      terminationGracePeriodSeconds: 30
    }
  }
}

// Easy Auth configuration for the websocket app
resource websocketAppAuth 'Microsoft.App/containerApps/authConfigs@2023-11-02-preview' = {
  name: 'current'
  parent: websocketApp
  properties: {
    platform: {
      enabled: true
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: containerAppsAuthAppId
          openIdIssuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
        }
      }
    }
  }
}

// Reference the ACR as an existing resource
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: containerRegistryName
}

var acrPullRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

// Assign AcrPull role to the managed identity
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(subscription().id, resourceGroup().id, acrPullRole)
  properties: {
    roleDefinitionId: acrPullRole
    principalId: userAssignedManagedIdentityForContainerApp.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Container App Environment name')
output containerAppEnvironmentName string = containerAppEnvironment.name

@description('Container App Environment ID')
output containerAppEnvironmentId string = containerAppEnvironment.id

@description('Container App Environment default domain')
output containerAppEnvironmentDefaultDomain string = containerAppEnvironment.properties.defaultDomain

@description('WebSocket application name')
output websocketAppName string = websocketApp.name

@description('WebSocket application ID')
output websocketAppId string = websocketApp.id

@description('WebSocket application FQDN')
output websocketAppFqdn string = websocketApp.properties.configuration.ingress.fqdn

@description('WebSocket application URL')
output websocketAppUrl string = 'wss://${websocketApp.properties.configuration.ingress.fqdn}'

@description('WebSocket application latest revision name')
output websocketAppLatestRevisionName string = websocketApp.properties.latestRevisionName

@description('WebSocket application outbound IP addresses')
output websocketAppOutboundIpAddresses array = websocketApp.properties.outboundIpAddresses
