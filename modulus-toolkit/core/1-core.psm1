#tlukas, 09.09.2024

#write-host "Loading \core\1-init.psm1!" -ForegroundColor Green

#region --- mapping network shares
function Test-DriveReady {
    param([Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$Letter)
    try {
        $drv = Get-PSDrive -Name $Letter -ErrorAction SilentlyContinue
        if (-not $drv) { return $false }
        return Test-Path -LiteralPath "$Letter`:\" -ErrorAction SilentlyContinue
    } catch { return $false }
}

function Confirm-DriveMounted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$Letter,
        [Parameter(Mandatory)][string]$Unc,
        [int]$Retries = 2,
        [int]$WaitMs = 500,
        [pscredential]$Credential
    )

    # Remove conflicting mapping (M:/I: already mapped to *other* UNC)
    $existing = Get-PSDrive -Name $Letter -ErrorAction SilentlyContinue
    if ($existing -and $existing.DisplayRoot -and ($existing.DisplayRoot -ne $Unc)) {
        #Write-Log "Found $Letter : mapped to '$($existing.DisplayRoot)'. Removing conflicting mapping..." INFO
        try { Remove-PSDrive -Name $Letter -ErrorAction Stop } catch {
            #Write-Log "Failed to remove existing $Letter:: $_" ERROR
        }
    }

    if (Test-DriveReady -Letter $Letter) { return $true }

    for ($i=1; $i -le $Retries; $i++) {
        try {
            $msg = "Mounting $Letter : to '$Unc' (attempt $i/$Retries) with New-PSDrive -Persist"
            #Write-Log $msg INFO
            if ($PSBoundParameters.ContainsKey('Credential')) {
                New-PSDrive -Name $Letter -PSProvider FileSystem -Root $Unc -Persist -Scope Global -Credential $Credential -ErrorAction Stop | Out-Null
            } else {
                New-PSDrive -Name $Letter -PSProvider FileSystem -Root $Unc -Persist -Scope Global -ErrorAction Stop | Out-Null
            }
        } catch {
            #Write-Log "New-PSDrive failed: $($_.Exception.Message). Trying 'net use'..." WARNING
            try {
                if ($PSBoundParameters.ContainsKey('Credential')) {
                    $user = $Credential.UserName
                    $pass = $Credential.GetNetworkCredential().Password
                    cmd.exe /c "net use ${Letter}: `"$Unc`" `"$pass`" /user:`"$user`" /persistent:yes" | Out-Null
                } else {
                    cmd.exe /c "net use ${Letter}: `"$Unc`" /persistent:yes" | Out-Null
                }
            } catch {
                #Write-Log "Fallback 'net use' failed: $_" ERROR
            }
        }

        Start-Sleep -Milliseconds $WaitMs
        if (Test-DriveReady -Letter $Letter) { return $true }
    }

    return $false
}

function Test-HostReachable {
    param([Parameter(Mandatory)][string]$ComputerName)
    try {
        return (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue)
    } catch { return $false }
}

function Mount-NetworkDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$DriveLetter,
        [Parameter(Mandatory)][string]$UncPath,
        [int]$RetryCount = 2,
        [int]$WaitMsBetweenRetries = 500,
        [pscredential]$Credential
    )

    #Write-Host "Mount-NetworkDrive $DriveLetter => $UncPath"
    # lightweight reachability hint
    try {
        $TestHost = ([uri]("file://$UncPath")).Host
        if (Test-HostReachable -ComputerName $TestHost) {
            #Write-Host "Host $TestHost reachable."
            #Write-Host "Host $TestHost not reachable; will still attempt to mount." 
        }
    } catch { }

    if (Test-DriveReady -Letter $DriveLetter) {
        #Write-Host "$DriveLetter : already mounted and reachable."
        return $true
    }

    $ok = Confirm-DriveMounted -Letter $DriveLetter -Unc $UncPath -Retries $RetryCount -WaitMs $WaitMsBetweenRetries -Credential:$Credential
    if ($ok) { 
        #Write-Host "$DriveLetter : mounted successfully."
        return $true 
    } else { 
        #Write-Host "Failed to mount $DriveLetter : at '$UncPath'."
        return $false 
    }
}

function Mount-M-Share {
    [CmdletBinding()] param([pscredential]$Credential)
    
    #checking correct server
    $server = $env:MODULUS_SERVER
    if ($server -notin ("APP","1VM")) { 
        #Write-Host "You are not on the APP server"
        Return
    }
    
    $hostname  = Get-MOD-APP-hostname
    $unc       = "\\$hostname\Galaxis"
    Mount-NetworkDrive -DriveLetter 'M' -UncPath $unc #-Credential:$Credential
}

function Mount-I-Share {
    [CmdletBinding()] param([pscredential]$Credential)
    
    #checking correct server
    $server = $env:MODULUS_SERVER
    if ($server -in ("APP","1VM")) { 
        #Write-Host "You are  on the APP server"  
        Return
    }
    
    $hostname  = Get-MOD-APP-hostname
    $unc       = "\\$hostname\I"
    Mount-NetworkDrive -DriveLetter 'I' -UncPath $unc #-Credential:$Credential
}
#endregion

#region --- all-in-one logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "VERBOSE", "SUCCESS")]
        [string]$Level = "INFO",

        # Default prefers I: (caller can override)
        [string]$BaseLogPath = 'I:\modulus-toolkit\logs',

        [switch]$Header,
        [switch]$Scope,
        
        # NEW: Switch to suppress console output, while still writing to file
        [switch]$Silent 
    )

    #for local testing
    $hostname = hostname
    if ($hostname -eq 'tlukas') {
        $BaseLogPath = 'C:\Users\ThomasLukas\Desktop\templates\test-output'
    }

    # --- helpers local to Write-Log (keeps scope clean) ---
    function New-LogDirectoryIfMissing([string]$Path) {
        try {
            [void][IO.Directory]::CreateDirectory($Path)   # idempotent & race-safe
            return $true
        } catch {
            Write-Host "[Logger] Failed to ensure directory '$Path': $($_.Exception.Message)" -ForegroundColor DarkYellow
            return $false
        }
    }

    function Resolve-LogPath([string]$Preferred, [string]$Fallback) {
        $resolved = $Preferred

        # If preferred is on I:, try mounting once using your wrapper
        $isOnI = $Preferred -like 'I:*'
        if ($isOnI -and -not (Test-Path -LiteralPath $resolved -PathType Container -ErrorAction SilentlyContinue)) {
            $mounted = $false
            # Assuming Mount-I-share is a defined function in your module
            try { $mounted = [bool](Mount-I-share) } catch { $mounted = $false }

            if ($mounted -and -not (Test-Path -LiteralPath $resolved -PathType Container -ErrorAction SilentlyContinue)) {
                New-LogDirectoryIfMissing $resolved | Out-Null
            }
        }

        # If still missing, fall back locally
        if (-not (Test-Path -LiteralPath $resolved -PathType Container -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path -LiteralPath $Fallback -PathType Container -ErrorAction SilentlyContinue)) {
                New-LogDirectoryIfMissing $Fallback | Out-Null
            }
            #i don't like that output, so fuck it
            #Write-Host "[Logger] I: not available; using fallback." -ForegroundColor Gray
            #Write-Host $Fallback -ForegroundColor Gray
            return $Fallback
        }

        return $resolved
    }
    # --- end helpers ---

    # Resolve the final log directory (no M:, only I: -> local)
    $fallbackPath   = 'C:\Program Files\PowerShell\Modules\modulus-toolkit\logs'
    $ResolvedLogPath = Resolve-LogPath -Preferred $BaseLogPath -Fallback $fallbackPath

    # Timestamp & formatting
    $timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted   = "[$timestamp] [$Level] $Message"
    $logFileName = "toolkit-$ENV:MODULUS_SERVER.log"
    $logFilePath = Join-Path -Path $ResolvedLogPath -ChildPath $logFileName

    # Define log level hierarchy (Adjusted to standard best practice order)
    $logLevels = @{
        "VERBOSE" = 1 
        "DEBUG"   = 2
        "INFO"    = 3
        "SUCCESS" = 4
        "WARNING" = 5
        "ERROR"   = 6
    }

    # Smart cache: refresh if MODULUS_LOG changed or not yet set
    # CRITICAL FIX: Safely convert $env:MODULUS_LOG to uppercase, handling $null/empty
    $envLogUpper = ($env:MODULUS_LOG -as [string]).ToUpper()
    
    if (
        -not $Global:ModulusResolvedLogLevel -or
        -not $Global:ModulusResolvedLogLevelSource -or
        $envLogUpper -ne $Global:ModulusResolvedLogLevelSource
    ) {
        $envLevel     = $envLogUpper
        $usedFallback = $false

        $wasInvalidValue = $false

        if (-not $envLevel) {
             # Case 1: Variable is unset/empty
            $envLevel        = "INFO"
            $usedFallback    = $true
        } elseif (-not $logLevels.ContainsKey($envLevel)) {
             # Case 2: Variable is set but value is invalid (user requested change)
            $envLevel        = "INFO"
            $usedFallback    = $true
            $wasInvalidValue = $true
        }

        # Store the clean, uppercase, resolved value in the global cache
        $Global:ModulusResolvedLogLevel       = $envLevel
        # Store the actual environment variable's uppercase value for refresh check
        $Global:ModulusResolvedLogLevelSource = $envLogUpper

        if ($usedFallback) {
            # Implementation of the user's request for a Warning if the value was invalid.
            if ($wasInvalidValue) {
                Write-Host "[Logger] WARNING: MODULUS_LOG value ('$($env:MODULUS_LOG)') is invalid. Defaulting to INFO." -ForegroundColor Yellow
            } else {
                Write-Host "[Logger] MODULUS_LOG not set. Defaulting to INFO." -ForegroundColor Gray
            }
        }
    }

    # $resolvedLevel is already clean and uppercase from the cache block
    $resolvedLevel = $Global:ModulusResolvedLogLevel

    # Determine color (UPDATED: SUCCESS is Cyan, DEBUG is DarkCyan)
    switch ($Level) {
        "INFO"    { $color = "Green" }
        "SUCCESS" { $color = "Cyan" }      # Success is now Cyan
        "WARNING" { $color = "Yellow" }
        "ERROR"   { $color = "Red" }
        "DEBUG"   { $color = "DarkCyan" }  # Debug is now DarkCyan
        "VERBOSE" { $color = "DarkGray" }
        default   { $color = "White" }
    }

    if ($Header) { $color = "Blue" }
    if ($Scope)  { $Header = $true; $color = "Magenta" }

    # --- Prepare content for a single log file write operation ---
    $logContent = $formatted
    if ($Header) {
        # Prepend an empty line to the content to visually separate headers in the file
        $logContent = "`n" + $logContent
    }
    # --- End content preparation ---

    # Console output only if level >= resolved level AND -Silent was NOT used
    if (-not $Silent -and ($logLevels[$Level] -ge $logLevels[$resolvedLevel])) {
        $width  = $formatted.Length
        $border = "+" + ("-" * ([math]::Max($width - 2, 0))) + "+"

        if ($Header) {
            Write-Host ""
            Write-Host $border -ForegroundColor $color
        }

        Write-Host $formatted -ForegroundColor $color

        if ($Header) {
            Write-Host $border -ForegroundColor $color
        }
    }

    # Always write to log file (single I/O operation)
    try {
        if (-not (Test-Path -LiteralPath $ResolvedLogPath -PathType Container -ErrorAction SilentlyContinue)) {
            New-LogDirectoryIfMissing $ResolvedLogPath | Out-Null
        }
        # Write the compiled content, which includes the leading blank line if it was a header.
        Add-Content -LiteralPath $logFilePath -Value $logContent -Encoding UTF8
    } catch {
        Write-Host "[Logger] Failed to write log '$logFilePath': $($_.Exception.Message)" -ForegroundColor Red
    }
}
#endregion

#region --- toolkits elevation handling
function Set-ElevatedState {
    param (
        [bool]$Enable
    )
    $TokenFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\elevated-token"
    if ($Enable) {
        #option 1: user-specific token
        #$secureToken = ConvertTo-SecureString "elevated" -AsPlainText -Force
        #$secureToken | ConvertFrom-SecureString | Set-Content $TokenFilePath

        #option 2: system-wide token
        $tokenBytes = [System.Text.Encoding]::UTF8.GetBytes("elevated")
        $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $tokenBytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
        [System.IO.File]::WriteAllBytes($TokenFilePath, $encryptedBytes)
        Write-Log "Elevated state enabled."
    } else {
        Remove-Item -Path $TokenFilePath -Force -ErrorAction SilentlyContinue
        Write-Log "Elevated state disabled."
    }
}

function Enable-ToolkitElevation {
    $expected = "54321doM"
    $password = Read-Host -Prompt "Please enter the password" -AsSecureString
    #Convert the secure string to plain text for comparison (not recommended for sensitive applications)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

    if ($plainPassword -eq $expected) {
        Set-ElevatedState -enable $True
        Reload-Profile
    } else {
        Write-Log "Wrong credential. No change!" -level ERROR
    }
}
Set-Alias -Name Elevate-Toolkit -Value Enable-ToolkitElevation

function Suspend-Toolkit {
    Set-ElevatedState -enable $False
    Reload-Profile
}

function Get-ElevatedState {

    $SP = Test-FeatureUnlocked "SP"
    if ($SP) { 
        return $true 
    }

    $TokenFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\elevated-token"
    if (Test-Path $TokenFilePath) {
        try {
            # Read the encrypted token as bytes
            $encryptedBytes = [System.IO.File]::ReadAllBytes($TokenFilePath)
            # Decrypt the bytes using DPAPI with the LocalMachine scope
            $decryptedBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $encryptedBytes, 
                $null, 
                [System.Security.Cryptography.DataProtectionScope]::LocalMachine
            )
            # Convert the decrypted bytes back into a string
            $decryptedToken = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
            # Compare the token to the expected value
            if ($decryptedToken -eq "elevated") {
                return $true
            }
        } catch {
            # Optionally log or handle the error
        }
    }
    return $false
}
#endregion

#region --- toolkits feature handling
function Get-FeatureUnlockKeys {
    <#
    .SYNOPSIS
    Retrieves and processes the MODULUS_KEY environment variable.
    .OUTPUTS
    [string[]] - An array of uppercase feature codes (e.g., 'SP', 'CC', 'LB').
    #>
    [CmdletBinding(DefaultParameterSetName='AllKeys')]
    param()

    # 1. Access the Environment Variable
    $keyString = $env:MODULUS_KEY

    # 2. Check for existence/value
    if (-not $keyString) {
        # Key variable is not set or is empty
        return @()
    }

    # 3. Split the string into an array of feature codes
    # -split operator with ',' delimiter
    # .Trim() removes any accidental whitespace around the codes
    $keyArray = $keyString.ToUpper().Split(',', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }

    return $keyArray
}

function Test-FeatureUnlocked {
    <#
    .SYNOPSIS
    Checks if a specific feature is enabled by the MODULUS_KEY.
    .PARAMETER FeatureCode
    The code for the feature to check (e.g., 'SP', 'CC').
    .OUTPUTS
    [boolean] - $true if the feature is unlocked, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$FeatureCode
    )

    # 1. Get the list of all unlocked keys
    $unlockedKeys = Get-FeatureUnlockKeys

    # 2. Check if the requested FeatureCode is in the array
    # The -contains operator is ideal for checking if an array contains an element.
    if ($unlockedKeys -contains $FeatureCode.ToUpper().Trim()) {
        # Write-Verbose "Feature '$FeatureCode' is UNLOCKED."
        return $true
    } else {
        # Write-Verbose "Feature '$FeatureCode' is LOCKED. (Requires: $FeatureCode)"
        return $false
    }
}
#endregion

#region --- profile-helper
function Reset-Profile {
    # Executes the current user's profile script ($PROFILE) in the current scope.
    . $PROFILE
}
Set-Alias -Name Reload-Profile -Value Reset-Profile
#endregion

#region --- internet connectivity helper
function Test-InternetConnection {
    try {
        Test-Connection -ComputerName "www.google.com" -Count 1 -Quiet
    } catch {
        return $false
    }
}
#endregion

#region --- initialization environment variables
function Initialize-Environment {
    # Check if the environment variable 'MODULUS_SERVER' exists
    $modulusServer = [System.Environment]::GetEnvironmentVariable("MODULUS_SERVER", [System.EnvironmentVariableTarget]::Machine)

    #Write-Host "Initializing needed MODULUS_SERVER environment variable..." -ForegroundColor Green
    if (-not $modulusServer) {
        Write-Log "The MODULUS_SERVER environment variable does not exist." WARNING

        # Define options for the user to choose from
        $options = @{
            1 = "DB  - Database server    - part of a 3VM deployment.";
            2 = "APP - Application server - part of a 3VM deployment.";
            3 = "FS  - Floor server       - part of a 3VM deployment.";
            4 = "1VM - All-in-One server deployment.";
            5 = "WS  - Workstation connected to an existing system."
        }

        # Define the corresponding values for the MODULUS_SERVER variable
        $serverValues = @{
            1 = "DB";
            2 = "APP";
            3 = "FS";
            4 = "1VM";
            5 = "WS";
        }

        # Loop until the user confirms their choice
        $confirmed = $false
        while (-not $confirmed) {
            # Display the options in yellow, sorted by number
            foreach ($key in ($options.Keys | Sort-Object)) {
                Write-Log "$key. $($options[$key])" WARNING
            }

            # Ask the user to select an option
            $selection = Read-Host "Please choose an option (1-5)"

            # Validate the selection
            if ($selection -as [int] -and $options.ContainsKey([int]$selection)) {
                $selectedOption = $options[[int]$selection]
                $serverType = $serverValues[[int]$selection]  # Use the integer selection as key

                # Confirm the user's selection
                Write-Log "You selected: $selectedOption"
                $confirmation = Read-Host "Do you want to set MODULUS_SERVER to '$serverType'? (y/n)"

                if ($confirmation -eq 'y') {
                    # Set the environment variable only if confirmed
                    [System.Environment]::SetEnvironmentVariable("MODULUS_SERVER", $serverType, [System.EnvironmentVariableTarget]::Machine)
                    Write-Log "MODULUS_SERVER has been set to '$serverType'." 
                    $confirmed = $true
					Return $true
                } else {
                    Write-Log "Selection not confirmed. Please try again." WARNING
                }
            } else {
                Write-Log "Invalid selection. Please choose a valid option (1-5)." ERROR
            }
        }
    } else {
        #Write-Host "MODULUS_SERVER environment variable already exists: $modulusServer" -ForegroundColor Green
		Return $true
    }
}
#endregion

#region --- initialization module-dependencies
function Initialize-Modules {
    param (
        [string[]]$Modules,
        [string]$ModulePath = "C:\Program Files\PowerShell\Modules"
    )

    $init = $True

    #Write-Host "Initializing needed modules..." -ForegroundColor Green

    $internetConnected = Test-InternetConnection
    
    foreach ($module in $Modules) {
        $moduleExists = Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue
        
        if ($internetConnected) {
            if (-not $moduleExists) {
                Write-Log "$module is not installed. Attempting to download..." WARNING
                try {
                    Install-Module -Name $module -Scope AllUsers -Force -ErrorAction Stop
                    Write-Log "$module installed successfully."
                } catch {
                    Write-Log "Failed to install $module. Please ensure you have the necessary permissions and try again." WARNING
                    $init = $False
                    #return $False  
                }
            }  
        } else {
            #Write-Warning "No internet connection. Cannot install $module."
        }

        try {
            Import-Module $module -ErrorAction Stop
            #Write-Host "$module imported successfully." -ForegroundColor Green
        } catch {
            Write-Log "Failed to import $module." WARNING
            if (-not $internetConnected) {
                Write-Log "Your environment is not connected to the internet!" ERROR
                Write-Log "Please provide the modules following modules manually to $ModulePath and retry!" WARNING
                foreach ($module in $Modules) {
                    Write-Log "- $module" WARNING
                }
            }
            $init = $False
            #return $false
        }
    }
    
    if (-not $init) {
        Write-Log "Loading modulus-toolkit failed because of missing prerequisites!" WARNING
        Write-Log "Exiting in 60 seconds!" WARNING
        Start-Sleep -Seconds 60
        Exit
    }
    #return $true
}
#endregion

#region --- initialization vault and helpers
function Initialize-Vault {
    param (
        #[string]$Vault = $global:Vault
        [string]$Vault = 'modulus-toolkit'
    )
    $defaultPassword = ConvertTo-SecureString ";-D" -AsPlainText -Force
    # Check if the vault exists
    if (-not (Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue)) {
        Register-SecretVault -Name $Vault -ModuleName Microsoft.PowerShell.SecretStore
        Write-Log "Vault $Vault created." WARNING
        Set-SecretStoreConfiguration -Authentication None -Password $defaultPassword -Confirm:$false
        #Set-SecretStoreConfiguration -Authentication None -Confirm:$false
    }
    else {
        #Write-Host "Initializing module vault..." -ForegroundColor Green
    }
}

