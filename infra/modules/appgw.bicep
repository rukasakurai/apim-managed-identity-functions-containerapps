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

// === Incremental addition: APIM backend (always present) ===
// Decision pending (future): add HTTPS listener & certificate for end-user TLS termination.
// Decision pending (future): autoscale vs fixed capacity beyond current 'capacity' param.
// Decision pending (future): path-based routing vs single basic rule.
// Decision pending (future): custom health probe path & advanced WAF exclusions.
// Decision pending (future): HTTP->HTTPS redirect once HTTPS listener introduced.
// Decision pending (future): TLS policy hardening (disable TLS 1.0/1.1) when HTTPS added.
@description('Public hostname (FQDN) of the APIM gateway, e.g. myapim.azure-api.net. Used as backend FQDN.')
param apimHostname string

@description('Path used for health probing APIM; must return 200. Minimal default reuses existing hello operation. Future: replace with dedicated /healthz when added.')
param healthProbePath string = '/hello-api/hello'

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
		// APIM backend (HTTPS to APIM). Frontend remains HTTP for now; future: add HTTPS listener + redirect.
		backendHttpSettingsCollection: [
			{
				name: 'bhs-apim'
				properties: {
					protocol: 'Https'
					port: 443
					pickHostNameFromBackendAddress: false
					hostName: apimHostname // Future decision: SNI override vs pickHostNameFromBackendAddress.
					requestTimeout: 30
					// Added minimal custom probe referencing existing functional path (avoid 502 due to default / probe returning 404).
					probe: {
						id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, 'probe-apim')
					}
					// Future decision: cookie-based affinity.
				}
			}
		]
		backendAddressPools: [
			{
				name: 'bp-apim'
				properties: {
					backendAddresses: [
						{ fqdn: apimHostname }
					]
				}
			}
		]
		requestRoutingRules: [
			{
				name: 'rule-apim'
				properties: {
					priority: 100
					ruleType: 'Basic'
					httpListener: {
						id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'listener-http')
					}
					backendAddressPool: {
						id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'bp-apim')
					}
					backendHttpSettings: {
						id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'bhs-apim')
					}
					// Future decision: convert to path-based routing or introduce multiple rules.
				}
			}
		]
		probes: [
			{
				name: 'probe-apim'
				properties: {
					protocol: 'Https'
					path: healthProbePath
					host: apimHostname
					interval: 30
					timeout: 30
					unhealthyThreshold: 3
					pickHostNameFromBackendHttpSettings: false
					match: {
						statusCodes: [
							'200'
						]
					}
				}
			}
		] // Minimal probe now present; consider dedicated /healthz + broader status codes (e.g. 200-399) later.
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

