# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 22.10.2024

#check if toolkit is in elevated state
if (Get-ElevatedState) {
    #Write-Host "Loading 8-oracle-admin.psm1!" -ForegroundColor Cyan
    #Continue loading the psm1
} else {
    #Skipping the rest of the file
    Return;
}

<#INFO
- Oracle tnsnames.ora attempt
- DB update first steps
- default profile
- JP update helper
- expdp / impdp
- execute sysprivs
#>

#region --- Oracle tnsnames.ora attempt
function Set-Oracle-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "    Client32 tnsnames.ora    " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow
    
    $config = get-MOD-Component-Config "Oracle Client Home (32-bit)" "tnsnames.ora"

    $hostname = Get-MOD-DB-hostname

    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    # Read the content of the tnsnames.ora file
    $tnsnamesContent = Get-Content -Path $config -Raw

    # Define the entries you want to modify (e.g., GLX and JKP)
    $entriesToModify = @("GLX", "JKP", "JKP.local","LISTENER_GLX","LISTENER_JKP")

    # Iterate through each entry and update the hostname
    #foreach ($entry in $entriesToModify) {
        #$pattern = "HOST = \w+"
        #$replacement = "HOST = $hostname"
        #$tnsnamesContent = $tnsnamesContent -replace "(?s)($entry.*?($pattern))", "`$1 -replace '$pattern', '$replacement'"
    #}

    # Iterate through each entry and update the hostname
    foreach ($entry in $entriesToModify) {
        $tnsnamesContent = $tnsnamesContent -replace "(?ms)(($entry\s*=\s*\n\s*\(.*?HOST\s*=\s*)\w+)", "`$2$hostname"
    }

    # Write the updated content back to the tnsnames.ora file
    $tnsnamesContent | Set-Content -Path $config
    write-host "-----------------------------" -ForegroundColor Green
}
#endregion

#region --- DB update first steps

#TODO: maybe rename to Load-*
function Execute-GalaxisOracle-jar {
	$directory = Get-PrepDir 
	$directory = $directory + '\HFandLib\'
    #---
    $user = 'mis'
    $DB   = 'GLX'
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    $pass = $cred.GetNetworkCredential().Password
	$file = 'galaxisoracle.jar'
	$file = $directory + $file
    #---
    if (Test-Path $file) {
		loadjava -u $user/$pass@GLX -r -v $file
    } else {
        throw "Did not find $file - make sure you run Prep-HFandLib first!"
    }
}
#endregion