function Set-CredentialInVault {
    param (
        [string]$User,
        [string]$Domain = $null,
        [string]$Target,  # This can be Hostname or Database name
        #[string]$Vault = $global:Vault
        [string]$Vault = 'modulus-toolkit'
    )

    # Construct credential name based on domain/hostname and target
    $CredentialName = if ($Domain) { "$Domain\$User@$Target" } else { "$User@$Target" }

    # Check if the credential already exists
    if (Get-SecretInfo -Name $CredentialName -Vault $Vault -ErrorAction SilentlyContinue) {
        $overwrite = Read-Host "Credential $CredentialName already exists. Do you want to overwrite it? (y/n)"
        if ($overwrite -ne 'y') {
            Write-Log "Operation cancelled. Credential $CredentialName was not overwritten." ERROR
            return
        }
    }

    # Prompt for credential and store in vault
    $Credential = Get-Credential -UserName $User
    Set-Secret -Name $CredentialName -Secret $Credential -Vault $Vault
    Write-Log "Credential $CredentialName stored (or overwritten) in the vault."
    
    #TODO - maybe return the credential that was just inserted
    #Get-CredentialFromVault
}

function Get-CredentialFromVault {
    param (
        [string]$User,
        [string]$Domain = $null,
        [string]$Target,  # This can be Hostname or Database name
        #[string]$Vault = $global:Vault
        [string]$Vault = 'modulus-toolkit'
    )

    # Construct credential name based on domain/hostname and target
    $CredentialName = if ($Domain) { "$Domain\$User@$Target" } else { "$User@$Target" }

    # Try to retrieve the credential from the vault
    $Credential = Get-Secret -Name $CredentialName -Vault $Vault -ErrorAction SilentlyContinue

    if ($Credential) {
        Write-Log "Credential $CredentialName retrieved from the vault." -Level DEBUG
        return $Credential
    } else {
        Write-Log "Credential $CredentialName not found in the vault." -Level WARNING
        return $null
    }
}

function Remove-CredentialFromVault {
    param (
        [string]$User,
        [string]$Domain = $null,
        [string]$Target,  # This can be Hostname or Database name
        #[string]$Vault = $global:Vault
        [string]$Vault = 'modulus-toolkit'
    )

    # Construct credential name based on domain/hostname and target
    $CredentialName = if ($Domain) { "$Domain\$User@$Target" } else { "$User@$Target" }

    # Check if the credential exists before attempting to remove it
    if (Get-SecretInfo -Name $CredentialName -Vault $Vault -ErrorAction SilentlyContinue) {
        # Remove the secret from the vault
        Remove-Secret -Name $CredentialName -Vault $Vault
        Write-Log "Credential $CredentialName removed from the vault." WARNING
    } else {
        Write-Log "Credential $CredentialName not found in the vault." ERROR
    }
}

function Enable-VaultWithoutPassword {
    # Set the vault configuration to disable password requirement
    Set-SecretStoreConfiguration -Authentication None -Confirm:$false
    #Write-Host "Password requirement for SecretStore vault has been disabled."
}

function Disable-VaultWithoutPassword {
    # Set the vault configuration to enable password requirement
    Set-SecretStoreConfiguration -Authentication Password -Confirm:$false
    #Write-Host "Password requirement for SecretStore vault has been enabled."
}
#endregion

#region --- initialization crypto function and helpers
$EmbeddedCmsBlob = @'
-----BEGIN CMS-----
MIIB4gYJKoZIhvcNAQcDoIIB0zCCAc8CAQAxggFKMIIBRgIBADAuMBoxGDAWBgNVBAMMD21vZHVs
dXMtdG9vbGtpdAIQWLpm+y9KsZ1EZbwFkcgQXTANBgkqhkiG9w0BAQEFAASCAQC67jmcmzaBhHXH
uGLmUWJ1wc15Y+xn+UwZ8LFDMM/dXgGpqxxYqaFaeHr88gfVf+UP/imnXsquSbVYx9uYGV1xlba0
HdWtX9FrMFwWSmuh/lldhJwLCH5WFCtPJzsOde2mjHN0T1K/giTDaZpKGI4SoSwrHjQ5qa7Cru9q
phtCJY5vS3/ZZrcezvJxj1oMyD8IKKy78t7B8A4DmCCf21YLp1ehe2HOI1VVODxl1ly7P7FOOiAH
akF/FZzzISjmvT0zaAXEne2mIEXInzKfYXq+m4kHAKkwmxNa+GzVuwUM7zf5D4eoHFVwdWMDdwMW
dBzqZSfb6YePREvRMk/QFEypMHwGCSqGSIb3DQEHATAdBglghkgBZQMEASoEEI422RrDpxxQEbTN
yWxL0JKAUCOSZndlY3cQ00ebWK/hPd9pCwXDxaxF3VzGdilTjuu8h/lJpfVhd3DrOqAuDSbDfB24
Ajfo2Dey3QQRgUGPyjT+HkFu8h4/V9/2BF1PrBNZ
-----END CMS-----
'@

function _GetCleanCms {
    param([Parameter(Mandatory)][string]$Raw)
    $r = $Raw -replace '^\uFEFF',''
    $r = $r -replace '^\s*(-----BEGIN CMS-----)','$1'
    $r = $r -replace '(-----END CMS-----)\s*$','$1'
    return $r
}

function Get-CryptoModuleParams {
    [CmdletBinding()]
    param([switch]$UseCache, [switch]$ThrowOnError)

    try {
        if ($UseCache -and $script:ModuleCryptoCache) {
            #Write-Log -Message "Get-CryptoModuleParams: cache hit" -Level DEBUG
            return $script:ModuleCryptoCache
        }

        if (-not $EmbeddedCmsBlob) { throw "Embedded CMS blob is empty or undefined." }

        $cms = _GetCleanCms -Raw $EmbeddedCmsBlob

        # NOTE: use (?s) for singleline
        if ($cms -notmatch '(?s)^-----BEGIN CMS-----.*-----END CMS-----\s*$') {
            throw "Embedded CMS content is invalid or missing markers."
        }

        #Write-Log -Message "Decrypting embedded CMS…" -Level DEBUG
        $json = Microsoft.PowerShell.Security\Unprotect-CmsMessage -Content $cms
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw "Unprotect-CmsMessage returned empty content for embedded CMS."
        }

        $o = $json | ConvertFrom-Json
        if (-not $o.Passphrase -or -not $o.SaltString) {
            throw "Decrypted JSON is missing required fields (Passphrase / SaltString)."
        }

        $result = [pscustomobject]@{
            Passphrase = [string]$o.Passphrase
            SaltString = [string]$o.SaltString
            SaltBytes  = [Text.Encoding]::ASCII.GetBytes([string]$o.SaltString)
        }

        if ($UseCache) {
            $script:ModuleCryptoCache = $result
            #Write-Log -Message "Get-CryptoModuleParams: cached" -Level DEBUG
        }

        #Write-Log -Message "Loaded crypto params from embedded CMS" -Level INFO
        return $result
    }
    catch {
        $msg = "Crypto parameters could not be loaded. $($_.Exception.Message)"
        Write-Log -Message $msg -Level ERROR
        if ($ThrowOnError) { throw $msg }
    }
}

function Get-LegacyCryptoContext {
    <#
      Derives legacy Key/IV from Passphrase/Salt (embedded).
      Legacy constants preserved: PBKDF2 iterations=3, keysize=128, IV=16 bytes from KDF.
      Returns: [pscustomobject] with Key (byte[]), IV (byte[])
    #>
    [CmdletBinding()]
    param(
        [int]$Iterations   = 3,
        [int]$KeySizeBits  = 128,  # 16 bytes
        [int]$IVSizeBytes  = 16    # AES block size
    )

    $cacheKey = "$Iterations|$KeySizeBits|$IVSizeBytes"
    if ($script:LegacyCryptoCache -and $script:LegacyCryptoCache.Key -eq $cacheKey) {
        #Write-Log "Get-LegacyCryptoContext: cache hit" DEBUG
        return $script:LegacyCryptoCache.Context
    }

    $p = Get-CryptoModuleParams -UseCache -ThrowOnError
    if (-not $p) { throw "Crypto params unavailable." }

    #Write-Log "Deriving legacy Key/IV (PBKDF2 iters=$Iterations, key=$KeySizeBitsb, iv=$IVSizeBytesb)" DEBUG
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $p.Passphrase,
        $p.SaltBytes,
        $Iterations
    )

    $key = $kdf.GetBytes($KeySizeBits / 8)  # 16 bytes
    $iv  = $kdf.GetBytes($IVSizeBytes)      # 16 bytes

    $ctx = [pscustomobject]@{ Key = $key; IV = $iv }
    $script:LegacyCryptoCache = [pscustomobject]@{ Key = $cacheKey; Context = $ctx }
    #Write-Log "Key/IV derived and cached" DEBUG
    return $ctx
}

function Test-CryptoModule {
    <#
      Returns $true if the embedded CMS can be decrypted by the current identity.
    #>
    [CmdletBinding()] param()
    try {
        $cms = _GetCleanCms -Raw $EmbeddedCmsBlob
        $null = Microsoft.PowerShell.Security\Unprotect-CmsMessage -Content $cms
        #Write-Log -Message "Embedded CMS decrypt test: OK" -Level INFO
        $true
    } catch {
        #Write-Log -Message ("Embedded CMS decrypt test: FAILED ({0})" -f $_.Exception.Message) -Level WARNING
        $false
    }
}

function Initialize-CryptoModule {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$PfxPath,
        [SecureString]$PfxPassword,
        [ValidateSet('Cert:\LocalMachine\My','Cert:\CurrentUser\My')]
        [string]$Store = 'Cert:\LocalMachine\My',
        [string]$Subject = 'CN=modulus-toolkit',
        [string]$GrantPrivateKeyTo,
        [switch]$DeletePfxAfterImport
    )

    function _getCert([string]$subject,[string]$store){
        Get-ChildItem $store -ErrorAction SilentlyContinue |
          Where-Object { $_.Subject -eq $subject } |
          Sort-Object NotAfter -Descending |
          Select-Object -First 1
    }
    function _grantPrivateKeyRead($cert, [string]$identity){
        # Best-effort for legacy CSP keys. For CNG, use certlm.msc → Manage Private Keys…
        try {
            $csp = $cert.PrivateKey.CspKeyContainerInfo
            if ($csp -and $csp.UniqueKeyContainerName) {
                $mk = if ($Store -like 'Cert:\LocalMachine\*') { "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys" }
                      else { Join-Path $env:APPDATA "Microsoft\Crypto\RSA\$([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)" }
                $keyFile = Join-Path $mk $csp.UniqueKeyContainerName
                if (Test-Path -LiteralPath $keyFile) {
                    $acl = Get-Acl -LiteralPath $keyFile
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity,'Read','Allow')
                    $acl.AddAccessRule($rule) | Out-Null
                    Set-Acl -LiteralPath $keyFile -AclObject $acl
                    return $true
                }
            }
        } catch { }
        return $false
    }

    #yeah i know
    $PfxPassword = ConvertTo-SecureString 'Crypto12345' -AsPlainText -Force

    try {
        if (Test-CryptoModule) {
            #Write-Log "Install-CryptoModule: decryption already works; no action needed" INFO
            return $true
        }

        if (-not $PfxPath)     { throw "No private key available. Supply -PfxPath." }
        if (-not (Test-Path -LiteralPath $PfxPath -PathType Leaf)) { throw "PFX not found at '$PfxPath'." }
        if (-not $PfxPassword) { throw "PFX password (-PfxPassword) is required to import $PfxPath." }

        Write-Log "Importing PFX into $Store …" INFO
        $null = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation $Store -Password $PfxPassword -Exportable

        if ($GrantPrivateKeyTo) {
            try {
                $cert = _getCert -subject $Subject -store $Store
                if (-not $cert) {
                    Write-Log "Could not locate cert by subject [$Subject] to grant permissions." WARNING
                }
                elseif (-not (_grantPrivateKeyRead -cert $cert -identity $GrantPrivateKeyTo)) {
                    Write-Log "Could not grant private-key read via script (likely CNG). Use certlm.msc → Personal → Certificates → $Subject → Manage Private Keys…" WARNING
                } else {
                    Write-Log "Granted private-key READ to [$GrantPrivateKeyTo]" INFO
                }
            } catch {
                Write-Log "Grant step failed: $($_.Exception.Message)" WARNING
            }
        }

        Write-Log "Verifying decryption with embedded CMS…" INFO
        if (-not (Test-CryptoModule)) {
            throw "Decryption still failing after import. Ensure the PFX matches the embedded CMS and the running identity has READ access to the private key."
        }
        Write-Log "Decryption OK" INFO

        if ($DeletePfxAfterImport -and $PfxPath -and (Test-Path -LiteralPath $PfxPath -PathType Leaf)) {
        try {
            # clear read-only if needed, then delete
            $fi = Get-Item -LiteralPath $PfxPath -Force
            if ($fi.Attributes -band [IO.FileAttributes]::ReadOnly) { $fi.IsReadOnly = $false }
            Remove-Item -LiteralPath $PfxPath -Force
            Write-Log -Message "Deleted PFX: $PfxPath" -Level INFO
        } catch {
            Write-Log -Message ("Failed to delete PFX ({0})" -f $_.Exception.Message) -Level WARNING
        }
}

        Write-Log "Initialization complete" INFO
        return $true
    }
    catch {
        Write-Log "Install-CryptoModule failed: $($_.Exception.Message)" ERROR
        return $false
    }
}
#endregion

#region --- initialization tool functions
function Find-Tool {
    param (
        [string]$ToolName,
        [string[]]$CommonPaths
    )
    
    foreach ($path in $CommonPaths) {
        $fullPath = Join-Path -Path $path -ChildPath $ToolName
        #write-host $fullPath
        if (Test-Path -Path $fullPath -PathType Leaf) {
            return $fullPath
        }
    }

    throw "$ToolName not found in common paths"
}

function Initialize-Tools {
    # Common paths for 7-Zip
    $7z_commonPaths = @(
        "$env:ProgramFiles\7-Zip\",
        "C:\Program Files (x86)\7-Zip\"
    )

    #Write-Host "Initializing needed tools..." -ForegroundColor Green
    
    $7z_path = Find-Tool -ToolName "7z.exe" -CommonPaths $7z_commonPaths
    if (-not (Get-Alias 7z -ErrorAction SilentlyContinue)) {
        Set-Alias 7z $7z_path -Scope Global
    }
    if (-not (Get-Alias 7zip -ErrorAction SilentlyContinue)) {
        Set-Alias 7zip $7z_path -Scope Global
    }

    # Common paths for Notepad++
    $np_commonPaths = @(
        "$env:ProgramFiles\Notepad++\",
        "C:\Program Files (x86)\Notepad++\"
    )
    
    $npPP_path = Find-Tool -ToolName "notepad++.exe" -CommonPaths $np_commonPaths
    if (-not (Get-Alias np -ErrorAction SilentlyContinue)) {
        Set-Alias np $npPP_path -Scope Global
    }
    if (-not (Get-Alias np++ -ErrorAction SilentlyContinue)) {
        Set-Alias np++ $npPP_path -Scope Global
    }
}
#endregion

#region --- version handling and update functions
function Get-ModuleRoot {
    param([string]$Name)
    $m = Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $m) { throw "Module '$Name' not found in PSModulePath." }
    return $m.ModuleBase
}

function Get-CurrentVersion {
    param([string]$ModuleRoot)
    $psd1 = Get-ChildItem -Path $ModuleRoot -Filter *.psd1 | Select-Object -First 1
    if (-not $psd1) { throw "No .psd1 found in '$ModuleRoot'." }
    $data = Import-PowerShellDataFile -Path $psd1.FullName
    if (-not $data.ModuleVersion) { throw "ModuleVersion missing in '$($psd1.Name)'." }
    return [version]$data.ModuleVersion
}

function Get-AvailableArchives {
    param([string]$Dir)
    $rx = '^modulus-toolkit-(\d+(?:\.\d+){1,3})\.7z$'
    Get-ChildItem -Path $Dir -File -Filter '*.7z' | ForEach-Object {
        if ($_.Name -match $rx) {
            [pscustomobject]@{
                File    = $_.FullName
                Name    = $_.Name
                Version = [version]$Matches[1]
            }
        }
    }
}
#endregion

#region --- .NET & ASP.NET check
function Assert-InstalledRuntime {
    [CmdletBinding()]
    param(
        [int]$MinMajor = 8,
        [switch]$PassThru,
        [switch]$OnlyOnFailure,
        [switch]$Quiet
    )

    #only run on APP/1VM servers
    $server = $env:MODULUS_SERVER
    if ($server -notin ("APP","1VM")) { 
        Return $true
    }

    # tolerant parser: "8.0.0[-...]" -> [version] 8.0.0
    function ConvertTo-VersionSafe {
        param([string]$Name)
        if ($Name -match '^\d+\.\d+\.\d+') {
            try { return [version]$matches[0] } catch {}
        }
        return $null
    }

    # Candidate roots (handles 32/64-bit hosts)
    $pfCandidates = @($env:ProgramW6432, $env:ProgramFiles) | Where-Object { $_ } | Select-Object -Unique

    # Runtime → relative path
    $rel = @{
        ".NET"    = "dotnet\shared\Microsoft.NETCore.App"
        "ASP.NET" = "dotnet\shared\Microsoft.AspNetCore.App"
    }

    # 1) Probe/filesystem scan
    $results = foreach ($name in $rel.Keys) {
        $paths = foreach ($pf in $pfCandidates) { Join-Path $pf $rel[$name] }
        $paths = $paths | Select-Object -Unique

        $versions = New-Object System.Collections.Generic.List[version]
        $existingPaths = @()
        foreach ($p in $paths) {
            if (Test-Path -LiteralPath $p -PathType Container) {
                $existingPaths += $p
                $dirs = Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue
                foreach ($d in $dirs) {
                    $v = ConvertTo-VersionSafe -Name $d.Name
                    if ($v) { [void]$versions.Add($v) }
                }
            }
        }

        $versions = $versions | Sort-Object
        [pscustomobject]@{
            Runtime      = $name
            Paths        = $existingPaths
            Versions     = $versions
            Lowest       = ($versions | Select-Object -First 1)
            Highest      = ($versions | Select-Object -Last 1)
            MeetsMinimum = ($versions | Where-Object { $_.Major -ge $MinMajor }).Count -gt 0
        }
    }

    # 2) Decide overall state
    $allMet = -not (($results | Select-Object -ExpandProperty MeetsMinimum) -contains $false)

    # 3) Build output lines (no emission yet)
    $lines = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($r in $results) {
        $lines.Add([pscustomobject]@{ Message = $r.Runtime; Level = "DEBUG" })
        if ($r.Versions.Count -gt 0) {
            foreach ($v in $r.Versions) {
                $lines.Add([pscustomobject]@{ Message = "- $($v.ToString())"; Level = "DEBUG" })
            }
        } else {
            $lines.Add([pscustomobject]@{ Message = "- (no versions found)"; Level = "DEBUG" })
        }
    }

    $lines.Add([pscustomobject]@{ Message = "Summary"; Level = "INFO" })
    foreach ($r in $results) {
        $pathsText = if ($r.Paths.Count -gt 0) { $r.Paths -join '; ' } else { '(not found)' }
        $meets = if ($r.MeetsMinimum) { ">= $MinMajor ✓" } else { "< $MinMajor ✗" }
        $lowest = if ($r.Lowest) { $r.Lowest.ToString() } else { "-" }
        $highest = if ($r.Highest) { $r.Highest.ToString() } else { "-" }
        $lines.Add([pscustomobject]@{
            Message = "- $($r.Runtime): lowest $lowest, highest $highest, requirement $meets [$pathsText]"
            Level   = if ($r.MeetsMinimum) { "INFO" } else { "WARNING" }
        })
    }

    if ($allMet) {
        $lines.Add([pscustomobject]@{ Message = "Requirements met"; Level = "INFO" })
    } else {
        $missing = $results | Where-Object { -not $_.MeetsMinimum } | Select-Object -ExpandProperty Runtime
        $todo = @()
        if ($missing -contains ".NET")    { $todo += ".NET Runtime $MinMajor.x" }
        if ($missing -contains "ASP.NET") { $todo += "ASP.NET Core Runtime $MinMajor.x" }
        $lines.Add([pscustomobject]@{
            Message = "Minimum version $MinMajor+ is not met for: $($missing -join ', '). Please install: $($todo -join ' and ')."
            Level   = "WARNING"
        })
    }

    # 4) Emit using your existing Write-Log, with levels
    if (-not $Quiet) {
        if ($OnlyOnFailure) {
            if (-not $allMet) {
                foreach ($l in $lines) { Write-Log $l.Message -Level $l.Level }
            }
        } else {
            foreach ($l in $lines) { Write-Log $l.Message -Level $l.Level }
        }
    }

    if ($PassThru) { return $results }
    return $allMet
}
#endregion 

