# ================== 0. Load config and resolve all key names ==================
$parametersPath = "./parameters.json"
if (!(Test-Path -Path $parametersPath)) {
    Write-Error "Parameters file not found at path: $parametersPath"
    exit 1
}
$parameters = Get-Content -Raw -Path $parametersPath | ConvertFrom-Json
$projectTag = $parameters.parameters.tags.value.Project
$resourceGroupName = "$projectTag-rg"
$storagePrefix = $parameters.parameters.storageAccountName.value

# ================== 1. Resolve Databricks workspace name and URL ==================
$wsName = az databricks workspace list -g $resourceGroupName --query "[0].name" -o tsv
if ([string]::IsNullOrWhiteSpace($wsName)) {
    Write-Error "No Databricks workspace found in resource group $resourceGroupName."
    exit 1
}
Write-Host "Databricks workspace name: $wsName"

$wsUrlShort = az databricks workspace show -n $wsName -g $resourceGroupName --query "workspaceUrl" -o tsv
if ([string]::IsNullOrWhiteSpace($wsUrlShort)) {
    Write-Error "Unable to retrieve workspace URL for $wsName."
    exit 1
}
$wsUrl = "https://$wsUrlShort"
Write-Host "Databricks workspace URL: $wsUrl"

# ================== 2. Ensure Databricks PAT is set ==================
if (-not $env:DATABRICKS_TOKEN) {
    Write-Error "Environment variable DATABRICKS_TOKEN not set. Please set your personal access token before running."
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $env:DATABRICKS_TOKEN"
    "Content-Type"  = "application/json"
}

# ================== 3. Identify Databricks user and workspace folder ==================
$userInfoUri = "$wsUrl/api/2.0/preview/scim/v2/Me"
try {
    $userInfo = Invoke-RestMethod -Method GET -Uri $userInfoUri -Headers $headers
} catch {
    Write-Error "Failed to call Databricks API: $_"
    exit 1
}
$userName = $userInfo.userName
Write-Host "Workspace userName: $userName"

$repoRoot = (Get-Location).Path
$localNotebooksFolder = Join-Path $repoRoot "notebooks"
$workspaceFolderPath = "/Users/$userName/notebooks"

function Ensure-Workspace-Dir {
    param ($folderPath)
    $mkdirPayload = @{ path = $folderPath; object_type = "DIRECTORY" } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$wsUrl/api/2.0/workspace/mkdirs" -Method POST -Headers $headers -Body $mkdirPayload | Out-Null
        Write-Host "Ensured workspace directory: $folderPath"
    } catch {
        Write-Warning "Failed to ensure directory $folderPath $_"
    }
}
Ensure-Workspace-Dir $workspaceFolderPath

# ================== 4. Upload notebooks from local 'notebooks' folder ==================
$files = Get-ChildItem -Path (Join-Path $localNotebooksFolder '*') -Include *.py,*.scala,*.sql,*.dbc -File
Write-Host "Found $($files.Count) notebook file(s) in $localNotebooksFolder"
if ($files.Count -eq 0) {
    Write-Host "No notebook files found! Please check your local folder or path."
}

foreach ($file in $files) {
    $filePath = $file.FullName
    $fileName = $file.Name
    $fileExt = $file.Extension.ToLower()
    Write-Host "Uploading $fileName to $workspaceFolderPath ..."

    $contentBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($filePath))
    $language = switch ($fileExt) {
        ".py"    { "PYTHON" }
        ".scala" { "SCALA" }
        ".sql"   { "SQL" }
        ".dbc"   { "" }
        default  { "PYTHON" }
    }
    $format = if ($fileExt -eq ".dbc") { "DBC" } else { "SOURCE" }

    $importPayload = @{
        path      = "$workspaceFolderPath/$fileName"
        format    = $format
        language  = $language
        content   = $contentBase64
        overwrite = $true
    } | ConvertTo-Json -Depth 10

    try {
        $resp = Invoke-RestMethod -Uri "$wsUrl/api/2.0/workspace/import" -Method POST -Headers $headers -Body $importPayload
        Write-Host "✅ Imported: $fileName"
    } catch {
        Write-Warning "❌ Failed to import $fileName : $_"
    }
}

# List files in Databricks folder
$listUri = "$wsUrl/api/2.0/workspace/list?path=$($workspaceFolderPath)"
try {
    $result = Invoke-RestMethod -Uri $listUri -Method GET -Headers $headers
    if ($result.objects) {
        $result.objects | ForEach-Object {
            Write-Host " - $($_.path)  ($($_.object_type))"
        }
    } else {
        Write-Host " (No files found in $workspaceFolderPath)"
    }
} catch {
    Write-Warning "❌ Failed to list contents of $workspaceFolderPath - $_"
}

