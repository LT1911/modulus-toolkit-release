#tlukas, 18.09.2025

#Write-Host "Loading 12-liquibase.psm1!" -ForegroundColor Green

#region --- exit on wrong PS-version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "Liquibase helper requires PowerShell 7+. Detected $($PSVersionTable.PSVersion). Skipping module load."
    return
}
#endregion

#region --- parameters and config
$script:LbProjectsRoot = 'I:\modulus-toolkit\liquibase'
$script:LiquibaseExe = 'C:\Program Files\liquibase\liquibase.bat' # Fallback logic is in Get-LbExe

# Define configuration for each project
$script:LbProjects = @{
    'GLX' = @{
        DefaultsFileName  = 'liquibase.properties'
        ChangelogFile     = 'changelog\main.xml'
        LogLevel          = 'info'
    }
    'JKP' = @{
        DefaultsFileName  = 'liquibase.properties' 
        ChangelogFile     = 'changelog\empty-changelog.xml' 
        LogLevel          = 'warning'
    }
}
#endregion

#region --- internal helpers
function Resolve-PathSafe {
    param([Parameter(Mandatory)][string]$Path)
    # Allows path resolution or returns original path on error
    try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { $Path }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$FullPath
    )
    # Calculates the path of FullPath relative to BasePath
    $base = [System.IO.Path]::GetFullPath((Resolve-PathSafe $BasePath))
    $full = [System.IO.Path]::GetFullPath((Resolve-PathSafe $FullPath))
    $uBase = [Uri]($base + [IO.Path]::DirectorySeparatorChar)
    $uFull = [Uri]$full
    ($uBase.MakeRelativeUri($uFull).ToString()) -replace '%20',' '
}

function Get-LbExe {
    $exe = $script:LiquibaseExe
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        $cmd = Get-Command 'liquibase' -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        throw "Liquibase executable not found at '$exe' and not in PATH."
    }
    return $exe
}

function Get-LbConfig {
    param([Parameter(Mandatory)][string]$Project)
    if (-not $script:LbProjects.ContainsKey($Project)) {
        throw "Configuration for project '$Project' not found."
    }
    
    $config = $script:LbProjects[$Project]
    $projPath = Join-Path $script:LbProjectsRoot $Project
    
    $defaultsFile = Join-Path $projPath $config.DefaultsFileName
    $resolvedDefaults = Resolve-PathSafe $defaultsFile
    if (-not (Test-Path -LiteralPath $resolvedDefaults -PathType Leaf)) { throw "Defaults file not found: $resolvedDefaults" }
    
    $changelogFile = Join-Path $projPath $config.ChangelogFile
    $resolvedChangelog = Resolve-PathSafe $changelogFile
    if (-not (Test-Path -LiteralPath $resolvedChangelog -PathType Leaf)) { throw "Changelog file not found: $resolvedChangelog" }
    
    return [PSCustomObject]@{
        ProjectRoot   = $projPath
        DefaultsFile  = $resolvedDefaults
        ChangelogFile = $resolvedChangelog
        LogLevel      = $config.LogLevel
    }
}

function New-ArgList {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][psobject]$LbConfig,
        [string[]]$Args
    )
    $list = @()
    
    if ($LbConfig.LogLevel) { $list += @('--log-level', $LbConfig.LogLevel) }
    $list += @('--defaults-file', $LbConfig.DefaultsFile)

    $effectiveSearchPath = Split-Path $LbConfig.ChangelogFile -Parent
    $list += @('--searchPath', $effectiveSearchPath)

    $relChangelog = (Get-RelativePath -BasePath $effectiveSearchPath -FullPath $LbConfig.ChangelogFile) -replace '\\','/'
    $list += @('--changelog-file', $relChangelog)

    $list += $Command
    if ($Args) { $list += $Args }

    return ,$list
}

