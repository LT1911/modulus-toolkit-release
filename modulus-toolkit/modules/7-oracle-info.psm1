#tlukas, 06.08.2024

#write-host "Loading 7-oracle-info.psm1!" -ForegroundColor Green

#region --- helpers
#region --- helpers: background
function Invoke-ActionWithConfirmation {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')] 
    param (
        [Parameter(Mandatory=$true)]
        [string]$Action, 
        
        [Parameter(Mandatory=$true)]
        [string]$Target
    )

    write-log "User-input needed - please read and decide carefully!" -Header
    write-host " "
    write-log "Target: $Target"
    Write-Log "Action: $Action"

    if ($PSCmdlet.ShouldProcess($Target, $Action)) {
        write-Log "Action confirmed by user: $($Target) - $Action" WARNING
        return $true
    } else {
        write-Log "Action cancelled by user or skipped due to PowerShell confirmation settings." INFO
        return $false
    }
}

function Get-DatabaseCredentials {
    param (
        [string]$user,
        [string]$DB
    )

    $cred = Get-CredentialFromVault -User $user -Target $DB

    if (-not $cred) {
        Set-CredentialInVault -User $user -Target $DB
        $cred = Get-CredentialFromVault -User $user -Target $DB
    }
    return $cred
}

function Set-DatabaseCredentials {
    param (
        [string]$user,
        [string]$DB
    )

    Set-CredentialInVault -User $user -Target $DB
}

