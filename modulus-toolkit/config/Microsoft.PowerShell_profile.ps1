#tlukas, 02.10.2024
# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs


$currentUser = $env:USERNAME
$allowedUsers = @("ThomasLukas", "Administrator", "SysprepUser")

if ($allowedUsers -contains $currentUser) {
    # Ensure the module is force-reloaded at session start but avoid redundant imports
    $module = Get-Module -Name 'modulus-toolkit'

    if ($null -ne $module) {
        Remove-Module -Name 'modulus-toolkit' -ErrorAction SilentlyContinue
    }

    $mainKey  = Test-Path -Path 'C:\Program Files\PowerShell\Modules\modulus-toolkit\TK.key'
    if ($mainKey) {
        Import-Module modulus-toolkit -Force -DisableNameChecking
        if (Get-ElevatedState) {
            Write-host "Toolkit is elevated." -ForegroundColor Green
        }
        #run a check upon startup
        Assert-MOD-Components -Silent
    } else {
        #no $mainKey, no party
        Return
    }
}
else {
    Return
}