# # ================== 5. Create Databricks cluster ==================
$clusterPayload = @{
    cluster_name           = "sandbox-cluster"
    spark_version          = "13.3.x-scala2.12"
    node_type_id           = "Standard_DS3_v2"
    num_workers            = 2
    autotermination_minutes= 30
} | ConvertTo-Json

$clusterCreateResp = Invoke-RestMethod -Uri "$wsUrl/api/2.0/clusters/create" -Method POST -Headers $headers -Body $clusterPayload
$clusterId = $clusterCreateResp.cluster_id
Write-Host "Created cluster with cluster_id: $clusterId"

# Wait for cluster RUNNING
$maxWait = 600
$waited = 0
while ($true) {
    $statusResp = Invoke-RestMethod -Uri "$wsUrl/api/2.0/clusters/get?cluster_id=$clusterId" -Headers $headers
    if ($statusResp.state -eq "RUNNING") { break }
    if ($statusResp.state -eq "TERMINATED" -or $statusResp.state -eq "ERROR") {
        throw "Cluster failed to start."
    }
    Start-Sleep -Seconds 10
    $waited += 10
    if ($waited -gt $maxWait) { throw "Cluster did not reach RUNNING state in time." }
}
# Write-Host "Cluster is RUNNING."

# # ================== 6. Query Storage Account (Azure - for dynamic name) ==================
$storageAccountName = az storage account list `
    --resource-group $resourceGroupName `
    --query "[?starts_with(name, '$storagePrefix')].name | [0]" `
    -o tsv

if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
    Write-Error "Could not find a storage account starting with '$storagePrefix' in $resourceGroupName."
    exit 1
}
Write-Host "Resolved storage account name: $storageAccountName"

# # ================== 7. Submit notebook job using the created cluster ==================

# Adjust variable below to the notebook you want to run!
$notebookPath = "$workspaceFolderPath/squirrel_poc.py"

$runPayload = @{
    existing_cluster_id = $clusterId
    notebook_task = @{
        notebook_path = $notebookPath
        base_parameters = @{
            storage_account  = $storageAccountName
            input_container  = "input"
            output_container = "output"
            csv_file         = "park-data.csv"
        }
    }
} | ConvertTo-Json

$runResp = Invoke-RestMethod -Uri "$wsUrl/api/2.0/jobs/runs/submit" -Method POST -Headers $headers -Body $runPayload
$runId = $runResp.run_id
Write-Host "Notebook run submitted, run_id: $runId"

# Poll for job completion
while ($true) {
    $jobStatus = Invoke-RestMethod -Uri "$wsUrl/api/2.0/jobs/runs/get?run_id=$runId" -Headers $headers
    $state = $jobStatus.state.life_cycle_state
    if ($state -in @("TERMINATED","SKIPPED","INTERNAL_ERROR")) { break }
    Start-Sleep -Seconds 10
}
Write-Host "Job $runId completed state: $state"

# ================== 8. Terminate cluster after job is done ==================
$clusterDeletePayload = @{ cluster_id = $clusterId } | ConvertTo-Json
Invoke-RestMethod -Uri "$wsUrl/api/2.0/clusters/delete" -Method POST -Headers $headers -Body $clusterDeletePayload
Write-Host "Cluster $clusterId terminated."

# ================== 9. List output from Azure 'output' container ==================
Write-Host "`nListing blobs in the 'output' container..."

$storageKey = az storage account keys list `
    --account-name $storageAccountName `
    --resource-group $resourceGroupName `
    --query "[0].value" -o tsv

if ([string]::IsNullOrWhiteSpace($storageKey)) {
    Write-Error "Failed to get storage account key for $storageAccountName."
    exit 1
}

$blobs = az storage blob list `
    --account-name $storageAccountName `
    --container-name output `
    --account-key $storageKey `
    --query "[].name" -o tsv

if ($blobs) {
    Write-Host "Output files found:"
    $blobs | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "No files found in the output container."
}

# ================== 10. Download the output file to local ==================
# (Change file name if your output is different)
$outputFile = "squirrel_output.xlsx"
Write-Host "`nDownloading $outputFile from Azure blob..."

az storage blob download `
    --account-name $storageAccountName `
    --container-name output `
    --name $outputFile `
    --file $outputFile `
    --account-key $storageKey

Write-Host "`n✅ Download complete: $outputFile (saved in current directory)"