function Execute-SQL-Script {
    param (
        [PSCredential]$cred,      
        [string]$DB,
        [string]$script,
        [string]$scriptArgs = ""
    )

    # --- Robust Path Determination Logic ---
    $defaultScriptDir = 'C:\Program Files\PowerShell\Modules\modulus-toolkit\scripts\'
    
    # 1. Check for Absolute Path Indicators:
    #    - Starts with a drive letter and colon (e.g., C:)
    #    - Starts with two backslashes (UNC path, e.g., \\server)
    if ($script -match '^[a-zA-Z]:' -or $script.StartsWith('\\')) {
        # Input looks like an absolute path, use it directly.
        $scriptPath = $script
        Write-Log "Identified as Absolute Path: $scriptPath" VERBOSE
    } 
    # 2. Check for Root Path Indicator (e.g., starting with C:\ or /)
    #    NOTE: $script.StartsWith('/') is useful for Linux-style absolute paths
    elseif ([System.IO.Path]::IsPathRooted($script)) {
         # This catches cases like C:\ or \Temp, and allows for robust checks on different OSs.
         $scriptPath = $script
         Write-Log "Identified as Rooted Path: $scriptPath" VERBOSE
    }
    else {
        # Input is a bare filename or a path snippet (e.g., dba\compile.sql).
        # Prepend the default directory. We use Join-Path for clean construction.
        $scriptPath = Join-Path -Path $defaultScriptDir -ChildPath $script
        Write-Log "Identified as Snippet/Filename, combined: $scriptPath" VERBOSE
    }
    # --- End Path Determination Logic ---

    $user = $cred.UserName
    $pass = $cred.GetNetworkCredential().Password

    if (Test-Path $scriptPath) {
        # Prepare SQL*Plus command
        $scriptToExecute = "`"$scriptPath`""
        
        # Determine the SQL*Plus connection string (using sysdba if user is 'sys')
        if ($cred.UserName -eq 'sys') {
            $sqlplusCommand = "sqlplus -silent $user/$pass@$DB as sysdba @$scriptToExecute $scriptArgs"
            Write-Log "Executing 'sqlplus -silent $user/***@$DB as sysdba @$scriptToExecute $scriptArgs'" VERBOSE
        } else {
            $sqlplusCommand = "sqlplus -silent $user/$pass@$DB @$scriptToExecute $scriptArgs"
            Write-Log "Executing 'sqlplus -silent $user/***@$DB @$scriptToExecute $scriptArgs'" VERBOSE
        }

        # Execute the command and capture output
        try {
            Write-Log "Started at:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')" VERBOSE
            $output = cmd /c $sqlplusCommand 2>&1
            Write-Log "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')" VERBOSE
            Return $output
        }
        catch {
            Write-Log "An error occurred while executing the SQL script." ERROR
            $err = $_.Exception.Message
            Write-Log $err ERROR
            Return $false
        }

    } else {
        Write-Log "SQL file not found at $scriptPath!" ERROR
        Return $false
    }
}

function Show-OPatch-version {
    write-Log "Showing oracle OPatch version:" INFO
    opatch version
}
#endregion

#region --- helpers: top-level function calls
function Invoke-SqlScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential,
        
        [Parameter(Mandatory=$true)]
        [string]$TNS,
        
        [Parameter(Mandatory=$true)]
        [string]$Script,

        [Parameter(Mandatory=$true)]
        [string]$StartLogMessage,

        [Parameter(Mandatory=$true)]
        [string]$EndLogMessage,
        
        [string]$ScriptArgs = ""
    )
    
    # Pre-execution logging
    write-Log "$StartLogMessage" INFO

    # Execute the core engine
    #    $output = Execute-SQL-Script `
    Execute-SQL-Script `
        -cred $Credential `
        -DB $TNS `
        -script $Script `
        -scriptArgs $ScriptArgs

    # Post-execution logging
    write-Log "$EndLogMessage" INFO

    # Return the output for processing, or just display it (depending on how you use it)
    #return $output
}

function Invoke-SqlScriptWithSpool {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential,
        
        [Parameter(Mandatory=$true)]
        [string]$TNS,
        
        [Parameter(Mandatory=$true)]
        [string]$Script,
        
        [Parameter(Mandatory=$true)]
        [string]$WorkingDirectory,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputFileName,
        
        [string]$ScriptArgs = "" 
    )
    
    # 1. Define Paths and Preserve Current Location
    $fullOutputPath = Join-Path -Path $WorkingDirectory -ChildPath $OutputFileName
    $originalLocation = Get-Location
    
    # Check if the process should continue
    if ($PSCmdlet.ShouldProcess("Running script '$Script' on $TNS", "Spooling output to $fullOutputPath")) {
        
        # 2. Change Directory to Working Directory
        write-Log "Changing directory to: $WorkingDirectory" INFO
        Set-Location -Path $WorkingDirectory
        
        # 3. Handle File Cleanup (The core requirement)
        if (Test-Path $OutputFileName) {
            write-Log "Removing existing file: $fullOutputPath" INFO
            Remove-Item $OutputFileName -ErrorAction SilentlyContinue
        }
        
        # 4. Execute the SQL Script (This is where the spooling happens inside the .sql file)
        write-Log "Starting SQL execution to generate spool file." INFO
        
        # Execute-SQL-Script handles the connection and command execution
        $sqlOutput = Execute-SQL-Script `
            -cred $Credential `
            -DB $TNS `
            -script $Script `
            -scriptArgs $ScriptArgs
        
        # You can process the $sqlOutput variable here if needed (e.g., check for SQL*Plus errors)

        # 5. Final Logging and Location Restore
        write-Log "Spooled output completed." INFO
        if (Test-Path $OutputFileName) {
            write-Log "Spooled file generated: $fullOutputPath" SUCCESS
            write-Log "np $fullOutputPath" SUCCESS 
        } else {
            write-Log "WARNING: Spool file not found after execution: $fullOutputPath" WARN
        }
        
        # Restore original directory
        Set-Location -Path $originalLocation
    }
}
#endregion
#endregion

#region --- info
#region --- info: Oracle versions and OPatch version 
function Show-GLX-oracle-patch-version {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'oracle_patch_version.sql'
    
    Show-OPatch-version

    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing Oracle patches in $TNS using $script!" `
        -EndLogMessage "Finished listing Orache patches in $TNS!" 
}

function Show-JKP-oracle-patch-version {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'oracle_patch_version.sql'
    
    Show-OPatch-version
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing Oracle patches in $TNS using $script!" `
        -EndLogMessage "Finished listing Orache patches in $TNS!" 
}
#endregion

#region --- info: list modulus specific users
function Show-GLX-mod-users {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'list_mod_users.sql'

    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing modulus-specific users in $TNS using $script!" `
        -EndLogMessage "Finished listing modulus-specific users in $TNS!" 
}

function Show-JKP-mod-users {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'list_mod_users.sql'

    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing modulus-specific users in $TNS using $script!" `
        -EndLogMessage "Finished listing modulus-specific users in $TNS!" 
}
#endregion

