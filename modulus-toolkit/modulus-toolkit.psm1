# tlukas, 24.10.2025

#region --- parameters
$ModuleRoot = 'C:\Program Files\PowerShell\Modules\modulus-toolkit'
$server     = $env:COMPUTERNAME
$serverType = $env:MODULUS_SERVER
$elevated   = Get-ElevatedState
$SP = Test-FeatureUnlocked "SP" #SysPrep
$CC = Test-FeatureUnlocked "CC" #CasinoChanger
$LB = Test-FeatureUnlocked "LB" #LiquiBase
$HC = Test-FeatureUnlocked "HC" #HealthCheck
$RS = Test-FeatureUnlocked "RS" #ReplicatedScope
$GU = Test-FeatureUnlocked "GU" #GuidedUpdate
$moduleVersion = "Unknown (Error)" # Default fallback value
try {
    $manifestPath = Join-Path $ModuleRoot "modulus-toolkit.psd1"
    $moduleData = Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop
    $moduleVersion = $moduleData.ModuleVersion
} catch {
    #Write-Warning "Failed to read module manifest for version: $($_.Exception.Message)"
}
#endregion

#region --- imports depending on elevation MODULUS_KEY-variable + welcome message
if ($elevated) {    
    $importParams = @{
        DisableNameChecking = $true
        WarningAction       = 'SilentlyContinue'
    }
    Import-Module (Join-Path $ModuleRoot 'modules\4-server-admin.psm1') @importParams -Global
    Import-Module (Join-Path $ModuleRoot 'modules\6-devops-admin.psm1') @importParams -Global
    Import-Module (Join-Path $ModuleRoot 'modules\8-oracle-admin.psm1') @importParams -Global
    Import-Module (Join-Path $ModuleRoot 'modules\grafana.psm1') @importParams -Global
    if ($SP) { Import-Module (Join-Path $ModuleRoot 'modules\9-sysprep.psm1') @importParams -Global }
    if ($CC) { Import-Module (Join-Path $ModuleRoot 'modules\10-casinochanger.psm1') @importParams -Global }
    if ($LB) { Import-Module (Join-Path $ModuleRoot 'modules\12-liquibase.psm1') @importParams -Global }
    if ($HC) { Import-Module (Join-Path $ModuleRoot 'modules\11-healthcheck.psm1') @importParams -Global }
    if ($RS) { Import-Module (Join-Path $ModuleRoot 'modules\replicatedscope.psm1') @importParams -Global }
    if ($GU) { Import-Module (Join-Path $ModuleRoot 'modules\guidedupdate.psm1') @importParams -Global }
    
    #Write-Host "Loading modulus-toolkit v$($moduleVersion) in elevated mode!" -ForegroundColor Blue
    Write-Host "Loading modulus-toolkit v$($moduleVersion)" -ForegroundColor Yellow -NoNewline
    Write-Host " on $($server) ($($serverType))" -ForegroundColor DarkYellow -NoNewline
    Write-Host " in elevated mode!" -ForegroundColor DarkRed 
} else {
    Write-Host "Loading modulus-toolkit v$($moduleVersion)" -ForegroundColor Yellow -NoNewline
    Write-Host " on $($server) ($($serverType))" -ForegroundColor DarkYellow -NoNewline
    Write-Host " in standard mode!" -ForegroundColor Gray
}
#TODO - help file rework and showing the message only once per session
#Write-host "Type 'Get-Help Modulus' for getting started." -ForegroundColor DarkGray
#endregion

#region --- one-time session initialization
# This logic runs every time the module is imported, but only calls Initialize-ModulusProfile once per session.
if (-not (Get-Variable -Name Global:Modulus_Profile_Init_Complete -ErrorAction SilentlyContinue)) {
    #Write-Verbose "Calling Initialize-ModulusProfile for one-time session setup." -Verbose
    if (Get-Command -Name 'Initialize-ModulusProfile' -ErrorAction SilentlyContinue) {
        
        # Initialize-ModulusProfile contains internal checks (up-to-date/overwrite)
        if (Initialize-ModulusProfile) {
            $Global:Modulus_Profile_Init_Complete = $true
        }
    }
}
#endregion