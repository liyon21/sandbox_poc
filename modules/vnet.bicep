@description('VNet name')
param vnetName string = 'sandbox-vnet'

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('VM subnet')
param vmSubnetName string
param vmSubnetPrefix string

@description('Databricks private subnet')
param databricksPrivateSubnetName string
param databricksPrivateSubnetPrefix string

@description('Databricks public subnet')
param databricksPublicSubnetName string
param databricksPublicSubnetPrefix string

@description('Tags')
param tags object

@description('NSG IDs (optional) for attaching to subnets')
param vmNsgId string = ''
param databricksPrivateNsgId string = ''
param databricksPublicNsgId string = ''

resource sandboxVnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: vnetName
  location: resourceGroup().location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: [
      {
        name: vmSubnetName
        properties: {
          addressPrefix: vmSubnetPrefix
          networkSecurityGroup: empty(vmNsgId) ? null : { id: vmNsgId }
        }
      }
      {
        name: databricksPrivateSubnetName
        properties: {
          addressPrefix: databricksPrivateSubnetPrefix
          networkSecurityGroup: empty(databricksPrivateNsgId) ? null : { id: databricksPrivateNsgId }
          delegations: [
            {
              name: 'databricksPrivateDelegation'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
        }
      }
      {
        name: databricksPublicSubnetName
        properties: {
          addressPrefix: databricksPublicSubnetPrefix
          networkSecurityGroup: empty(databricksPublicNsgId) ? null : { id: databricksPublicNsgId }
          delegations: [
            {
              name: 'databricksPublicDelegation'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
        }
      }
    ]
  }
}

// Outputs
output vnetId string = sandboxVnet.id
output vmSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', sandboxVnet.name, vmSubnetName)
output databricksPrivateSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', sandboxVnet.name, databricksPrivateSubnetName)
output databricksPublicSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', sandboxVnet.name, databricksPublicSubnetName)
