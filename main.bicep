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
param managedRgName string

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

// ------------------- Timestamp parameter for uniqueness -------------------
@description('Current UTC timestamp for unique naming')
param timestamp string = utcNow()

// ------------------- Derived Values -------------------
var managedRgId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${managedRgName}'

// Clean timestamp for names
var ts4 = substring(replace(replace(replace(replace(timestamp, '-', ''), ':', ''), 'T', ''), 'Z', ''), 0, 4)

// Storage account unique name
var saUniq = substring(uniqueString(resourceGroup().id, storageAccountName), 0, 6)
var storageRaw = toLower('${storageAccountName}${saUniq}${ts4}')
var storageAccountNameWithTimestamp = length(storageRaw) >= 24 ? substring(storageRaw, 0, 24) : storageRaw

// Databricks DBFS account unique name
var dbfsAccountPrefix = 'db'
var dbxBase0 = toLower(replace(replace(replace(databricksName, '-', ''), '_', ''), ' ', ''))
var dbxBase  = substring(dbxBase0, 0, min([6, length(dbxBase0)]))
var dbxUniq = substring(uniqueString(subscription().subscriptionId, resourceGroup().id, databricksName), 0, 6)
var ts8 = substring(replace(replace(replace(replace(timestamp, '-', ''), ':', ''), 'T', ''), 'Z', ''), 0, 8)
var dbfsAccountNameTrimmed = length('${dbfsAccountPrefix}${dbxBase}${dbxUniq}${ts8}') >= 20 ? substring('${dbfsAccountPrefix}${dbxBase}${dbxUniq}${ts8}', 0, 20) : '${dbfsAccountPrefix}${dbxBase}${dbxUniq}${ts8}'
// ------------------- Modules -------------------

// Deploy NSG for VM
module nsgModule 'modules/nsg.bicep' = {
  name: 'nsgDeployment'
  params: {
    location: location
    tags: tags
  }
}

// Deploy empty NSGs for Databricks subnets
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

// Deploy VNet with NSG attachments
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

// Deploy Storage Account
module storageModule 'modules/storageaccount.bicep' = {
  name: 'storageDeployment'
  params: {
    location: location
    tags: tags
    storageAccountName: storageAccountNameWithTimestamp
    skuName: storageAccountSkuName
  }
}

// Deploy VM
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

// Deploy Databricks Workspace
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
output storageId string = storageModule.outputs.storageId
output databricksPrivateNSGId string = databricksPrivateNSG.id
output databricksPublicNSGId string = databricksPublicNSG.id
