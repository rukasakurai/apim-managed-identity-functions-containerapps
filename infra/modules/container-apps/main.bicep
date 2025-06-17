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

@description('User-assigned managed identity resource ID')
param userAssignedIdentityId string

@description('Principal ID of the user-assigned managed identity')
param userAssignedIdentityPrincipalId string

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string

@description('Log Analytics workspace key for monitoring')
@secure()
param logAnalyticsWorkspaceKey string

@description('Container registry server URL')
param containerRegistryServer string

@description('Whether to enable internal load balancer only')
param internalLoadBalancerOnly bool = false

@description('WebSocket application port')
param websocketPort int = 8080

// Variables for resource naming
// Ensure names stay within Azure limits (32 chars for Container Apps)
var shortResourceToken = take(resourceToken, 6)  // Use only first 6 chars of resource token
var containerAppEnvironmentName = '${take(resourcePrefix, 10)}-cae-${shortResourceToken}'
var websocketAppName = '${take(resourcePrefix, 10)}-ws-${shortResourceToken}'
// Use base image for initial deployment - update after building custom image
var containerImageName = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

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
        customerId: logAnalyticsWorkspaceId
        sharedKey: logAnalyticsWorkspaceKey
      }
    }

    // Network configuration
    vnetConfiguration: internalLoadBalancerOnly
      ? {
          internal: true
        }
      : null

    // Zone redundancy for high availability in production
    zoneRedundant: environmentName == 'prod'

    // Workload profiles for different performance requirements
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    // Dapr configuration (optional - version is read-only)
    daprConfiguration: {}
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

  // Managed Identity configuration
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }

  properties: {
    // Environment reference
    environmentId: containerAppEnvironment.id

    // Workload profile
    workloadProfileName: 'Consumption'

    // Application configuration
    configuration: {
      // Active revisions mode - single for simple deployments
      activeRevisionsMode: 'Single'

      // Maximum inactive revisions to keep
      maxInactiveRevisions: 3

      // Container registry configuration with managed identity
      registries: [
        {
          server: containerRegistryServer
          identity: userAssignedIdentityId
        }
      ]

      // Ingress configuration for WebSocket traffic
      ingress: {
        external: true
        targetPort: websocketPort
        transport: 'tcp' // WebSocket requires TCP transport
        allowInsecure: false // Force HTTPS in production

        // Traffic distribution (100% to latest revision)
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]

        // CORS policy for web clients
        corsPolicy: {
          allowedOrigins: ['*'] // Configure appropriately for production
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
          allowCredentials: false
        }

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
            {
              name: 'AZURE_CLIENT_ID'
              value: userAssignedIdentityPrincipalId
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