function Invoke-LbCli {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Args,
        [switch]$PassThru
    )
    
    # 1. Configuration and Executable Lookup
    try {
        $config = Get-LbConfig -Project $Project
        $exe = Get-LbExe
        $argList = New-ArgList -Command $Command -Args $Args -LbConfig $config
    } catch {
        Write-Error "CRITICAL ERROR: Configuration setup failed for project '$Project'. Reason: $($_.Exception.Message)"
        return
    }

    if ($PSCmdlet.ShouldProcess("'$Command' against $($config.ProjectRoot)", "Liquibase CLI")) {
        Write-Verbose ("Running: {0} {1}" -f $exe, ($argList -join ' '))

        $ExitCode = 0
        $stdout = ''
        $stderr = ''
        
        # 2. Execute command using native PowerShell call operator (&)
        try {
            $result = & $exe $argList *>&1 
            
            $ExitCode = $LASTEXITCODE
            $stdout = $result | Out-String 
        } catch {
            $ExitCode = $LASTEXITCODE
            $stderr = $_.Exception.Message 
        }

        # 3. Handle non-zero exit code (error)
        if ($ExitCode -ne 0) {
            $combinedError = if ($stdout -ne '') { $stdout } else { $stderr }
            Write-Error ("Liquibase exited with code {0}.`n{1}" -f $ExitCode, $combinedError.Trim())
        }

        # 4. Output the captured stream (Liquibase logs, status, history, etc.)
        if ($stdout -ne '') {
            #Write-Host $stdout.Trim()
        }

        # 5. Return object if -PassThru is used
        if ($PassThru) { 
            return [PSCustomObject]@{ 
                ExitCode=$ExitCode; 
                StdOut=$stdout; 
                StdErr=$stderr 
            } 
        }
    }
}

function Get-LbNewestTag {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Project)

    # 1. Capture output using -PassThru. Output will contain the history table.
    $output = Invoke-LbCli -Project $Project -Command 'history' -Args @() -PassThru # Removed '--format csv' as it requires commercial features for console output
    
    # 2. Add Null Check and Exit Code Check
    if (-not $output -or $output.ExitCode -ne 0) {
        Write-Warning "Failed to execute Liquibase history command for project '$Project'."
        return "" 
    }

    # 3. Parsing Logic: Find the line containing the main tag record.
    # We look for the last line that has content and try to extract the last field (Tag).
    
    # Filter for lines that are not headers and have content (i.e., the table rows)
    $historyLines = $output.StdOut.Trim() -split "`n" | Where-Object { 
        $_ -match '\|' -and $_ -notmatch 'Deployment ID' -and $_ -notmatch '---' 
    }
    
    if (-not $historyLines) { return "" }
    
    # The newest tag is typically the last line in the history table output
    $tagRecord = $historyLines[-1]
    
    if ($tagRecord) {
        # Regex to find the last column (the Tag) in the history table output
        # It captures the content of the field just before the final vertical bar.
        # Example: | 8096613021 | 9/17/25, 10:10 AM | main.xml | tlukas | 10.101 | 10.101-tag |
        if ($tagRecord -match '\|([^\|]+)\|\s*$') {
            # Capture the value in the second-to-last field (the Tag column)
            # Since the tag may be the last field or second-to-last depending on the last column format, 
            # we target the last field with content before the final pipe separator.
            $fields = $tagRecord -split '\|' | Where-Object { $_.Trim() -ne "" }
            # The actual tag is typically the last or second-to-last field in the parsed fields array
            return $fields[-1].Trim()
        }
    }
    return ""
}
#endregion

#region --- functions for the toolkit-user
function Get-GlxDbStatus {
    [CmdletBinding()] param([string]$Contexts,[string]$LabelFilter,[switch]$VerboseOutput)
    $args = @()
    if ($VerboseOutput) { $args += '--verbose' }
    if ($Contexts)     { $args += @('--contexts', $Contexts) }
    if ($LabelFilter) { $args += @('--labels',   $LabelFilter) }
    Invoke-LbCli -Project 'GLX' -Command 'status' -Args $args
    
    Get-LiquibaseLogContent GLX
}

function Show-GlxDbVersion {
    [CmdletBinding()] param()
    Invoke-LbCli -Project 'GLX' -Command 'history'

    Get-LiquibaseLogContent GLX
}

function Invoke-GlxValidate {
    [CmdletBinding()] param([string]$Contexts,[string]$LabelFilter)
    $args = @()
    if ($Contexts)     { $args += @('--contexts', $Contexts) }
    if ($LabelFilter) { $args += @('--labels',   $LabelFilter) }
    Invoke-LbCli -Project 'GLX' -Command 'validate' -Args $args

    Get-LiquibaseLogContent GLX
}