#region --- scope.json topic
#region --- scope.json logic(initialization, diff, merge, legacy-conversion, file I/O)
function Get-ConfigSchema {
  [OutputType([hashtable])]
  param()

  $schema = [ordered]@{
    version = 1
    root = [ordered]@{
      type='object'; allowUnknown=$false; children=[ordered]@{

        general = [ordered]@{
          type='object'; allowUnknown=$false; children=[ordered]@{
            system   = @{ type='string';  default='3VM';            required=$true;  userEditable=$true }
            timezone = @{ type='string';  default='Europe/Vienna';  required=$true;  userEditable=$true }
            language = @{ type='string';  default='en';             required=$true;  userEditable=$true }
            currency = @{ type='string';  default='EUR';            required=$true;  userEditable=$true }
          }
        }

        customer = [ordered]@{
          type='object'; allowUnknown=$false; children=[ordered]@{
            code = @{ type='string'; default='MOD';               required=$true;  userEditable=$true }
            name = @{ type='string'; default='Modulus S.a.r.l.';  required=$true;  userEditable=$true }
          }
        }

        casino = [ordered]@{
          type='object'; allowUnknown=$false; children=[ordered]@{
            ID       = @{ type='number'; default=999;               required=$true;  userEditable=$true } # lock identity, but when?
            code     = @{ type='string'; default='TL';              required=$true;  userEditable=$true }
            name     = @{ type='string'; default='LAB Template';    required=$true;  userEditable=$true }
            longname = @{ type='string'; default='MOD LAB Template';required=$true;  userEditable=$true }

            modules = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                CAWA        = @{ type='boolean'; default=$true }
                Jackpot     = @{ type='boolean'; default=$true }
                Replication = @{ type='boolean'; default=$false }
                R4R         = @{ type='boolean'; default=$false }
                MyBar       = @{ type='boolean'; default=$false }
              }
            }

            RFIDKeys = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                BlowfishKey  = @{ type='string'; default='1MNZ1obhhiDhP4zc1rIv2Qa+4ESGyJO94bTt7txlhZU=';    required=$true;  userEditable=$true } 
                ReadKey_MAD  = @{ type='string'; default='uAUc8/dyBJ4mtfcG9aV1zQ==';                        required=$true;  userEditable=$true } 
                WriteKey_MAD = @{ type='string'; default='tMvBcO9a0wy3tomAVgnkPw==';                        required=$true;  userEditable=$true } 
              }
            }
          }
        }

        databases = [ordered]@{
          type='object'; allowUnknown=$false; children=[ordered]@{
            GLX = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                TNS = @{ type='string'; default='GLX'; required=$true; userEditable=$true }
              }
            }
            JKP = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                TNS = @{ type='string'; default='JKP'; required=$true; userEditable=$true }
              }
            }
            users = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                as_jackpot   = @{ type='string'; default='as_jackpot';  required=$true; userEditable=$true }
                as_security  = @{ type='string'; default='as_security'; required=$true; userEditable=$true }
                as_jp_report = @{ type='string'; default='as_jp_report';required=$true; userEditable=$true }
                specific     = @{ type='string'; default='site';        required=$true; userEditable=$true }
              }
            }
          }
        }

        servers = [ordered]@{
          type='object'; allowUnknown=$false; children=[ordered]@{

            DB = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                hostname = @{ type='string'; default='ModulusDB'; required=$true; userEditable=$true }
                networkAdapters = [ordered]@{
                  type='object'; allowUnknown=$true; children=[ordered]@{
                    OFFICE = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='OFFICE';       required=$true; userEditable=$false }
                        IP   = @{ type='string'; default='192.168.1.20'; required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.0.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='';             required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'}; default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                    MODULUS = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='MODULUS';         required=$true; userEditable=$true }
                        IP   = @{ type='string'; default='192.168.0.120';   required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.255.0';   required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='192.168.0.1';     required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'};    default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                  }
                }
              }
            }

            APP = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                hostname = @{ type='string'; default='ModulusAPP'; required=$true; userEditable=$true }
                networkAdapters = [ordered]@{
                  type='object'; allowUnknown=$true; children=[ordered]@{
                    OFFICE = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='OFFICE';       required=$true; userEditable=$false }
                        IP   = @{ type='string'; default='192.168.1.21'; required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.0.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='';             required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'}; default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                    MODULUS = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='MODULUS';        required=$true; userEditable=$true }
                        IP   = @{ type='string'; default='192.168.0.121';  required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.255.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='192.168.0.1';    required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'};   default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                  }
                }
              }
            }

            FS = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                hostname = @{ type='string'; default='ModulusFS'; required=$true; userEditable=$true }
                networkAdapters = [ordered]@{
                  type='object'; allowUnknown=$true; children=[ordered]@{
                    OFFICE = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='OFFICE';       required=$true; userEditable=$false }
                        IP   = @{ type='string'; default='192.168.1.22'; required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.0.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='';             required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'}; default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                    FLOOR = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='FLOOR';        required=$true; userEditable=$false }
                        IP   = @{ type='string'; default='10.10.10.1';   required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.0.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='';             required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'}; default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                    MODULUS = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='MODULUS';         required=$true; userEditable=$true }
                        IP   = @{ type='string'; default='192.168.0.122';   required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.255.0';   required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='192.168.0.1';     required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'};    default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                  }
                }
                DHCP = [ordered]@{
                  type='array'
                  items=[ordered]@{
                    type='object'
                    mergeKey='name'
                    children=[ordered]@{
                      name = @{ type='string'; required=$true; userEditable=$false } # identity
                      from = @{ type='string'; required=$true; userEditable=$true  }
                      to   = @{ type='string'; required=$true; userEditable=$true  }
                    }
                  }
                  default=@(
                    @{ name='range1'; from='10.10.10.10'; to='10.10.12.254' }
                    @{ name='range2'; from='10.10.13.1';  to='10.10.13.254' }
                  )
                }
              }
            }

            '1VM' = [ordered]@{
              type='object'; allowUnknown=$false; children=[ordered]@{
                hostname = @{ type='string'; default='Modulus1VM'; required=$true; userEditable=$true }
                networkAdapters = [ordered]@{
                  type='object'; allowUnknown=$true; children=[ordered]@{
                    OFFICE = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='OFFICE';       required=$true; userEditable=$false }
                        IP   = @{ type='string'; default='192.168.1.23'; required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.0.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='';             required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'}; default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                    FLOOR = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='FLOOR';        required=$true; userEditable=$false }
                        IP   = @{ type='string'; default='10.10.10.1';   required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.0.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='';             required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'}; default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                    MODULUS = [ordered]@{
                      type='object'; allowUnknown=$false; children=[ordered]@{
                        name = @{ type='string'; default='MODULUS';        required=$true; userEditable=$true }
                        IP   = @{ type='string'; default='192.168.0.123';  required=$true; userEditable=$true }
                        SNM  = @{ type='string'; default='255.255.255.0';  required=$true; userEditable=$true }
                        DG   = @{ type='string'; default='192.168.0.1';    required=$true; userEditable=$true }
                        DNS  = @{ type='array';  items=@{type='string'};   default=@('','') }
                        VLAN = @{ type='string'; default=$null }
                        DHCP = @{ type='boolean'; default=$false }
                      }
                    }
                  }
                }
                DHCP = [ordered]@{
                  type='array'
                  items=[ordered]@{
                    type='object'
                    mergeKey='name'
                    children=[ordered]@{
                      name = @{ type='string'; required=$true; userEditable=$false }
                      from = @{ type='string'; required=$true; userEditable=$true  }
                      to   = @{ type='string'; required=$true; userEditable=$true  }
                    }
                  }
                  default=@(
                    @{ name='range1'; from='10.10.10.10'; to='10.10.12.254' }
                    @{ name='range2'; from='10.10.13.1';  to='10.10.13.254' }
                  )
                }
              }
            }
          }
        }
		
		directories = [ordered]@{
		  type='object'; allowUnknown=$false; children=[ordered]@{
			workspace  = @{ type='string'; default='I:\modulus-toolkit';  required=$true; userEditable=$true }
			galaxis    = @{ type='string'; default='D:\Galaxis';          required=$true; userEditable=$true }
			onlinedata = @{ type='string'; default='D:\OnlineData';       required=$true; userEditable=$true }
			backup     = @{ type='string'; default='D:\_BACKUP';          required=$true; userEditable=$true }
		  }
		}
	  
	  }
    }
  }
  return $schema
}

function Read-JsonFile {
  [CmdletBinding()] Param(
    [Parameter(Mandatory)] [string] $Path
  )
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if (-not $raw.Trim()) { return $null }
    return $raw | ConvertFrom-Json -Depth 100 -AsHashtable
  } catch {
    throw "Failed to read/parse JSON at '$Path': $($_.Exception.Message)"
  }
}

function Write-JsonFile {
  [CmdletBinding(SupportsShouldProcess)] Param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [object] $Object,
    [switch] $Backup
  )
  $json = $Object | ConvertTo-Json -Depth 100 -Compress:$false
  if ($PSCmdlet.ShouldProcess($Path,'Write JSON')) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    if ($Backup -and (Test-Path -LiteralPath $Path)) {
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      Copy-Item -LiteralPath $Path -Destination "$Path.bak.$stamp" -ErrorAction Stop
    }
    #Set-Content -LiteralPath $Path -Value $json -NoNewline
    Set-Content -LiteralPath $Path -Value $json -NoNewline -Encoding UTF8
  }
}

function Invoke-ConfigReconcile-prev {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
  Param(
    [Parameter(Mandatory)] [string] $Path,
    [switch] $Backup
  )

  $schema = Get-ConfigSchema
  $desiredVersion = [int]$schema.version

  $current = Read-JsonFile -Path $Path
  if (-not $current) { $current = @{} }

  if (-not $current.ContainsKey('__meta')) { $current['__meta'] = @{} }
  $meta = $current['__meta']
  if (-not ($meta -is [hashtable])) { $meta = @{}; $current['__meta'] = $meta }
  $meta['managedBy']         = 'modulus-toolkit'
  $meta['lastReconciledUtc'] = (Get-Date).ToUniversalTime().ToString('o')
  $meta['version']           = $meta['version'] ?? 0

  $migrations = @()
  if ([int]$meta['version'] -lt $desiredVersion) {
    $migrations = Invoke-ConfigMigration -From ([int]$meta['version']) -To $desiredVersion -Config ($current)
    $meta['version'] = $desiredVersion
  }

  $changes = [System.Collections.ArrayList]::new()
  $result  = Merge-Schema -Schema $schema.root -Current $current -Path '$'
  $newRoot = $result.Object
  foreach ($c in @($result.Changes)) { [void]$changes.Add($c) }

  $newRoot['__meta'] = $meta

  $writeNeeded = ($changes.Count -gt 0) -or ($migrations.Count -gt 0)
  if ($writeNeeded) {
    if ($PSCmdlet.ShouldProcess($Path,'Write reconciled config')) {
      Write-JsonFile -Path $Path -Object $newRoot -Backup:$Backup
    }
  }

  [pscustomobject]@{
    Path       = $Path
    Changed    = $writeNeeded
    Changes    = @($changes)
    Migrations = $migrations
    Result     = $newRoot
  }
}

function Invoke-ConfigReconcile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    Param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter()]          [object] $CurrentObject, # <--- NEW: Accepts an in-memory object (like your migrated $scope)
        [switch] $Backup
    )

    $schema = Get-ConfigSchema
    $desiredVersion = [int]$schema.version

    # -------------------------------------------------------------
    # CORE FIX: Load object from parameter OR disk
    # -------------------------------------------------------------
    if ($CurrentObject) {
        $current = $CurrentObject
        Write-Log "Starting reconciliation from in-memory object." VERBOSE
    } else {
        $current = Read-JsonFile -Path $Path
        Write-Log "Starting reconciliation from file: '$Path'." VERBOSE
    }
    # -------------------------------------------------------------

    if (-not $current) { $current = @{} }

    if (-not $current.ContainsKey('__meta')) { $current['__meta'] = @{} }
    $meta = $current['__meta']
    if (-not ($meta -is [hashtable])) { $meta = @{}; $current['__meta'] = $meta }
    $meta['managedBy']         = 'modulus-toolkit'
    $meta['lastReconciledUtc'] = (Get-Date).ToUniversalTime().ToString('o')
    $meta['version']           = $meta['version'] ?? 0

    $migrations = @()
    if ([int]$meta['version'] -lt $desiredVersion) {
    $migrations = Invoke-ConfigMigration -From ([int]$meta['version']) -To $desiredVersion -Config ($current)
    $meta['version'] = $desiredVersion
    }

    $changes = [System.Collections.ArrayList]::new()
    $result  = Merge-Schema -Schema $schema.root -Current $current -Path '$'
    $newRoot = $result.Object
    foreach ($c in @($result.Changes)) { [void]$changes.Add($c) }

    $newRoot['__meta'] = $meta

    # If reconciliation found changes OR migrations ran, a write is needed.
    $writeNeeded = ($changes.Count -gt 0) -or ($migrations.Count -gt 0)

    # -------------------------------------------------------------
    # The write is now CONDITIONAL based on $writeNeeded
    # -------------------------------------------------------------
    if ($writeNeeded) {
    if ($PSCmdlet.ShouldProcess($Path,'Write reconciled config')) {
        Write-JsonFile -Path $Path -Object $newRoot -Backup:$Backup
    }
    }
    # -------------------------------------------------------------

    # The function returns a PSCustomObject that explicitly includes the Changed status
    [pscustomobject]@{
    Path       = $Path
    Changed    = $writeNeeded # <--- EXPLICIT RETURN STATUS
    Changes    = @($changes)
    Migrations = $migrations
    Result     = $newRoot
    }
}

function Merge-Schema {
  [CmdletBinding()] Param(
    [Parameter(Mandatory)] [hashtable] $Schema,
    [Parameter()]           [object]    $Current,
    [Parameter(Mandatory)]  [string]    $Path
  )
  $changes = [System.Collections.ArrayList]::new()
  $type = $Schema.type

  switch ($type) {
    'object' {
      $allowUnknown = $Schema.allowUnknown
      $children     = $Schema.children
      if (-not ($Current -is [hashtable])) {
        $Current = @{}
        [void]$changes.Add(@{Path=$Path;Action='replace';Detail='init object'})
      }

      $out = [ordered]@{}

      foreach ($k in $children.Keys) {
        $childSchema = $children[$k]
        $childPath   = "$Path.$k"
        $val = if ($Current.ContainsKey($k)) { $Current[$k] } else { $null }
        $r = Merge-Schema -Schema $childSchema -Current $val -Path $childPath
        $out[$k] = $r.Object
        foreach ($c in @($r.Changes)) { [void]$changes.Add($c) }
      }

      if ($allowUnknown) {
        foreach ($k in $Current.Keys) {
          if (-not $children.Contains($k)) {  # OrderedDictionary => .Contains()
            $out[$k] = $Current[$k]
          }
        }
      } else {
        foreach ($k in $Current.Keys) {
          if (-not $children.Contains($k)) {  # OrderedDictionary => .Contains()
            [void]$changes.Add(@{Path="$Path.$k";Action='prune';Detail='removed unknown key'})
          }
        }
      }

      return @{ Object = $out; Changes = @($changes) }
    }

    'array' {
      if ($null -eq $Current -or -not ($Current -is [System.Collections.IEnumerable])) {
        $Current = @()
        [void]$changes.Add(@{Path=$Path;Action='replace';Detail='init array'})
      }
      $itemsSchema  = $Schema.items
      $mergeKey     = $itemsSchema.mergeKey
      $currItems    = @($Current)
      $targetItems  = @()
      $defaultItems = @($Schema.default) | ForEach-Object { $_ }

      if ($mergeKey) {
        $index = @{}
        foreach ($it in $currItems) {
          if ($it -is [hashtable] -and $it.ContainsKey($mergeKey)) { $index[$it[$mergeKey]] = $it }
        }

        foreach ($def in $defaultItems) {
          $key = $def[$mergeKey]
          # If missing, reconcile using the default object (prevents required-key errors)
          $cur = if ($index.ContainsKey($key)) { $index[$key] } else { $def }
          $r   = Merge-Schema -Schema $itemsSchema -Current $cur -Path "$Path[?@$mergeKey=='$key']"
          $targetItems += $r.Object
          foreach ($c in @($r.Changes)) { [void]$changes.Add($c) }
          if ($index.ContainsKey($key)) { $null = $index.Remove($key) }
        }

        foreach ($k in $index.Keys) {
          $cur = $index[$k]
          $r   = Merge-Schema -Schema $itemsSchema -Current $cur -Path "$Path[?@$mergeKey=='$k']"
          $targetItems += $r.Object
          foreach ($c in @($r.Changes)) { [void]$changes.Add($c) }
        }
      } else {
        if ($defaultItems.Count -gt 0 -and $currItems.Count -eq 0) {
          foreach ($def in $defaultItems) { $targetItems += $def }
          [void]$changes.Add(@{Path=$Path;Action='setDefault';Detail='array default applied'})
        } else {
          $targetItems = $currItems
        }
      }

      return @{ Object = $targetItems; Changes = @($changes) }
    }

    default { # primitives
      $required     = $Schema.required
      $userEditable = if ($Schema.ContainsKey('userEditable')) { [bool]$Schema.userEditable } else { $true }
      $hasCurrent   = $null -ne $Current

      if (-not $hasCurrent) {
        if ($Schema.ContainsKey('default')) {
          return @{ Object=$Schema.default; Changes=@(@{Path=$Path;Action='setDefault';Detail='missing -> default'}) }
        }
        if ($required) { throw "Required key missing at $Path and no default provided" }
        return @{ Object=$null; Changes=@() }
      }

      if (-not $userEditable -and $Schema.ContainsKey('default')) {
        if ($Current -ne $Schema.default) {
          return @{ Object=$Schema.default; Changes=@(@{Path=$Path;Action='enforce';Detail='userEditable:$false -> default'}) }
        }
      }

      return @{ Object=$Current; Changes=@() }
    }
  }
}

function Invoke-ConfigMigration{
  [CmdletBinding()] Param(
    [Parameter(Mandatory)] [int] $From,
    [Parameter(Mandatory)] [int] $To,
    [Parameter(Mandatory)] [hashtable] $Config
  )
  $changes = [System.Collections.Generic.List[hashtable]]::new()

  for ($v=$From+1; $v -le $To; $v++) {
    switch ($v) {
      1 { # first schema version, no-op for fresh installs
        $changes.Add(@{Version=$v; Action='noop'; Detail='initial schema'})
      }
      default {
        $changes.Add(@{Version=$v; Action='noop'; Detail='no migrations defined'})
      }
    }
  }
  return $changes
}

function Compare-ConfigToSchema {
  <# Returns a summary of what would change without writing. #>
  [CmdletBinding()] Param(
    [Parameter(Mandatory)] [string] $Path
  )
  $tmp = New-TemporaryFile
  try {
    $result = Invoke-ConfigReconcile -Path $Path -WhatIf
    return $result
  } finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
}

function Initialize-Config-prev {
  [CmdletBinding()] Param(
    [switch] $Force
  )

  $Path = Join-Path (Get-ModulePath) "config\scope.json"
  if ((Test-Path -LiteralPath $Path) -and -not $Force) {
    throw "Config already exists at '$Path'. Use -Force to overwrite."
  }
  $schema = Get-ConfigSchema
  $obj = (Invoke-ConfigReconcile -Path $Path -WhatIf:$false).Result
  Write-JsonFile -Path $Path -Object $obj -Backup:$false
}

function Initialize-Config {
    [CmdletBinding()] Param(
    [switch] $Force
    )

    $Path = Join-Path (Get-ModulePath) "config\scope.json"

    # Ensure the file exists before reconciliation runs
    if (-not (Test-Path -LiteralPath $Path) -or $Force) {
        # This ensures that even if -Force is used, the system starts with defaults.
        # The first time the file is created, reconciliation will set $writeNeeded=$true.
        $null = Invoke-ConfigReconcile -Path $Path -WhatIf:$false
    }

    # This second call runs on every startup to check for schema drift.
    # If a new column is added, $writeNeeded will be $true, and the file will be written.
    $result = Invoke-ConfigReconcile -Path $Path -WhatIf:$false

    # REMOVE THE UNCONDITIONAL OVERWRITE BLOCK:
    # $obj = $result.Result
    # Write-JsonFile -Path $Path -Object $obj -Backup:$false 
    # By removing this, you prevent the manual overwrite, 
    # allowing the internal conditional write logic to handle the job.

    return $result.Result
}

