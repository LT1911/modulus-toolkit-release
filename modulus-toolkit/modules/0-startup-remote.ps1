# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#mod-startup.ps1 to ensure PSSessions are running in PS7 scope with ability to load modulus-toolkit!
# Ensure PowerShell 7 is launched in the remote session
if ($PSVersionTable.PSVersion.Major -lt 7) {

    #copied from modulus-core.psm1, TODO: put in function, replace both occurences of these 3 lines
    $modulus_profile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\Microsoft.PowerShell_profile.ps1"
    $profile_path    = "C:\Program Files\PowerShell\7\profile.ps1"
    Copy-Item $modulus_profile -Destination $profile_path -Force
    
    & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoExit -Command {
        Write-Host "Started PowerShell 7 session" -ForegroundColor Green
        # Add any additional startup commands here
    }
} else {
    Write-Host "Already running PowerShell 7" -ForegroundColor Green
}