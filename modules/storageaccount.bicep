@description('Location for all resources')
param location string

@description('Tags to apply to the storage account')
param tags object = {}

@description('Name of the storage account')
param storageAccountName string

@description('SKU for the storage account, e.g., Standard_LRS')
param skuName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// Output the storage account resource ID for other modules
output storageId string = storageAccount.id