#region --- default profile
function Set-GLX-default-profile {

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'set_default_profile.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Setting up the default profile for $DB - case sensitive settings included!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}

function Set-JKP-default-profile {

    $user   = 'sys'
    $DB     = 'JKP'
    $script = 'set_default_profile.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Setting up the default profile for $DB - case sensitive settings included!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}
#endregion

#region --- JP update helper
function Set-JKP-DB-version-1050 {

    $user   = 'as_security'
    $DB     = 'JKP'
    $script = 'grips_patch_table_disable_trigger.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB

    # 1st step: disable trigger in as_security!
    write-host "Disabling trigger in $user!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    # 2nd step: update table in as_security!
    $script = 'grips_patch_table_update.sql'
    write-host "Updating versions in $user!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    # 3rd step: enable trigger in as_security!
    $script = 'grips_patch_table_enable_trigger.sql'
    write-host "Enabling trigger in $user!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    # 4th step: disable trigger in as_base!
    $user   = 'as_base'
    $script = 'grips_patch_table_disable_trigger.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    write-host "Disabling trigger in $user!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    # 5th step: update table in as_jackpot!
    $user   = 'as_jackpot'
    $script = 'grips_patch_table_update.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    write-host "Updating versions in $user!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    # 6th step: enable trigger in as_base!
    $user   = 'as_base'
    $script = 'grips_patch_table_enable_trigger.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    write-host "Enabling trigger in $user!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script

    Write-host "Done. Please check the versions again." -ForegroundColor Red

}
#endregion

#region --- change hostname/IP in relevant DB tables
function Update-Scope-CPOSTRV {
    
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings
    $new_codsociet = $general_settings.specifics.SOCIET
    $new_codetabli = $general_settings.specifics.etabli
    $sp_user       = $general_settings.database_users.specific
    $new_APP_HN    = Get-MOD-APP-hostname
    $new_DB_HN     = Get-MOD-DB-hostname

    $reconfigScope = Get-ReconfigurationScope
    $old_APP_HN    = $reconfigScope.APP_HN
    $old_DB_HN     = $reconfigScope.DB_HN

    $onthefly = @"
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN
    UPDATE 
        $sp_user.CPOSTRV
    SET
        COD_POST   = '$new_APP_HN',
        COD_SOCIET = '$new_codsociet',
        COD_ETABLI = '$new_codetabli'
    WHERE
        COD_POST   = '$old_APP_HN';
    UPDATE 
        $sp_user.CPOSTRV
    SET
        COD_POST   = '$new_DB_HN',
        COD_SOCIET = '$new_codsociet',
        COD_ETABLI = '$new_codetabli'
    WHERE
        COD_POST   = '$old_DB_HN';
    COMMIT;
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\CPOSTRV.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'onthefly\CPOSTRV.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Updating $sp_user.CPOSTRV in $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}

function Update-Scope-FRECEPTION {
    
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings
    $new_codsociet = $general_settings.specifics.SOCIET
    $new_codetabli = $general_settings.specifics.etabli
    $sp_user       = $general_settings.database_users.specific
    $new_APP_HN    = Get-MOD-APP-hostname
    $new_DB_HN     = Get-MOD-DB-hostname

    $reconfigScope = Get-ReconfigurationScope
    $old_APP_HN    = $reconfigScope.APP_HN
    $old_DB_HN     = $reconfigScope.DB_HN

    $onthefly = @"
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN
    UPDATE 
        $sp_user.FRECEPTION
    SET
        HSTNME   = '$new_APP_HN'
    WHERE
        HSTNME   = '$old_APP_HN';
    UPDATE 
        $sp_user.FRECEPTION
    SET
        HSTNME   = '$new_DB_HN'
    WHERE
        HSTNME   = '$old_DB_HN';
    COMMIT;
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\FRECEPTION.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'onthefly\FRECEPTION.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Updating $sp_user.FRECEPTION in $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}

function Update-Scope-SWKSTNDIS {
    
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings
    $new_codsociet = $general_settings.specifics.SOCIET
    $new_codetabli = $general_settings.specifics.etabli
    $sp_user       = $general_settings.database_users.specific
    $new_APP_HN    = Get-MOD-APP-hostname
    $new_DB_HN     = Get-MOD-DB-hostname

    $reconfigScope = Get-ReconfigurationScope
    $old_APP_HN    = $reconfigScope.APP_HN
    $old_DB_HN     = $reconfigScope.DB_HN

    $onthefly = @"
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN
    UPDATE 
        $sp_user.SWKSTNDIS
    SET
        COD_POST   = '$new_APP_HN'
    WHERE
        COD_POST   = '$old_APP_HN';
    UPDATE 
        $sp_user.SWKSTNDIS
    SET
        COD_POST   = '$new_DB_HN'
    WHERE
        COD_POST   = '$old_DB_HN';
    COMMIT;
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\SWKSTNDIS.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'onthefly\SWKSTNDIS.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Updating $sp_user.SWKSTNDIS in $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}

function Update-Scope-NFLRSVR {
    
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings
    $new_FS_IP     = (Get-MOD-FS-OFFICE-NIC).IPAddress
    $new_FS_HN     = Get-MOD-FS-hostname

    $reconfigScope = Get-ReconfigurationScope
    $old_FS_HN     = $reconfigScope.FS_HN

    $onthefly = @"
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN
    UPDATE 
        SLOT.NFLRSVR
    SET
        ID_ADR   = '$new_FS_IP',
        hostname = '$new_FS_HN'
    WHERE
        hostname = '$old_FS_HN';
    COMMIT;
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\NFLRSVR.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'onthefly\NFLRSVR.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Updating SLOT.NFLRSVR in $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
}

function Update-Scope-APP_PARAM {
    
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings
    $sp_user       = $general_settings.database_users.specific
    $new_APP_IP     = (Get-MOD-APP-OFFICE-NIC).IPAddress

    $reconfigScope = Get-ReconfigurationScope
    $old_APP_IP     = $reconfigScope.APP_IP

    $onthefly = @"
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN
    UPDATE 
        $sp_user.APP_PARAM
    SET
        VALUE    = '$new_APP_IP'
    WHERE
        VALUE    = '$old_APP_IP';
    COMMIT;
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\APP_PARAM.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'onthefly\APP_PARAM.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Updating $sp_user.APP_PARAM in $DB!" -ForegroundColor Yellow
    $Test = Execute-SQL-Script -cred $cred -DB $DB -script $script
    $Test
}

function Enable-AutomaticMeterIntegration {
    
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings
    $sp_user       = $general_settings.database_users.specific
    $new_FS_IP     = (Get-MOD-FS-OFFICE-NIC).IPAddress
    $new_FS_HN     = Get-MOD-FS-hostname

    $onthefly = @"
BEGIN
    UPDATE 
        $sp_user.APP_PARAM
    SET
        VALUE = '1'
    WHERE
        key   = 'AUTOMATIC_INTEGRATION'
    COMMIT;
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\APP_PARAM.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'onthefly\APP_PARAM.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
   
	write-host "Updating $sp_user.APP_PARAM in $DB!" -ForegroundColor Yellow
    $Test = Execute-SQL-Script -cred $cred -DB $DB -script $script
    $Test
}

#endregion

#region --- expdp / impdp
function Prep-GLX-EXP_DIR {

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'GLX_EXP_DIR.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    #$wd     = 'G:\Export'
    #$output = 'output_GLX_EXP_DIR.sql'

    # steps before execution
    #$cwd = Get-Location
    #Set-Location -Path $wd

    #if (!(Test-Path $script)) {
    #    write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
    #    Return $false
    #}

    # removing previously spooled output!
    #if (Test-Path $output) {
    #    write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
    #    remove-item $output -ErrorAction SilentlyContinue
    #}

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Preparing EXP_DIR in $DB using $script!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Prepared EXP_DIR in $DB!" -ForegroundColor Yellow
    #Write-host "Please check and recompile if needed!" -ForegroundColor Red
    #write-host "Spooled output to:" -ForegroundColor Yellow
    #write-host "np $wd\$output" -ForegroundColor Yellow
    #Set-Location -Path $cwd
}

function Prep-JKP-EXP_DIR {

    $user   = 'sys'
    $DB     = 'JKP'
    $script = 'JKP_EXP_DIR.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    #$wd     = 'F:\Export'
    #$output = 'output_JKP_EXP_DIR.sql'

    # steps before execution
    #$cwd = Get-Location
    #Set-Location -Path $wd

    #if (!(Test-Path $script)) {
    #    write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
    #    Return $false
    #}

    # removing previously spooled output!
    #if (Test-Path $output) {
    #    write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
    #    remove-item $output -ErrorAction SilentlyContinue
    #}

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Preparing EXP_DIR in $DB using $script!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -script $script
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Prepared EXP_DIR in $DB!" -ForegroundColor Yellow
    #Write-host "Please check and recompile if needed!" -ForegroundColor Red
    #write-host "Spooled output to:" -ForegroundColor Yellow
    #write-host "np $wd\$output" -ForegroundColor Yellow
    #Set-Location -Path $cwd
}

function Execute-Full-Export {
    param (
        [PSCredential]$cred,    
        [string]$DB,
        [string]$EXP_DIR
    )

    #static defintion of expdp-binary!
    $expdp = 'D:\Oracle\Ora19c\bin\expdp.exe'
    if (!(Test-Path $expdp)) {
        Write-Host "Error: expdp executable not found at $expdp!" -ForegroundColor Red
        Return $False
    }
    
    #managing credentials
    $user = $cred.UserName
    $pass = $cred.GetNetworkCredential().Password

    $dmp = $DB+"_full.dmp"
    $log = $DB+"_full.log"
    $par = "expdp_"+$DB+".par"

    #checking directory and previous files
    if (Test-Path $EXP_DIR) {

        if (Test-Path "$EXP_DIR\$dmp") {
            write-host "Removing previous dump file!" -ForegroundColor Yellow
            Remove-item "$EXP_DIR\$dmp" -Force
        }
        if (Test-Path "$EXP_DIR\$dmp") {
            write-host "Removing previous log file!" -ForegroundColor Yellow
            Remove-item $log -Force
        }
        if (Test-Path "$EXP_DIR\$par") {
            write-host "Removing previous par file!" -ForegroundColor Yellow
            Remove-item "$EXP_DIR\$dmp" -Force
        }
    } else {
        Write-Host "Info: target destination $EXP_DIR was not found!" -ForegroundColor Yellow
        Write-Host "Info: Creating $EXP_DIR!"
        New-Item -Path $EXP_DIR
    }

    $content = @"
userid=$user/$pass@$DB
directory=EXP_DIR
dumpfile=$dmp
logfile=$log
full=y
"@
    
    $content | Out-File -FilePath $par -Encoding ASCII

    Write-Host "Starting FULL export for $DB to $EXP_DIR!" -ForegroundColor Yellow
    Write-host "Started at:  $(Get-Date)" -ForegroundColor Yellow

    & $expdp parfile=$par
    
    Remove-Item $par -ErrorAction SilentlyContinue

    Write-host "Finished at:  $(Get-Date)" -ForegroundColor Yellow
    write-host "Export log can be found at:" -ForegroundColor Yellow
    write-host "np $EXP_DIR\$log" -ForegroundColor Yellow
}

function Execute-Full-Import {
    param (
        [PSCredential]$cred,    
        [string]$DB,
        [string]$EXP_DIR
    )

    #static defintion of expdp-binary!
    $impdp = 'D:\Oracle\Ora19c\bin\impdp.exe'
    if (!(Test-Path $impdp)) {
        Write-Host "Error: impdp executable not found at $expdp!" -ForegroundColor Red
        Return $False
    }
    
    #managing credentials
    $user = $cred.UserName
    $pass = $cred.GetNetworkCredential().Password

    $dmp = $DB+"_full.dmp"
    $log = $DB+"_full_imp.log"
    $par = "impdp_"+$DB+".par"

    #checking directory and previous files
    if (Test-Path $EXP_DIR) {

        if (!(Test-Path "$EXP_DIR\$dmp")) {
            write-host "Error: Cannot find $EXP_DIR\$dmp, aborting import! " -ForegroundColor Red
            Return $False
        }
        if (Test-Path "$EXP_DIR\$log") {
            write-host "Removing previous log file!" -ForegroundColor Yellow
            Remove-item "$EXP_DIR\$log" -Force
        }
        if (Test-Path "$EXP_DIR\$par") {
            write-host "Removing previous par file!" -ForegroundColor Yellow
            Remove-item "$EXP_DIR\$par" -Force
        }
    } else {
        Write-Host "Error:  $EXP_DIR does not exit, therefore dmp file cannot exist as well!" -ForegroundColor Red
        Write-Host "Error:  Please check your database directories as well as your dmp file you want to import!" -ForegroundColor Red
        #Write-Host "Info: Creating $EXP_DIR!"
        #New-Item -Path $EXP_DIR
    }

    $content = @"
userid=$user/$pass@$DB
directory=EXP_DIR
dumpfile=$dmp
logfile=$log
full=y
"@
    
    $content | Out-File -FilePath $par -Encoding ASCII

    Write-Host "Starting FULL import into $DB using $dmp!" -ForegroundColor Yellow
    Write-host "Started at:  $(Get-Date)" -ForegroundColor Yellow

    & $impdp parfile=$par
    
    Remove-Item $par -ErrorAction SilentlyContinue

    Write-host "Finished at:  $(Get-Date)" -ForegroundColor Yellow
    write-host "Import log can be found at:" -ForegroundColor Yellow
    write-host "np $EXP_DIR\$log" -ForegroundColor Yellow
}

function Execute-GLX-drop-users {

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'drop_mod_users.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $wd     = 'G:\Export'
    $output = 'output_drop_mod_users.sql'

    # ask for confirmation before even attempting
    $confirmation = Confirm-Action -ExpectedConfirmationText "dropGLXschemas" -WarningMessage "All modulus-specific users from $DB will be dropped. Do you confirm you want to do that?"

    if (!$confirmation) {
        Return $False
        write-host "Aborting - nothing has been dropped!" -ForegroundColor Green
    }

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $wd

    if (!(Test-Path $script)) {
        write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
        Return $false
    }

    # removing previously spooled output!
    if (Test-Path $output) {
        write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
        remove-item $output -ErrorAction SilentlyContinue
    }

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Dropping users from $DB using $wd\$script " -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -scriptPath "$wd\$script"
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Dropped users from $DB using $wd\$script " -ForegroundColor Yellow
    Write-host "Check users to verify!" -ForegroundColor Red
    write-host "Spooled output to:" -ForegroundColor Yellow
    write-host "np $wd\$output" -ForegroundColor Yellow
    Set-Location -Path $cwd
}

function Execute-JKP-drop-users {

    $user   = 'sys'
    $DB     = 'JKP'
    $script = 'drop_mod_users.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $wd     = 'F:\Export'
    $output = 'output_drop_mod_users.sql'

    # ask for confirmation before even attempting
    $confirmation = Confirm-Action -ExpectedConfirmationText "dropJKPschemas" -WarningMessage "All modulus-specific users from $DB will be dropped. Do you confirm you want to do that?"

    if (!$confirmation) {
        Return $False
        write-host "Aborting - nothing has been dropped!" -ForegroundColor Green
    }

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $wd

    if (!(Test-Path $script)) {
        write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
        Return $false
    }

    # removing previously spooled output!
    if (Test-Path $output) {
        write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
        remove-item $output -ErrorAction SilentlyContinue
    }

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Dropping users from $DB using $wd\$script " -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -scriptPath "$wd\$script"
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Dropped users from $DB using $wd\$script " -ForegroundColor Yellow
    Write-host "Check users to verify!" -ForegroundColor Red
    write-host "Spooled output to:" -ForegroundColor Yellow
    write-host "np $wd\$output" -ForegroundColor Yellow
    Set-Location -Path $cwd
}

function Export-GLX-Full {

    $user   = 'system'
    $DB     = 'GLX'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $EXP_DIR= 'G:\Export'

    #Prep-GLX-EXP_DIR

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $EXP_DIR
    
    Execute-Full-Export -cred $cred -DB $DB -EXP_DIR $EXP_DIR
   
    # steps after execution
    Set-Location -Path $cwd
}

function Export-JKP-Full {
   
    $user   = 'system'
    $DB     = 'JKP'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $EXP_DIR= 'F:\Export'

    #Prep-JKP-EXP_DIR

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $EXP_DIR
    
    Execute-Full-Export -cred $cred -DB $DB -EXP_DIR $EXP_DIR
   
    # steps after execution
    Set-Location -Path $cwd
}

function Import-GLX-Full {
   
    $user   = 'system'
    $DB     = 'GLX'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $EXP_DIR= 'G:\Export'

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $EXP_DIR
    
    Execute-Full-Import -cred $cred -DB $DB -EXP_DIR $EXP_DIR
   
    # steps after execution
    Set-Location -Path $cwd
}

function Import-JKP-Full {
   
    $user   = 'system'
    $DB     = 'JKP'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $EXP_DIR= 'F:\Export'

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $EXP_DIR
    
    Execute-Full-Import -cred $cred -DB $DB -EXP_DIR $EXP_DIR
   
    # steps after execution
    Set-Location -Path $cwd
}
#endregion

#region --- execute sysprivs
function Execute-GLX-sys-privileges {

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'grant_sys_privileges.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $wd     = 'G:\Export'
    $output = 'output_sys_privileges.sql'

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $wd

    if (!(Test-Path $script)) {
        write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
        Return $false
    }

    # removing previously spooled output!
    if (Test-Path $output) {
        write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
        remove-item $output -ErrorAction SilentlyContinue
    }

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Applying $wd\$script to $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -scriptPath "$wd\$script"
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Applied $wd\$script to $DB!" -ForegroundColor Yellow
    Write-host "Please check and compile $DB!" -ForegroundColor Red
    write-host "Spooled output to:" -ForegroundColor Yellow
    write-host "np $wd\$output" -ForegroundColor Yellow
    Set-Location -Path $cwd
}

function Execute-GLX-table-privileges {

    $user   = 'sys'
    $DB     = 'GLX'
    $script = 'grant_table_privileges.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $wd     = 'G:\Export'
    $output = 'output_table_privileges.sql'

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $wd

    if (!(Test-Path $script)) {
        write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
        Return $false
    }

    # removing previously spooled output!
    if (Test-Path $output) {
        write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
        remove-item $output -ErrorAction SilentlyContinue
    }

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Applying $wd\$script to $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -scriptPath "$wd\$script"
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Applied $wd\$script to $DB!" -ForegroundColor Yellow
    Write-host "Please check and compile $DB!" -ForegroundColor Red
    write-host "Spooled output to:" -ForegroundColor Yellow
    write-host "np $wd\$output" -ForegroundColor Yellow
    Set-Location -Path $cwd
}

function Execute-JKP-sys-privileges {

    $user   = 'sys'
    $DB     = 'JKP'
    $script = 'grant_sys_privileges.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $wd     = 'F:\Export'
    $output = 'output_sys_privileges.sql'

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $wd

    if (!(Test-Path $script)) {
        write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
        Return $false
    }

    # removing previously spooled output!
    if (Test-Path $output) {
        write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
        remove-item $output -ErrorAction SilentlyContinue
    }

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Applying $wd\$script to $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -scriptPath "$wd\$script"
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Applied $wd\$script to $DB!" -ForegroundColor Yellow
    Write-host "Please check and compile $DB!" -ForegroundColor Red
    write-host "Spooled output to:" -ForegroundColor Yellow
    write-host "np $wd\$output" -ForegroundColor Yellow
    Set-Location -Path $cwd
}

function Execute-JKP-table-privileges {

    $user   = 'sys'
    $DB     = 'JKP'
    $script = 'grant_table_privileges.sql'
    $cred   = Get-DatabaseCredentials -user $user -DB $DB
    $wd     = 'F:\Export'
    $output = 'output_table_privileges.sql'

    # steps before execution
    $cwd = Get-Location
    Set-Location -Path $wd

    if (!(Test-Path $script)) {
        write-host "$wd\$script does not exist, aborting!" -ForegroundColor Red
        Return $false
    }

    # removing previously spooled output!
    if (Test-Path $output) {
        write-host "Removing $wd\$output - it will be regenerated by the spooled output!" -ForegroundColor Yellow
        remove-item $output -ErrorAction SilentlyContinue
    }

    # execution + info
    #Write-Host "Starting execution of $file for $DB_NAME!"
    #Write-Host "Started at:  $(Get-Date)"
    write-host "Applying $wd\$script to $DB!" -ForegroundColor Yellow
    Execute-SQL-Script -cred $cred -DB $DB -scriptPath "$wd\$script"
    
    # steps after execution
    #Write-Host "Execution completed for $file"
    #Write-Host "Completed at: $(Get-Date)"
    write-host "Applied $wd\$script to $DB!" -ForegroundColor Yellow
    Write-host "Please check and compile $DB!" -ForegroundColor Red
    write-host "Spooled output to:" -ForegroundColor Yellow
    write-host "np $wd\$output" -ForegroundColor Yellow
    Set-Location -Path $cwd
}
#endregion