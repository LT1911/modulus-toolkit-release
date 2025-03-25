# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#mod-sysprep-startup.ps1 to ensure PSSessions are running in PS7 scope with ability to load modulus-toolkit!
# Ensure PowerShell 7 is launched
if ($PSVersionTable.PSVersion.Major -lt 7) {

	#copied from modulus-core.psm1, TODO: put in function, replace both occurences of these 3 lines
    $modulus_profile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\Microsoft.PowerShell_profile.ps1"
    $profile_path    = "C:\Program Files\PowerShell\7\profile.ps1"
    Copy-Item $modulus_profile -Destination $profile_path -Force

    & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoExit -Command {
        Write-Host "Started PowerShell 7 session" -ForegroundColor Green

        #TODO: move initialize into last step of modulus-sysprep 
        #and only do sysprep if certain environment variable is set, then i can have only 1 startup.ps1
		Modulus-Sysprep
		Initialize-VM $ENV:MODULUS_SERVER	
    }
} else {
    Write-Host "Already running PowerShell 7" -ForegroundColor Green
	
    #TODO: move initialize into last step of modulus-sysprep 
    #and only do sysprep if certain environment variable is set, then i can have only 1 startup.ps1
	Modulus-Sysprep
	Initialize-VM $ENV:MODULUS_SERVER	
	
}