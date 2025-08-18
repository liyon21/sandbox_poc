param(
    [string]$ParametersFile = (Join-Path $PSScriptRoot '..\parameters.json')
)

Write-Host "=== Post-deploy verification: starting ==="

if (!(Test-Path -LiteralPath $ParametersFile)) {
    Write-Host "Parameters file not found at: $ParametersFile" -ForegroundColor Red
    exit 1
}

$parameters       = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json
$location         = $parameters.parameters.location.value
$projectTag       = $parameters.parameters.tags.value.Project
$rgName           = "$projectTag-rg"
$vnetName         = $parameters.parameters.vnetName.value
$vmSubnetName     = $parameters.parameters.vmSubnetName.value
$dbxPubSubnetName = $parameters.parameters.databricksPublicSubnetName.value
$dbxPrvSubnetName = $parameters.parameters.databricksPrivateSubnetName.value

Write-Host "Resource Group : $rgName"
Write-Host "Location       : $location"
Write-Host ""

# 1) RG exists?
$rgExists = az group exists -n $rgName -o tsv
if ($rgExists -ne "true") {
    Write-Host "[X] Resource group '$rgName' not found." -ForegroundColor Red
    exit 1
}
$rg = az group show -n $rgName -o json | ConvertFrom-Json
Write-Host "[OK] Resource group found. Location: $($rg.location)"

# 2) List resources (quick view)
Write-Host ""
Write-Host "Resources in $rgName"
az resource list -g $rgName --output table

# 3) Network checks: VNet and subnets + NSG associations
function Check-Subnet {
    param($VnetName, $SubnetName)
    $subnet = az network vnet subnet show -g $rgName --vnet-name $VnetName --name $SubnetName -o json 2>$null | ConvertFrom-Json
    if (-not $subnet) {
        Write-Host "[X] Subnet '$SubnetName' not found in vnet '$VnetName'." -ForegroundColor Red
        return $false
    }
    $nsgId = $subnet.networkSecurityGroup.id
    if ([string]::IsNullOrWhiteSpace($nsgId)) {
        Write-Host "[!] Subnet '$SubnetName' has NO NSG attached." -ForegroundColor Yellow
        return $true
    } else {
        Write-Host "[OK] Subnet '$SubnetName' has NSG attached: $nsgId"
        return $true
    }
}

Write-Host ""
Write-Host "Checking VNet & Subnets..."
$vnet = az network vnet show -g $rgName -n $vnetName -o json 2>$null | ConvertFrom-Json
if (-not $vnet) {
    Write-Host "[X] VNet '$vnetName' not found." -ForegroundColor Red
} else {
    Write-Host "[OK] VNet '$vnetName' found."
    $null = Check-Subnet -VnetName $vnetName -SubnetName $vmSubnetName
    $null = Check-Subnet -VnetName $vnetName -SubnetName $dbxPubSubnetName
    $null = Check-Subnet -VnetName $vnetName -SubnetName $dbxPrvSubnetName
}

# 4) Databricks workspace presence & URL
Write-Host ""
Write-Host "Checking Databricks workspace..."
$wsName = az databricks workspace list -g $rgName --query "[0].name" -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($wsName)) {
    Write-Host "[!] No Databricks workspace found in RG (if deployment failed earlier, this is expected)." -ForegroundColor Yellow
} else {
    $ws       = az databricks workspace show -g $rgName -n $wsName -o json | ConvertFrom-Json
    $wsState  = $ws.properties.provisioningState
    $wsUrl    = $ws.properties.workspaceUrl
    Write-Host "[OK] Databricks workspace: $wsName"
    Write-Host "     Provisioning state: $wsState"
    if ($wsUrl) { Write-Host "     URL: https://$wsUrl" }

    # 5) Managed RG linkage check
    Write-Host ""
    Write-Host "Checking Databricks managed resource group linkage..."
    # Find any RG whose managedBy references this workspace
    $managedByFilter = "/resourceGroups/$rgName/providers/Microsoft.Databricks/workspaces/$wsName"
    $managedRg = az group list --query "[?managedBy!=null && contains(managedBy, '$managedByFilter')].[name,managedBy]" -o tsv
    if ([string]::IsNullOrWhiteSpace($managedRg)) {
        # As a fallback, show any RGs that look like Databricks-managed
        $guess = az group list --query "[?contains(name, 'databricks')].[name,managedBy]" -o tsv
        if ($guess) {
            Write-Host "[!] No RG with managedBy pointing to the workspace was found, but Databricks-like RGs exist:"
            $guess | ForEach-Object { Write-Host "    $_" }
            Write-Host "    If one of these exists from a previous run, delete it before redeploying."
        } else {
            Write-Host "[!] No Databricks-managed RG found yet. It may still be provisioning."
        }
    } else {
        Write-Host "[OK] Managed RG linkage detected:"
        $managedRg -split "`n" | ForEach-Object { Write-Host "    $_" }
    }
}

Write-Host ""
Write-Host "=== Post-deploy verification: completed ==="
