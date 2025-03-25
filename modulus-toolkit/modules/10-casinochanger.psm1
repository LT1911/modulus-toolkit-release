# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 29.10.2024

#region --- check if toolkit is in elevated state
if (Get-ElevatedState) {
    $CasinoChangerKey = Test-Path -Path 'C:\Program Files\PowerShell\Modules\modulus-toolkit\CC.key'
    if($CasinoChangerKey) { 
        Write-Host "CC.key found - CasinoChanger functionality enabled!" -ForegroundColor Cyan
    } else {
        Return
    }
} else {
    #Skipping the rest of the file
    Return
}
#endregion

#region --- MD, setup & cleanup
function Open-CasinoChanger-Help {
	write-host " > Opening modulus-toolkit's CasinoChanger help file!" -ForegroundColor Yellow
	$path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\CasinoChanger.md"
	if (Test-Path -path $path) {
        Start-Process "chrome.exe" "`"$path`""
    } else {
        Write-Host "Help file was not found at $path" -ForegroundColor Red
    }
}

function Setup-CasinoChanger {
    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'CasinoChanger\CC_setup.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Setting up the CasinoChanger functionality for $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}

function Cleanup-CasinoChanger {
    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'CasinoChanger\CC_cleanup.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Cleaning up the CasinoChanger functionality for $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}
#endregion



#region --- actual execution
function Execute-CasinoChanger {

    Setup-CasinoChanger

    write-host "---------------------------" -ForegroundColor Yellow
    write-host "       CasionChanger       " -ForegroundColor Yellow
    write-host "          running          " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow

    #ask for user confirmation
    $confirm = Read-Host "Do you want to proceed with the CasinoChanger script (Y/N)?"
    if ($confirm -ne "Y") {
        write-host "CasionChanger aborted!"
        write-host "----------------------"
        Exit
    }

    $old_casinoID  = Read-Host "Please enter the CASINO_ID you want to replace!: (example from template: 999)"
   
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings

    $new_casinoID  = $general_settings.specifics.casinoID
    $new_codsociet = $general_settings.specifics.SOCIET
    $new_codetabli = $general_settings.specifics.etabli
    $new_longname  = $general_settings.specifics.longname
    $new_shortname = $general_settings.specifics.shortname
     
    $old_casinoID
    $new_casinoID
    $new_codsociet
    $new_codetabli

    Start-Sleep -Seconds 3
    $confirm = Read-Host "If all the input is correct, please confirm you want to continue with the reconfiguration: (Y/N)"
    if ($confirm -ne "Y") {
        write-host "Reconfiguration aborted!"
        write-host "-----------------------"
        Exit
    }

    $CC_execution = @"
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
set serveroutput on
BEGIN
    MOD_CasinoChanger(      
        $old_casinoID,                
        $new_casinoID,                
        '$new_codsociet',              
        '$new_codetabli',               
        'MODULUS',          
        '$new_longname',          
        '$new_shortname'               
    );
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\CasinoChanger\CC_execution.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $CC_execution | Out-File -FilePath $outputFilePath -Encoding UTF8

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'CasinoChanger\CC_execution.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Executing the CasinoChanger main script for $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    Cleanup-CasinoChanger
    
}
#endregion