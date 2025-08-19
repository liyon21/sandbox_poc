@description('Location for all resources')
param location string

@description('Tags to apply to resources')
param tags object

// ------------------- VM Configuration -------------------
param vmName string
param adminUsername string
@secure() 
param adminPassword string
param vmSize string = 'Standard_B1s'

// ------------------- Databricks Configuration -------------------
param databricksName string

// ------------------- Storage Configuration -------------------
param storageAccountName string
param storageAccountSkuName string

// ------------------- VNet & Subnets -------------------
param vnetName string
param vnetAddressPrefix string
param vmSubnetName string
param vmSubnetPrefix string
param databricksPrivateSubnetName string
param databricksPrivateSubnetPrefix string
param databricksPublicSubnetName string
param databricksPublicSubnetPrefix string

// ------------------- New Params for Dynamic Containers -------------------
@description('Input container name for CSV data')
param inputContainerName string = 'input'

@description('Output container name for generated files')
param outputContainerName string = 'output'

// ------------------- Unique Identifier (stable, no utcNow) -------------------
@description('Unique identifier for naming, use resource group ID for stability')
param uniqueId string = uniqueString(resourceGroup().id)

// ------------------- Derived Values -------------------

// Managed resource group for Databricks
var managedRgName = '${databricksName}-managed-rg'
var managedRgId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${managedRgName}'

// Storage account unique name
var saUniq = substring(uniqueId, 0, 6)
var storageRaw = toLower('${storageAccountName}${saUniq}')
var storageAccountNameUnique = length(storageRaw) > 24 ? substring(storageRaw, 0, 24) : storageRaw

// Databricks DBFS account unique name (14-char limit)
var dbfsAccountPrefix = 'db'
var dbxBase0 = toLower(replace(replace(replace(databricksName, '-', ''), '_', ''), ' ', ''))
var dbxBase = substring(dbxBase0, 0, min([6, length(dbxBase0)]))
var dbxUniq = substring(uniqueId, 0, 6)
var dbfsAccountNameTrimmed = length('${dbfsAccountPrefix}${dbxBase}${dbxUniq}') > 14 ? substring('${dbfsAccountPrefix}${dbxBase}${dbxUniq}', 0, 14) : '${dbfsAccountPrefix}${dbxBase}${dbxUniq}'

// ------------------- Resources -------------------

// NSG for VM
module nsgModule 'modules/nsg.bicep' = {
  name: 'nsgDeployment'
  params: {
    location: location
    tags: tags
  }
}

// NSGs for Databricks Subnets
resource databricksPrivateNSG 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: '${databricksPrivateSubnetName}-nsg'
  location: location
  tags: tags
}

resource databricksPublicNSG 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: '${databricksPublicSubnetName}-nsg'
  location: location
  tags: tags
}

// VNet with attached NSGs
module vnetModule 'modules/vnet.bicep' = {
  name: 'vnetDeployment'
  params: {
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    vmSubnetName: vmSubnetName
    vmSubnetPrefix: vmSubnetPrefix
    databricksPrivateSubnetName: databricksPrivateSubnetName
    databricksPrivateSubnetPrefix: databricksPrivateSubnetPrefix
    databricksPublicSubnetName: databricksPublicSubnetName
    databricksPublicSubnetPrefix: databricksPublicSubnetPrefix
    tags: tags
    vmNsgId: nsgModule.outputs.nsgId
    databricksPrivateNsgId: databricksPrivateNSG.id
    databricksPublicNsgId: databricksPublicNSG.id
  }
}

// Storage Account with blob support and containers
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountNameUnique
  location: location
  tags: tags
  sku: {
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
}

resource inputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: toLower(inputContainerName)  // Enforce lowercase for container names
  parent: blobServices
  properties: {
    publicAccess: 'None'
  }
}

resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: toLower(outputContainerName)  // Enforce lowercase for container names
  parent: blobServices
  properties: {
    publicAccess: 'None'
  }
}

// VM deployment module
module vmModule 'modules/vm.bicep' = {
  name: 'vmDeployment'
  params: {
    vmName: vmName
    location: location
    tags: tags
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    subnetId: vnetModule.outputs.vmSubnetId
    nsgId: nsgModule.outputs.nsgId
  }
}

// Databricks workspace module
module databricksModule 'modules/databricks.bicep' = {
  name: 'databricksDeployment'
  params: {
    databricksName: databricksName
    location: location
    tags: tags
    vnetId: vnetModule.outputs.vnetId
    privateSubnetName: databricksPrivateSubnetName
    publicSubnetName: databricksPublicSubnetName
    storageAccountName: dbfsAccountNameTrimmed
    managedRgId: managedRgId
  }
}

// ------------------- Outputs -------------------
output vmId string = vmModule.outputs.vmId
output nicId string = vmModule.outputs.nicId
output databricksId string = databricksModule.outputs.databricksId
output storageId string = storageAccount.id
output databricksPrivateNSGId string = databricksPrivateNSG.id
output databricksPublicNSGId string = databricksPublicNSG.id
output storageAccountNameUnique string = storageAccountNameUnique
output databricksManagedIdentityPrincipalId string = databricksModule.outputs.principalId
output inputContainerName string = inputContainerName
output outputContainerName string = outputContainerName
