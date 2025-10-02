// Application Gateway (WAF_v2) minimal module
// Goal: Deploy a working WAF-enabled Application Gateway WITHOUT backend targets yet.
// Decisions documented inline to make future evolution explicit while avoiding overengineering now.
// - WAF mode: Prevention (user choice). Can be relaxed to Detection later if tuning false positives.
// - OWASP rule set: 3.2 (current recommended). Future upgrades may require updating rule set version.
// - Capacity: Fixed (manual) capacity of 1 instance (simplicity). Autoscale can be introduced later.
// - Listener: HTTP only initially (no certificate provided). HTTPS + certificate (Key Vault or PFX) to be added later.
// - Backend: Placeholder empty pool to satisfy schema. Real backends (APIM, Container Apps, Functions) added later.
// - Diagnostics: Enabled to Log Analytics (access, performance, firewall) using workspace ID passed from platform.
// - Naming: Per-module unique suffix for consistency with existing modules (no shared global suffix now).

targetScope = 'resourceGroup'

@description('Name prefix shared across solution modules.')
param resourcePrefix string

@description('Environment name (dev, test, prod).')
param environmentName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Subnet ID dedicated to this Application Gateway (from network module).')
param appGatewaySubnetId string

@description('Log Analytics workspace resource ID for diagnostics.')
param logAnalyticsWorkspaceId string

@description('OWASP Core Rule Set version (update when newer stable versions become recommended).')
param owaspVersion string = '3.2'

// Decision: Fixed capacity of 1 (simplicity). Increase or switch to autoscale later if traffic demands.
@description('Fixed instance capacity for Application Gateway (manual scale).')
@allowed([1,2])
param capacity int = 1

// Internal naming & tokens
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceToken = '${resourcePrefix}-${environmentName}-${uniqueSuffix}'
var appGatewayName = '${resourceToken}-agw'
var publicIpName = '${resourceToken}-agw-pip'
var dnsLabel = toLower(replace('${take(resourcePrefix, 18)}-${environmentName}-${uniqueSuffix}', '_', '-'))

// Tags (aligned with other modules; no additional tags now)
var tags = {
	'azd-env-name': environmentName
	environment: environmentName
	project: resourcePrefix
	component: 'app-gateway'
}

// Public IP (Standard Static) with DNS label
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
	name: publicIpName
	location: location
	tags: tags
	sku: {
		name: 'Standard'
	}
	properties: {
		publicIPAllocationMethod: 'Static'
		dnsSettings: {
			domainNameLabel: dnsLabel
		}
	}
}

// Minimal WAF-enabled Application Gateway (HTTP listener initially; HTTPS added later)
resource appGateway 'Microsoft.Network/applicationGateways@2024-07-01' = {
	name: appGatewayName
	location: location
	tags: tags
	properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: capacity
	  }
		webApplicationFirewallConfiguration: {
			enabled: true
			firewallMode: 'Prevention' // Decision: start strict; adjust if false positives appear when backends added.
			ruleSetType: 'OWASP'
			ruleSetVersion: owaspVersion // NOTE: May need update when new stable CRS released.
		}
		gatewayIPConfigurations: [
			{
				name: 'gwipc'
				properties: {
					subnet: {
						id: appGatewaySubnetId
					}
				}
			}
		]
		frontendIPConfigurations: [
			{
				name: 'feip-public'
				properties: {
					publicIPAddress: {
						id: publicIp.id
					}
				}
			}
		]
		frontendPorts: [
			{
				name: 'feport-80'
				properties: {
					port: 80
				}
			}
		]
		// No SSL certificates yet (HTTPS will be introduced later with Key Vault or PFX parameterization)
		sslCertificates: []
		httpListeners: [
			{
				name: 'listener-http'
				properties: {
					protocol: 'Http'
					frontendIPConfiguration: {
						id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'feip-public')
					}
					frontendPort: {
						id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'feport-80')
					}
				}
			}
		]
		// Placeholder backend HTTP settings (HTTPS or advanced settings added later when real backends exist)
		backendHttpSettingsCollection: [
			{
				name: 'bhs-placeholder'
				properties: {
					protocol: 'Http'
					port: 80
					pickHostNameFromBackendAddress: false
					requestTimeout: 30
				}
			}
		]
		// Placeholder empty backend pool (legal; will show unhealthy until targets are added later)
		backendAddressPools: [
			{
				name: 'bp-placeholder'
				properties: {
					backendAddresses: []
				}
			}
		]
		// Minimal basic rule tying listener to placeholder pool/settings
		requestRoutingRules: [
			{
				name: 'rule-placeholder'
				properties: {
					priority: 100
					ruleType: 'Basic'
					httpListener: {
						id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'listener-http')
					}
					backendAddressPool: {
						id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'bp-placeholder')
					}
					backendHttpSettings: {
						id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'bhs-placeholder')
					}
				}
			}
		]
		probes: [] // Added later when real backends are introduced.
		urlPathMaps: [] // Path-based routing deferred.
		rewriteRuleSets: [] // Rewrite rules deferred.
		enableHttp2: true // Decision: enable HTTP/2 now (common best practice).
	}
}

/*
// === ARM Fallback (Uncomment if Bicep type issue prevents deployment) ===
module appGateway_armFallback 'br/public:azdeployment/v1' = {
	name: 'appGateway-arm-fallback'
	// Hypothetical public registry module placeholder; replace with inline JSON if needed.
	// For full control without relying on Bicep type system, you could instead embed an 'Microsoft.Resources/deployments' resource
	// with a raw ARM template specifying the applicationGateway including top-level 'sku'. Keeping repo lean for now.
}
*/

// Diagnostic settings: capture access, performance, firewall logs to Log Analytics (resource-specific tables)
resource appGatewayDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
	name: '${resourceToken}-agw-logs'
	scope: appGateway
	properties: {
		workspaceId: logAnalyticsWorkspaceId
		logAnalyticsDestinationType: 'Dedicated'
		logs: [
			{
				category: 'ApplicationGatewayAccessLog'
				enabled: true
				retentionPolicy: {
					enabled: false
					days: 0
				}
			}
			{
				category: 'ApplicationGatewayPerformanceLog'
				enabled: true
				retentionPolicy: {
					enabled: false
					days: 0
				}
			}
			{
				category: 'ApplicationGatewayFirewallLog'
				enabled: true
				retentionPolicy: {
					enabled: false
					days: 0
				}
			}
		]
		metrics: [
			{
				category: 'AllMetrics'
				enabled: true
				retentionPolicy: {
					enabled: false
					days: 0
				}
			}
		]
	}
}

// Outputs
@description('Application Gateway resource ID')
output appGatewayId string = appGateway.id

@description('Application Gateway public IP address')
output publicIpAddress string = publicIp.properties.ipAddress

@description('Application Gateway public DNS FQDN')
output appGatewayFqdn string = publicIp.properties.dnsSettings.fqdn

@description('App Gateway subnet ID (for reference / future modules)')
output appGatewaySubnetId string = appGatewaySubnetId

