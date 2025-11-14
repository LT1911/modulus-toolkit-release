#tlukas, 27.10.2025

#region --- parameters 
$ProfileLoadStartTime = Get-Date
# Save the user's original warning preference to ensure normal shell operation
$OriginalWarningPreference = $global:WarningPreference
$global:WarningPreference = 'SilentlyContinue'

$moduleName   = 'modulus-toolkit'
$moduleKey    = Test-Path "Env:\MODULUS_KEY"
$key          = $env:MODULUS_KEY
$currentUser  = $env:USERNAME
$allowedUsers = @(
    'ThomasLukas','Administrator','SysprepUser',
    'ext_atronic',
    'scs_su_modulus','csa_su_modulus',
    'scz_su_modulus','csg_su_modulus',
    'sec_su_modulus','scw_su_modulus'
)
#endregion

#region --- old profile cleanup
$publicProfilePath = $PROFILE.AllUsersAllHosts
$signature = '#tlukas'
$cleanUpTime = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

if (Test-Path $publicProfilePath) {
    # Only read the first line for a quick check, using the user's preferred signature
    $firstLine = (Get-Content $publicProfilePath -TotalCount 1 -ErrorAction SilentlyContinue)
    
    # Check if the file starts with the specified signature
    if ($firstLine -like "$signature*") {
        Write-Warning "[$cleanUpTime] Detected legacy custom profile at '$publicProfilePath'. Removing to prevent conflicts."
        # Use Remove-Item with -Force and SilentlyContinue for robustness
        Remove-Item $publicProfilePath -Force -ErrorAction SilentlyContinue
    }
}
#endregion

#region --- preliminary checks
if ($allowedUsers -and ($allowedUsers -notcontains $currentUser)) { 
    $moduleLoadSkipped = $true 
}
#if (-not (Test-Path $moduleKey -PathType Leaf)) { 
if (-not $moduleKey) {
    $moduleLoadSkipped = $true
}
#endregion

#region --- checks to determine if $needsReload
if (-not $moduleLoadSkipped) {
    $latest = Get-Module -ListAvailable $moduleName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $latest) { $moduleLoadSkipped = $true } 

    if (-not $moduleLoadSkipped) {
        $loaded = Get-Module $moduleName -ErrorAction SilentlyContinue
        $needsReload = $false

        if ($loaded -eq $null) {
            $needsReload = $true
        } else {
            if (($loaded.Version -lt $latest.Version) -or ($loaded.Path -ne $latest.Path)) {
                $needsReload = $true
            }
        }

        #Checks say: we must reload
        if ($needsReload) {
            # If a version is loaded, remove it first
            if ($loaded) { Remove-Module $moduleName -ErrorAction SilentlyContinue }
            
            # Ensure the correct execution policy is set for the module files
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force -ErrorAction SilentlyContinue

            # Import the specific newest path. 
            # We use -DisableNameChecking to suppress unapproved verb warnings
            Import-Module -Name $latest.Path -Global -DisableNameChecking -WarningAction SilentlyContinue
        }
    }
}
#endregion

#region --- restoring original $global:WarningPreference and output
# Restore the user's original warning preference to ensure normal shell operation
$global:WarningPreference = $OriginalWarningPreference

# Final execution time log
#$ProfileLoadStartTime = Get-Date #for testing output-format, not for actual code
$executionTime = (Get-Date) - $ProfileLoadStartTime
Write-Host "Loading modulus-toolkit profiles took $([int]$executionTime.TotalMilliseconds)ms." -ForegroundColor DarkGray -NoNewline
#showing the loaded functionality key
if ($key.length -gt 1) {
    write-host " ($key)" -ForegroundColor DarkGray
} else {
    Write-Host "" #just a new line
}
#endregion