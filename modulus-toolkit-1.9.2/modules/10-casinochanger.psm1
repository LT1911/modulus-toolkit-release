#tlukas, 29.10.2024

#write-host "Loading 10-casinochanger.psm1!" -ForegroundColor Green

#region --- MD, install&uninstall
function Open-MOD-CasinoChanger-Manual {
    Write-Log "Open-MOD-CasinoChanger-Manual" -Header
    Write-Log "Check your browser and follow the instructions in the manual!"

	$path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\CasinoChanger.md"
	if (Test-Path -path $path) {
        Start-Process "chrome.exe" "`"$path`""
    } else {
        Write-Log "Manual was not found at $path" -Level ERROR
    }
}

function Install-CasinoChanger {
    #Write-Log "Install-CasinoChanger" -Header
    Write-log "Installing needed procedures..."

    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'CasinoChanger\CC_setup.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Installing CasinoChanger into $TNS" `
        -EndLogMessage "Finished!" 
}
function Uninstall-CasinoChanger {
    #Write-Log "Uninstall-CasinoChanger" -Header
    Write-log "Uninstalling no longer needed procedures..."
    
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'CasinoChanger\CC_cleanup.sql'

    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Uninstalling CasinoChanger from $TNS" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- actual execution REWORK TODO
function Start-CasinoChanger {

    Write-Log "Start-CasinoChanger" -Header

    Install-CasinoChanger

    #ask for user confirmation
    $confirm = Read-Host "Do you want to proceed with the CasinoChanger script (Y/N)?"
    if ($confirm -ne "Y") {
        Write-Log "CasinoChanger aborted!" WARNING
        Return
    }

    $old_casinoID  = Read-Host "Please enter the CASINO_ID you want to replace!: (example from template: 999)"
   
    
    $new_codsociet = Get-CustomerCode
    $new_casinoID  = Get-CasinoID
    $new_codetabli = Get-CasinoCode
    $new_shortname = Get-CasinoName
    $new_longname  = Get-CasinoLongName
     
    $old_casinoID
    $new_casinoID
    $new_codsociet
    $new_codetabli

    Start-Sleep -Seconds 3
    $confirm = Read-Host "If all the input is correct, please confirm you want to continue with the reconfiguration: (Y/N)"
    if ($confirm -ne "Y") {
        Write-Log "CasinoChanger aborted!" WARNING
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
   
	Write-Log "Starting the CasinoChanger main script for $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    Uninstall-CasinoChanger

    Write-log "Start-CasinoChanger completed!" -Level INFO
}
#endregion

#Export-ModuleMember -Function * -Alias * -Variable *