function Convert-LegacyConfig-prev {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Optional: if empty or missing on disk, we'll skip migration gracefully.
        [Parameter()]
        [string]$LegacyPath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ScopePath,

        [switch]$RemoveLegacy
    )

    # --- Helpers -------------------------------------------------------------
    function Read-Json([string]$path) {
        Write-Log "Reading JSON file: $path" VERBOSE
        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
    }

    function Save-Json([object]$obj, [string]$path) {
        Write-Log "Saving JSON to: $path" VERBOSE
        $json = $obj | ConvertTo-Json -Depth 100
        Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    }

    function Set-IfPresent {
        param(
            [Parameter(Mandatory)]$TargetRef,   # [ref]
            $Value,
            [string]$PathDescription
        )
        $isConfigured = $false
        if ($null -ne $Value) {
            if ($Value -is [string]) { $isConfigured = ($Value.Trim() -ne "") }
            elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
                $isConfigured = ($Value.Count -gt 0)
            } else {
                $isConfigured = $true
            }
        }
        if ($isConfigured) {
            Write-Log "Migrating value for $PathDescription → '$Value'" VERBOSE
            $TargetRef.Value = $Value
        } else {
            Write-Log "Skipping empty or null value for $PathDescription" VERBOSE
        }
    }

    function Resolve-ObjectNodePath([object]$base, [string[]]$path) {
        $node = $base
        foreach ($p in $path) {
            if ($null -eq $node.$p) {
                Write-Log "Creating missing object node: $($path -join '.')" VERBOSE
                $node | Add-Member -NotePropertyName $p -NotePropertyValue ([ordered]@{})
            }
            $node = $node.$p
        }
        return $node
    }

    function Convert-NicToMap($legacyNics) {
        if (-not $legacyNics) { return $null }
        Write-Log "Converting NIC array to map format" VERBOSE
        $map = [ordered]@{}
        foreach ($nic in $legacyNics) {
            $k = $nic.AdapterName
            if ([string]::IsNullOrWhiteSpace($k)) { continue }
            Write-Log " → NIC '$k' with IP $($nic.IPAddress)" VERBOSE
            $map[$k] = [ordered]@{
                name = $nic.AdapterName
                IP   = $nic.IPAddress
                SNM  = $nic.SubnetMask
                DG   = $nic.DefaultGateway
                DNS  = @($nic.DNS)
                VLAN = $nic.VLAN
                DHCP = [bool]$nic.DHCPEnabled
            }
        }
        return $map
    }

    function Convert-DhcpToArray($legacyDhcpObj) {
        if (-not $legacyDhcpObj -or $legacyDhcpObj.PSObject.Properties.Count -eq 0) { return $null }
        Write-Log "Converting DHCP object to array format" VERBOSE
        $arr = @()
        foreach ($p in $legacyDhcpObj.PSObject.Properties) {
            $name = $p.Name
            $val  = $p.Value
            if ($val -and $val.from -and $val.to) {
                Write-Log " → DHCP '$name' from $($val.from) to $($val.to)" VERBOSE
                $arr += [ordered]@{ name = $name; from = $val.from; to = $val.to }
            }
        }
        return $arr
    }

    # --- Early-out if legacy file missing -----------------------------------
    if (-not $LegacyPath -or -not (Test-Path -LiteralPath $LegacyPath -PathType Leaf)) {
        $shown = if ($LegacyPath) { $LegacyPath } else { "<not provided>" }
        #Write-Log "Legacy config not found ($shown). No migration needed; skipping." VERBOSE
        if ($RemoveLegacy) {
            #Write-Log "-RemoveLegacy was specified but legacy file is absent: nothing to delete." VERBOSE
        }
        return
    }

    # --- Load files ----------------------------------------------------------
    Write-Log "Starting migration from legacy → scope" VERBOSE
    $legacy = Read-Json $LegacyPath
    $scope  = Read-Json $ScopePath

    # Guard: legacy casino ID
    $legacyCasinoId = $legacy.general_settings.specifics.casinoID
    Write-Log "Detected legacy casinoID: $legacyCasinoId" VERBOSE

    $IsTemplate = ($legacyCasinoId -eq 999)
    if ($IsTemplate) {
        Write-Log "Legacy casinoID is 999 (template). No data migration will be performed." VERBOSE

        if ($RemoveLegacy) {
            if ($PSCmdlet.ShouldProcess($LegacyPath, "Delete legacy template config")) {
                Write-Log "Removing legacy template file: $LegacyPath" VERBOSE
                Remove-Item -LiteralPath $LegacyPath -Force
                Write-Log "Legacy template file removed." VERBOSE
            }
        } else {
            Write-Log "Template detected and -RemoveLegacy not specified: leaving legacy file in place." VERBOSE
        }
        return
    }

    # --- Backup scope.json ---------------------------------------------------
    $backupPath = "{0}.bak.{1:yyyyMMdd-HHmmss}.json" -f $ScopePath, (Get-Date)
    if ($PSCmdlet.ShouldProcess($ScopePath, "Backup to $backupPath")) {
        Write-Log "Creating backup of scope.json → $backupPath" VERBOSE
        Copy-Item -LiteralPath $ScopePath -Destination $backupPath -Force
    }

    # --- General -------------------------------------------------------------
    $general = Resolve-ObjectNodePath $scope @('general')
    Set-IfPresent ([ref]$general.system)   $legacy.general_settings.system   'general.system'
    Set-IfPresent ([ref]$general.timezone) $legacy.general_settings.timezone 'general.timezone'

    # --- Customer ------------------------------------------------------------
    $customer = Resolve-ObjectNodePath $scope @('customer')
    Set-IfPresent ([ref]$customer.code) $legacy.general_settings.specifics.societ        'customer.code'
    #Set-IfPresent ([ref]$customer.name) $legacy.general_settings.specifics.society_name  'customer.name'

    # --- Casino --------------------------------------------------------------
    $casino = Resolve-ObjectNodePath $scope @('casino')
    Set-IfPresent ([ref]$casino.ID)       $legacy.general_settings.specifics.casinoID 'casino.ID'
    Set-IfPresent ([ref]$casino.code)     $legacy.general_settings.specifics.etabli   'casino.code'
    Set-IfPresent ([ref]$casino.longname) $legacy.general_settings.longname           'casino.longname'
    Set-IfPresent ([ref]$casino.name)     $legacy.general_settings.shortname          'casino.name'

    $modules = Resolve-ObjectNodePath $scope @('casino','modules')
    Set-IfPresent ([ref]$modules.CAWA)    $legacy.general_settings.specifics.CAWA    'casino.modules.CAWA'
    Set-IfPresent ([ref]$modules.Jackpot) $legacy.general_settings.specifics.Jackpot 'casino.modules.Jackpot'
    Set-IfPresent ([ref]$modules.R4R)     $legacy.general_settings.specifics.R4R     'casino.modules.R4R'
    Write-Log "Leaving Replication/MyBar as-is (no legacy source)" VERBOSE

    # --- Databases -----------------------------------------------------------
    $dbRoot = Resolve-ObjectNodePath $scope @('databases')
    $glx = Resolve-ObjectNodePath $scope @('databases','GLX')
    $jkp = Resolve-ObjectNodePath $scope @('databases','JKP')
    Set-IfPresent ([ref]$glx.TNS) $legacy.general_settings.databases.GLX_DB 'databases.GLX.TNS'
    Set-IfPresent ([ref]$jkp.TNS) $legacy.general_settings.databases.JKP_DB 'databases.JKP.TNS'

    $dbUsers = Resolve-ObjectNodePath $scope @('databases','users')
    Set-IfPresent ([ref]$dbUsers.as_security) $legacy.general_settings.database_users.security 'databases.users.as_security'
    Set-IfPresent ([ref]$dbUsers.specific)    $legacy.general_settings.database_users.specific 'databases.users.specific'
    Write-Log "Skipping dbx and credentials (not part of new schema)" VERBOSE

    # --- Servers -------------------------------------------------------------
    $srvRoot = Resolve-ObjectNodePath $scope @('servers')
    foreach ($legacySrv in @($legacy.servers)) {
        $name = $legacySrv.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        Write-Log "Processing server '$name'" VERBOSE
        $srvNode = Resolve-ObjectNodePath $scope @('servers', $name)
        Set-IfPresent ([ref]$srvNode.hostname) $legacySrv.hostname "servers.$name.hostname"

        # NICs
        $nicMap = Convert-NicToMap $legacySrv.networkAdapters
        if ($nicMap) {
            Write-Log "Applying $($nicMap.Keys.Count) NICs to servers.$name.networkAdapters" VERBOSE
            $srvNode.networkAdapters = $nicMap
        }

        # DHCP ranges
        if ($legacySrv.PSObject.Properties.Name -contains 'DHCPranges') {
            $dhcpArray = Convert-DhcpToArray $legacySrv.DHCPranges
            if ($dhcpArray) {
                Write-Log "Applying DHCP ranges ($($dhcpArray.Count)) to servers.$name.DHCP" VERBOSE
                $srvNode.DHCP = $dhcpArray
            }
        }
    }

    # --- __meta --------------------------------------------------------------
    $meta = Resolve-ObjectNodePath $scope @('__meta')
    if (-not $meta.managedBy) { $meta.managedBy = 'modulus-toolkit' }
    $meta.lastReconciledUtc = [DateTime]::UtcNow.ToString("o")
    if (-not $meta.version) { $meta.version = 1 }
    Write-Log "Updated __meta section (lastReconciledUtc/version)" VERBOSE

    # --- Write back ----------------------------------------------------------
    if ($PSCmdlet.ShouldProcess($ScopePath, "Write merged configuration")) {
        Write-Log "Writing merged data back to scope.json" VERBOSE
        Save-Json $scope $ScopePath
        
        #workaround for testing
        #$tmpPath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\scope.json.migrated"
        #Save-Json $scope $tmpPath
    }

    # --- Remove legacy file if requested ------------------------------------
    if ($RemoveLegacy) {
        if ($PSCmdlet.ShouldProcess($LegacyPath, "Delete legacy config")) {
            Write-Log "Removing legacy file: $LegacyPath" VERBOSE
            Remove-Item -LiteralPath $LegacyPath -Force
        }
    }

    Write-Log "Migration completed successfully." VERBOSE
}

function Convert-LegacyConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Optional: if empty or missing on disk, we'll skip migration gracefully.
        [Parameter()]
        [string]$LegacyPath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ScopePath,

        [switch]$RemoveLegacy
    )

    # --- Helpers -------------------------------------------------------------
    function Read-Json([string]$path) {
        Write-Log "Reading JSON file: $path" VERBOSE
        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
    }

    function Save-Json([object]$obj, [string]$path) {
        Write-Log "Saving JSON to: $path" VERBOSE
        $json = $obj | ConvertTo-Json -Depth 100
        Set-Content -LiteralPath $path -Value $json -Encoding UTF8
    }

    function Set-IfPresent {
        param(
            [Parameter(Mandatory)]$TargetRef,   # [ref]
            $Value,
            [string]$PathDescription
        )
        $isConfigured = $false
        if ($null -ne $Value) {
            if ($Value -is [string]) { $isConfigured = ($Value.Trim() -ne "") }
            elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
                $isConfigured = ($Value.Count -gt 0)
            } else {
                $isConfigured = $true
            }
        }
        if ($isConfigured) {
            Write-Log "Migrating value for $PathDescription → '$Value'" VERBOSE
            $TargetRef.Value = $Value
        } else {
            Write-Log "Skipping empty or null value for $PathDescription" VERBOSE
        }
    }

    function Resolve-ObjectNodePath([object]$base, [string[]]$path) {
        $node = $base
        foreach ($p in $path) {
            if ($null -eq $node.$p) {
                Write-Log "Creating missing object node: $($path -join '.')" VERBOSE
                $node | Add-Member -NotePropertyName $p -NotePropertyValue ([ordered]@{})
            }
            $node = $node.$p
        }
        return $node
    }

    function Convert-NicToMap($legacyNics) {
        if (-not $legacyNics) { return $null }
        Write-Log "Converting NIC array to map format" VERBOSE
        $map = [ordered]@{}
        foreach ($nic in $legacyNics) {
            $k = $nic.AdapterName
            if ([string]::IsNullOrWhiteSpace($k)) { continue }
            Write-Log " → NIC '$k' with IP $($nic.IPAddress)" VERBOSE
            $map[$k] = [ordered]@{
                name = $nic.AdapterName
                IP   = $nic.IPAddress
                SNM  = $nic.SubnetMask
                DG   = $nic.DefaultGateway
                DNS  = @($nic.DNS)
                VLAN = $nic.VLAN
                DHCP = [bool]$nic.DHCPEnabled
            }
        }
        return $map
    }

    function Convert-DhcpToArray($legacyDhcpObj) {
        if (-not $legacyDhcpObj -or $legacyDhcpObj.PSObject.Properties.Count -eq 0) { return $null }
        Write-Log "Converting DHCP object to array format" VERBOSE
        $arr = @()
        foreach ($p in $legacyDhcpObj.PSObject.Properties) {
            $name = $p.Name
            $val  = $p.Value
            if ($val -and $val.from -and $val.to) {
                Write-Log " → DHCP '$name' from $($val.from) to $($val.to)" VERBOSE
                $arr += [ordered]@{ name = $name; from = $val.from; to = $val.to }
            }
        }
        return $arr
    }

    # --- Early-out if legacy file missing -----------------------------------
    if (-not $LegacyPath -or -not (Test-Path -LiteralPath $LegacyPath -PathType Leaf)) {
        $shown = if ($LegacyPath) { $LegacyPath } else { "<not provided>" }
        #Write-Log "Legacy config not found ($shown). No migration needed; skipping." VERBOSE
        if ($RemoveLegacy) {
            #Write-Log "-RemoveLegacy was specified but legacy file is absent: nothing to delete." VERBOSE
        }
        return
    }

    # --- Load files ----------------------------------------------------------
    Write-Log "Starting migration from legacy → scope" VERBOSE
    $legacy = Read-Json $LegacyPath
    $scope  = Read-Json $ScopePath

    # Guard: legacy casino ID
    $legacyCasinoId = $legacy.general_settings.specifics.casinoID
    Write-Log "Detected legacy casinoID: $legacyCasinoId" VERBOSE

    $IsTemplate = ($legacyCasinoId -eq 999)
    if ($IsTemplate) {
        Write-Log "Legacy casinoID is 999 (template). No data migration will be performed." VERBOSE

        if ($RemoveLegacy) {
            if ($PSCmdlet.ShouldProcess($LegacyPath, "Delete legacy template config")) {
                Write-Log "Removing legacy template file: $LegacyPath" VERBOSE
                Remove-Item -LiteralPath $LegacyPath -Force
                Write-Log "Legacy template file removed." VERBOSE
            }
        } else {
            Write-Log "Template detected and -RemoveLegacy not specified: leaving legacy file in place." VERBOSE
        }
        return
    }

    # --- Backup scope.json ---------------------------------------------------
    $backupPath = "{0}.bak.{1:yyyyMMdd-HHmmss}.json" -f $ScopePath, (Get-Date)
    if ($PSCmdlet.ShouldProcess($ScopePath, "Backup to $backupPath")) {
        Write-Log "Creating backup of scope.json → $backupPath" VERBOSE
        Copy-Item -LiteralPath $ScopePath -Destination $backupPath -Force
    }

    # --- General -------------------------------------------------------------
    $general = Resolve-ObjectNodePath $scope @('general')
    Set-IfPresent ([ref]$general.system)   $legacy.general_settings.system   'general.system'
    Set-IfPresent ([ref]$general.timezone) $legacy.general_settings.timezone 'general.timezone'

    # --- Customer ------------------------------------------------------------
    $customer = Resolve-ObjectNodePath $scope @('customer')
    Set-IfPresent ([ref]$customer.code) $legacy.general_settings.specifics.societ        'customer.code'
    #Set-IfPresent ([ref]$customer.name) $legacy.general_settings.specifics.society_name  'customer.name'

    # --- Casino --------------------------------------------------------------
    $casino = Resolve-ObjectNodePath $scope @('casino')
    Set-IfPresent ([ref]$casino.ID)       $legacy.general_settings.specifics.casinoID 'casino.ID'
    Set-IfPresent ([ref]$casino.code)     $legacy.general_settings.specifics.etabli   'casino.code'
    Set-IfPresent ([ref]$casino.longname) $legacy.general_settings.longname           'casino.longname'
    Set-IfPresent ([ref]$casino.name)     $legacy.general_settings.shortname          'casino.name'

    $modules = Resolve-ObjectNodePath $scope @('casino','modules')
    Set-IfPresent ([ref]$modules.CAWA)    $legacy.general_settings.specifics.CAWA    'casino.modules.CAWA'
    Set-IfPresent ([ref]$modules.Jackpot) $legacy.general_settings.specifics.Jackpot 'casino.modules.Jackpot'
    Set-IfPresent ([ref]$modules.R4R)     $legacy.general_settings.specifics.R4R     'casino.modules.R4R'
    Write-Log "Leaving Replication/MyBar as-is (no legacy source)" VERBOSE

    # --- Databases -----------------------------------------------------------
    $dbRoot = Resolve-ObjectNodePath $scope @('databases')
    $glx = Resolve-ObjectNodePath $scope @('databases','GLX')
    $jkp = Resolve-ObjectNodePath $scope @('databases','JKP')
    Set-IfPresent ([ref]$glx.TNS) $legacy.general_settings.databases.GLX_DB 'databases.GLX.TNS'
    Set-IfPresent ([ref]$jkp.TNS) $legacy.general_settings.databases.JKP_DB 'databases.JKP.TNS'

    $dbUsers = Resolve-ObjectNodePath $scope @('databases','users')
    Set-IfPresent ([ref]$dbUsers.as_security) $legacy.general_settings.database_users.security 'databases.users.as_security'
    Set-IfPresent ([ref]$dbUsers.specific)    $legacy.general_settings.database_users.specific 'databases.users.specific'
    Write-Log "Skipping dbx and credentials (not part of new schema)" VERBOSE

    # --- Servers -------------------------------------------------------------
    $srvRoot = Resolve-ObjectNodePath $scope @('servers')
    foreach ($legacySrv in @($legacy.servers)) {
        $name = $legacySrv.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        Write-Log "Processing server '$name'" VERBOSE
        $srvNode = Resolve-ObjectNodePath $scope @('servers', $name)
        Set-IfPresent ([ref]$srvNode.hostname) $legacySrv.hostname "servers.$name.hostname"

        # NICs
        $nicMap = Convert-NicToMap $legacySrv.networkAdapters
        if ($nicMap) {
            Write-Log "Applying $($nicMap.Keys.Count) NICs to servers.$name.networkAdapters" VERBOSE
            $srvNode.networkAdapters = $nicMap
        }

        # DHCP ranges
        if ($legacySrv.PSObject.Properties.Name -contains 'DHCPranges') {
            $dhcpArray = Convert-DhcpToArray $legacySrv.DHCPranges
            if ($dhcpArray) {
                Write-Log "Applying DHCP ranges ($($dhcpArray.Count)) to servers.$name.DHCP" VERBOSE
                $srvNode.DHCP = $dhcpArray
            }
        }
    }

    # --- __meta --------------------------------------------------------------
    $meta = Resolve-ObjectNodePath $scope @('__meta')
    if (-not $meta.managedBy) { $meta.managedBy = 'modulus-toolkit' }
    
    # ⚠️ FIX: Comment out manual meta updates to allow Invoke-ConfigReconcile to handle the authoritative stamp.
    # $meta.lastReconciledUtc = [DateTime]::UtcNow.ToString("o")
    # if (-not $meta.version) { $meta.version = 1 }
    
    Write-Log "Updated __meta section (managedBy only). Preparing for reconciled write." VERBOSE

    # --- Write back (THE FIX: Call Safe Reconciliation) ----------------------
    if ($PSCmdlet.ShouldProcess($ScopePath, "Write merged configuration")) {
        Write-Log "Applying final schema reconciliation and writing migrated config" VERBOSE
        
        # 🛑 CRITICAL FIX: Convert the PSCustomObject to a deep Hashtable via JSON serialization.
        # This prevents the 'A hash table can only be added...' error.
        $scopeAsHashtable = $scope | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
        
        # 1. Call Invoke-ConfigReconcile with the new Hashtable object.
        $reconcileResult = Invoke-ConfigReconcile -Path $ScopePath -CurrentObject $scopeAsHashtable -Backup:$false
        if (-not $reconcileResult.Changed) {
            Write-Log "Reconciliation completed but found no structural changes to write." VERBOSE
        }
        
        # ---------------------------------------------------------------------
        
        # ⚠️ NOTE: The original lines below are now redundant/obsolete but kept 
        # as per the instruction to avoid removing lines. They will not execute 
        # the Save-Json command. The actual write happens inside Invoke-ConfigReconcile.
        
        # Write-Log "Writing merged data back to scope.json" VERBOSE
        # Save-Json $scope $ScopePath
        
        #workaround for testing
        #$tmpPath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\scope.json.migrated"
        #Save-Json $scope $tmpPath
    }

    # --- Remove legacy file if requested ------------------------------------
    if ($RemoveLegacy) {
        if ($PSCmdlet.ShouldProcess($LegacyPath, "Delete legacy config")) {
            Write-Log "Removing legacy file: $LegacyPath" VERBOSE
            Remove-Item -LiteralPath $LegacyPath -Force
        }
    }

    Write-Log "Migration completed successfully." VERBOSE
}
#endregion

