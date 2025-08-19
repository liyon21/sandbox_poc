param(
    [string]$ParametersFile = (Join-Path $PSScriptRoot '..\parameters.json')
)

Write-Host "=== Destroy: starting ==="

# -------------------- Load parameters --------------------
if (!(Test-Path -LiteralPath $ParametersFile)) {
    Write-Host "Parameters file not found at: $ParametersFile" -ForegroundColor Red
    exit 1
}
$parameters = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json
$ResourceGroupName = "$($parameters.parameters.tags.value.Project)-rg"

Write-Host "Deleting resources under Resource Group: $ResourceGroupName"

# -------------------- Check Azure login --------------------
try {
    az account show > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not logged in. Attempting az login..." -ForegroundColor Yellow
        az login | Out-Null
    }
} catch {
    Write-Host "Azure CLI not logged in and automatic login failed." -ForegroundColor Red
    throw
}
# 1. Delete Databricks workspace and wait until gone
$databricksWorkspace = az resource list `
    --resource-group $ResourceGroupName `
    --resource-type Microsoft.Databricks/workspaces `
    --query "[0].name" -o tsv

if ($databricksWorkspace) {
    Write-Host "Deleting Databricks workspace: $databricksWorkspace ..."
    az databricks workspace delete `
        --name $databricksWorkspace `
        --resource-group $ResourceGroupName `
        --yes --no-wait

    # Poll until it’s deleted
    Write-Host "Waiting for Databricks workspace cleanup..."
    do {
        Start-Sleep -Seconds 30
        $exists = az resource list `
            --resource-group $ResourceGroupName `
            --resource-type Microsoft.Databricks/workspaces `
            --query "[?name=='$databricksWorkspace']" -o tsv
    } while ($exists)
    Write-Host "Databricks workspace fully deleted."
}

# 2. Delete VM(s) first
$vms = az vm list -g $ResourceGroupName --query "[].name" -o tsv
foreach ($vm in $vms) {
    Write-Host "Deleting VM: $vm ..."
    az vm delete -g $ResourceGroupName -n $vm --yes
}

# 3. Delete NIC(s)
$nics = az network nic list -g $ResourceGroupName --query "[].name" -o tsv
foreach ($nic in $nics) {
    Write-Host "Deleting NIC: $nic ..."
    az network nic delete -g $ResourceGroupName -n $nic
}

# 4. Delete disks
$disks = az disk list -g $ResourceGroupName --query "[].name" -o tsv
foreach ($disk in $disks) {
    Write-Host "Deleting Disk: $disk ..."
    az disk delete -g $ResourceGroupName -n $disk --yes
}

# 5. Delete Storage Accounts
$stgs = az storage account list -g $ResourceGroupName --query "[].name" -o tsv
foreach ($stg in $stgs) {
    Write-Host "Deleting Storage Account: $stg ..."
    az storage account delete -g $ResourceGroupName -n $stg --yes
}

# 6. Delete VNet last
$vnets = az network vnet list -g $ResourceGroupName --query "[].name" -o tsv
foreach ($vnet in $vnets) {
    Write-Host "Deleting VNet: $vnet ..."
    az network vnet delete -g $ResourceGroupName -n $vnet
}

# 7. Catch any remaining resources
$resources = az resource list -g $ResourceGroupName --query "[].id" -o tsv
foreach ($resId in $resources) {
    Write-Host "Deleting leftover resource: $resId ..."
    az resource delete --ids $resId
}


Write-Host "✅ All resources deleted under $ResourceGroupName, RG still exists."
