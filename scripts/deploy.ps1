param(
    # Defaults assume this script lives in ./scripts and the files are at repo root
    [string]$TemplateFile   = (Join-Path $PSScriptRoot '..\main.bicep'),
    [string]$ParametersFile = (Join-Path $PSScriptRoot '..\parameters.json')
)

Write-Host "=== Deploy: starting ==="

# -------------------- Load parameters --------------------
if (!(Test-Path -LiteralPath $ParametersFile)) {
    Write-Host "Parameters file not found at: $ParametersFile" -ForegroundColor Red
    exit 1
}
$parameters = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json
$Location = $parameters.parameters.location.value
$ResourceGroupName = "$($parameters.parameters.tags.value.Project)-rg"

Write-Host "Resource Group : $ResourceGroupName"
Write-Host "Location       : $Location"
Write-Host "Template       : $TemplateFile"
Write-Host "Parameters     : $ParametersFile"

# -------------------- Generate random suffix for Databricks name --------------------
$RandomSuffix = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
$DatabricksNameRandomized = "$($parameters.parameters.databricksName.value)$RandomSuffix"
Write-Host "Databricks name (randomized): $DatabricksNameRandomized"

# -------------------- (Optional) Azure login check for local runs --------------------
try {
    az account show > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not logged in. Attempting az login..." -ForegroundColor Yellow
        az login | Out-Null
    }
} catch {
    Write-Host "Azure CLI not logged in and automatic login failed." -ForegroundColor Yellow
    throw
}

# -------------------- Ensure RG exists (pre-check + create + post-check) --------------------
$rgExists = az group exists -n $ResourceGroupName -o tsv
if ($rgExists -eq "true") {
    $rg = az group show -n $ResourceGroupName -o json | ConvertFrom-Json
    Write-Host "RG already exists in location: $($rg.location)"
} else {
    Write-Host "RG does not exist. Creating..."
    az group create --name $ResourceGroupName --location $Location --output none
    $rgAfter = az group show -n $ResourceGroupName -o json 2>$null | ConvertFrom-Json
    if ($rgAfter) {
        Write-Host "RG created successfully in location: $($rgAfter.location)"
    } else {
        Write-Host "Failed to create RG '$ResourceGroupName'." -ForegroundColor Red
        exit 1
    }
}

# -------------------- Check existing deployment record --------------------
$deploymentName = "sandbox-deployment"
$existingDeploymentRaw = az deployment group list --resource-group $ResourceGroupName --query "[?name=='$deploymentName']" -o json
$existingDeployment = if ($existingDeploymentRaw) { $existingDeploymentRaw | ConvertFrom-Json } else { @() }

if ($existingDeployment.Count -gt 0) {
    Write-Host "Updating existing deployment record: $deploymentName"
} else {
    Write-Host "Creating new deployment record: $deploymentName"
}

# -------------------- Deploy Bicep with randomized Databricks name --------------------
Write-Host "Starting deployment..."
$deploymentResult = az deployment group create `
  --resource-group $ResourceGroupName `
  --name $deploymentName `
  --template-file $TemplateFile `
  --parameters @$ParametersFile `
  --parameters databricksName=$DatabricksNameRandomized `
  --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host "Deployment failed due to CLI error." -ForegroundColor Red
    exit 1
}

# Convert the JSON output once
$deploymentJson = $deploymentResult | ConvertFrom-Json

# Check provisioning state
if ($deploymentJson.properties.provisioningState -ne "Succeeded") {
    Write-Host "Deployment failed (provisioningState=$($deploymentJson.properties.provisioningState))." -ForegroundColor Red
    exit 1
}

Write-Host "Deployment succeeded."


# -------------------- Show deployment outputs --------------------
Write-Host "`nDeployment outputs:"
$deploymentOutputs = az deployment group show -g $ResourceGroupName -n $deploymentName --query "properties.outputs" -o json
if ($deploymentOutputs) {
    Write-Output $deploymentOutputs
} else {
    Write-Host "(no outputs returned)"
}

# -------------------- List resources in the RG --------------------
Write-Host "`nResources in $ResourceGroupName"
az resource list --resource-group $ResourceGroupName --output table

# -------------------- Databricks workspace info (name + URL) --------------------
Write-Host "`nChecking Databricks workspace in RG..."
$wsName = az databricks workspace list -g $ResourceGroupName --query "[0].name" -o tsv 2>$null
if ([string]::IsNullOrWhiteSpace($wsName)) {
    Write-Host "No Databricks workspace found in RG (expected after first successful deploy)." -ForegroundColor Yellow
} else {
    $wsUrl = az databricks workspace show -n $wsName -g $ResourceGroupName --query "workspaceUrl" -o tsv
    Write-Host "Databricks workspace: $wsName"
    Write-Host "Databricks URL     : https://$wsUrl"
}

Write-Host "`n=== Deploy: completed ==="
