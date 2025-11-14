#tlukas, 22.10.2024

#write-host "Loading 8-oracle-admin.psm1!" -ForegroundColor Green

#region --- action
#region --- action: GLX - loadjava galaxisoracle.jar
function Execute-GalaxisOracle-jar {
    Write-Log "Execute-GalaxisOracle-jar" -Header
	#region - parameters
    $directory = Get-PrepPath 
	$directory = $directory + '\HFandLib\'
    $user = Get-DBUser-mis
    $DB   = Get-DbTNS-GLX
    $cred = Get-DbCred-mis
    $pass = $cred.GetNetworkCredential().Password
	$file = 'galaxisoracle.jar'
	$file = $directory + $file
    #endregion
    #region - execution
    if (Test-Path $file) {
		loadjava -u $user/$pass@GLX -r -v $file
    } else {
        Write-Log "Did not find $file - make sure you run Prep-HFandLib first!" ERROR
    }
    #endregion
    Write-log "Execute-GalaxisOracle-jar completed!" -Level INFO
}
#endregion

#region --- action: GLX&JKP default profile
function Set-GLX-default-profile {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'set_default_profile.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Setting up a default profile in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

function Set-JKP-default-profile {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'set_default_profile.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Setting up a default profile in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: JKP - JP update helper (set version to 1050)
function Set-JKP-DB-version-1050 {
    $security = Get-DbCred-security
    $base     = Get-DbCred-base
    $jackpot  = Get-DbCred-jackpot
    $TNS      = Get-DBTns-JKP
    
    #1 security - trigger - disable
    $script = 'grips_patch_table_disable_trigger.sql'
    Invoke-SqlScript -Credential $security `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Disabling trigger in security user using $script!" `
        -EndLogMessage "Finished!" 
    
    #2 security - update version
    $script = 'grips_patch_table_update.sql'
    Invoke-SqlScript -Credential $security `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating versions in security user using $script!" `
        -EndLogMessage "Finished!" 
    
    #3 security - trigger - enable
    $script = 'grips_patch_table_enable_trigger.sql'
    Invoke-SqlScript -Credential $security `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Enabling trigger in security user using $script!" `
        -EndLogMessage "Finished!" 

    #4 base - trigger - disable
    $script = 'grips_patch_table_disable_trigger.sql'
    Invoke-SqlScript -Credential $base `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Disabling trigger in base user using $script!" `
        -EndLogMessage "Finished!" 
    
    #5 jackpot - update version
    $script = 'grips_patch_table_update.sql'
    Invoke-SqlScript -Credential $jackpot `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating versions in jackpot user using $script!" `
        -EndLogMessage "Finished!" 
    
    #6 base - trigger - enable
    $script = 'grips_patch_table_enable_trigger.sql'
    Invoke-SqlScript -Credential $base `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Enabling trigger in base user using $script!" `
        -EndLogMessage "Finished!" 

    Write-Log "Done. Please check the versions again." WARNING
}
#endregion

#region --- action: JKP - daylight savings
function Set-JKP-DaylightSavings {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'set_daylight_savings.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Setting up the DaylightSavings in $TNS using $script!" `
        -EndLogMessage "Finished!"
}
#endregion

#region --- action: GLX - create grafanau-user on the fly
function Set-GLX-Grafanau-user {
    #region - parameters
    $cred   = Get-DbCred-grafanauGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\create_grafanau_user.sql'
    $pass   = Get-DbPass-grafanau
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
    $onthefly_old = @'
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN
    -- Create the monitoring user "grafanau"
    CREATE USER grafanau IDENTIFIED BY '{{PH_GRAFANAU_DB_PASSWORD}}';

    -- Grant the "grafanau" user the required permissions
    GRANT CONNECT TO grafanau;
    GRANT SELECT ON SYS.GV_$RESOURCE_LIMIT to grafanau;
    GRANT SELECT ON SYS.V_$SESSION to grafanau;
    GRANT SELECT ON SYS.V_$WAITCLASSMETRIC to grafanau;
    GRANT SELECT ON SYS.GV_$PROCESS to grafanau;
    GRANT SELECT ON SYS.GV_$SYSSTAT to grafanau;
    GRANT SELECT ON SYS.V_$DATAFILE to grafanau;
    GRANT SELECT ON SYS.V_$ASM_DISKGROUP_STAT to grafanau;
    GRANT SELECT ON SYS.V_$SYSTEM_WAIT_CLASS to grafanau;
    GRANT SELECT ON SYS.DBA_TABLESPACE_USAGE_METRICS to grafanau;
    GRANT SELECT ON SYS.DBA_TABLESPACES to grafanau;
    GRANT SELECT ON SYS.GLOBAL_NAME to grafanau;

exit;
END;
/
EXIT
'@

    $onthefly = @'
SET HEADING ON
SET ECHO ON
SET NEWPAGE NONE
SET FEEDBACK ON
SET PAGESIZE 5000
SET LINESIZE 1000

DECLARE
    user_exists NUMBER;
    user_name CONSTANT VARCHAR2(30) := 'GRAFANAU';
    user_password CONSTANT VARCHAR2(100) := '{{PH_GRAFANAU_DB_PASSWORD}}';
BEGIN
    -- 1. Check if the user already exists
    SELECT COUNT(1)
    INTO user_exists
    FROM DBA_USERS
    WHERE USERNAME = user_name;

    IF user_exists > 0 THEN
        -- User exists: only update the password
        DBMS_OUTPUT.PUT_LINE('User ' || user_name || ' already exists. Setting/resetting password.');
        EXECUTE IMMEDIATE 'ALTER USER ' || user_name || ' IDENTIFIED BY "' || user_password || '"';
    ELSE
        -- User does not exist: create user and grant privileges
        DBMS_OUTPUT.PUT_LINE('User ' || user_name || ' does not exist. Creating user and granting privileges.');

        -- Create the monitoring user "grafanau"
        EXECUTE IMMEDIATE 'CREATE USER ' || user_name || ' IDENTIFIED BY "' || user_password || '"';

        -- Grant the "grafanau" user the required permissions
        EXECUTE IMMEDIATE 'GRANT CONNECT TO ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GV_$RESOURCE_LIMIT to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$SESSION to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$WAITCLASSMETRIC to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GV_$PROCESS to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GV_$SYSSTAT to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$DATAFILE to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$ASM_DISKGROUP_STAT to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$SYSTEM_WAIT_CLASS to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.DBA_TABLESPACE_USAGE_METRICS to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.DBA_TABLESPACES to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GLOBAL_NAME to ' || user_name;

    END IF;

    DBMS_OUTPUT.PUT_LINE('User setup complete.');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
        -- Re-raise the exception to stop execution if necessary
        RAISE;
END;
/
EXIT
'@

    #replace my password
    $onthefly = $onthefly.Replace("{{PH_GRAFANAU_DB_PASSWORD}}",$pass)

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\create_grafanau_user.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8
    #endregion

    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Creating user grafanau in $TNS!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: GLX - create grafanau-user on the fly
function Set-JKP-Grafanau-user {
    #region - parameters
    $cred   = Get-DbCred-grafanauJKP
    $TNS    = Get-DBTns-JKP
    $script = 'onthefly\create_grafanau_user.sql'
    $pass   = Get-DbPass-grafanau
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
    $onthefly_old = @'
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN
    -- Create the monitoring user "grafanau"
    CREATE USER grafanau IDENTIFIED BY '{{PH_GRAFANAU_DB_PASSWORD}}';

    -- Grant the "grafanau" user the required permissions
    GRANT CONNECT TO grafanau;
    GRANT SELECT ON SYS.GV_$RESOURCE_LIMIT to grafanau;
    GRANT SELECT ON SYS.V_$SESSION to grafanau;
    GRANT SELECT ON SYS.V_$WAITCLASSMETRIC to grafanau;
    GRANT SELECT ON SYS.GV_$PROCESS to grafanau;
    GRANT SELECT ON SYS.GV_$SYSSTAT to grafanau;
    GRANT SELECT ON SYS.V_$DATAFILE to grafanau;
    GRANT SELECT ON SYS.V_$ASM_DISKGROUP_STAT to grafanau;
    GRANT SELECT ON SYS.V_$SYSTEM_WAIT_CLASS to grafanau;
    GRANT SELECT ON SYS.DBA_TABLESPACE_USAGE_METRICS to grafanau;
    GRANT SELECT ON SYS.DBA_TABLESPACES to grafanau;
    GRANT SELECT ON SYS.GLOBAL_NAME to grafanau;

exit;
END;
/
EXIT
'@

    $onthefly = @'
SET HEADING ON
SET ECHO ON
SET NEWPAGE NONE
SET FEEDBACK ON
SET PAGESIZE 5000
SET LINESIZE 1000

DECLARE
    user_exists NUMBER;
    user_name CONSTANT VARCHAR2(30) := 'GRAFANAU';
    user_password CONSTANT VARCHAR2(100) := '{{PH_GRAFANAU_DB_PASSWORD}}';
BEGIN
    -- 1. Check if the user already exists
    SELECT COUNT(1)
    INTO user_exists
    FROM DBA_USERS
    WHERE USERNAME = user_name;

    IF user_exists > 0 THEN
        -- User exists: only update the password
        DBMS_OUTPUT.PUT_LINE('User ' || user_name || ' already exists. Setting/resetting password.');
        EXECUTE IMMEDIATE 'ALTER USER ' || user_name || ' IDENTIFIED BY "' || user_password || '"';
    ELSE
        -- User does not exist: create user and grant privileges
        DBMS_OUTPUT.PUT_LINE('User ' || user_name || ' does not exist. Creating user and granting privileges.');

        -- Create the monitoring user "grafanau"
        EXECUTE IMMEDIATE 'CREATE USER ' || user_name || ' IDENTIFIED BY "' || user_password || '"';

        -- Grant the "grafanau" user the required permissions
        EXECUTE IMMEDIATE 'GRANT CONNECT TO ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GV_$RESOURCE_LIMIT to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$SESSION to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$WAITCLASSMETRIC to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GV_$PROCESS to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GV_$SYSSTAT to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$DATAFILE to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$ASM_DISKGROUP_STAT to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.V_$SYSTEM_WAIT_CLASS to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.DBA_TABLESPACE_USAGE_METRICS to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.DBA_TABLESPACES to ' || user_name;
        EXECUTE IMMEDIATE 'GRANT SELECT ON SYS.GLOBAL_NAME to ' || user_name;

    END IF;

    DBMS_OUTPUT.PUT_LINE('User setup complete.');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
        -- Re-raise the exception to stop execution if necessary
        RAISE;
END;
/
EXIT
'@

    #replace my password
    $onthefly = $onthefly.Replace("{{PH_GRAFANAU_DB_PASSWORD}}",$pass)

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\create_grafanau_user.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8
    #endregion

    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Creating user grafanau in $TNS!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: GLX - create scripts on the fly and execute
#region --- action: GLX - CPOSTRV - update old to new scope
function Update-Scope-CPOSTRV {
    #region - parameters
    $new_codsociet = Get-CustomerCode
    $new_codetabli = Get-CasinoCode
    $sp_user       = Get-DbUser-specific
    $new_APP_HN    = Get-MOD-APP-hostname
    $new_DB_HN     = Get-MOD-DB-hostname

    #TODO - reconfiguation scope or previous scope - how to rework the json-structure?
    $reconfigScope = Get-ReconfigurationScope
    $old_APP_HN    = $reconfigScope.APP_HN
    $old_DB_HN     = $reconfigScope.DB_HN
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
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
    #endregion

    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\CPOSTRV.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating $sp_user.CPOSTRV in $TNS!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: GLX - FRECEPTION - update old to new scope
function Update-Scope-FRECEPTION {
    #region - parameters
    $sp_user       = Get-DbUser-specific
    $new_APP_HN    = Get-MOD-APP-hostname
    $new_DB_HN     = Get-MOD-DB-hostname

    #TODO
    $reconfigScope = Get-ReconfigurationScope
    $old_APP_HN    = $reconfigScope.APP_HN
    $old_DB_HN     = $reconfigScope.DB_HN
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
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
    #endregion
    
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\FRECEPTION.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating $sp_user.FRECEPTION in $TNS!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: GLX - SWKSTNDIS - update old to new scope
function Update-Scope-SWKSTNDIS {
    #region - parameters
    $sp_user       = Get-DBUser-specific
    $new_APP_HN    = Get-MOD-APP-hostname
    $new_DB_HN     = Get-MOD-DB-hostname

    #TODO
    $reconfigScope = Get-ReconfigurationScope
    $old_APP_HN    = $reconfigScope.APP_HN
    $old_DB_HN     = $reconfigScope.DB_HN
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
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
    #endregion

    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\SWKSTNDIS.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating $sp_user.SWKSTNDIS in $TNS!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: GLX - NFLRSVR - update old to new scope
function Update-Scope-NFLRSVR {
    #region - parameters
    $new_FS_IP     = Get-MOD-FS-OFFICE-IP
    $new_FS_HN     = Get-MOD-FS-hostname

    $reconfigScope = Get-ReconfigurationScope
    $old_FS_HN     = $reconfigScope.FS_HN
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
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
        IP_ADR   = '$new_FS_IP',
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
    #endregion

    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\NFLRSVR.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating $sp_user.NFLRSVR in $TNS!" `
        -EndLogMessage "Finished!"    
}
#endregion

#region --- action: GLX - APP_PARAM - setting new scope
function Update-Scope-APP_PARAM {
    #region - parameters
    $sp_user   = Get-DbUser-specific
    $casino_ID = Get-CasinoID
    $APP_IP    = Get-MOD-APP-OFFICE-IP
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
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
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'CardManager' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$casino_ID'
    WHERE 
        APP_CODE = 'ClearanceManager' AND KEY = 'CASINO';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'ClearanceManager' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'MFillManager' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'HphManager' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'TckOutValManager' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'Consumption' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'Database' AND KEY = 'SPY_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'SnefDataChangeNotifier' AND KEY = 'SNEF_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'SlotMachineServer' AND KEY = 'HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$casino_ID'
    WHERE 
        APP_CODE = 'Casino' AND KEY = 'ID';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'Util' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'RTDS' AND KEY = 'SLOTSERVERIP';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'RTDS' AND KEY = 'TRANSACTIONSERVERIP';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'RTDS' AND KEY = 'ALARMSERVERIP';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'CasinoActivity' AND KEY = 'OL_HOST';

    UPDATE 
        $sp_user.APP_PARAM 
    SET 
        VALUE = '$APP_IP'
    WHERE 
        APP_CODE = 'EarningPotential' AND KEY = 'OL_HOST';

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
    #endregion

    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\APP_PARAM.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating $sp_user.APP_PARAM in $TNS!" `
        -EndLogMessage "Finished!"    
}
#endregion

#region --- action: GLX - setting new Society and Casino Names in a couple of tables
#(GALAXIS.BSOCIET, GALAXIS.CASINOS, GALAXIS.BETABLI, GALAXIS.CPARCAI, QPCASH.TCKSET, AS_SBC.CASINOS MKTDTM.DIM_CASINOS, SPA.DIM_CASINOS)
function Update-Scope-CasinoNames {
    #region - parameters
    $sp_user           = Get-DbUser-specific
    $society_ID        = Get-CustomerCode
    $society_name      = Get-CustomerName
    $casino_ID         = Get-CasinoID
    $casino_short_name = Get-CasinoName
    $casino_long_name  = Get-CasinoLongName
    $direction         = "TBD"          #TODO - not yet in json
    $GALAXIS_DB_user   = Get-DbUser-galaxis
    $QPCASH_DB_user    = Get-DbUser-qpcash
    $AS_SBC_DB_user    = Get-DbUser-sbc
    $MKTDTM_DB_user    = Get-DbUser-mktdtm
    $SPA_DB_user       = Get-DbUser-spa
    #endregion

    #region - create script on the fly and save to scripts\onthefly\
    $onthefly = @"
set heading on
set echo on
set newpage none
set feedback on
set pagesize 5000
set linesize 1000
BEGIN

    UPDATE  
        $GALAXIS_DB_user.BSOCIET        
    SET 
        NOM_SOCIET = '$society_name',
        DIRECTION  = '$direction'
    WHERE 
        COD_SOCIET = '$society_ID';

    UPDATE  
        $GALAXIS_DB_user.CASINOS 
    SET 
        CAS_NAME  = '$casino_long_name',
        LIB_COURT = '$casino_short_name',
        CMT       = 'set by modulus-toolkit'
    WHERE 
        ID_CASINO = '$casino_ID';

    UPDATE  
        $GALAXIS_DB_user.BETABLI 
    SET 
        NOM_ETABLI = '$casino_long_name',
        NOM_COURT  = '$casino_short_name',
        DIRECTIOn  = '$direction'
    WHERE 
        ID_CASINO = '$casino_ID';

    UPDATE  
        $GALAXIS_DB_user.BETABLI 
    SET 
        NOM_ETABLI = '$casino_long_name',
        NOM_COURT  = '$casino_short_name',
        DIRECTIOn  = '$direction'
    WHERE 
        ID_CASINO = '$casino_ID';

    UPDATE 
        $sp_user.CPARCAI      
    SET 
        LIB_BC1 = '$casino_long_name',
        LIB_BC2 = '$casino_short_name',
        LIB_BC3 = 'to be defined in Data Setup',
        LIB_BC4 = 'to be defined in Data Setup',
        LIB_BC5 = 'to be defined in Data Setup'
    WHERE 
        COD_SOCIET = '$society_ID' AND COD_ETABLI = '$casino_ID';

    UPDATE 
        $QPCASH_DB_user.TCKSET  
    SET 
        COMP_NAME = '$casino_long_name',
        ADR_LINE1 = 'TBD',
        ADR_LINE2 = 'TBD' 
    WHERE 
        ID_CASINO = '$casino_ID';

    UPDATE 
        $AS_SBC_DB_user.CASINOS 
    SET 
        NAME = '$casino_short_name'
    WHERE 
        CASINO_ID = '$casino_ID';

    UPDATE 
        $MKTDTM_DB_user.DIM_CASINOS 
    SET 
        CAS_LNGNME = '$casino_long_name',
        CAS_SHTNME = '$casino_short_name',
        COM_LNGNME = '$society_name'
    WHERE 
        ID_CASINO = '$casino_ID';

    UPDATE 
        $SPA_DB_user.DIM_CASINOS 
    SET 
        CAS_LNGNME = '$casino_long_name',
        CAS_SHTNME = '$casino_short_name',
        COM_LNGNME = '$society_name'
    WHERE 
        ID_CASINO = '$casino_ID';

    COMMIT;
END;
/
EXIT
"@

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\CASINONAMES.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8
    #endregion
    
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\CASINONAMES.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating Society and Casino names in a couple of tables in $TNS!" `
        -EndLogMessage "Finished!"    
}
#endregion

#region --- action: GLX - APP_PARAM - activate AutomaticMeterIntegration
function Enable-AutomaticMeterIntegration {    
    $sp_user       = Get-DbUser specific

    #region - create script on the fly and save to scripts\onthefly\
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

    $outputFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\onthefly\AUTOMATIC_INTEGRATION_1.sql"
    #Save the constructed PL/SQL block to a file
    if (Test-Path $outputFilePath) {
        Remove-Item $outputFilePath -Force
    }
    $onthefly | Out-File -FilePath $outputFilePath -Encoding UTF8
    #endregion

    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'onthefly\AUTOMATIC_INTEGRATION_1.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Updating $sp_user.APP_PARAM in $DB to enable AUTOMATIC_INTEGRATION!" `
        -EndLogMessage "Finished!"
}
#endregion
#endregion

#region --- action: EXPORT/IMPORT topic
#region --- action: spooling drop_mod_user.sql
function Spool-GLX-drop-users {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'spool_drop_mod_users.sql'    
    $wd     = 'G:\Export'
    $output = 'drop_mod_users.sql'
    
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -WorkingDirectory $wd `
        -OutputFileName $output
}

function Spool-JKP-drop-users {
   $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'spool_drop_mod_users.sql'    
    $wd     = 'F:\Export'
    $output = 'drop_mod_users.sql'
    
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -WorkingDirectory $wd `
        -OutputFileName $output
}
#endregion

#region --- action: GLX - drop all modulus users with previously spooled script
function Execute-GLX-drop-users {
    #region - parameters
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'drop_mod_users.sql'
    $wd     = 'G:\Export'
    $output = 'output_drop_mod_users.sql'
    $scriptPath = "$wd\$script"
    #endregion

    #region - checks
    #check if script exists
    if (!(Test-Path $scriptPath)) {
        write-Log "$scriptPath does not exist, aborting!" ERROR
        Return $False
    }
    #check for user confirmation
    $confirmation = Invoke-ActionWithConfirmation -Action "Dropping all modulus-specific users" -Target $TNS
    if (!$confirmation) { Return $False }
    #endregion

    #region - execution and some output
    write-Log "Dropped users from $TNS using $wd\$script " INFO
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $scriptPath `
        -WorkingDirectory $wd `
        -OutputFileName $output
    
    Write-Log "Check users to verify!" WARNING
    #endregion
}
#endregion

#region --- action: JKP - drop all modulus users with previously spooled script
function Execute-JKP-drop-users {
    #region - parameters
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'drop_mod_users.sql'
    $wd     = 'F:\Export'
    $output = 'output_drop_mod_users.sql'
    $scriptPath = "$wd\$script"
    #endregion

    #region - checks
    #check if script exists
    if (!(Test-Path $scriptPath)) {
        write-Log "$scriptPath does not exist, aborting!" ERROR
        Return $False
    }
    #check for user confirmation
    $confirmation = Invoke-ActionWithConfirmation -Action "Dropping all modulus-specific users" -Target $TNS
    if (!$confirmation) { Return $False }
    #endregion

    #region - execution and some output
    write-Log "Dropped users from $TNS using $wd\$script " INFO
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $scriptPath `
        -WorkingDirectory $wd `
        -OutputFileName $output
    
    Write-Log "Check users to verify!" WARNING
    #endregion
}
#endregion

#region --- action: GLX - prepare export directory
function Prep-GLX-EXP_DIR {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'GLX_EXP_DIR.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Preparing EXP_DIR in $TNS using $script!" `
        -EndLogMessage "Finished!"
}
#endregion

#region --- action: JKP - prepare export directory
function Prep-JKP-EXP_DIR {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'GLX_EXP_DIR.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Preparing EXP_DIR in $TNS using $script!" `
        -EndLogMessage "Finished!"
}
#endregion

#region --- action - OracleBinaryPath-helper
function Get-OracleBinaryPath {
    [CmdletBinding(DefaultParameterSetName='Default')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$BinaryName # e.g., 'expdp.exe', 'impdp.exe', 'sqlplus.exe'
    )

    $searchRoot = "D:\Oracle"
    
    if (-not (Test-Path $searchRoot -PathType Container)) {
        write-log "Error: The base Oracle search path '$searchRoot' does not exist." ERROR
        return $null
    }

    write-log "Searching for '$BinaryName' under '$searchRoot'..." VERBOSE

    # Define directories to exclude from the main search to avoid patch/temp copies
    $excludedDirs = @(
        '*.patch_storage', 
        '*.oui', 
        'deinstall', 
        'temp',
        'inventory' 
    )

    # Find all direct subdirectories under D:\Oracle (e.g., Ora19c, client32)
    $potentialHomes = Get-ChildItem -Path $searchRoot -Directory -Exclude $excludedDirs -ErrorAction SilentlyContinue

    foreach ($oracleHomeDir in $potentialHomes) {
        $binDir = Join-Path -Path $oracleHomeDir.FullName -ChildPath "bin"
        
        # Check if the mandatory 'bin' directory exists in this potential home
        if (-not (Test-Path $binDir -PathType Container)) {
            write-log "Skipping $($oracleHomeDir.Name): 'bin' directory not found." VERBOSE
            continue
        }
        
        $fullBinaryPath = Join-Path -Path $binDir -ChildPath $BinaryName
        
        # CORRECTED LINE: Removed the extra parenthesis
        if (Test-Path $fullBinaryPath) {
            Write-Log "Found valid binary at: $fullBinaryPath" VERBOSE
            # Return the full, absolute path to the binary (the main goal)
            return $fullBinaryPath 
        }
    }
    
    # If the binary is not found in any of the potential homes
    Write-Log "Could not find '$BinaryName' in the 'bin' directory of any standard Oracle Home under '$searchRoot'." ERROR
    return $false
}
#endregion

#region --- action: full export helper
function Execute-Full-Export {
    param (
        [PSCredential]$cred,    
        [string]$DB,
        [string]$EXP_DIR
    )

    #region - parameters
    $dmp = $DB+"_full.dmp"
    $log = $DB+"_full.log"
    $par = "expdp_"+$DB+".par"
    #managing credentials
    $user = $cred.UserName
    $pass = $cred.GetNetworkCredential().Password
    #endregion

    #binary available?
    $expdp = Get-OracleBinaryPath -BinaryName "expdp.exe"
    if (!($expdp)) { Return $False }
    
    #region - cleanup and prep
    #checking directory and previous files
    if (Test-Path $EXP_DIR) {
        if (Test-Path "$EXP_DIR\$dmp") {
            write-Log "Removing previous dump file!" INFO
            Remove-item "$EXP_DIR\$dmp" -Force
        }
        if (Test-Path "$EXP_DIR\$log") {
            write-Log "Removing previous log file!" INFO
            Remove-item "$EXP_DIR\$log" -Force
        }
        if (Test-Path "$EXP_DIR\$par") {
            write-Log "Removing previous par file!" INFO
            Remove-item "$EXP_DIR\$par" -Force
        }
    } else {
        Write-Log "Info: target destination $EXP_DIR was not found!" INFO
        Write-Log "Info: Creating $EXP_DIR!"
        New-Item -Path $EXP_DIR
    }
    #endregion

    #region - creating export-par-file
    $content = @"
userid=$user/$pass@$DB
directory=EXP_DIR
dumpfile=$dmp
logfile=$log
full=y
"@
    
    $content | Out-File -FilePath $par -Encoding ASCII
    #endregion
    
    #region - execution and output
    Write-Log "Starting FULL export for $DB to $EXP_DIR!" INFO
    Write-Log "Started at:   $(Get-Date)" INFO

    & $expdp parfile=$par
    
    Remove-Item $par -ErrorAction SilentlyContinue
    Write-Log "Finished at:  $(Get-Date)" INFO
    write-Log "Export log can be found at:" INFO
    write-Log "np $EXP_DIR\$log" INFO
    #endregion
}
#endregion

#region --- action: full import helper
function Execute-Full-Import {
    param (
        [PSCredential]$cred,    
        [string]$DB,
        [string]$EXP_DIR
    )

    #region - parameters
    $dmp = $DB+"_full.dmp"
    $log = $DB+"_full_imp.log"
    $par = "impdp_"+$DB+".par"
    #managing credentials
    $user = $cred.UserName
    $pass = $cred.GetNetworkCredential().Password
    #endregion

    #binary available?
    $impdp = Get-OracleBinaryPath -BinaryName "impdp.exe"
    if (!($impdp)) { Return $False }
    
    #region - cleanup and prep
    #checking directory and previous files
    if (Test-Path $EXP_DIR) {
        if (!(Test-Path "$EXP_DIR\$dmp")) {
            write-Log "Error: Cannot find $EXP_DIR\$dmp, aborting import! " INFO
            Return $False
        }
        if (Test-Path "$EXP_DIR\$log") {
            write-Log "Removing previous log file!" INFO
            Remove-item "$EXP_DIR\$log" -Force
        }
        if (Test-Path "$EXP_DIR\$par") {
            write-Log "Removing previous par file!" INFO
            Remove-item "$EXP_DIR\$par" -Force
        }
    } else {
        Write-Log "Error:  $EXP_DIR does not exit, therefore dmp file cannot exist as well!" ERROR
        Write-Log "Error:  Please check your database directories as well as your dmp file you want to import!" ERROR
    }
    #endregion

    #region - creating import-par-file
    $content = @"
userid=$user/$pass@$DB
directory=EXP_DIR
dumpfile=$dmp
logfile=$log
full=y
"@
    
    $content | Out-File -FilePath $par -Encoding ASCII
    #endregion

    #region - execution and output
    Write-Log "Starting FULL import into $DB using $dmp!" INFO
    Write-Log "Started at:   $(Get-Date)" INFO

    & $impdp parfile=$par
    
    Remove-Item $par -ErrorAction SilentlyContinue
    Write-Log "Finished at:  $(Get-Date)" INFO
    write-Log "Import log can be found at:" INFO
    write-Log "np $EXP_DIR\$log" INFO
    #endregion
}
#endregion

#region --- action: GLX - repair broken dba_jobs
function Repair-GLX-BrokenJobs {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'fix_broken_dba_jobs.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Repairing broken dba_jobs in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: JKP - repair broken dba_jobs
function Repair-JKP-BrokenJobs {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'fix_broken_dba_jobs.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Repairing broken dba_jobs in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- action: GLX - execute full export
function Export-GLX-Full {
    $TNS     = Get-DBTns-GLX
    $cred    = Get-DbCred-systemGLX
    $EXP_DIR = 'G:\Export'
    $cwd     = Get-Location
    
    #Prep-GLX-EXP_DIR
    
    Set-Location -Path $EXP_DIR
    Execute-Full-Export -cred $cred -DB $TNS -EXP_DIR $EXP_DIR
    Set-Location -Path $cwd
}
#endregion

#region --- action: JKP - execute full export
function Export-JKP-Full {
    $TNS     = Get-DBTns-JKP
    $cred    = Get-DbCred-systemJKP
    $EXP_DIR = 'F:\Export'
    $cwd     = Get-Location
    
    #Prep-JKP-EXP_DIR
    
    Set-Location -Path $EXP_DIR
    Execute-Full-Export -cred $cred -DB $TNS -EXP_DIR $EXP_DIR
    Set-Location -Path $cwd
}
#endregion

#region --- action: GLX - execute full import
function Import-GLX-Full {
    $TNS     = Get-DBTns-GLX
    $cred    = Get-DbCred-systemGLX
    $EXP_DIR = 'G:\Export'
    $cwd     = Get-Location
    
    Set-Location -Path $EXP_DIR
    Execute-Full-Import -cred $cred -DB $TNS -EXP_DIR $EXP_DIR
    Set-Location -Path $cwd
}
#endregion

#region --- action: JKP - execute full import
function Import-JKP-Full {
    $TNS     = Get-DBTns-JKP
    $cred    = Get-DbCred-systemJKP
    $EXP_DIR = 'F:\Export'
    $cwd     = Get-Location
    
    Set-Location -Path $EXP_DIR
    Execute-Full-Import -cred $cred -DB $TNS -EXP_DIR $EXP_DIR
    Set-Location -Path $cwd
}
#endregion
#endregion

#region --- action: compilation topic
#region --- action: compiling databases
function Compile-GLX-Serial {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'recomp_serial.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Compiling all invalid objects in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

function Compile-JKP-Serial {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'recomp_serial.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Compiling all invalid objects in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

function Compile-GLX-Invalids {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'compile_database.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Compiling all invalid objects in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

function Compile-JKP-Invalids {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'compile_database.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Compiling all invalid objects in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

#endregion

#region --- action: system and table privileges
#region --- action: GLX - execute sys privileges
function Execute-GLX-sys-privileges {
    #region - parameters
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'grant_sys_privileges.sql'
    $wd     = 'G:\Export'
    $output = 'output_sys_privileges.sql'
    $scriptPath = "$wd\$script"
    #endregion

    #region - checks
    #check if script exists
    if (!(Test-Path $scriptPath)) {
        write-Log "$scriptPath does not exist, aborting!" ERROR
        Return $False
    }
    #check for user confirmation
    $confirmation = Invoke-ActionWithConfirmation -Action "Applying previously spooled system privileges" -Target $TNS
    if (!$confirmation) { Return $False }
    #endregion

    #region - execution and some output
    write-Log "Applying system privileges to $TNS using $scriptPath" INFO
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $scriptPath `
        -WorkingDirectory $wd `
        -OutputFileName $output
    #endregion
}
#endregion

#region --- action: GLX - execute table privileges
function Execute-GLX-table-privileges {
    #region - parameters
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'grant_table_privileges.sql'
    $wd     = 'G:\Export'
    $output = 'output_table_privileges.sql'
    $scriptPath = "$wd\$script"
    #endregion

    #region - checks
    #check if script exists
    if (!(Test-Path $scriptPath)) {
        write-Log "$scriptPath does not exist, aborting!" ERROR
        Return $False
    }
    #check for user confirmation
    $confirmation = Invoke-ActionWithConfirmation -Action "Applying previously spooled table privileges" -Target $TNS
    if (!$confirmation) { Return $False }
    #endregion

    #region - execution and some output
    write-Log "Applying table privileges to $TNS using $scriptPath" INFO
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $scriptPath `
        -WorkingDirectory $wd `
        -OutputFileName $output
    #endregion
}
#endregion

#region --- action: JKP - execute sys privileges
function Execute-JKP-sys-privileges {
    #region - parameters
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'grant_sys_privileges.sql'
    $wd     = 'F:\Export'
    $output = 'output_sys_privileges.sql'
    $scriptPath = "$wd\$script"
    #endregion

    #region - checks
    #check if script exists
    if (!(Test-Path $scriptPath)) {
        write-Log "$scriptPath does not exist, aborting!" ERROR
        Return $False
    }
    #check for user confirmation
    $confirmation = Invoke-ActionWithConfirmation -Action "Applying previously spooled system privileges" -Target $TNS
    if (!$confirmation) { Return $False }
    #endregion

    #region - execution and some output
    write-Log "Applying system privileges to $TNS using $scriptPath" INFO
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $scriptPath `
        -WorkingDirectory $wd `
        -OutputFileName $output
    #endregion
}
#endregion

#region --- action: JKP - execute table privileges
function Execute-JKP-table-privileges {
    #region - parameters
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'grant_table_privileges.sql'
    $wd     = 'F:\Export'
    $output = 'output_table_privileges.sql'
    $scriptPath = "$wd\$script"
    #endregion

    #region - checks
    #check if script exists
    if (!(Test-Path $scriptPath)) {
        write-Log "$scriptPath does not exist, aborting!" ERROR
        Return $False
    }
    #check for user confirmation
    $confirmation = Invoke-ActionWithConfirmation -Action "Applying previously spooled table privileges" -Target $TNS
    if (!$confirmation) { Return $False }
    #endregion

    #region - execution and some output
    write-Log "Applying table privileges to $TNS using $scriptPath" INFO
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $scriptPath `
        -WorkingDirectory $wd `
        -OutputFileName $output
    #endregion
}
#endregion
#endregion

#endregion
#endregion

#Export-ModuleMember -Function * -Alias * -Variable *