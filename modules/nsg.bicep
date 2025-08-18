@description('Location for all resources')
param location string

@description('Tags to apply to resources')
param tags object

@description('Network Security Group name')
param nsgName string = 'sandbox-nsg'

@description('SSH access rule priority')
param sshPriority int = 1000

@description('SSH access port')
param sshPort string = '22'

resource sandboxNSG 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: sshPriority
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: sshPort
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
        }
      }
    ]
  }
}

output nsgId string = sandboxNSG.id