function Invoke-GlxUpdate {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([string]$Contexts,[string]$LabelFilter)
    $args = @()
    if ($Contexts)     { $args += @('--contexts', $Contexts) }
    if ($LabelFilter) { $args += @('--labels',   $LabelFilter) }
    Invoke-LbCli -Project 'GLX' -Command 'update' -Args $args

    Get-LiquibaseLogContent GLX
}

function Get-GlxNewestTag {
    [CmdletBinding()] param()
    Get-LbNewestTag -Project 'GLX'

    Get-LiquibaseLogContent GLX
}

function Get-JkpDbStatus {
    [CmdletBinding()] param([string]$Contexts,[string]$LabelFilter,[switch]$VerboseOutput)
    $args = @()
    if ($VerboseOutput) { $args += '--verbose' }
    if ($Contexts)     { $args += @('--contexts', $Contexts) }
    if ($LabelFilter) { $args += @('--labels',   $LabelFilter) }
    Invoke-LbCli -Project 'JKP' -Command 'status' -Args $args

    Get-LiquibaseLogContent GLX
}

function Show-JkpDbVersion {
    [CmdletBinding()] param()
    Invoke-LbCli -Project 'JKP' -Command 'history'

    Get-LiquibaseLogContent JKP
}

function Invoke-JkpValidate {
    [CmdletBinding()] param([string]$Contexts,[string]$LabelFilter)
    $args = @()
    if ($Contexts)     { $args += @('--contexts', $Contexts) }
    if ($LabelFilter) { $args += @('--labels',   $LabelFilter) }
    Invoke-LbCli -Project 'JKP' -Command 'validate' -Args $args

    Get-LiquibaseLogContent JKP
}

function Invoke-JkpUpdate {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([string]$Contexts,[string]$LabelFilter)
    $args = @()
    if ($Contexts)     { $args += @('--contexts', $Contexts) }
    if ($LabelFilter) { $args += @('--labels',   $LabelFilter) }
    Invoke-LbCli -Project 'JKP' -Command 'update' -Args $args

    Get-LiquibaseLogContent JKP
}

function Get-JkpNewestTag {
    [CmdletBinding()] param()
    Get-LbNewestTag -Project 'JKP'

    Get-LiquibaseLogContent JKP
}

function Get-LiquibaseLogContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('GLX', 'JKP')]
        [string]$Environment
    )

    $BasePath = 'I:\modulus-toolkit\logs\'
    $LogFileName = "liquibase-$Environment.log"
    $LogPath = Join-Path -Path $BasePath -ChildPath $LogFileName

    # Define a log prefix for each output line
    $LogPrefix = "[liquibase]"

    # Check if the file exists
    if (-not (Test-Path -Path $LogPath -PathType Leaf)) {
        write-log "File not found at path: $LogPath" WARNING
        return
    }

    try {
        # Read the file content LINE-BY-LINE (by omitting -Raw)
        $LogContentLines = Get-Content -Path $LogPath

        write-log "Showing content from $($LogPath):"
        # Output each line of the log content, prefixed with the desired tag
        foreach ($line in $LogContentLines) {
            # Trim leading/trailing whitespace from the line for cleaner output
            $trimmedLine = $line.Trim()
            
            # Only log non-empty lines
            if ($trimmedLine) {
                Write-Host "$LogPrefix $trimmedLine"
                write-log  "$LogPrefix $trimmedLine" -Silent
            }
        }
    }
    catch {
        write-log "An error occurred while reading the log file: $($_.Exception.Message)" ERROR
    }
}
#endregion

#region --- exporting the functions for use
#'Invoke-LbCli', # FIX: Exported for internal function visibility - removed this one, no need to be exported
Export-ModuleMember -Function @(
    'Get-GlxDbStatus','Show-GlxDbVersion','Invoke-GlxValidate','Invoke-GlxUpdate', 'Get-GlxNewestTag',
    'Get-JkpDbStatus','Show-JkpDbVersion','Invoke-JkpValidate','Invoke-JkpUpdate', 'Get-JkpNewestTag'
)
#endregion