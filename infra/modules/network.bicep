// Network Module (minimal) - Creates a single VNet + dedicated subnet for Application Gateway
// NOTE: Intentionally minimal per current requirements. Only an App Gateway subnet is created now.
// Future evolution (APIM, Container Apps, Private Endpoints) can add more subnets or move this to a
// broader network design. Keeping it lean avoids premature complexity.

targetScope = 'resourceGroup'

@description('Name prefix shared across resources (aligned with other modules).')
param resourcePrefix string

@description('Deployment environment name (dev, test, prod). Used for naming + tags.')
param environmentName string

@description('Azure region (defaults to current resource group location).')
param location string = resourceGroup().location

@description('Virtual network address space. Chosen /16 allows room for future subnets without re-IP. Documented decision.')
param addressSpace array = [
	'10.50.0.0/16'
]

@description('Application Gateway dedicated subnet CIDR. Must remain dedicated to App Gateway resources.')
param appGatewaySubnetCidr string = '10.50.10.0/24'

// Decision: We use a per-module unique suffix like other modules (not centralized) to stay consistent and simple.
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceToken = '${resourcePrefix}-${environmentName}-${uniqueSuffix}'
var vnetName = '${resourceToken}-vnet'

// Tags pattern aligned with existing modules (no extra tags per user guidance not to overengineer).
var tags = {
	'azd-env-name': environmentName
	environment: environmentName
	project: resourcePrefix
	component: 'network'
}

// Virtual Network with only the App Gateway subnet for now.
resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
	name: vnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: addressSpace
		}
		subnets: [
			{
				name: 'appgw'
				properties: {
					addressPrefix: appGatewaySubnetCidr
				}
			}
		]
	}
}

// Outputs kept intentionally small (avoid overengineering). Additional subnet outputs can be added later.
@description('Virtual Network ID')
output vnetId string = vnet.id

@description('App Gateway subnet ID (dedicated)')
output appGatewaySubnetId string = vnet.properties.subnets[0].id

