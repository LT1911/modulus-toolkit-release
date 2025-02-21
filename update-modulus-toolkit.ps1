# tlukas, 20.02.2025
# modulus-toolkit Update Script with PBKDF2-based Password Verification

# --- Configuration ---
$moduleName       = "modulus-toolkit"                                                                               # Name of the module to update
$versionUrl       = "https://raw.githubusercontent.com/LT1911/modulus-toolkit-release/main/version.txt"             # URL to the remote version file
$archiveUrl       = "https://raw.githubusercontent.com/LT1911/modulus-toolkit-release/main/modulus-toolkit.7z"      # URL to the packaged module archive
$passwordHashUrl  = "https://raw.githubusercontent.com/LT1911/modulus-toolkit-release/main/passwordHash.json"       # URL to the JSON file with PBKDF2 parameters
$localModulePath  = "C:\Program Files\PowerShell\Modules\$moduleName"                                               # Where the module is installed

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
    Return
}

# --- Step 3: Compare Versions ---
if ($remoteVersion -le $currentVersion) {
    Write-Host "No update needed. Installed version is up-to-date."
    Return
}
Write-Host "An update is available. Proceeding with update..."

# --- Step 4: Password Check Using PBKDF2 Parameters from Remote JSON ---
try {
    $jsonContent = (Invoke-WebRequest -Uri $passwordHashUrl -UseBasicParsing).Content | ConvertFrom-Json
    $expectedSalt      = $jsonContent.Salt        # Base64-encoded salt
    $expectedHash      = $jsonContent.Hash        # Base64-encoded expected hash
    $expectedIterations= $jsonContent.Iterations  # Number of iterations (e.g., 10000)
} catch {
    Write-Error "Failed to retrieve or parse password hash JSON from $passwordHashUrl"
    Return
}

# Prompt the user for a password securely
$secureInput = Read-Host "Enter password to proceed with update" -AsSecureString
$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
)

# Convert the salt from Base64 to a byte array
$saltBytes = [Convert]::FromBase64String($expectedSalt)

# Create a PBKDF2 instance to derive the hash from the input password
$pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($plainPassword, $saltBytes, $expectedIterations)
# Get the derived key (assuming the expected hash is 32 bytes long, typical for SHA256)
$derivedKeyBytes = $pbkdf2.GetBytes(32)
$derivedHash = [Convert]::ToBase64String($derivedKeyBytes)

if ($derivedHash -ne $expectedHash) {
    Write-Error "Incorrect password. Update aborted."
    Exit 1
}
Write-Host "Password verified. Continuing with the update..."

# --- Step 5: Download the Module Archive ---
# Determine the Downloads folder using the Shell COM object
$shell = New-Object -ComObject Shell.Application
$downloadsFolder = $shell.Namespace("shell:Downloads").Self.Path

# Define the path (including filename) for the downloaded archive
$tempArchive = Join-Path -Path $downloadsFolder -ChildPath ("modulus-toolkit.7z")
Write-Host "Downloading module archive to $tempArchive"
try {
    Invoke-WebRequest -Uri $archiveUrl -OutFile $tempArchive -UseBasicParsing
} catch {
    Write-Error "Failed to download the module archive from $archiveUrl"
    Exit 1
}

#write-host "Waiting for the download to complete..."
#Start-Sleep -Seconds 5  # Pause to ensure the file is written before extraction

# --- Step 6: Extract the Archive using the call operator ---
$extractPath = $downloadsFolder

#if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
#New-Item -ItemType Directory -Path $extractPath | Out-Null

Write-Host "Extracting archive..."
$sevenZipExe = 'C:\Program Files\7-Zip\7z.exe'  # Provide the full path if necessary
# Use the call operator (&) so that PowerShell correctly interprets the command and its parameters.
& $sevenZipExe x $tempArchive -o"$extractPath" -p"$plainPassword" -y

# Check for errors by verifying that files were extracted.
if (!(Test-Path $extractPath) -or (Get-ChildItem $extractPath | Measure-Object).Count -eq 0) {
    Write-Error "Extraction failed."
    Exit
} else {
    Write-Host "Extraction succeeded."
}

# --- Step 7: Install the Updated Module ---
<#backup not needed
if (Test-Path $localModulePath) {
    $backupPath = $localModulePath + "_" + (Get-Date -Format "yyyyMMddHHmmss")
    try {
        Rename-Item $localModulePath $backupPath -Force
        Write-Host "Backed up existing module to $backupPath"
    } catch {
        Write-Warning "Failed to back up the current module."
    }
}
#>

try {
    # Assumes the archive contains the module folder structure.
    Move-Item -Path (Join-Path $extractPath "\modulus-toolkit\*") -Destination $localModulePath -Force -ErrorAction SilentlyContinue
    Write-Host "Module updated successfully to version $remoteVersion."
} catch {
    Write-Error "Installation failed. Update aborted."
    Return
}

# --- Step 8: Cleanup ---
Remove-Item $tempArchive -Force
Remove-Item $extractPath"\modulus-toolkit\" -Recurse -Force

Write-Host "Update complete. Please restart your PowerShell session or run 'Import-Module $moduleName -Force' to reload the module."
