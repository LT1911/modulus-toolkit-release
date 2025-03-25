# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 07.10.2024

#write-host "Loading 5-devops-info.psm1!" -ForegroundColor Green

#copied to mod-sysprep-startup.psm1, TODO: put in function, replace both occurences of these 3 lines
$modulus_profile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\Microsoft.PowerShell_profile.ps1"
$profile_path    = "C:\Program Files\PowerShell\7\profile.ps1"
Copy-Item $modulus_profile -Destination $profile_path -Force


#region --- toolkit-related cleanup functions
function Clear-PrepDir {
	#write-Log -Level INFO -Message 'Clearing preparation folder!'
    
	$prepDir    = (Get-PSConfig).directories.prep
    Get-ChildItem $prepDir | Remove-Item -Recurse -Force
}

function Clear-LogsDir {
	#write-Log -Level INFO -Message 'Clearing log folder!'
    
	$logs    = (Get-PSConfig).directories.logs
    Get-ChildItem $logs | Remove-Item -Recurse -Force
}
#endregion
