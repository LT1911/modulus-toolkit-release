#tlukas, 20.02.2025

$moduleName = "modulus-toolkit"                                                                             # Name of the module to update
$versionUrl = "https://raw.githubusercontent.com/LT1911/modulus-toolkit-release/main/version.txt"           # URL to the remote version file
$archiveUrl = "https://raw.githubusercontent.com/LT1911/modulus-toolkit-release/main/modulus-toolkit.7z"    # URL to the packaged module archive

$localModulePath = "C:\Program Files\PowerShell\Modules\$moduleName"

# --- Step 1: Determine the Current Installed Version ---
if (Test-Path "$localModulePath\$moduleName.psd1") {
    try {
        $manifest = Import-PowerShellDataFile "$localModulePath\$moduleName.psd1"
        $currentVersion = [version]$manifest.ModuleVersion
    } catch {
        Write-Warning "Failed to parse manifest; defaulting to version 0.0.0."
        $currentVersion = [version]"0.0.0"
    }
} else {
    $currentVersion = [version]"0.0.0"
}
Write-Host "Current installed version: $currentVersion"

# --- Step 2: Get the Latest Version from Remote ---
try {
    $remoteVersionString = (Invoke-WebRequest -Uri $versionUrl -UseBasicParsing).Content.Trim()
    $remoteVersion = [version]$remoteVersionString
    Write-Host "Latest available version: $remoteVersion"
} catch {
    Write-Error "Failed to retrieve remote version information from $versionUrl"
    #exit 1
}

# --- Step 3: Compare Versions ---
if ($remoteVersion -le $currentVersion) {
    Write-Host "No update needed. Installed version is up-to-date."
    #exit 0
}
Write-Host "An update is available. Proceeding with update..."



# --- Step 4: Download the Module Archive ---
#$tempArchive = Join-Path ([System.IO.Path]::GetTempPath()) ("modulus-toolkit_" + (Get-Date -Format "yyyyMMddHHmmss") + ".7z")

$shell = New-Object -ComObject Shell.Application
$downloadsFolder = $shell.Namespace("shell:Downloads").Self.Path
$downloadsFolder

Write-Host "Downloading module archive to $downloadsFolder"
try {
    Invoke-WebRequest -Uri $archiveUrl -OutFile $downloadsFolder -UseBasicParsing
} catch {
    Write-Error "Failed to download the module archive from $archiveUrl"
    #exit 1
}


<#
# --- Step 4.5: Password Check ---
# Prompt for a password before continuing with extraction and deployment.
# Note: For production use, consider comparing secure hash values instead of plain text.
$expectedPassword = "YourSecurePassword"  # Replace with your actual password or secure retrieval method
$secureInput = Read-Host "Enter password to proceed with update" -AsSecureString

# Convert the secure string to plain text for comparison (demonstration purposes only)
$inputPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
)

if ($inputPassword -ne $expectedPassword) {
    Write-Error "Incorrect password. Update aborted."
    # Optionally, delete the downloaded archive if the password check fails
    if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force }
    exit 1
}

Write-Host "Password verified. Continuing with the update..."

# --- Step 5: Extract the Archive ---
$extractPath = Join-Path ([System.IO.Path]::GetTempPath()) "ModuleUpdate"
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
New-Item -ItemType Directory -Path $extractPath | Out-Null

Write-Host "Extracting archive..."
$sevenZipExe = "7z"  # Ensure 7z.exe is in your PATH or provide the full path
$extractCommand = "$sevenZipExe x `"$tempArchive`" -o`"$extractPath`" -y"
try {
    Invoke-Expression $extractCommand
} catch {
    Write-Error "Extraction failed."
    exit 1
}

# --- Step 6: Install the Updated Module ---
if (Test-Path $localModulePath) {
    $backupPath = $localModulePath + "_" + (Get-Date -Format "yyyyMMddHHmmss")
    try {
        Rename-Item $localModulePath $backupPath -Force
        Write-Host "Backed up existing module to $backupPath"
    } catch {
        Write-Warning "Failed to back up the current module."
    }
}
try {
    Move-Item -Path (Join-Path $extractPath "*") -Destination $localModulePath -Force
    Write-Host "Module updated successfully to version $remoteVersion."
} catch {
    Write-Error "Installation failed. Update aborted."
    exit 1
}

# --- Step 7: Cleanup ---
Remove-Item $tempArchive -Force
Remove-Item $extractPath -Recurse -Force

Write-Host "Update complete. Please restart your PowerShell session or run 'Import-Module $moduleName -Force' to reload the module."
#>