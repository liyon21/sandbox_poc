@description('Name of the Databricks workspace')
param databricksName string

@description('Azure region for the Databricks workspace')
param location string

@description('Tags to apply to the Databricks workspace')
param tags object = {}

@description('ID of the existing virtual network')
param vnetId string

@description('Name of the private subnet inside the VNet for Databricks')
param privateSubnetName string

@description('Name of the public subnet inside the VNet for Databricks')
param publicSubnetName string

@description('Name of the storage account for Databricks')
param storageAccountName string

@description('Managed resource group ID where Databricks resources will be deployed')
param managedRgId string

resource databricksWorkspace 'Microsoft.Databricks/workspaces@2025-03-01-preview' = {
  name: databricksName
  location: location
  tags: tags
  properties: {
    managedResourceGroupId: managedRgId
    parameters: {
      customVirtualNetworkId: { value: vnetId }
      customPrivateSubnetName: { value: privateSubnetName }
      customPublicSubnetName: { value: publicSubnetName }
      storageAccountName: { value: storageAccountName }
      enableNoPublicIp: { value: true }
    }
  }
  sku: {
    name: 'premium'
    tier: 'Premium'
  }
}

// Output the Databricks workspace resource ID for referencing in main.bicep
output databricksId string = databricksWorkspace.id