#region --- scope.json config helpers
function Split-ConfigKey {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Key)
    $segments = $Key -split '\.'
    $steps = foreach ($seg in $segments) {
        if ($seg -notmatch '^(?<name>[^[]+)(\[(?<selector>.+?)\])?$') {
            throw "Invalid path segment: '$seg' in '$Key'"
        }
        $name = $Matches.name
        $selector = $Matches.selector
        $selObj = $null
        if ($selector) {
            if ($selector -match '^\d+$') {
                $selObj = [int]$selector
            } elseif ($selector -match '^(?<k>[^=]+)=(?<v>.+)$') {
                $selObj = [ordered]@{ Key = $Matches.k; Value = $Matches.v }
            } else {
                throw "Unsupported selector syntax: [$selector]"
            }
        }
        [ordered]@{ Name = $name; Selector = $selObj }
    }
    ,$steps
}
function Resolve-ConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Root,
        [Parameter(Mandatory)][string]$Key
    )

    $steps = Split-ConfigKey $Key
    $current = $Root
    $parent  = $null
    $lastKey = $null

    for ($i=0; $i -lt $steps.Count; $i++) {
        $s = $steps[$i]

        if ($current -isnot [hashtable]) {
            if ($current -is [System.Collections.IList]) {
                throw "Expected object but found array while resolving '$($s.Name)'. Add a selector like [0] or [name=...]."
            }
            throw "Cannot traverse non-container at '$($s.Name)'."
        }

        if (-not $current.ContainsKey($s.Name)) {
            return @{ Parent=$current; Key=$s.Name; Value=$null; Remaining=$steps[$i..($steps.Count-1)] }
        }

        $node = $current[$s.Name]

        if ($null -ne $s.Selector) {
            if ($node -isnot [System.Collections.IList]) {
                return @{ Parent=$current; Key=$s.Name; Value=$null; Remaining=$steps[$i..($steps.Count-1)] }
            }

            if ($s.Selector -is [int]) {
                $idx = $s.Selector
                if ($idx -lt 0 -or $idx -ge $node.Count) {
                    return @{ Parent=$node; Key=$idx; Value=$null; Remaining=$steps[$i..($steps.Count-1)] }
                }
                $parent=$node; $lastKey=$idx; $current=$node[$idx]
            } else {
                $match = $node | Where-Object { $_[$s.Selector.Key] -eq $s.Selector.Value } | Select-Object -First 1
                if (-not $match) {
                    return @{ Parent=$node; Key=[ordered]@{type='selector';Selector=$s.Selector}; Value=$null; Remaining=$steps[$i..($steps.Count-1)] }
                }
                $parent=$node; $lastKey=$node.IndexOf($match); $current=$match
            }
        } else {
            $parent=$current; $lastKey=$s.Name; $current=$node
        }
    }

    @{ Parent=$parent; Key=$lastKey; Value=$current; Remaining=@() }
}

function Set-ConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Root,
        [Parameter(Mandatory)][string]$Key
    )

    $steps  = Split-ConfigKey -Key $Key
    $cursor = $Root

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $s = $steps[$i]

        if (-not $cursor.ContainsKey($s.Name)) {
            if ($null -ne $s.Selector) {
                $cursor[$s.Name] = New-Object System.Collections.ArrayList
            } else {
                $cursor[$s.Name] = @{}
            }
        }

        $node = $cursor[$s.Name]

        if ($null -ne $s.Selector) {
            # Ensure we have an ArrayList to allow Add/insert operations
            if ($node -isnot [System.Collections.IList]) {
                $cursor[$s.Name] = New-Object System.Collections.ArrayList
                $node = $cursor[$s.Name]
            } elseif ($node.GetType().Name -ne 'ArrayList') {
                $alist = New-Object System.Collections.ArrayList
                [void]$alist.AddRange(@($node))  # copy fixed-size object[] into ArrayList
                $cursor[$s.Name] = $alist
                $node = $alist
            }

            if ($s.Selector -is [int]) {
                $idx = $s.Selector
                while ($node.Count -le $idx) { [void]$node.Add(@{}) }
                $cursor = $node[$idx]
            } else {
                $k = $s.Selector.Key
                $v = $s.Selector.Value
                $match = $null
                foreach ($el in $node) {
                    if ($el[$k] -eq $v) { $match = $el; break }
                }
                if ($null -eq $match) {
                    $match = @{}
                    $match[$k] = $v
                    [void]$node.Add($match)
                }
                $cursor = $match
            }
        } else {
            if ($i -lt $steps.Count - 1) {
                if ($node -isnot [hashtable]) {
                    $cursor[$s.Name] = @{}
                    $node = $cursor[$s.Name]
                }
                $cursor = $node
            }
        }
    }

    # ----- Return parent container and final key ---------------------------
    $last = $steps[-1]

    if ($null -ne $last.Selector) {
        # Build parent path (all but last step)
        $parts = @()
        for ($j = 0; $j -lt $steps.Count - 1; $j++) {
            $p = $steps[$j]
            $seg = $p.Name
            if ($null -ne $p.Selector) {
                if ($p.Selector -is [int]) {
                    $seg = "$seg[$($p.Selector)]"
                } else {
                    $seg = "$seg[$($p.Selector.Key)=$($p.Selector.Value)]"
                }
            }
            $parts += $seg
        }
        $parentPath = ($parts -join '.')
        $parent = if ($parts.Count -gt 0) {
            (Resolve-ConfigPath -Root $Root -Key $parentPath).Value
        } else {
            $Root
        }

        # Ensure parent is an ArrayList here as well (defensive)
        if ($parent -is [System.Array]) {
            $alist = New-Object System.Collections.ArrayList
            [void]$alist.AddRange(@($parent))
            $parent = $alist
        }

        if ($last.Selector -is [int]) {
            return @{ Parent = $parent; Key = $last.Selector }
        } else {
            $idx = 0
            foreach ($el in $parent) {
                if ($el[$last.Selector.Key] -eq $last.Selector.Value) {
                    return @{ Parent = $parent; Key = $idx }
                }
                $idx++
            }
            throw "Internal: selector element not found after creation."
        }
    } else {
        if ($steps.Count -gt 1) {
            $parts = @()
            for ($j = 0; $j -lt $steps.Count - 1; $j++) {
                $p = $steps[$j]
                $seg = $p.Name
                if ($null -ne $p.Selector) {
                    if ($p.Selector -is [int]) {
                        $seg = "$seg[$($p.Selector)]"
                    } else {
                        $seg = "$seg[$($p.Selector.Key)=$($p.Selector.Value)]"
                    }
                }
                $parts += $seg
            }
            $parentPath = ($parts -join '.')
            $parent = (Resolve-ConfigPath -Root $Root -Key $parentPath).Value
        } else {
            $parent = $Root
        }
        return @{ Parent = $parent; Key = $last.Name }
    }
}

function Test-ConfigValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Validator, [Parameter()][object]$Value)
    switch ($Validator.ToLowerInvariant()) {
        'ipaddress' { return [bool]([System.Net.IPAddress]::TryParse("$Value",[ref]([System.Net.IPAddress]::None))) }
        'hostname'  { return $Value -match '^[A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?$' }
        'nonempty'  { return ($null -ne $Value -and "$Value".Length -gt 0) }
        default     { return $true }
    }
}

function Test-ArrayEqual {
    param([Parameter(Mandatory)]$A, [Parameter(Mandatory)]$B)
    # Coerce to simple object[] so ArrayList vs object[] differences don't matter
    $aa = @($A); $bb = @($B)
    if ($aa.Count -ne $bb.Count) { return $false }
    for ($i=0; $i -lt $aa.Count; $i++) {
        if ($aa[$i] -ne $bb[$i]) { return $false }
    }
    return $true
}
#endregion

#region --- scope.json "public calls"
function Get-ScopeValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,

        [switch]$Ensure,
        [object]$Default = $null,

        #(optional) interactive behavior
        [switch]$Prompt,                    # enable prompting when missing/empty
        [string]$PromptLabel,               # nice label; falls back to derived label from the key
        [string]$ValidateAs,                # reuse your Test-ConfigValue validators (IpAddress|Hostname|NonEmpty|...)
        [int]$MaxAttempts = 3,              # re-prompt attempts
        [switch]$AllowEmpty,                # treat "" as acceptable
        [switch]$NonInteractive             # never prompt, even if -Prompt is set
    )

    # Hardcoded path (your decision)
    $ConfigPath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\scope.json"

    # --- Helper: derive a sensible label from the key if none provided
    $deriveLabel = {
        param([string]$k)
        $last = ($k -split '\.')[-1]
        # prettify common tokens
        $last -replace '([A-Z])', ' $1' -replace '^ ', '' | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }
    }

    # Read current config (may be $null)
    $cfg = Read-JsonFile -Path $ConfigPath

    if ($null -eq $cfg) {
        # File missing/empty
        if ($Ensure -and $PSBoundParameters.ContainsKey('Default')) {
            Write-Log "Get-ScopeValue: file missing or empty → creating and setting default for '$Key'." VERBOSE
            $cfg = @{}
            $target = Set-ConfigPath -Root $cfg -Key $Key
            if ($target.Parent -is [hashtable] -or $target.Parent -is [System.Collections.IList]) {
                $target.Parent[$target.Key] = $Default
            }
            if (-not $cfg.ContainsKey('__meta')) { $cfg['__meta'] = @{} }
            $cfg['__meta']['lastReconciledUtc'] = (Get-Date).ToUniversalTime().ToString('o')
            Write-JsonFile -Path $ConfigPath -Object $cfg
            return $Default
        }

        if ($Prompt -and -not $NonInteractive) {
            # We can prompt even if the file is missing; Set-ScopeValue will scaffold and write.
            $label = if ($PromptLabel) { $PromptLabel } else { & $deriveLabel $Key }
            Write-Log "Get-ScopeValue: '$Key' missing; prompting user ($label)." WARNING
            $attempts = 0
            while ($attempts -lt $MaxAttempts) {
                $hint = @()
                if ($ValidateAs) { $hint += "Expected: $ValidateAs" }
                if ($PSBoundParameters.ContainsKey('Default')) { $hint += "Default: $Default (Enter to accept)" }
                if ($hint.Count) { Write-Host ($hint -join ' | ') }

                $answer = Read-Host -Prompt $label
                if ([string]::IsNullOrEmpty($answer) -and $PSBoundParameters.ContainsKey('Default')) {
                    $answer = $Default
                }
                if (-not $AllowEmpty -and [string]::IsNullOrEmpty($answer)) {
                    $remaining = $MaxAttempts - $attempts - 1
                    Write-Host "Empty value not allowed for '$label'." 
                    if ($remaining -gt 0) { Write-Host "Try again ($remaining attempts left)..." }
                    $attempts++; continue
                }
                if ($ValidateAs -and -not (Test-ConfigValue -Validator $ValidateAs -Value $answer)) {
                    $remaining = $MaxAttempts - $attempts - 1
                    Write-Host "Invalid value for '$label' (validator: $ValidateAs)." 
                    if ($remaining -gt 0) { Write-Host "Try again ($remaining attempts left)..." }
                    $attempts++; continue
                }

                # Persist and return the confirmed value
                Set-ScopeValue -Key $Key -Value $answer -ValidateAs $ValidateAs -CreateMissing
                $cfg2 = Read-JsonFile -Path $ConfigPath
                return (Resolve-ConfigPath -Root $cfg2 -Key $Key).Value
            }

            throw "No valid value provided for '$Key'. Supply it in scope.json or rerun with -Default/-Prompt."
        }

        # Non-interactive or no prompt requested
        return $null
    }

    # Config exists → resolve the value
    $res = Resolve-ConfigPath -Root $cfg -Key $Key
    $val = $res.Value

    # Decide emptiness
    $isEmpty = $null -eq $val -or ($val -is [string] -and $val -eq "")
    if ($AllowEmpty) {
        # Treat "" as a valid value
        if ($val -is [string] -and $val -eq "") { $isEmpty = $false }
    }

    # Ensure+Default path (auto-set, no prompt)
    if ($Ensure -and $PSBoundParameters.ContainsKey('Default') -and $isEmpty) {
        Write-Log "Get-ScopeValue: '$Key' missing/empty → setting default." VERBOSE
        Set-ScopeValue -Key $Key -Value $Default -ValidateAs $ValidateAs -CreateMissing | Out-Null
        $cfg2 = Read-JsonFile -Path $ConfigPath
        return (Resolve-ConfigPath -Root $cfg2 -Key $Key).Value
    }

    # Prompt path (only if still missing/empty and allowed)
    if ($Prompt -and -not $NonInteractive -and $isEmpty) {
        $label = if ($PromptLabel) { $PromptLabel } else { & $deriveLabel $Key }
        Write-Log "Get-ScopeValue: '$Key' missing/empty; prompting user ($label)." WARNING
        $attempts = 0
        while ($attempts -lt $MaxAttempts) {
            $hint = @()
            if ($ValidateAs) { $hint += "Expected: $ValidateAs" }
            if ($PSBoundParameters.ContainsKey('Default')) { $hint += "Default: $Default (Enter to accept)" }
            if ($hint.Count) { Write-Host ($hint -join ' | ') }

            $answer = Read-Host -Prompt $label
            if ([string]::IsNullOrEmpty($answer) -and $PSBoundParameters.ContainsKey('Default')) {
                $answer = $Default
            }
            if (-not $AllowEmpty -and [string]::IsNullOrEmpty($answer)) {
                $remaining = $MaxAttempts - $attempts - 1
                Write-Host "Empty value not allowed for '$label'." 
                if ($remaining -gt 0) { Write-Host "Try again ($remaining attempts left)..." }
                $attempts++; continue
            }
            if ($ValidateAs -and -not (Test-ConfigValue -Validator $ValidateAs -Value $answer)) {
                $remaining = $MaxAttempts - $attempts - 1
                Write-Host "Invalid value for '$label' (validator: $ValidateAs)." 
                if ($remaining -gt 0) { Write-Host "Try again ($remaining attempts left)..." }
                $attempts++; continue
            }

            Set-ScopeValue -Key $Key -Value $answer -ValidateAs $ValidateAs -CreateMissing
            $cfg2 = Read-JsonFile -Path $ConfigPath
            return (Resolve-ConfigPath -Root $cfg2 -Key $Key).Value
        }

        throw "No valid value provided for '$Key'. Supply it in scope.json or rerun with -Default/-Prompt."
    }

    # Value present (or empty but allowed) → return it
    return $val
}

function Set-ScopeValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowNull()][object]$Value,  # allow explicit nulls (e.g., clear VLAN)
        [string]$ValidateAs,
        [switch]$CreateMissing
    )

    # Only validate non-null values
    if ($ValidateAs -and $null -ne $Value) {
        if (-not (Test-ConfigValue -Validator $ValidateAs -Value $Value)) {
            throw "Validation failed for '$Key' as $ValidateAs with value '$Value'."
        }
    }

    # Hardcoded scope path (your design)
    $ConfigPath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\scope.json"

    $cfg = Read-JsonFile -Path $ConfigPath
    if ($null -eq $cfg) { $cfg = @{} }

    # Resolve the path; create if requested
    $res = Resolve-ConfigPath -Root $cfg -Key $Key
    $exists = ($res.Remaining.Count -eq 0 -and $null -ne $res.Value)

    $parent = $null; $k = $null
    if (-not $exists) {
        if (-not $CreateMissing) { throw "Path '$Key' does not exist. Use -CreateMissing to scaffold." }
        # NOTE: you renamed Ensure-ConfigPath -> Set-ConfigPath; using your name here.
        $target = Set-ConfigPath -Root $cfg -Key $Key
        $parent = $target.Parent; $k = $target.Key
    } else {
        $parent = $res.Parent; $k = $res.Key
    }

    # Current value for change detection (supports hashtable key or array index)
    $hasCurrent = $false
    $current = $null
    if     ($parent -is [hashtable]) {
        $hasCurrent = $parent.ContainsKey($k)
        if ($hasCurrent) { $current = $parent[$k] }
    }
    elseif ($parent -is [System.Collections.IList]) {
        $hasCurrent = ($k -is [int] -and $k -ge 0 -and $k -lt $parent.Count)
        if ($hasCurrent) { $current = $parent[$k] }
    }

    # Deep equality for arrays; scalar/object equality otherwise
    $equal =
        ($hasCurrent) -and (
            (($current -is [System.Collections.IList]) -and ($Value -is [System.Collections.IList]) -and (Test-ArrayEqual $current $Value)) -or
            (-not ($current -is [System.Collections.IList]) -and -not ($Value -is [System.Collections.IList]) -and ($current -ceq $Value))
        )

    $changed = -not $equal

    if ($changed) {
        if ($PSCmdlet.ShouldProcess($ConfigPath, "Set $Key")) {
            if     ($parent -is [hashtable])               { $parent[$k] = $Value }
            elseif ($parent -is [System.Collections.IList]) { $parent[$k] = $Value }
            else { throw "Internal: unsupported parent container for '$Key'." }

            if (-not $cfg.ContainsKey('__meta')) { $cfg['__meta'] = @{} }
            $cfg['__meta']['lastReconciledUtc'] = (Get-Date).ToUniversalTime().ToString('o')

            Write-JsonFile -Path $ConfigPath -Object $cfg

            $display = if ($null -eq $Value) { '<null>' }
                        elseif ($Value -is [System.Collections.IList]) { (@($Value) -join ', ') }
                        else { "$Value" }
            Write-Log "Set-ScopeValue: $Key = $display" VERBOSE

        }
    } else {
        Write-Log "Set-ScopeValue: $Key already desired value; no change." VERBOSE
    }
}

Set-Alias Get-Scope Get-ScopeValue
Set-Alias Set-Scope Set-ScopeValue
#endregion
#endregion

#region --- JSON handling for .\config\*.json
function Get-ModulePath {
    Return 'C:\Program Files\Powershell\Modules\modulus-toolkit\'
}


function Get-EnvironmentVariables {
    $configFile = Join-Path (Get-ModulePath) "config\envvars.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $configFile"
    }
}

function Get-Components {
    $configFile = Join-Path (Get-ModulePath) "config\components.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json -Depth 10
    } else {
        throw "Config file not found: $configFile"
    }
}

function Get-ReconfigurationScope {
    $configFile = Join-Path (Get-ModulePath) "config\mod-RE-config.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json -Depth 10
    } else {
        throw "Config file not found: $configFile"
    }
}

#TODO: rework this, only used in update-mod-component
function Get-BinaryVersion {
    param (
        [string]$binaryPath
    )
    
    try {
        $file = Get-ItemProperty -Path $binaryPath

        $version = $file.VersionInfo.FileVersion
        #write-host $version
        
        if (($version -eq "0.0.0.0") -or ($version -eq "-")) {
            #abnormal version

            $major = $file.VersionInfo.FileVersionRaw.Major 
            $minor = $file.VersionInfo.FileVersionRaw.Minor
            $build = $file.VersionInfo.FileVersionRaw.Build
            $rev   = $file.VersionInfo.FileVersionRaw.Revision

            $version  = "$major.$minor.$build.$rev"
            return $version

        } else {
            #normal version
            return $version
        }
    } catch {
        return ""
    }
}
#endregion

#region --- shortcuts to open tools and applications from I: - no prereq
function NewDMM {
    $newDMM = "I:\Tools\NewDMM\Modulus NewDMM.lnk"
    if (Test-Path $newDMM)
    {
        #Unblock-File -Path $newDMM
        & $newDMM
    } else {
        Write-Log "$newDMM was not found! - Make sure you mapped I:-share!" WARNING
    }
}

function CleanRegistry {
    $clean = "I:\Tools\NewDMM\CleanRegistry.exe"
    if (Test-Path $clean)
    {
        #Unblock-File -Path $clean
        & $clean
    } else {
        Write-Log "$clean was not found! - Make sure you mapped I:-share!" WARNING
    }
}

function QB {
    $qb = "D:\Onlinedata\bin\qb.exe"
    if (Test-Path $qb)
    {
        #Unblock-File -Path $clean
        & $qb
    } else {
        Write-Log "$qb was not found! - Make sure you have it installed!" WARNING
    }
}
#endregion

