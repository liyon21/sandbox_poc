param(
    [string]$ParametersFile = (Join-Path $PSScriptRoot '..\parameters.json'),
    [string]$DataFolder     = (Join-Path $PSScriptRoot '..\data'),
    [string]$InputContainer = 'input',
    [string]$OutputContainer = 'output'
)

Write-Host "=== Storage setup & upload: starting ==="

if (!(Test-Path -LiteralPath $ParametersFile)) {
    Write-Host "Parameters file not found at: $ParametersFile" -ForegroundColor Red
    exit 1
}
$parameters = Get-Content -LiteralPath $ParametersFile -Raw | ConvertFrom-Json

$rgName           = "$($parameters.parameters.tags.value.Project)-rg"
$storagePrefix    = $parameters.parameters.storageAccountName.value

Write-Host "Resource Group        : $rgName"
Write-Host "Storage name (prefix) : $storagePrefix"
Write-Host "Data folder           : $DataFolder"
Write-Host ""

# Resolve actual storage account name created by Bicep (prefix + random suffix)
$storageName = az storage account list `
    --resource-group $rgName `
    --query "[?starts_with(name, '$storagePrefix')].name | [0]" -o tsv

if ([string]::IsNullOrWhiteSpace($storageName)) {
    Write-Host "[X] Could not find a storage account starting with '$storagePrefix' in RG '$rgName'." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Resolved Storage Account: $storageName"

# Get key
$storageKey = az storage account keys list `
    --resource-group $rgName `
    --account-name $storageName `
    --query "[0].value" -o tsv

if ([string]::IsNullOrWhiteSpace($storageKey)) {
    Write-Host "[X] Failed to retrieve storage account key." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Retrieved storage key."

# Create containers if needed
Write-Host ""
Write-Host "Ensuring containers exist..."
az storage container create --name $InputContainer  --account-name $storageName --account-key $storageKey --output none
az storage container create --name $OutputContainer --account-name $storageName --account-key $storageKey --output none
Write-Host "[OK] Containers '$InputContainer' and '$OutputContainer' are ready."

# Upload data files
if (!(Test-Path -LiteralPath $DataFolder)) {
    Write-Host "[!] Data folder '$DataFolder' not found. Skipping upload." -ForegroundColor Yellow
} else {
    $files = Get-ChildItem -LiteralPath $DataFolder -File
    if ($files.Count -eq 0) {
        Write-Host "[!] No files found in '$DataFolder'. Skipping upload." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Uploading files to container '$InputContainer'..."
        foreach ($f in $files) {
            Write-Host " - $($f.Name)"
            az storage blob upload `
                --account-name $storageName `
                --account-key $storageKey `
                --container-name $InputContainer `
                --name $f.Name `
                --file $f.FullName `
                --overwrite true `
                --output none
        }
        Write-Host "[OK] Upload complete."
    }
}

# List blobs to confirm
Write-Host ""
Write-Host "Blobs in '$InputContainer':"
az storage blob list --account-name $storageName --account-key $storageKey --container-name $InputContainer --query "[].{name:name,size:properties.contentLength}" -o table

Write-Host ""
Write-Host "=== Storage setup & upload: completed ==="