#region --- info: list dba_users
function Show-GLX-dba-users {
    write-Log "still TODO, not implemented yet" ERROR
}

function Show-JKP-dba-users {
    write-Log "still TODO, not implemented yet" ERROR
}
#endregion

#region --- info: GLX-specific galaxis.betabli 
function Show-GLX-betabli {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'check_galaxis_betabli.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing relevant content of table galaxis.betabli in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- info: JKP-specific DB versions
function Show-JKP-DB-version {
    $security   = Get-DbCred-security
    $jackpot    = Get-DbCred-jackpot
    $TNS        = Get-DBTns-JKP
    $script     = 'grips_patch_table_check.sql'
    
    Invoke-SqlScript -Credential $security `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing modules and versions in security-schema in $TNS using $script!" `
        -EndLogMessage "Finished!" 

	Invoke-SqlScript -Credential $jackpot `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing modules and versions in jackpot-schema in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- info: JKP-specific GLI checksums 
#TODO - find a better solution, maybe combine, but how? which function name
function Show-JKP-SHA1-and-SHA256-checksums {
    $cred       = Get-DbCred-sysJKP
    $jackpot    = Get-DbUser-jackpot
    $TNS        = Get-DBTns-JKP
    $script     = 'db_object_hash_SHA1_SHA256.sql'
    $scriptArgs = "$jackpot GALAXIS MIS"
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -ScriptArgs $scriptArgs `
        -StartLogMessage "Listing SHA1 and SHA256 checksums in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

function Show-GLX-SHA1-and-SHA256-checksums {
    $cred       = Get-DbCred-sysGLX
    $jackpot    = Get-DbUser-jackpot
    $TNS        = Get-DBTns-GLX
    $script     = 'db_object_hash_SHA1_SHA256.sql'
    $scriptArgs = "$jackpot GALAXIS MIS"
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -ScriptArgs $scriptArgs `
        -StartLogMessage "Listing SHA1 and SHA256 checksums in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- info: spooling system and table privileges
function Spool-GLX-sys-privileges {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'spool_sys_privileges.sql'    
    $wd     = 'G:\Export'
    $output = 'grant_sys_privileges.sql'
    
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -WorkingDirectory $wd `
        -OutputFileName $output
}

function Spool-JKP-sys-privileges {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'spool_sys_privileges.sql'    
    $wd     = 'F:\Export'
    $output = 'grant_sys_privileges.sql'
    
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -WorkingDirectory $wd `
        -OutputFileName $output
}

function Spool-GLX-table-privileges {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'spool_table_privileges.sql'    
    $wd     = 'G:\Export'
    $output = 'grant_table_privileges.sql'
    
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -WorkingDirectory $wd `
        -OutputFileName $output
}

function Spool-JKP-table-privileges {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'spool_table_privileges.sql'    
    $wd     = 'F:\Export'
    $output = 'grant_table_privileges.sql'
    
    Invoke-SqlScriptWithSpool -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -WorkingDirectory $wd `
        -OutputFileName $output
}
#endregion

#region --- info: show invalid objects
function Show-GLX-Invalids {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'check_invalid_objects.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Showing all invalid objects in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

function Show-JKP-Invalids {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'check_invalid_objects.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Showing all invalid objects in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion

#region --- info: show broken jobs
function Show-GLX-BrokenJobs {
    $cred   = Get-DbCred-sysGLX
    $TNS    = Get-DBTns-GLX
    $script = 'broken_dba_jobs.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing all broken dba_jobs in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}

function Show-JKP-BrokenJobs {
    $cred   = Get-DbCred-sysJKP
    $TNS    = Get-DBTns-JKP
    $script = 'broken_dba_jobs.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "Listing all broken dba_jobs in $TNS using $script!" `
        -EndLogMessage "Finished!" 
}
#endregion
#endregion

function Show-GLX-Tag {
    $cred   = Get-DbCred-systemGLX
    $TNS    = Get-DBTns-glx 
    $script = 'liquibase-tag.sql'
    
    Invoke-SqlScript -Credential $cred `
        -TNS $TNS `
        -Script $script `
        -StartLogMessage "$TNS - liquibase-tag:" `
        -EndLogMessage "Finished!" 
}


#Export-ModuleMember -Function * -Alias * -Variable *