#region --- weird helpers for deployment -> should be a proper confirmation logic at some point
#function for user input about Continue or Abort
function CoA {

    $continue = Confirm-YesNo -Message "Do you want to continue?" -Default "Yes"
    if ($continue) {
        Write-Log "Continuing..."
        Return $true
    } else {
        Write-Log "Aborting!" -Level WARNING
        Return $false 
    }
}

function Confirm-YesNo {
    [CmdletBinding()]
    param(
        # The question to ask
        [string]$Message = "Proceed?",
        # Default choice if user just presses Enter or input is unrecognized
        [ValidateSet("Yes","No")]
        [string]$Default = "No",
        # Extra accepted tokens (in addition to Y/YES and N/NO)
        [string[]]$YesAliases = @(),
        [string[]]$NoAliases  = @(),
        # Skip prompting (useful for automation or CI)
        [switch]$Force
    )

    if ($Force) { return $true }

    $caption = "Confirmation"
    $choices = @(
        (New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Proceed"),
        (New-Object System.Management.Automation.Host.ChoiceDescription "&No",  "Cancel")
    )
    $defaultIndex = if ($Default -eq "Yes") { 0 } else { 1 }

    # Try PromptForChoice first (structured, localized, consistent)
    try {
        $result = $Host.UI.PromptForChoice($caption, $Message, $choices, $defaultIndex)
        return ($result -eq 0)
    }
    catch {
        # Fallback to Read-Host (e.g., restricted/non-interactive hosts)
        $prompt = "$Message (Y/N) [default: $Default]"
        $answer = (Read-Host $prompt).Trim().ToUpper()

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return ($Default -eq "Yes")
        }

        $yesSet = @("Y","YES") + ($YesAliases | ForEach-Object { $_.ToUpper() })
        $noSet  = @("N","NO")  + ($NoAliases  | ForEach-Object { $_.ToUpper() })

        if ($yesSet -contains $answer) { return $true  }
        if ($noSet  -contains $answer) { return $false }

        # Unrecognized -> honor default
        return ($Default -eq "Yes")
    }
}
#endregion

#region --- list Galaxis sources in staging area
function Show-SourcesDir {
    $sourcesDir = Get-SourcesPath
    Get-ChildItem $sourcesDir | Format-Table Name, LastWriteTime
}

function Show-NewestSources {
    [CmdletBinding()]
    param(
        [string] $Sources = (Get-SourcesPath),
        [switch] $AsObject
    )

    $components = @(
        @{ Name='Galaxis Config';        Pattern='Galaxis*(Config only).7z' }
        @{ Name='Galaxis Executable';    Pattern='Galaxis*(Executable only).7z' }
        @{ Name='Galaxis Other';         Pattern='Galaxis*(Other only).7z' }
        @{ Name='SYSTM Config';          Pattern='SYSTM*(Config only).7z' }
        @{ Name='SYSTM Executable';      Pattern='SYSTM*(Executable only).7z' }
        @{ Name='GalaxisWeb';            Pattern='GalaxisWeb.1*.7z' }                 # excludes Configuration
        @{ Name='GalaxisWeb Config';     Pattern='GalaxisWeb.Configuration*.7z' }
        @{ Name='MBoxUI';                Pattern='MBoxUI.1*.7z' }
        @{ Name='MBoxUI Config';         Pattern='MBoxUI.Configuration*.7z' }
        @{ Name='PlayWatch Process';     Pattern='RgMonitorProcess*.7z' }
        @{ Name='PlayWatch Website';     Pattern='RgMonitorWebsite*.7z' }
        @{ Name='CRYSTAL Control';       Pattern='Crystal_Control*.7z' }
        @{ Name='Install Package';       Pattern='UnCompressOnGalaxisHomeInstall*.7z' }
    )

    $rows = foreach ($c in $components) {
        $all = Resolve-ArchiveCandidates -Directory $Sources -Pattern $c.Pattern
        if (-not $all) { continue }

        $sel = Select-NewestArchive -Candidates $all
        $pick = $sel.Candidate
        [pscustomobject]@{
            Component   = $c.Name
            Version     = if ($pick.Version) { $pick.Version.ToString() } else { "<none>" }
            File        = $pick.Name
            ModifiedUtc = Get-Date $pick.LastWriteTime -AsUTC -Format "yyyy-MM-dd HH:mm"
            SizeMB      = [math]::Round($pick.Length / 1MB, 2)
            Matches     = ($sel.All | Measure-Object).Count
            Path        = $pick.File
        }
    }

    if ($AsObject) { return $rows }
    $rows | Sort-Object Component | Format-Table Component, Version, File, ModifiedUtc, SizeMB, Matches -AutoSize
}
#endregion

#region --- list prepared Galaxis packages
function Show-PrepDir {
    $prepDir = Get-PrepPath
    Get-ChildItem $prepDir | Format-Table Name, LastWriteTime
}
#endregion

#region --- Backup Modulus folders
function Backup-GLXDir {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

    Write-Log "Backup-GLXDir" -Header

	if ($AskIf) {
        $confirm = Read-Host "Do you want to backup your current D:\Galaxis directory?"
        if ($confirm -ne "Y") {
            Write-Log "User chose not to create a backup!" -Level WARNING
            return
        }
    }

	$GLXDir = Get-GalaxisPath
    $backupDir = Get-BackupPath

	#region checks
	#aborting if $Source does not exist
	if (!(Test-Path $GLXDir))
	{
		Write-Log "Folder $GLXDir does not exist, aborting!" -Level WARNING
		exit
	}

	#create $Destination if it does not exist already
	if(!(Test-Path $backupDir))
	{
		New-Item -Path $backupDir -ItemType Directory > $null
		write-verbose "Creating folder: $backupDir"
	}

	#creating final $dst folder OR clearing it if exists
	$backupDir = $backupDir+"\Galaxis_"+(get-date).toString('ddMMyyyy-HH24')
	if(Test-Path $backupDir)
	{
		#write-host 'Deleting previous backup from today!'
		#Get-ChildItem -Path $Destination -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item -Recurse
		#Remove-Item -Path $Destination -Recurse -ErrorAction SilentlyContinue
		#gci $Destination -recurse  | remove-item -recurse 
	}else{
		New-Item -Path $backupDir -ItemType Directory > $null
		write-verbose "Creating folder: $backupDir"
	}
	#endregion

	#region robocopy params

	#$XD = '"D:\Galaxis\Log", "D:\Galaxis\Application\OnLine\AlarmServer\Current\dat", "D:\Galaxis\Application\OnLine\AlarmServer\Current\log", "D:\Galaxis\Application\OnLine\SlotMachineServer\Current\dat", "D:\Galaxis\Application\OnLine\SlotMachineServer\Current\log", "D:\Galaxis\Application\OnLine\TransactionServer\Current\dat", "D:\Galaxis\Application\OnLine\TransactionServer\Current\log"'
	#$XF = '"BDESC*", "*minidump*", "*.err", "FullLog*.txt", "ShortLog*.txt"'

	#$params = '/MIR /NP /NDL /NC /BYTES /NJH /NJS /XD {0} /XF {1}' -f $XD, $XF;
	#/NP 	= no progress
	#/NDL	= no directory output
	#/NC	= no file class output
	#/BYTES = filesize in bytes, important for staging and progress-calc of mod-log function
	#/NJH	= no robocopy header
	#/NJS	= no robocopy summary
	#/XD 	= directories to be excluded
	#/XF	= files to be excluded
	#endregion


	Start-MOD-Copy -Source $GLXdir -Destination $backupDir #-CommonRobocopyParams $params 

	Write-Log "Backup of D:\Galaxis completed."
}
function Backup-OnlineData {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

    Write-Log "Backup-OnlineData" -Header

	if ($AskIf) {
        $confirm = Read-Host "Do you want to backup your current D:\OnlineData directory?"
        if ($confirm -ne "Y") {
            Write-Log "User chose not to create a backup!" -Level WARNING
            return
        }
    }

    $OLData = Get-OnlinedataPath
    $backupDir = Get-BackupPath

	#region checks
	#aborting if $Source does not exist
	if (!(Test-Path $OLData))
	{
		Write-Log "Folder $OLData does not exist, aborting!" -Level WARNING
		exit
	}

	#create $Destination if it does not exist already
	if(!(Test-Path $backupDir))
	{
		New-Item -Path $backupDir -ItemType Directory > $null
		write-verbose "Creating folder: $backupDir"
	}

	#creating final $dst folder OR clearing it if exists
	$backupDir = $backupDir+"\OnlineData_"+(get-date).toString('ddMMyyyy-HH24')
	if(Test-Path $backupDir)
	{
		#write-host 'Deleting previous backup from today!'
		#Get-ChildItem -Path $Destination -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item -Recurse
		#Remove-Item -Path $Destination -Recurse -ErrorAction SilentlyContinue
		#gci $Destination -recurse  | remove-item -recurse 
	}else{
		New-Item -Path $backupDir -ItemType Directory > $null
		write-verbose "Creating folder: $backupDir"
	}
	#endregion

	#region robocopy params

	#$XD = '"D:\OnlineData\Log", "D:\OnlineData\excata", "D:\OnlineData\jpdata", "D:\OnlineData\Relay\Logs", "D:\OnlineData\nginx\logs", "D:\OnlineData\FM\LOG", "D:\OnlineData\Dbx\log"'
	#$XF = '"BDESC*", "*minidump*", "*.err", "FullLog*.txt", "ShortLog*.txt", "server*.log"'

	#$params = '/MIR /NP /NDL /NC /BYTES /NJH /NJS /XD {0} /XF {1}' -f $XD, $XF;
	#/NP 	= no progress
	#/NDL	= no directory output
	#/NC	= no file class output
	#/BYTES = filesize in bytes, important for staging and progress-calc of mod-log function
	#/NJH	= no robocopy header
	#/NJS	= no robocopy summary
	#/XD 	= directories to be excluded
	#/XF	= files to be excluded
	#endregion


	Start-MOD-Copy -Source $OLData -Destination $backupDir #-CommonRobocopyParams $params 

	Write-Log "Backup of D:\OnlineData completed."
}
#endregion

#region --- check currently installed Galaxis version (APP server only)
function Show-CurrentGLXVersion {
	$GLX = Get-GalaxisPath
	$currentVersion = ((Get-Item $GLX'\Program\bin\BackOfficeSlotOperation.Controls.dll').VersionInfo).ProductVersion
	write-host ' - Currently deployed vesion: '								    -ForegroundColor Green 
	if($currentVersion) {
		write-host '------------------------------'								-ForegroundColor Green 
		Write-Host '  - '$currentVersion
		write-host '------------------------------'								-ForegroundColor Green 
	} else {
		write-host '------------------------------'								-ForegroundColor Red 
		Write-Host '  - UNKOWN VERSION !!!        '								-ForegroundColor Red
		write-host '------------------------------'								-ForegroundColor Red 
	}
}
#endregion

#region --- open TK config
function Open-TK-Config {
    $configFile = Join-Path (Get-ModulePath) "config\scope.json"
    if (Test-Path $configFile) {
        np $configFile
    } else {
        throw "Config file not found: $configFile"
    }
}
#endregion

#region --- readme.MD

