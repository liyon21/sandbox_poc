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

Write-Host "Resource Group to delete: $ResourceGroupName"

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

# -------------------- Check if RG exists --------------------
$rgExists = az group exists -n $ResourceGroupName -o tsv
if ($rgExists -eq "true") {
    Write-Host "Resource Group exists. Proceeding to delete..."
} else {
    Write-Host "Resource Group '$ResourceGroupName' does not exist. Nothing to delete." -ForegroundColor Yellow
    exit 0
}

# -------------------- Delete Resource Group --------------------
Write-Host "Deleting Resource Group '$ResourceGroupName' (this may take a few minutes)..."
az group delete --name $ResourceGroupName --yes --no-wait

Write-Host "`nResource Group deletion triggered successfully."

Write-Host "`n=== Destroy: completed ==="
