# scripts/create-rg.ps1

param (
    [string]$ParametersFile = "$(Split-Path $PSScriptRoot -Parent)\parameters.json"
)

# Load parameters
$parameters = Get-Content $ParametersFile -Raw | ConvertFrom-Json

# Extract values from parameters.json
$ProjectName      = $parameters.parameters.tags.value.Project
$ResourceGroupName = "$ProjectName-rg"
$Location          = $parameters.parameters.location.value

Write-Host "🚀 Checking Resource Group '$ResourceGroupName' in location '$Location'..."

# Check if resource group already exists
$rg = az group show --name $ResourceGroupName --only-show-errors 2>$null

if ($LASTEXITCODE -eq 0 -and $rg) {
    Write-Host "✅ Resource Group '$ResourceGroupName' already exists."
}
else {
    Write-Host "🚀 Resource Group '$ResourceGroupName' does not exist. Creating in location '$Location'..."
    $create = az group create --name $ResourceGroupName --location $Location --tags Project=$ProjectName --only-show-errors | ConvertFrom-Json

    if ($LASTEXITCODE -eq 0 -and $create.name -eq $ResourceGroupName) {
        Write-Host "✅ Resource Group '$ResourceGroupName' successfully created in location '$Location'."
    }
    else {
        Write-Host "❌ Failed to create Resource Group '$ResourceGroupName'. Please check logs."
    }
}
