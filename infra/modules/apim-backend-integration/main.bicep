// APIM Backend Integration Module - Connects backends to APIM
targetScope = 'resourceGroup'

@description('The name of the existing APIM service')
param apimServiceName string

@description('The backend type (function, containerapp)')
@allowed(['function', 'containerapp'])
param backendType string

@description('The backend resource ID')
param backendResourceId string

@description('The backend hostname')
param backendHostname string

@description('The backend API path prefix')
param backendApiPath string = '/api'

@description('The APIM API path')
param apimApiPath string

@description('The API display name')
param apiDisplayName string

@description('The backend authentication app ID (for managed identity auth)')
param backendAppId string

@description('The backend name identifier')
param backendName string

// Reference existing APIM service
resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

// Backend configuration
resource backend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apimService
  name: '${backendName}-backend'
  properties: {
    description: 'Backend for ${backendType}: ${backendName}'
    url: 'https://${backendHostname}${backendApiPath}'
    protocol: 'http'
    resourceId: '${environment().resourceManager}${backendResourceId}'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// API definition
resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apimService
  name: '${backendName}-api'
  properties: {
    displayName: apiDisplayName
    description: 'API for ${backendType}: ${backendName}'
    serviceUrl: 'https://${backendHostname}${backendApiPath}'
    path: apimApiPath
    protocols: ['https']
    subscriptionRequired: false
    apiType: 'http'
  }
}

// Simple operation that matches the Azure Function's hello endpoint
resource helloOperation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: api
  name: 'hello-get'
  properties: {
    displayName: 'Get Hello'
    method: 'GET'
    urlTemplate: '/hello'
    description: 'Hello world endpoint from Azure Function'
  }
}

// Policy for managed identity authentication on the hello operation
resource helloOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: helloOperation
  name: 'policy'
  properties: {
    value: '<policies>\n  <inbound>\n    <authentication-managed-identity resource="api://${backendAppId}"/>\n    <set-backend-service backend-id="${backend.name}" />\n  </inbound>\n  <backend><base /></backend>\n  <outbound><base /></outbound>\n  <on-error><base /></on-error>\n</policies>'
  }
}

// Add API to the backend services product
resource apiProduct 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  name: '${apimService.name}/backend-services/${api.name}'
}

// Outputs
@description('The backend ID')
output backendId string = backend.id

@description('The API ID')
output apiId string = api.id

@description('The API URL through APIM')
output apiUrl string = '${apimService.properties.gatewayUrl}/${apimApiPath}'

@description('The backend name')
output backendName string = backend.name

@description('The API name')
output apiName string = api.name