#function to open all the manuals that we have!
function Open-MOD-Manual {
    [CmdletBinding()]
    param(
        # Optional, still tab-completes via ValidateSet; defaults to README
        [ValidateSet("README","README_extended","1097","1099","Peripherals","QPon-checklist","Workstation","GLX-dictionary","Manual")]
        [string]$Manual = "README"
    )

    Write-Log "Open-MOD-Manual $Manual" -Header
    Write-Log "Check your browser and follow the instructions in the manual!"

    # Resolve the module base at runtime (works regardless of locale / install path)
    $moduleBase = $MyInvocation.MyCommand.Module.ModuleBase

    # Map the logical name to a relative path under the module
    $relative = switch ($Manual) {
        "README"          { "README.md" }
        "README_extended" { "manuals\README_extended.md" }
        "1097"            { "manuals\1097_manual.md" }
        "1099"            { "manuals\1099_manual.md" }
        "Peripherals"     { "manuals\Peripherals.md" }
        "QPon-checklist"  { "manuals\QPon-checklist.md" }
        "Workstation"     { "manuals\Workstation.md" }
        "GLX-dictionary"  { "manuals\GLX_dictionary.md" }
        "Manual"          { "manuals\Manual_steps.md" }
        default           { throw "Invalid manual: $Manual" }
    }

    $path = Join-Path -Path $moduleBase -ChildPath $relative

    if (Test-Path -LiteralPath $path) {
        # Prefer Chrome if present; otherwise fall back to default file handler
        <#
        $chrome = Get-Command "chrome.exe" -ErrorAction SilentlyContinue
        if ($chrome) {
            Start-Process -FilePath $chrome.Path -ArgumentList "`"$path`""
        } else {
            Start-Process -FilePath $path
        }
        #>
        Start-Process "chrome.exe" "`"$path`""
    } else {
        Write-Log "Manual was not found at $path" -Level ERROR
    }
}
#endregion

#region --- service-related functions 
function Show-MOD-Services {
	
    Write-Log "Show-MOD-Services" -Header

	$GalaxisServices = @()	

    $GalaxisServices += Get-Service -Name "pinit"				-ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -Name "OracleServiceGLX"	-ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -Name "OracleServiceJKP"	-ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -Name "OracleOraDB19Home1TNSListener" 	-ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -Name "Alloy" 	            -ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -displayName "Galaxis*"		-ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -Name "RabbitMQ"			-ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -Name "PlayerSegmentLink"	-ErrorAction SilentlyContinue
    $GalaxisServices += Get-Service -Name "nginx"	 			-ErrorAction SilentlyContinue
 
    #sorthing by StartupType, Status and DisplayName
    $GalaxisServices = $GalaxisServices | Sort-Object StartupType, Status, DisplayName

    foreach ($service in $GalaxisServices) {
        if ($service.StartupType -ne 'Disabled') {
            if ($service.Status -eq 'Running') {
                Write-Host "$($service.Status) $($service.DisplayName)" -ForegroundColor Green
            } elseif ($service.Status -eq 'Stopped') {
                Write-Host "$($service.Status) $($service.DisplayName)" -ForegroundColor Gray
            } else {
                Write-Host "$($service.Status) $($service.DisplayName)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "$($service.StartupType) $($service.DisplayName)" -ForegroundColor Red
        }
	}
}

function Start-MOD-Services {
    Write-Log "Start-MOD-Services" -Header

    Test-UnblockMoTW -Path `
        'D:\Galaxis\', `
        'D:\OnlineData' `
        -Recurse

    $dotnetCheck = Assert-InstalledRuntime -OnlyOnFailure
    if (-not $dotnetCheck) {
        Write-Log "Cannot start services because .NET runtime requirements are not met!" -Level ERROR
        return
    }
	
	$GSS = Get-Service -Name "GalaxisStartupService" -ErrorAction SilentlyContinue
	if($GSS) {
		Start-Service $GSS
		Write-Log 'GalaxisStartupService started!' 
	} else {
		$pinit = Get-Service -Name "pinit" -ErrorAction SilentlyContinue
		if ($pinit) {
			Start-Service $pinit
			Write-Log "pinit started!" 
		}
	}

	#giving the services some time to breath
	Start-Sleep -Seconds 1
	
	$GLXservices = Get-Service -displayName "Galaxis*"
	foreach ($service in $GLXservices)
	{
		$status = (Get-Service -name $service.name).Status
		$startType = (Get-Service -name $service.name).StartType
		
		if ($startType -ne "Disabled")
		{
			if ($status -ne "Running")
			{
				Start-Service -Name $service.name
				$output =  "Started " + $service.name + "!"
				Write-Log $output DEBUG
			}
		}
	}
}
function Stop-MOD-Services {
    
    Write-Log "Stop-MOD-Services" -Header

	$RMQ = Get-Service -Name "RabbitMQ" -ErrorAction SilentlyContinue
	if($RMQ) {
		Stop-Service $RMQ
		write-Log 'RabbitMQ stopped!'
	}

	#wsl --shutdown
	
	$GSS = Get-Service -Name "GalaxisStartupService" -ErrorAction SilentlyContinue
	if ($GSS)
	{
		Stop-Service $GSS
		write-Log 'GalaxisStartupService stopped!' 
	} else {
		$pinit = Get-Service -name "pinit" -ErrorAction SilentlyContinue
		if ($pinit) {
			Stop-Service $pinit
			Write-Log "pinit stopped!" 
		}
	}

	Start-Sleep -Seconds 1
	
	$GLXservices = Get-Service -displayName "Galaxis*"
	foreach ($service in $GLXservices)
	{
		$status = (Get-Service -name $service.name).status 
		if ($status -eq "Running")
		{
			Stop-Service -Name $service.name
			$output =  "Stopped " + $service.name + "!"
			Write-Log $output 
		}
	}

	#Get-Service -Name "nginx" | Stop-Service						-ErrorAction SilentlyContinue
	#write-Log 'nginx stopped!' DEBUG
}
#endregion

#TODO: rework, check missing stuff? use mod-compnent.json maybe? fill using this?
#region --- Open-* functions
function Open-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('ALL','hosts','Oracle','inittab','QB','JPApps','inittab','GDC','RTDS','AlarmServer','TransactionServer','SlotMachineServer','AddressBook','AML','AuthenticationService','Bus','BusHO','CashWalletManager','CashWalletService','Database','Datamart','MarketingDatamart','Messenger','QPonCash','Report','SlotDataExporter','TBL','triggermemberdataserver','CasinoSyncService','nginx','AMLService','GalaxisAPI','LicenseService','MessengerService','NotificationService','TableSetupService','JPS','Web','CFCS','Control')]
        [string]$Config
    )

    if ($Config -eq "ALL") {
       #list all of them?
       Write-Log "Not implemented yet. Sorry!"
    } else {
        switch ($Config) {
            #C:\Program Files (x86)\Modulus\
            "hosts"                     { np "C:\Windows\system32\drivers\etc\hosts" }
            "Oracle" {
                np "C:\Oracle\client32\network\admin\sqlnet.ora"
                np "C:\Oracle\client32\network\admin\tnsnames.ora"
                np "C:\Oracle\client32\network\admin\replicatedscope.ora"
                
                if ($ENV:MODULUS_SERVER -eq "DB") {
                    np "D:\Oracle\Ora19c\network\admin\listener.ora"
                    np "D:\Oracle\Ora19c\network\admin\sqlnet.ora"
                    np "D:\Oracle\Ora19c\network\admin\tnsnames.ora"    
                    np "D:\Oracle\Ora19c\network\admin\replicatedscope.ora" 
                }

            }
            "JPApps" {
                np "C:\Program Files (x86)\Modulus\Jackpot Applications\Settings\JPApplicationSettings.ini"
                np "C:\Program Files (x86)\Modulus\Jackpot Reporting\Settings\JPReportSettings.ini"
                np "C:\Program Files (x86)\Modulus\SecurityServer Configuration\Settings\SecurityApplicationSettings.ini"
            }
            #D:\OnlineData\
            "inittab"                   { np "D:\OnlineData\cfg\inittab" }
            #D:\Galaxis\Application\ -> GDC + RTDS
            "GDC"                       { np "D:\Galaxis\Application\Control\Service\GameDayChange\Current\gamedaychange.properties" }
            "AlarmServer"               { np "D:\Galaxis\Application\OnLine\AlarmServer\Current\alarmserver.properties" }
            "TransactionServer"         { np "D:\Galaxis\Application\OnLine\TransactionServer\Current\transactionserver.properties" }
            "SlotMachineServer"         { D:\Galaxis\Application\OnLine\SlotMachineServer\Current\smserv3configuration.bat }
            "RTDS" {
                np "D:\Galaxis\Application\Control\Service\GameDayChange\Current\gamedaychange.properties"
                np "D:\Galaxis\Application\OnLine\TransactionServer\Current\transactionserver.properties"
                D:\Galaxis\Application\OnLine\SlotMachineServer\Current\smserv3configuration.bat
            }

            #D:\Galaxis\Program\Common\
            "AddressBook"               { np "D:\Galaxis\Program\Common\AddressBook.xml" }
            "AML"                       { np "D:\Galaxis\Program\Common\Aml.ini" }
            "AuthenticationService"     { np "D:\Galaxis\Program\Common\AuthenticationService.ini" }
            "Bus"                       { np "D:\Galaxis\Program\Common\Bus.ini" }
            "BusHO"                     { np "D:\Galaxis\Program\Common\busho.ini" }
            "CashWalletManager"         { np "D:\Galaxis\Program\Common\CashWalletManager.ini" }
            "CashWalletService"         { np "D:\Galaxis\Program\Common\CashWalletService.ini" }
            "Database"                  { np "D:\Galaxis\Program\Common\DataBase.ini" }
            "Datamart"                  { np "D:\Galaxis\Program\Common\Datamart.ini" }
            "MarketingDatamart"         { np "D:\Galaxis\Program\Common\MarketingDatamart.ini" }
            "Messenger"                 { np "D:\Galaxis\Program\Common\Messenger.ini" }
            "QPonCash"                  { np "D:\Galaxis\Program\Common\QPonCash.ini" }
            "Report"                    { np "D:\Galaxis\Program\Common\Report.ini" }
            "SlotDataExporter"          { np "D:\Galaxis\Program\Common\SlotDataExporter.ini" }
            "TBL"                       { np "D:\Galaxis\Program\Common\TBL.ini" }
            "triggermemberdataserver"   { np "D:\Galaxis\Program\Common\triggermemberdataserver.properties" }
            #D:\Galaxis\Program\bin\
            "AMLService"                { np "D:\Galaxis\Program\bin\AmlService\appsettings.json" }
            "GalaxisAPI"                { np "D:\Galaxis\Program\bin\GalaxisApi\appsettings.json" }
            "LicenseService"            { np "D:\Galaxis\Program\bin\LicenseService\appsettings.json" }
            "NotificationService"       { np "D:\Galaxis\Program\bin\NotificationService\appsettings.json" }
            "TableSetupService"         { np "D:\Galaxis\Program\bin\TableSetupService\appsettings.json" }
            "Web"                       { np "D:\Galaxis\Web\SYSTM\assets\config.json" }
            "nginx" { 
                np "D:\Galaxis\Program\bin\nginx\conf\nginx.conf"
                np "D:\Galaxis\Program\bin\nginx\modulus\reverse-proxy.conf" 
            }
            "CasinoSynchronizationService" { 
                np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\CasinoSynchronization-Settings.config" 
                np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\CaWa-Settings.config" 
                np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\ConnectionStrings-Settings.config" 
                np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\Marketing-Settings.config"
                np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\SmibNotification-Settings.config"
            }
            "CFCS" { 
                np "D:\OnlineData\CRYSTAL.Net\CRYSTAL Floor Communication Service\CRYSTAL Floor Communication Service.exe.config" 
                np "D:\OnlineData\CRYSTAL.Net\CRYSTAL Floor Communication Service\log4net.xml"
            }
            "Control" { 
                np "D:\OnlineData\bin\control\ControlLauncher.exe.config" 
                np "D:\OnlineData\bin\control\log4net.config"
            }
            Default { throw "Invalid Config: $Config" }
        }
    }
}
#endregion

#TODO: check missing stuff? use mod-compnent.json maybe? fill using this?
#region --- Show-ConfigContent 
function Show-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('ALL','JPApps','inittab','GDC','RTDS','AlarmServer','TransactionServer','SlotMachineServer','AddressBook','AML','AuthenticationService','Bus','BusHO','CashWalletManager','CashWalletService','Database','Datamart','MarketingDatamart','Messenger','QPonCash','Report','SlotDataExporter','TBL','triggermemberdataserver','CasinoSynchronizationService','nginx','AMLService','GalaxisAPI','LicenseService','MessengerService','NotificationService','TableSetupService')]
        [string]$Config
    )
    
    if ($Config -eq "ALL") {
       #list all of them?
       write-Log "Not implemented yet. Sorry!"
    } else {
        switch ($Config) {
            #C:\Program Files (x86)\Modulus\
            "JPApps" { Show-JPApps-Config }
            #D:\OnlineData\
            #"inittab"                   { np "D:\OnlineData\cfg\inittab" }
            #D:\Galaxis\Application\ -> GDC + RTDS
            #"GDC"                       { np "D:\Galaxis\Application\Control\Service\GameDayChange\Current\gamedaychange.properties" }
            #"AlarmServer"               { np "D:\Galaxis\Application\OnLine\AlarmServer\Current\alarmserver.properties" }
            #"TransactionServer"         { np "D:\Galaxis\Application\OnLine\TransactionServer\Current\transactionserver.properties" }
            #"SlotMachineServer"         { D:\Galaxis\Application\OnLine\SlotMachineServer\Current\smserv3configuration.bat }
            #"RTDS" {
            #    np "D:\Galaxis\Application\Control\Service\GameDayChange\Current\gamedaychange.properties"
            #    np "D:\Galaxis\Application\OnLine\TransactionServer\Current\transactionserver.properties"
            #    D:\Galaxis\Application\OnLine\SlotMachineServer\Current\smserv3configuration.bat
            #}

            #D:\Galaxis\Program\Common\
            #"AddressBook"               { np "D:\Galaxis\Program\Common\AddressBook.xml" }
            #"AML"                       { np "D:\Galaxis\Program\Common\Aml.ini" }
            #"AuthenticationService"     { np "D:\Galaxis\Program\Common\AuthenticationService.ini" }
            #"Bus"                       { np "D:\Galaxis\Program\Common\Bus.ini" }
            #"BusHO"                     { np "D:\Galaxis\Program\Common\busho.ini" }
            #"CashWalletManager"         { np "D:\Galaxis\Program\Common\CashWalletManager.ini" }
            #"CashWalletService"         { np "D:\Galaxis\Program\Common\CashWalletService.ini" }
            #"Database"                  { np "D:\Galaxis\Program\Common\DataBase.ini" }
            #"Datamart"                  { np "D:\Galaxis\Program\Common\Datamart.ini" }
            #"MarketingDatamart"         { np "D:\Galaxis\Program\Common\MarketingDatamart.ini" }
            #"Messenger"                 { np "D:\Galaxis\Program\Common\Messenger.ini" }
            #"QPonCash"                  { np "D:\Galaxis\Program\Common\QPonCash.ini" }
            #"Report"                    { np "D:\Galaxis\Program\Common\Report.ini" }
            #"SlotDataExporter"          { np "D:\Galaxis\Program\Common\SlotDataExporter.ini" }
            #"TBL"                       { np "D:\Galaxis\Program\Common\TBL.ini" }
            #"triggermemberdataserver"   { np "D:\Galaxis\Program\Common\triggermemberdataserver.properties" }
            ##D:\Galaxis\Program\bin\
            #"AMLService"                { np "D:\Galaxis\Program\bin\AmlService\appsettings.json" }
            #"GalaxisAPI"                { np "D:\Galaxis\Program\bin\GalaxisApi\appsettings.json" }
            #"LicenseService"            { np "D:\Galaxis\Program\bin\LicenseService\appsettings.json" }
            #"NotificationService"       { np "D:\Galaxis\Program\bin\NotificationService\appsettings.json" }
            #"TableSetupService"         { np "D:\Galaxis\Program\bin\TableSetupService\appsettings.json" }
            #"nginx" { 
            #    np "D:\Galaxis\Program\bin\nginx\conf\nginx.conf"
            #    np "D:\Galaxis\Program\bin\nginx\modulus\reverse-proxy.conf" 
            #}
            #"CasinoSynchronizationService" { 
            #    np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\CasinoSynchronization-Settings.config" 
            #    np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\CaWa-Settings.config" 
            #    np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\ConnectionStrings-Settings.config" 
            #    np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\Marketing-Settings.config"
            #    np "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\SmibNotification-Settings.config"
            #}
            Default { throw "Invalid Config: $Config" }
        }
    }
}
#endregion

#region --- Get-Functions for JP configuration files
function Get-JPApps-Config {
    #check if component is installed maybe?

    $config = get-MOD-Component-Config "Jackpot Configuration" "JPApplicationSettings.ini"

    if(-not (Test-path $config)) { Write-Log "File does not exist!" ; Return }
    
    $content = Get-IniContent $config
    $address = $content.SecurityServerConfig.Address
    $port    = $content.SecurityServerConfig.Port
    $connTO  = $content.SecurityServerConfig.ConnectionTimeOut 

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force
    Write-Log "-"
    Write-Log "JPApplicationSettings.ini:"
    Write-Log "-"
    Write-Log "[SecurityServerConfig]"
    Write-Log "Address=$address"
    Write-Log "Port=$port"
    Write-Log "ConnectionTimeout=$connTO"
    Write-Log "-"
}

function Get-JPReporting-Config {
    #check if component is installed maybe?

    $config = get-MOD-Component-Config "Jackpot Reporting" "JPReportSettings.ini"

    if(-not (Test-path $config)) { Write-Log "File does not exist!" ; Return }
    
    $content = Get-IniContent $config
    $address = $content.SecurityServerConfig.Address
    $port    = $content.SecurityServerConfig.Port
    $connTO  = $content.SecurityServerConfig.ConnectionTimeOut 

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force
    Write-Log "-"
    Write-Log "JPReportSettings.ini:"
    Write-Log "-"
    Write-Log "[SecurityServerConfig]"
    Write-Log "Address=$address"
    Write-Log "Port=$port"
    Write-Log "ConnectionTimeout=$connTO"
    Write-Log "-"
}

function Get-SecurityServerConfig-Config {
    #check if component is installed maybe?

    $config = get-MOD-Component-Config "SecurityServer Configuration" "SecurityApplications.ini"

    if(-not (Test-path $config)) { Write-Log "File does not exist!" ; Return }
    
    $content    = Get-IniContent $config
    $address    = $content.SecurityServerConfig.Address
    $port       = $content.SecurityServerConfig.Port
    $connTO     = $content.SecurityServerConfig.ConnectionTimeOut 
    $user       = $content.user.username
    $casino_id  = $content.DEFAULT_CASINO.ext_casino_id

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force
    Write-Log "-"
    Write-Log "SecurityApplicationSettings.ini:"
    Write-Log "-"
    Write-Log "[SecurityServerConfig]"
    Write-Log "Address=$address"
    Write-Log "Port=$port"
    Write-Log "ConnectionTimeout=$connTO"
    Write-Log "-"
    Write-Log "[User]"
    Write-Log "UserName=$user"
    Write-Log "[DEFAULT_CASINO]"
    Write-Log "ext_casino_id=$casino_id"
}
#endregion

#region --- FS config
function Show-FS-Config {
    Write-Log "Show-FS-Config" -Header

    $fscfg = get-MOD-Component-Config "Floorserver" "fscfg.tcl85"

    if(Test-Path -Path $fscfg) {
        Write-Log "Opening $fscfg !" -ForegroundColor Green
        Invoke-Item $fscfg
    } else {
        Write-Log "$fscfg cannot be found, please verify you are on a FS!" ERROR
    }
}
#endregion

#region --- AML - first test jörg
function Get-AML-Config {
    Write-Log "Get-AML-Config" -Header

    $config = get-MOD-Component-Config "Galaxis/SYSTM" "Aml.ini"

    if(-not (Test-path $config)) { Write-Log "$config does not exist!" ERROR ; Return }

    $content    = Get-IniContent $config
    $provider   = $content.CONNECTION.PROVIDER
    $datasource = $content.CONNECTION.datasource
    $schema     = $content.CONNECTION.schema
    $username   = $content.CONNECTION.username
    $pw         = $content.CONNECTION.password

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force

    Write-Log "-"
    Write-Log "AML.ini:"
    Write-Log "-"
    Write-Log "[CONNECTION]"
    Write-Log "PROVIDER=$provider"
    Write-Log "DATASOURCE=$datasource"
    Write-Log "SCHEMA=$schema"
    Write-Log "USERNAME=$username"
    Write-Log "PASSWORD=$pw"
    Write-Log "-"
    Write-Log "-----------------------------" -ForegroundColor Green
}

function Set-AML-Config {
    Write-Log "Set-AML-Config" -Header

    $config = get-MOD-Component-Config "Galaxis/SYSTM" "Aml.ini"

    if(-not (Test-path $config)) { Write-Log "$config does not exist!" ERROR ; Return }

    #$general_settings = Get-MOD-GeneralSettings
    #$DB = $general_settings.databases.GLX_DB

    $DB = Get-DBTns GLX
    $DBofficeIP = Get-MOD-DB-OFFICE-IP

    $content = Get-IniContent $config

    #$content.SecurityServerConfig.Address = $serverConfig.networkAdapters.OFFICE.IP
    #$content.SecurityServerConfig.Port = 1666
    #$content.SecurityServerConfig.ConnectionTimeOut = 21
    #$content.CONNECTION.PROVIDER = ''

    $content.CONNECTION.datasource = "//" + $DBofficeIP + ":1521/" + $DB

    Write-Log "TODO: credential management!" ERROR

    #$content.CONNECTION.schema
    #$content.CONNECTION.username
    #$content.CONNECTION.password

    Out-IniFile -InputObject $content -FilePath $config -Force
}
#endregion

#region --- 3VM checksums
function Show-MOD-Checksums {
    # List of files to search for files
    $files = @(
        "\\APPSERVER-HN\D$\Galaxis\Application\OnLine\AlarmServer\Current\alarmserver.jar",
        "\\APPSERVER-HN\D$\Galaxis\Application\Control\Service\ApplicationLauncherService\Current\ApplicationLauncherService.exe",
        "\\APPSERVER-HN\D$\Galaxis\Application\Control\Tool\ApplicationTimer\Program\Current\ApplicationTimer.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\BackOfficeSlotOperation.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\Common\common.jar",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\DataSetup.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\DataTool.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\StarVision\mfu.jar",
        "\\APPSERVER-HN\D$\Galaxis\Application\OnLine\SemiOnLine\Current\semionline.jar",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\SiteSecurity.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\SlotSetup.exe",
        "\\APPSERVER-HN\D$\Galaxis\Application\OnLine\SlotMachineServer\Current\smserv3.jar",
        "\\APPSERVER-HN\D$\Galaxis\Application\Control\Tool\StartUp\StartUpEngine\Current\StartupEngine.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\StarVision\starvision.jar",
        "\\APPSERVER-HN\D$\Galaxis\Application\OnLine\TransactionServer\Current\transactionserver.jar",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\CashWalletManager\CashWalletManager.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\QPonCashManager.exe"
        "\\APPSERVER-HN\D$\Galaxis\Program\StarTable\Startable.jar",
        "\\APPSERVER-HN\D$\Galaxis\Program\bin\TableBackOffice.exe",
        "\\APPSERVER-HN\D$\Galaxis\Program\StarTable\Tablemaster.jar",
        "\\APPSERVER-HN\D$\Galaxis\Program\StarTable\Tablereports.jar",
        "\\APPSERVER-HN\C$\Program Files (x86)\Modulus\Jackpot Applications\CasinoSettings\CasinoSettings.exe",
        "\\APPSERVER-HN\C$\Program Files (x86)\Modulus\Jackpot Applications\Configuration\JpConfiguration.exe",
        "\\APPSERVER-HN\C$\Program Files (x86)\Modulus\Jackpot Applications\Monitoring\JpMonitoring.exe",
        "\\APPSERVER-HN\C$\Program Files (x86)\Modulus\Jackpot Reporting\Reporting\JpReporting.exe",
        "\\APPSERVER-HN\C$\Program Files (x86)\Modulus\SecurityServer Configuration\Config\SecurityServerConfiguration.exe",
        "\\DBSERVER-HN\D$\OnlineData\Dbx\bin\dbx.exe",
        "\\FLOORSERVER-HN\d$\OnlineData\bin\bome3sh.exe",
        "\\FLOORSERVER-HN\d$\OnlineData\bin\Boss.exe",
        "\\FLOORSERVER-HN\d$\OnlineData\bin\cweb.tbc",
        "\\FLOORSERVER-HN\d$\OnlineData\bin\Excbuf.exe",
        "\\FLOORSERVER-HN\d$\OnlineData\bin\fsc.exe",
        "\\FLOORSERVER-HN\d$\OnlineData\bin\pinit.exe"	
    )

    $DB_HN  = Get-MOD-DB-hostname
    $APP_HN = Get-MOD-APP-hostname
    $FS_HN  = Get-MOD-FS-hostname
    
    #replacing
    $files = $files.replace('APPSERVER-HN',$APP_HN).replace('DBSERVER-HN',$DB_HN).replace("FLOORSERVER-HN",$FS_HN)

    # Loop through directories and collect file checksums
    $results = foreach ($file in $files) {
        Get-ChildItem $file -Recurse -File | ForEach-Object {
            $filePath = $_.FullName
            $sha1 = (Get-FileHash -Algorithm SHA1 -Path $filePath).Hash
            $md5 = (Get-FileHash -Algorithm MD5 -Path $filePath).Hash

            [PSCustomObject]@{
                'File' = $filePath
                'SHA1' = $sha1
                'MD5' = $md5
            }
        }
    }

    # Format and display the output
    $results | Sort-Object File | format-table -AutoSize
}
#endregion

#region --- component config and version handling
function get-MOD-Component-Config {
    param (
        [string]$ComponentName,
        [string]$ConfigName
    )
   $Component = Get-MOD-Component -all $ComponentName

   if ($ConfigName -ne "") {
    $config = $Component.ConfigFiles | Where-Object { $_.name -eq $ConfigName }
    Return $config.path
   }

   Return $Component.ConfigFiles
}

function Get-MOD-Component-Version {
    param (
        [string]$ComponentName
    )
    $Component = Get-MOD-Component -all $ComponentName
    $version = $Component.version 
    Return $version
}

#endregion

#region --- component handling
function Get-MOD-Component {
    param (
        [switch]$All,
        [switch]$Tools,
        [switch]$Modules,
        [switch]$Databases,
        [switch]$installed,
        [string]$Name
    )

    $jsonContent = Get-Components

    # Validation: Ensure only one of the flags is specified (except for -installed or -name)
    $specifiedFlags = @($Tools, $Modules, $Databases, $All) | Where-Object { $_ }

    if ($specifiedFlags.Count -gt 1) {
        throw "Specify only one of the following: -Tools, -Modules, -Databases, or -All."
    }

    # Load items based on the switch used
    $i = @()

    if ($All) {
        # Combine all items if -all is specified
        $items += $jsonContent.databases
        $items += $jsonContent.tools
        $items += $jsonContent.modules
    } elseif ($Tools) {
        $items = $jsonContent.tools
    } elseif ($Modules) {
        $items = $jsonContent.modules
    } elseif ($Databases) {
        $items = $jsonContent.databases
    } else {
        throw "Specify one of the following flags: -Tools, -Modules, -Databases, or -All."
    }

    # Apply name filtering if provided
    if ($Name) {
        $items = $items | Where-Object { $_.name -eq $Name }
    }

    # Apply installed filter if specified
    if ($installed) {
        $items = $items | Where-Object { $_.installed -eq $true }
    }

    # Return results
    return $items
}

function Set-MOD-Component {
    param (
        [switch]$Tools,
        [switch]$Modules,
        [switch]$Databases,
        [string]$Name,
        [hashtable]$Updates  # Hashtable to hold updates
    )

    $jsonContent = Get-Components

    # Load the correct section of the JSON based on the flag
    $itemToUpdate = $null

    if ($Tools) {
        $itemToUpdate = $jsonContent.tools | Where-Object { $_.name -eq $Name }
    } elseif ($Modules) {
        $itemToUpdate = $jsonContent.modules | Where-Object { $_.name -eq $Name }
    } elseif ($Databases) {
        $itemToUpdate = $jsonContent.databases | Where-Object { $_.name -eq $Name }
    } else {
        throw "Specify one of the following flags: -Tools, -Modules, or -Databases."
    }

    # Validate if the item exists
    if (-not $itemToUpdate) {
        throw "Item with the name '$Name' not found in the specified category."
    }

    # Apply updates from the hashtable
    foreach ($key in $Updates.Keys) {
        if ($itemToUpdate.PSObject.Properties.Name -contains $key) {
            $itemToUpdate.$key = $Updates[$key]
        } else {
            throw "Property '$key' does not exist on the item '$Name'."
        }
    }

    # Save updated content back to the JSON file
    #TODO: maybe rework without hardcoded path
    $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\components.json"

    Write-Host "Item '$Name' updated successfully." -ForegroundColor Green
}

function Show-MOD-Components {
    Show-MOD-Databases
    Show-MOD-Tools
    Show-MOD-Modules
}

function Show-MOD-Modules {
    $installed = Get-MOD-Component -Modules -installed
    if ($installed.Count -gt 0) {
        write-host "Modules on this server:" -ForegroundColor Yellow
        $installed | Format-Table -AutoSize -Property Name, Version
    } else {
        #Write-Host "No installed Modules found (yet!) - try 'Assert-MOD-Components' and retry!" -ForegroundColor Gray
    }
}

function Show-MOD-Tools {
    $installed = Get-MOD-Component -Tools -installed
    if ($installed.Count -gt 0) {
        write-host "Tools on this server:" -ForegroundColor Yellow
        $installed | Format-Table -AutoSize -Property Name, Version
    } else {
        #Write-Host "No installed Tools found (yet!) - try 'Assert-MOD-Components' and retry!" -ForegroundColor Gray
    }
}

function Show-MOD-Databases {
    $installed = Get-MOD-Component -Databases -installed
    if ($installed.Count -gt 0) {
        Write-Host "Databases on this server:" -ForegroundColor Yellow
        $installed | Format-Table -AutoSize -Property Name, Version
    } else {
        #Write-Host "No installed Databases found (yet!) - try 'Assert-MOD-Components' and retry!" -ForegroundColor Gray
    }
}

function Assert-MOD-Components {
    param (
        [switch]$Silent
    )

    $jsonContent = Get-Components
    if (-not $jsonContent) {
        throw "Failed to load JSON data from Get-Components."
    }

    $updatesMade = $false
    $ResetVersion = "0.0.0"

    foreach ($category in $jsonContent.PSObject.Properties.Name) {
        $components = $jsonContent.$category

        foreach ($component in $components) {
            $componentName = $component.name
            $isInstalled   = $false
            $updateVersion = $null

            if (-not $Silent) {
                Write-Host "Checking $componentName in category $category..."
            }

            if (Test-Path -Path $component.path) {
                $isInstalled = $true

                if ($component.PSObject.Properties["binary"] -and $component.binary) {
                    if (Test-Path -Path $component.binary) {
                        $binaryVersion = Get-BinaryVersion -binaryPath $component.binary
                        if ($binaryVersion) {
                            $updateVersion = $binaryVersion -replace ',', '.'
                        }
                    } else {
                        $updateVersion = $ResetVersion
                    }
                } else {
                    $updateVersion = $ResetVersion  # No binary field
                }

                if ($component.PSObject.Properties["service"] -and $component.service) {
                    $serviceExists = Get-Service -Name $component.service -ErrorAction SilentlyContinue
                    if (-not $serviceExists) {
                        $isInstalled = $false
                    }
                }
            }

            # NEW: if ultimately not installed, force version reset
            if (-not $isInstalled) {
                $updateVersion = $ResetVersion
            }

            $jsonComponent = $jsonContent.$category | Where-Object { $_.name -eq $componentName }

            if ($jsonComponent.installed -ne $isInstalled -or ($updateVersion -and $jsonComponent.version -ne $updateVersion)) {
                $jsonComponent.installed = $isInstalled
                if ($updateVersion -and $jsonComponent.version -ne $updateVersion) {
                    $jsonComponent.version = $updateVersion
                }
                $updatesMade = $true

                if (-not $Silent) {
                    $displayVersion = if ($isInstalled) { $updateVersion } else { "Not Installed" }
                    Write-Host "    Updated $componentName with installed: $isInstalled, version: $displayVersion" -ForegroundColor Yellow
                }
            } elseif (-not $Silent) {
                Write-Host "    No changes needed for $componentName." -ForegroundColor Green
            }
        }
    }

    if ($updatesMade) {
        $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\components.json"
        Write-Host "Updated modulus-toolkit components!" -ForegroundColor Yellow
    } else {
        #Write-Host "No changes detected." -ForegroundColor DarkGray
    }
}
#endregion

#region --- some weird handling to hide the toolkit
function Reset-ModulusContext {
    $token = "C:\Program Files\PowerShell\Modules\modulus-toolkit\elevated-token"

    function Confirm-Deletion ($filePath) {
        if (Test-Path -Path $filePath) {
            $fileName = [System.IO.Path]::GetFileName($filePath)  # Extract just the filename
            #Write-Host "DEBUG: Attempting to delete $filePath (Filename: $fileName)" -ForegroundColor Yellow
            $response = Read-Host ("Do you want to remove " + $fileName + "? (Y/N)")
            if ($response -match "^[Yy]$") {
                Remove-Item -Path $filePath -Force
                Write-Host "$fileName removed." -ForegroundColor Green
            } else {
                Write-Host "$fileName was not removed." -ForegroundColor Red
            }
        }
    }

    Confirm-Deletion $token
    Remove-Item -Path Env:MODULUS_KEY -ErrorAction SilentlyContinue

    # Ask before reloading the profile
    $reloadResponse = Read-Host "Do you want to reload the profile? (Y/N)"
    if ($reloadResponse -match "^[Yy]$") {
        Reload-Profile
        Write-Host "Profile reloaded." -ForegroundColor Green
    } else {
        Write-Host "Profile was not reloaded." -ForegroundColor Red
    }

    Clear-Host
}
Set-Alias -Name Modulus-Out -Value Reset-ModulusContext
#endregion

#region --- 7zip extraction
function Expand-7ZipFile {
    param (
        [string]$SourceFolder,
        [string]$TargetFolder,
        [string]$FilePattern = "*.7z",
        [string]$Subfolder = "",
        [string]$7ZipPath = "C:\Program Files\7-Zip\7z.exe"
    )

    $file = Get-ChildItem -Path $SourceFolder -Filter $FilePattern | Select-Object -First 1
    if (-not $file) {
        Write-Warning "No files found matching pattern '$FilePattern' in folder '$SourceFolder'."
        return $false
    }

    if (-not (Test-Path $7ZipPath)) {
        Write-Error "7z executable not found at $7ZipPath"
        return $false
    }

    $arguments = @(
        'x',
        "`"$($file.FullName)`"",
        "-o`"$TargetFolder`"",
        '-y'
    )

    if (-not [string]::IsNullOrWhiteSpace($Subfolder)) {
        $arguments += $Subfolder
    }

    Write-Progress -Activity "Extracting" -Status $file.Name -PercentComplete 0

    #$process = Start-Process -FilePath $7ZipPath -ArgumentList $args -NoNewWindow -Wait -PassThru
    #$process = Start-Process -FilePath $7ZipPath -ArgumentList $args -NoNewWindow -Wait -RedirectStandardOutput $null -RedirectStandardError $null
    
    $tempOut = [System.IO.Path]::GetTempFileName()
    $tempErr = [System.IO.Path]::GetTempFileName()

    $process = Start-Process -FilePath $7ZipPath -ArgumentList $arguments -NoNewWindow -Wait -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr -PassThru

    #$tempErr

    Remove-Item $tempOut, $tempErr -Force

    if ($process.ExitCode -eq 0) {
        Write-Progress -Activity "Extracting" -Status "Done" -Completed
        Write-Log "✔ Extraction of '$($file.Name)' complete." -ForegroundColor Green
        # Optionally clean up:

        return $true
    } else {
        Write-Log "❌ 7z exited with code $($process.ExitCode)"
        return $false
    }
}

#endregion

#region --- imp. copy function with progress bar
function Start-MOD-Copy {
    [CmdletBinding()]
    param (
          [Parameter(Mandatory = $true)]
            [string] $Source
        , [Parameter(Mandatory = $true)]
            [string] $Destination
		, [Parameter(Mandatory = $false)]
			[string] $CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS'
        , [Parameter(Mandatory = $false)]
            [string] $CustomLogPath        = 'default'
        , [int] $Gap = 200
        , [int] $ReportGap = 2000
    )
    # Define regular expression that will gather number of bytes copied
    $RegexBytes = '(?<=\s+)\d+(?=\s+)';

    #region Robocopy params
    # MIR = Mirror mode
    # NP  = Don't show progress percentage in log
    # NC  = Don't log file classes (existing, new file, etc.)
    # BYTES = Show file sizes in bytes
    # NJH = Do not display robocopy job header (JH)
    # NJS = Do not display robocopy job summary (JS)
    # TEE = Display log in stdout AND in target log file
    #$CommonRobocopyParams = '/MIR /NP /NDL /NC /BYTES /NJH /NJS';
    #$CommonRobocopyParams = '/E /Z /ZB /R:5 /W:5 /ndl'
    #endregion Robocopy params
 
    #region Robocopy Staging
    Write-Log "Analyzing robocopy job ..." DEBUG
    $StagingLogPath = '{0}\temp\{1} robocopy staging.log' -f $env:windir, (Get-Date -Format 'yyyy-MM-dd HH-mm-ss');

    $StagingArgumentList = '"{0}" "{1}" /LOG:"{2}" /L {3}' -f $Source, $Destination, $StagingLogPath, $CommonRobocopyParams;
    
    #Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList);
    Write-Log -Message ('Staging arguments: {0}' -f $StagingArgumentList) DEBUG

    Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -NoNewWindow;
    # Get the total number of files that will be copied
    $StagingContent = Get-Content -Path $StagingLogPath;
    $TotalFileCount = $StagingContent.Count - 1;

    # Get the total number of bytes to be copied
    #[RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | % { $BytesTotal = 0; } { $BytesTotal += $_.Value; };
    # % -> ForEach-Object
    
    [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | ForEach-Object { $BytesTotal = 0; } { $BytesTotal += $_.Value; };

    <#possible workaround for %
        $BytesTotal = 0
        [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | ForEach-Object {
            $BytesTotal += $_.Value
        }       
    #>

    Write-Log -Message ('Total bytes to be copied: {0}' -f $BytesTotal) DEBUG
    #endregion Robocopy Staging

    #region Start Robocopy
    # Begin the robocopy process
    
    #attempt to change log-path
    #$RobocopyLogPath = '{0}\temp\{1} robocopy.log' -f $env:windir, (Get-Date -Format 'yyyy-MM-dd HH-mm-ss');
    if($CustomLogPath -eq 'default') {
        $RobocopyLogPath = '{0}\temp\{1} robocopy.log' -f $env:windir, (Get-Date -Format 'yyyy-MM-dd HH-mm-ss');
    } else {
        $RobocopyLogPath = '{0}_{1}.log' -f $CustomLogPath, (Get-Date -Format 'yyyy-MM-dd HH-mm-ss');
    }

    $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $Source, $Destination, $RobocopyLogPath, $Gap, $CommonRobocopyParams;
    Write-Log -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList) DEBUG
    $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -NoNewWindow;
    Start-Sleep -Milliseconds 100;
    #endregion Start Robocopy

    #region Progress bar loop
    while (!$Robocopy.HasExited) {
        Start-Sleep -Milliseconds $ReportGap;
        $BytesCopied = 0;
        $LogContent = Get-Content -Path $RobocopyLogPath;
        $BytesCopied = [Regex]::Matches($LogContent, $RegexBytes) | ForEach-Object -Process { $BytesCopied += $_.Value; } -End { $BytesCopied; };
        $CopiedFileCount = $LogContent.Count - 1;
        Write-Log -Message ('Bytes copied: {0}' -f $BytesCopied) DEBUG
        Write-Log -Message ('Files copied: {0}' -f $LogContent.Count) DEBUG
        $Percentage = 0;
        if ($BytesCopied -gt 0) {
           $Percentage = (($BytesCopied/$BytesTotal)*100)
        }
        Write-Progress -Activity Robocopy -Status ("Copied {0} of {1} files; Copied {2} of {3} bytes" -f $CopiedFileCount, $TotalFileCount, $BytesCopied, $BytesTotal) -PercentComplete $Percentage
    }
    #endregion Progress loop

    Write-Progress -Activity "Robocopy" -Completed

    #region Function output
    [PSCustomObject]@{
        BytesCopied = $BytesCopied;
        FilesCopied = $CopiedFileCount;
    };
    #endregion Function output
}
#endregion

#region --- toolkit update functions
function Find-Toolkit-Updates {
    $hostname = Get-MOD-APP-hostname
    $unc = "\\$hostname\I"
    
    $ok = Confirm-DriveMounted -Letter "I" -Unc $unc -Retries 2 -WaitMs 500 #-Credential:$Credential
    if (-not $ok) { 
        #write-Host "Failed to mount I: at '$unc'" -ForegroundColor Red
        return 
    } 

    $SourcesDir = Get-SourcesPath
    $ModuleName = "modulus-toolkit"

    if (-not (Test-Path $SourcesDir)) { write-host "SourcesDir '$SourcesDir' does not exist. blub" -ForegroundColor Red; return }
        $moduleRoot    = Get-ModuleRoot -Name $ModuleName
        $currentVer    = Get-CurrentVersion -ModuleRoot $moduleRoot
        $archives      = Get-AvailableArchives -Dir $SourcesDir

    if (-not $archives) {
        #Write-Verbose "No matching archives in $SourcesDir."
        #return [pscustomobject]@{ Updated=$false; Reason="No archives found"; CurrentVersion=$currentVer; NewVersion=$null }
        Return
    }

    $candidate = $archives |
        Where-Object { $_.Version -gt $currentVer } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        #Write-Verbose "No newer version than $currentVer."
        #return [pscustomobject]@{ Updated=$false; Reason="Already up to date"; CurrentVersion=$currentVer; NewVersion=$currentVer }
    } else {
        Write-host "Found a newer version of the toolkit: $($candidate.Version) ($($candidate.Name))" -ForegroundColor Yellow
        Write-Host "You can update the toolkit by running 'Update-Toolkit'." -ForegroundColor Yellow
    }
}

function Update-Toolkit {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ScriptBlock] $OnUpdated
    )
    
    $SourcesDir = Get-SourcesPath
    $ModuleName = "modulus-toolkit"

    #begin
    try {
        if (-not (Test-Path $SourcesDir)) { throw "SourceDir '$SourcesDir' does not exist. blab" }
        $moduleRoot    = Get-ModuleRoot -Name $ModuleName
        $currentVer    = Get-CurrentVersion -ModuleRoot $moduleRoot
        $archives      = Get-AvailableArchives -Dir $SourcesDir

        if (-not $archives) {
            Write-Verbose "No matching archives in $SourcesDir."
            return [pscustomobject]@{ Updated=$false; Reason="No archives found"; CurrentVersion=$currentVer; NewVersion=$null }
        }

        $candidate = $archives |
            Where-Object { $_.Version -gt $currentVer } |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $candidate) {
            Write-Verbose "No newer version than $currentVer."
            return [pscustomobject]@{ Updated=$false; Reason="Already up to date"; CurrentVersion=$currentVer; NewVersion=$currentVer }
        }


        Write-Log "Current: $currentVer"
        Write-Log "Update : $($candidate.Version) ($($candidate.Name))"

        if ($PSCmdlet.ShouldProcess($moduleRoot, "Update $ModuleName to $($candidate.Version)")) {

            # Extract into a temp folder first
            $prep = Get-PrepPath

            Write-Log "Extracting $($candidate.Name) -> $prep\modulus-toolkit"
            $filePattern = 'modulus-toolkit*.7z'
            Expand-7ZipFile -SourceFolder $($candidate.File) -TargetFolder "$prep\modulus-toolkit" -FilePattern $filePattern -Subfolder "modulus-toolkit\*"

            # Overlay onto module directory (add/remove files)
            Write-log "Deploying to $moduleRoot"
            Write-Log "Full logs are available at:"
            $logs     = Get-LogsPath
            $logname = 'Update-modulus-toolkit_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'
            
            $package = Get-ChildItem $prep -filter modulus-toolkit* -Attributes Directory | ForEach-Object { $_.FullName }
            
            #robocopy $package $moduleRoot /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname
            robocopy $package "C:\Program Files\PowerShell\Modules\" /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname
            
            Write-Log "Please verify the deployment result:" DEBUG
            Get-Content $logs\$logname -Tail 11 | ForEach-Object {
                $line = $_.Trim()
                if (-not $line) { return }
                Write-Log $line -Level DEBUG
            }
            $updated = $true

            return [pscustomobject]@{
                Updated        = $updated
                CurrentVersion = $currentVer
                NewVersion     = $candidate.Version
                ModulePath     = $moduleRoot
                Archive        = $candidate.Name
            }
        }
    }
    catch {
        write-Log "An error occurred during the update process: $_" ERROR
        #Write-Log $_ ERROR
        return [pscustomobject]@{ Updated=$false; Error=$_.Exception.Message }
    }
    finally {
        if ($updated) {
            Write-Log "Update-Toolkit completed!" INFO
            
            #TODO: rework, rethink this part - jörg updated, deleted everything from "deployment-manifest.json" - this file should not be used, it was due to old code
            #caused an issue because it cleans up with the old code, and then it breaks.
            #if (Get-ElevatedState) {
            #    #Optional: Call cleanup function to remove old files
            #    if (Confirm-YesNo -Message "Do you want to clean your modulus-toolkit directory and remove unnecessary files?" -Default "Yes") {
            #        Reset-ToolkitState
            #    }
            #}
            
            Write-Log "Reloading profile to apply changes..." WARNING
            Reload-Profile
        }
    }
    #end
    
    #Return;
    
    #if (Test-InternetConnection) {
    #    Invoke-RestMethod https://raw.githubusercontent.com/LT1911/modulus-toolkit-release/main/update-modulus-toolkit.ps1 | Invoke-Expression  
    #}
    #else {
    #    Write-Log "No internet connection." ERROR
    #}
}
#endregion

#region --- overwrite PowerShell profile with Modulus profile
function Initialize-ModulusProfile {
    # This function initializes the Modulus-Toolkit profile for the current user.
    # It handles directory creation and provides guidance if blocked by Windows Security (Controlled Folder Access).
    # Returns $true if the profile is successfully initialized or already up-to-date, $false on failure.

    # --- Variable Setup ---
    $SourceProfile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\Microsoft.PowerShell_profile.ps1"
    
    # Destination path: $PROFILE refers to the CurrentUserCurrentHost profile
    $DestinationProfile = $PROFILE
    $DestinationDir = Split-Path -Path $DestinationProfile -Parent
    $ModuleName = "Modulus-Toolkit"
    
    # --- Pre-Checks ---
    if (-not (Test-Path -Path $SourceProfile)) {
        Write-Host "Source profile not found: '$SourceProfile'. Cannot initialize." -ForegroundColor Red
        return $false
    }
    
    # --- Directory Creation Logic ---
    if (-not (Test-Path -Path $DestinationDir)) {
        Write-Host "Current user profile directory not found: '$DestinationDir'." -ForegroundColor Yellow
        Write-Host "Attempting to create directory..."

        try {
            # Attempt to create the directory (e.g., C:\Users\User\Documents\PowerShell)
            New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null
            
            if (-not (Test-Path -Path $DestinationDir)) {
                # This throws a standard error if the initial New-Item didn't throw one
                throw "Directory creation failed unexpectedly after New-Item -Force."
            }
            Write-Host "Successfully created profile directory: '$DestinationDir'." -ForegroundColor Green

        } catch {
            $ErrorMessage = $_.Exception.Message
            
            # **Controlled Folder Access Check**
            # Check for common "Access Denied" or permission-related messages
            if ($ErrorMessage -match "Access to the path .* is denied" -or $ErrorMessage -match "UnauthorizedAccess") {
                
                Write-Error "🚨 Directory Creation Failed: Likely due to Windows Security (Controlled Folder Access)."
                Write-Host ""
                Write-Host "Action Required:" -ForegroundColor Red
                Write-Host "The application 'pwsh.exe' (PowerShell) is likely being blocked from writing to your Documents folder." -ForegroundColor White
                Write-Host ""
                Write-Host "1. Go to **Windows Security** (Search 'Windows Security')." -ForegroundColor Cyan
                Write-Host "2. Select **'Virus & threat protection'**." -ForegroundColor Cyan
                Write-Host "3. Under **'Ransomware protection'**, click **'Manage Controlled folder access'**." -ForegroundColor Cyan
                Write-Host "4. Select **'Allow an app through Controlled folder access'** and add the PowerShell executable:" -ForegroundColor Cyan
                Write-Host "   -> PowerShell 7: C:\Program Files\PowerShell\7\pwsh.exe" -ForegroundColor Yellow
                
                Write-Host ""
                Write-Host "Please allow the app and then re-run this function." -ForegroundColor Red
                
            } else {
                # Handle other unexpected errors
                Write-Error "Failed to create directory at '$DestinationDir'. An unexpected error occurred."
                Write-Error "Error Details: $($ErrorMessage)"
            }
            # Directory creation failed
            return $false 
        }
    }

    # --- Comparison and Copy Logic ---
    $ShouldCopy = $false
    
    if (-not (Test-Path -Path $DestinationProfile)) {
        Write-Host "Current user profile file for PowerShell not found. Initializing..." -ForegroundColor Yellow
        $ShouldCopy = $true
    } else {
        # Check if the existing profile file is different from the source template
        $SourceHash = (Get-FileHash -Path $SourceProfile -Algorithm SHA256).Hash
        $DestinationHash = (Get-FileHash -Path $DestinationProfile -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        
        if ($SourceHash -ne $DestinationHash) {
            Write-Host "User profile content differs from the $ModuleName template. Overwriting with the latest template." -ForegroundColor Cyan
            $ShouldCopy = $true
        }
    }
    
    # Perform the copy if necessary
    if ($ShouldCopy) {
        try {
            Copy-Item $SourceProfile -Destination $DestinationProfile -Force
            Write-Host "Successfully copied $ModuleName template to current user profile: '$DestinationProfile'." -ForegroundColor Green
            # Copy succeeded
            return $true
        } catch {
            Write-Error "Failed to copy profile: $($_.Exception.Message)"
            # Copy failed
            return $false
        }
    } else {
        # Profile is already initialized and up-to-date
        return $true
    }
}
#endregion

#Export-ModuleMember -Function * -Alias * -Variable *