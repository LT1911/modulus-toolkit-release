# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 09.09.2024

#write-host "Loading 1-core-init.psm1!" -ForegroundColor Green

#region --- global variables
$global:Vault = "modulus-toolkit"
#endregion

#region --- Toolkit elevation handling
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
        Write-Host "Elevated state enabled."
    } else {
        Remove-Item -Path $TokenFilePath -Force -ErrorAction SilentlyContinue
        Write-Host "Elevated state disabled."
    }
}

function Elevate-Toolkit {
    $expected = "54321doM"
    $password = Read-Host -Prompt "Please enter the password" -AsSecureString
    #Convert the secure string to plain text for comparison (not recommended for sensitive applications)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

    if ($plainPassword -eq $expected) {
        Set-ElevatedState -enable $True
        Reload-Profile
    } else {
        Write-Host "Wrong credential. No change!"
    }
}

function Suspend-Toolkit {
    Set-ElevatedState -enable $False
    Reload-Profile
}

<#backup Get-ElevatedState
function Get-ElevatedState {

    #if sysprep-key is found the system needs to be elevated
    $sysprepKey = Test-Path -Path 'C:\Program Files\PowerShell\Modules\modulus-toolkit\SP.key'
    if($sysprepKey) { return $true }

    $TokenFilePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\elevated-token"
    if (Test-Path $TokenFilePath) {
        $token = Get-Content $TokenFilePath | ConvertTo-SecureString
        if ($token.ToString() -eq (ConvertTo-SecureString "elevated" -AsPlainText -Force).ToString()) {
            return $true
        }
    }
    return $false
}
#>

function Get-ElevatedState {

    # if sysprep-key is found, the system needs to be elevated
    $sysprepKey = Test-Path -Path 'C:\Program Files\PowerShell\Modules\modulus-toolkit\SP.key'
    if ($sysprepKey) { 
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


function Reload-Profile {
    & "C:\Program Files\PowerShell\7\profile.ps1"
}
#endregion

#region --- initialization function definition
#test for internet connection
function Test-InternetConnection {
    try {
        Test-Connection -ComputerName "www.google.com" -Count 1 -Quiet
    } catch {
        return $false
    }
}

function Initialize-Environment {
    # Check if the environment variable 'MODULUS_SERVER' exists
    $modulusServer = [System.Environment]::GetEnvironmentVariable("MODULUS_SERVER", [System.EnvironmentVariableTarget]::Machine)

    #Write-Host "Initializing needed MODULUS_SERVER environment variable..." -ForegroundColor Green
    if (-not $modulusServer) {
        Write-host "The MODULUS_SERVER environment variable does not exist." -ForegroundColor Red

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
                Write-Host "$key. $($options[$key])" -ForegroundColor Yellow
            }

            # Ask the user to select an option
            $selection = Read-Host "Please choose an option (1-5)"

            # Validate the selection
            if ($selection -as [int] -and $options.ContainsKey([int]$selection)) {
                $selectedOption = $options[[int]$selection]
                $serverType = $serverValues[[int]$selection]  # Use the integer selection as key

                # Confirm the user's selection
                Write-Host "You selected: $selectedOption"
                $confirmation = Read-Host "Do you want to set MODULUS_SERVER to '$serverType'? (y/n)"

                if ($confirmation -eq 'y') {
                    # Set the environment variable only if confirmed
                    [System.Environment]::SetEnvironmentVariable("MODULUS_SERVER", $serverType, [System.EnvironmentVariableTarget]::Machine)
                    Write-Host "MODULUS_SERVER has been set to '$serverType'." -ForegroundColor Green
                    $confirmed = $true
					Return $true
                } else {
                    Write-Host "Selection not confirmed. Please try again." -ForegroundColor Yellow
                }
            } else {
                Write-Host "Invalid selection. Please choose a valid option (1-5)." -ForegroundColor Red
            }
        }
    } else {
        #Write-Host "MODULUS_SERVER environment variable already exists: $modulusServer" -ForegroundColor Green
		Return $true
    }
}

#initialize needed modules
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
                Write-Host "$module is not installed. Attempting to download..." -ForegroundColor Yellow
                try {
                    Install-Module -Name $module -Scope AllUsers -Force -ErrorAction Stop
                    Write-Host "$module installed successfully." -ForegroundColor Green
                } catch {
                    Write-Warning "Failed to install $module. Please ensure you have the necessary permissions and try again." 
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
            Write-Warning "Failed to import $module."
            if (-not $internetConnected) {
                Write-Host "Your environment is not connected to the internet!" -ForegroundColor Red
                Write-Host "Please provide the modules following modules manually to $ModulePath and retry!" -ForegroundColor Yellow
                foreach ($module in $Modules) {
                    write-host "- $module" -ForegroundColor Yellow
                }
            }
            $init = $False
            #return $false
        }
    }
    
    if (-not $init) {
        Write-warning "Loading modulus-toolkit failed because of missing prerequisites!"
        Write-warning "Exiting in 60 seconds!"
        Start-Sleep -Seconds 60
        Exit
    }
    #return $true
}

#function to initialize vault
function Initialize-Vault {
    param (
        [string]$Vault = $global:Vault
    )
    $defaultPassword = ConvertTo-SecureString ";-D" -AsPlainText -Force
    # Check if the vault exists
    if (-not (Get-SecretVault -Name $Vault -ErrorAction SilentlyContinue)) {
        Register-SecretVault -Name $Vault -ModuleName Microsoft.PowerShell.SecretStore
        Write-Host "Vault $Vault created." -ForegroundColor Yellow
        Set-SecretStoreConfiguration -Authentication None -Password $defaultPassword -Confirm:$false
        #Set-SecretStoreConfiguration -Authentication None -Confirm:$false
    }
    else {
        #Write-Host "Initializing module vault..." -ForegroundColor Green
    }
}

#function to set credentials
function Set-CredentialInVault {
    param (
        [string]$User,
        [string]$Domain = $null,
        [string]$Target,  # This can be Hostname or Database name
        [string]$Vault = $global:Vault
    )

    # Construct credential name based on domain/hostname and target
    $CredentialName = if ($Domain) { "$Domain\$User@$Target" } else { "$User@$Target" }

    # Check if the credential already exists
    if (Get-SecretInfo -Name $CredentialName -Vault $Vault -ErrorAction SilentlyContinue) {
        $overwrite = Read-Host "Credential $CredentialName already exists. Do you want to overwrite it? (y/n)"
        if ($overwrite -ne 'y') {
            Write-Host "Operation cancelled. Credential $CredentialName was not overwritten." -ForegroundColor Red
            return
        }
    }

    # Prompt for credential and store in vault
    $Credential = Get-Credential -UserName $User
    Set-Secret -Name $CredentialName -Secret $Credential -Vault $Vault
    Write-Host "Credential $CredentialName stored (or overwritten) in the vault." -ForegroundColor Green
    
    #TODO - maybe return the credential that was just inserted
    #Get-CredentialFromVault
}

#function to get credentials
function Get-CredentialFromVault {
    param (
        [string]$User,
        [string]$Domain = $null,
        [string]$Target,  # This can be Hostname or Database name
        [string]$Vault = $global:Vault
    )

    # Construct credential name based on domain/hostname and target
    $CredentialName = if ($Domain) { "$Domain\$User@$Target" } else { "$User@$Target" }

    # Try to retrieve the credential from the vault
    $Credential = Get-Secret -Name $CredentialName -Vault $Vault -ErrorAction SilentlyContinue

    if ($Credential) {
        Write-Host "Credential $CredentialName retrieved from the vault." -ForegroundColor Yellow
        return $Credential
    } else {
        Write-Host "Credential $CredentialName not found in the vault." -ForegroundColor Red
        return $null
    }
}

#function to remove credentials
function Remove-CredentialFromVault {
    param (
        [string]$User,
        [string]$Domain = $null,
        [string]$Target,  # This can be Hostname or Database name
        [string]$Vault = $global:Vault
    )

    # Construct credential name based on domain/hostname and target
    $CredentialName = if ($Domain) { "$Domain\$User@$Target" } else { "$User@$Target" }

    # Check if the credential exists before attempting to remove it
    if (Get-SecretInfo -Name $CredentialName -Vault $Vault -ErrorAction SilentlyContinue) {
        # Remove the secret from the vault
        Remove-Secret -Name $CredentialName -Vault $Vault
        Write-Host "Credential $CredentialName removed from the vault." -ForegroundColor Yellow
    } else {
        Write-Host "Credential $CredentialName not found in the vault." -ForegroundColor Red
    }
}

#function to disable the password requirement (unlock vault)
function Enable-VaultWithoutPassword {
    # Set the vault configuration to disable password requirement
    Set-SecretStoreConfiguration -Authentication None -Confirm:$false
    #Write-Host "Password requirement for SecretStore vault has been disabled."
}
#function to enable the password requirement (lock vault)
function Disable-VaultWithoutPassword {
    # Set the vault configuration to enable password requirement
    Set-SecretStoreConfiguration -Authentication Password -Confirm:$false
    #Write-Host "Password requirement for SecretStore vault has been enabled."
}

#function to find tool-binaries
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

#function to initialize aliases for commonly used tools
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

function Update-Toolkit {
    if (Test-InternetConnection) {
        Invoke-RestMethod https://raw.githubusercontent.com/LT1911/modulus-toolkit-release/main/update-modulus-toolkit.ps1 | Invoke-Expression  
    }
    else {
        Write-Host "No internet connection." -ForegroundColor Red
    }
}

#starting up the toolkit
Initialize-Modules -Modules @("PSIni", "Microsoft.PowerShell.SecretManagement","Microsoft.PowerShell.SecretStore")
Initialize-Vault -Vault $global:Vault
#Enable-VaultWithoutPassword

Initialize-Environment
Initialize-Tools

#might be good to set the 7z/np++ paths found here to the mod-components.json
#TODO: Set-MOD-Component ...




#region --- JSON handling for .\config\*.json
function Get-ModulePath {
    Return 'C:\Program Files\Powershell\Modules\modulus-toolkit\'
}

function Get-PlaceHolders {
    $configFile = Join-Path (Get-ModulePath) "config\mod-placeholders.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $configFile"
    }
}

function Get-PSConfig {
    $configFile = Join-Path (Get-ModulePath) "config\mod-PS-config.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $configFile"
    }
}

function Get-ENVConfig {
    $configFile = Join-Path (Get-ModulePath) "config\mod-ENV-config.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $configFile"
    }
}

function Get-VMConfig {
    $configFile = Join-Path (Get-ModulePath) "config\mod-VM-config.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $configFile"
    }
}

function Get-DB-Credentials {
    $configFile = Join-Path (Get-ModulePath) "config\mod-DB-credentials.json"
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $configFile"
    }
}

function Get-Components {
    $configFile = Join-Path (Get-ModulePath) "config\mod-components.json"
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

#region --- Get/Set-functions for mod-config.json
function Get-SourcesDir {
    
    $config = Get-PSConfig
    
    $sourcesDir = $config.directories.sources
    
    if (Test-Path $sourcesDir) {
        return $sourcesDir
    } else {
        throw "Folder does not exist: $sourcesDir"
    }
}

function Get-PrepDir {
    
    $config = Get-PSConfig
    
    $prepDir = $config.directories.prep
    
    if (Test-Path $prepDir) {
        return $prepDir
    } else {
        throw "Folder does not exist: $prepDir"
    }
}

function Get-GLXDir {
    
    $config = Get-PSConfig
    
    $GLXDir = $config.directories.Galaxis
    
    if (Test-Path $GLXDir) {
        return $GLXDir
    } else {
        throw "Folder does not exist: $GLXDir"
    }
}

function Get-LogsDir {
    
    $config = Get-PSConfig
    
    $logsDir = $config.directories.logs
    
    if (Test-Path $logsDir) {
        return $logsDir
    } else {
        throw "Folder does not exist: $logsDir"
    }
}
#endregion

#region --- to sort, probably not needed
<#
function Set-LogsDir {
    #TODO
}

function Set-GLXDir {
    #TODO
}

function Set-PrepDir {
    #TODO
}

function Set-SourcesDir {
    #TODO
}
#>

<#function for extracting with 7z with progress-bar, does not work!
function Extract-7ZipFileWithProgress {
    param (
        [string]$SourceFolder,
        [string]$TargetFolder,
        [string]$FilePattern = "*.7z",
        [string]$Subfolder = "",
        [string]$7ZipPath = "7z"
    )

    # Find the first matching file
    $file = Get-ChildItem -Path $SourceFolder -Filter $FilePattern | Select-Object -First 1

    if (-not $file) {
        Write-Warning "No files found matching pattern '$FilePattern' in folder '$SourceFolder'."
        return $false
    }

    # Get total size of the archive (in bytes)
    $totalSize = (Get-Item $file.FullName).Length

    # Initialize progress bar
    $progressActivity = "Extracting 7-Zip File"
    $progressStatus = "Extracting: $($file.Name)"
    Write-Progress -Activity $progressActivity -Status $progressStatus -PercentComplete 0

    # Start the extraction in a background job to allow real-time progress tracking
    Start-Job -ScriptBlock {
        param ($extractCommand)
        Invoke-Expression $extractCommand
    } -ArgumentList "$7ZipPath x `"$($file.FullName)`" -o`"$TargetFolder`" $Subfolder -y" | Out-Null

    try {
        # Track progress while extraction is ongoing
        do {
            Start-Sleep -Milliseconds 500 # Delay to prevent excessive CPU usage

            # Get the current size of extracted files (recursively in the target folder)
            $extractedSize = (Get-ChildItem -Path $TargetFolder -Recurse | Measure-Object -Property Length -Sum).Sum

            # Calculate percentage of completion
            $percentComplete = [math]::Round(($extractedSize / $totalSize) * 100, 2)

            # Update the progress bar
            Write-Progress -Activity $progressActivity -Status "$progressStatus ($percentComplete%)" -PercentComplete $percentComplete

        } while (Get-Job | Where-Object { $_.State -eq 'Running' })

        # Check if the job completed successfully
        $job = Get-Job | Where-Object { $_.State -ne 'Completed' }
        if ($job.State -eq 'Completed' -and $LASTEXITCODE -eq 0) {
            Write-Progress -Activity $progressActivity -Status "Extraction Complete" -PercentComplete 100
            Write-Host "Extraction of '$($file.Name)' completed successfully."
            return $true
        } else {
            Write-Host "Extraction failed with errors."
            return $false
        }
    } catch {
        Write-Error "An error occurred during extraction: $_"
        return $false
    } finally {
        Write-Progress -Activity $progressActivity -Status "Complete" -PercentComplete 100 -Completed
        # Clean up the background job
        Get-Job | Remove-Job
    }
}
#>
#endregion

#region --- shortcuts to open tools and applications from I: - no prereq
function NewDMM {
    $newDMM = "I:\Tools\NewDMM\Modulus NewDMM.lnk"
    if (Test-Path $newDMM)
    {
        #Unblock-File -Path $newDMM
        & $newDMM
    } else {
        write-host "$newDMM was not found! - Make sure you mapped I:-share!" -ForegroundColor Yellow
    }
}

function CleanRegistry {
    $clean = "I:\Tools\NewDMM\CleanRegistry.exe"
    if (Test-Path $clean)
    {
        #Unblock-File -Path $clean
        & $clean
    } else {
        write-host "$clean was not found! - Make sure you mapped I:-share!" -ForegroundColor Yellow
    }
}

function QB {
    $qb = "D:\Onlinedata\bin\qb.exe"
    if (Test-Path $qb)
    {
        #Unblock-File -Path $clean
        & $qb
    } else {
        write-host "$qb was not found! - Make sure you have it installed!" -ForegroundColor Yellow
    }
}
#endregion

#region --- weird helpers for deployment -> should be a proper confirmation logic at some point
#function for user input about Continue or Abort
function CoA {
   
    $yesno = Read-Host ' > Continue or abort? [Y/N]'					
    switch ($yesno.ToLower()) {
        y { write-host ' > Continuing...' ; Return $true }
        n { write-host ' > Aborting script!' ; Return $false }
        default { write-warning 'Invalid input, should be: Y/N' ; write-host '? - Invalid input! Aborting script!' ; Return $false }
    } 
}

#function for user input about hotfix confirmation
function Confirm-GLXHotfix {
    write-host '------------------'												-ForegroundColor Black -BackgroundColor Yellow
    write-host 'User-input needed:'												-ForegroundColor Black -BackgroundColor Yellow
    $yesno = Read-Host 'Do you want to start the hotfix? [y/n]'					
    switch ($yesno){
        Y { write-host 'Y - Starting script!' ;write-host 'Starting script!' ; Return $true }
        N { write-host 'N - Stopping script! No changes were made!' ; write-host 'Stopping script! No changes were made!' ; Return $false }
        default { write-warning 'Invalid input, should be: y/n' ; write-host '? - Invalid input! Aborting script!' ; Return $false }
    }
}
#endregion

#region --- list Galaxis sources in staging area
function Show-SourcesDir {
    $sourcesDir = Get-SourcesDir
    Get-ChildItem $sourcesDir | Format-Table Name, LastWriteTime
}
#endregion

#region --- list prepared Galaxis packages
function Show-PrepDir {
    $prepDir = Get-PrepDir
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

	if ($AskIf) {
        $confirm = Read-Host "Do you want to backup your current Galaxis directory?"
        if ($confirm -ne "Y") {
            Write-Output "User chose not to create a backup!"
            return
        }
    }

	$GLXDir = Get-GLXDir
	$backupDir = (Get-PSConfig).directories.backup

	#region checks
	#aborting if $Source does not exist
	if (!(Test-Path $GLXDir))
	{
		write-warning "Folder $GLXDir does not exist, aborting!"
		exit
	}

	#create $Destination if it does not exist already
	if(!(Test-Path $backupDir))
	{
		md $backupDir
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
		md $backupDir
		write-verbose "Creating folder: $backupDir"
	}
	#endregion

	#region robocopy params

	$XD = '"D:\Galaxis\Log", "D:\Galaxis\Application\OnLine\AlarmServer\Current\dat", "D:\Galaxis\Application\OnLine\AlarmServer\Current\log", "D:\Galaxis\Application\OnLine\SlotMachineServer\Current\dat", "D:\Galaxis\Application\OnLine\SlotMachineServer\Current\log", "D:\Galaxis\Application\OnLine\TransactionServer\Current\dat", "D:\Galaxis\Application\OnLine\TransactionServer\Current\log"'
	$XF = '"BDESC*", "*minidump*", "*.err", "FullLog*.txt", "ShortLog*.txt"'

	$params = '/MIR /NP /NDL /NC /BYTES /NJH /NJS /XD {0} /XF {1}' -f $XD, $XF;
	#/NP 	= no progress
	#/NDL	= no directory output
	#/NC	= no file class output
	#/BYTES = filesize in bytes, important for staging and progress-calc of mod-log function
	#/NJH	= no robocopy header
	#/NJS	= no robocopy summary
	#/XD 	= directories to be excluded
	#/XF	= files to be excluded
	#endregion


	mod-copy -Source $GLXdir -Destination $backupDir #-CommonRobocopyParams $params 

	write-host 'Backup done.'
}
function Backup-OnlineData {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

	if ($AskIf) {
        $confirm = Read-Host "Do you want to backup your current OnlineData directory?"
        if ($confirm -ne "Y") {
            Write-Output "User chose not to create a backup!"
            return
        }
    }

	$OLData = (Get-PSConfig).directories.OnlineData
	$backupDir = (Get-PSConfig).directories.backup

	#region checks
	#aborting if $Source does not exist
	if (!(Test-Path $OLData))
	{
		write-warning "Folder $OLData does not exist, aborting!"
		exit
	}

	#create $Destination if it does not exist already
	if(!(Test-Path $backupDir))
	{
		md $backupDir
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
		md $backupDir
		write-verbose "Creating folder: $backupDir"
	}
	#endregion

	#region robocopy params

	$XD = '"D:\OnlineData\Log", "D:\OnlineData\excata", "D:\OnlineData\jpdata", "D:\OnlineData\Relay\Logs", "D:\OnlineData\nginx\logs", "D:\OnlineData\FM\LOG", "D:\OnlineData\Dbx\log"'
	$XF = '"BDESC*", "*minidump*", "*.err", "FullLog*.txt", "ShortLog*.txt", "server*.log"'

	$params = '/MIR /NP /NDL /NC /BYTES /NJH /NJS /XD {0} /XF {1}' -f $XD, $XF;
	#/NP 	= no progress
	#/NDL	= no directory output
	#/NC	= no file class output
	#/BYTES = filesize in bytes, important for staging and progress-calc of mod-log function
	#/NJH	= no robocopy header
	#/NJS	= no robocopy summary
	#/XD 	= directories to be excluded
	#/XF	= files to be excluded
	#endregion


	mod-copy -Source $OLData -Destination $backupDir #-CommonRobocopyParams $params 

	write-host 'Backup done.'
}
#endregion

#region --- disclaimer about HF script #TODO-this needs to be reworked!
function Show-ScriptDisclaimer {
	write-host '         M O D U L U S                              ' 			-ForegroundColor Yellow #-BackgroundColor Yellow
	write-host '         -------------                              ' 			-ForegroundColor Yellow #-BackgroundColor Yellow
	write-host '                                      				' 			-ForegroundColor Yellow #-BackgroundColor Yellow
	write-host 'Starting Modulus hotfix update                      ' 			-ForegroundColor Yellow #-BackgroundColor Yellow
	write-host '---script v1.2----------------                      '			-ForegroundColor Yellow #-BackgroundColor Yellow
	write-host 'This script will do the following:                  '			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host ' - STOP your Galaxis services                       '			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host ' - CLEAN your Galaxis directory 					'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host ' - BACKUP your Galaxis directory (if you want!)		'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host ' - PREPARE the following packages:					'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host '    - Executable only								'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host '    - Config only									'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host '    - Other only									'			-ForegroundColor Yellow #-BackgroundColor Yellow
	#Write-host '    - Docker only									'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host '    - SYSTM Executable only							'	        -ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host '    - SYSTM Config only							    '	        -ForegroundColor Yellow #-BackgroundColor Yellow
	#Write-host '    - UncompressOnInstall							'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host ' - DEPLOY the prepared files 						'			-ForegroundColor Yellow #-BackgroundColor Yellow
	Write-host ' - START Galaxis services                           '			-ForegroundColor Yellow #-BackgroundColor Yellow
	#write-host '------------------------------                      '			-ForegroundColor Yellow #-BackgroundColor Yellow
	#write-host ' - Log can be found in .\logs\                      '			-ForegroundColor Yellow #-BackgroundColor Yellow
	write-host '------------------------------                      '			-ForegroundColor Yellow #-BackgroundColor Yellow
	write-host '                                                    '			-ForegroundColor Yellow #-BackgroundColor Yellow
}
#endregion

#region --- check currently installed Galaxis version (APP server only)
function Show-CurrentGLXVersion {
	$GLX = Get-GLXDir
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

#region --- readme.MD
function Open-MOD-Help {
	write-host " > Opening modulus-toolkit's help file!" -ForegroundColor Yellow
	$path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\README.md"
	if (Test-Path -path $path) {
        Start-Process "chrome.exe" "`"$path`""
    } else {
        Write-Host "Help file was not found at $path" -ForegroundColor Red
    }
}

#function to open GLX dictionary
function Open-MOD-Dictionary {
	write-host " > Opening modulus-toolkit's database dictionary for GLX!" -ForegroundColor Yellow
	$path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\GLX_dictionary.md"
	if (Test-Path -path $path) {
        Start-Process "chrome.exe" "`"$path`""
    } else {
        Write-Host "Dictionary file was not found at $path" -ForegroundColor Red
    }
}

#function to open all the manuals that we have!
function Open-MOD-Manual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("README_extended","1097","1099","Peripherals","Checklist","Workstation")]
        [string]$Manual
    )

    switch ($Manual) {
        "README_extended" { $path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\README_extended.md" }
        "1097" { $path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\1097_manual.md" }
        "1099" { $path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\1099_manual.md" }
        "Peripherals" { $path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\Peripherals.md" }
        "QPon-checklist" { $path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\QPon-checklist.md" }
        "Workstation" { $path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\Workstation.md" }
        Default { throw "Invalid manual: $Manual" }
    }

    Write-Host " > Opening modulus-toolkit's $Manual manual!" -ForegroundColor Yellow 
    if (Test-Path -path $path) {
        Start-Process "chrome.exe" "`"$path`""
    } else {
        Write-Host "Manual was not found at $path" -ForegroundColor Red
    }
}
#endregion

#region --- service-related functions 
function Show-MOD-Services {
	[CmdletBinding()] 
		param (
			#params not used at the moment, maybe which service or where to log
			#$log,
			#$logFile = "C:\modulus\logs\serviceLog.txt",
			#$logDir  = "C:\modulus\logs"
		)

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
 
	# Sort the services by their status (Running first, then Stopped)

    $GalaxisServices = $GalaxisServices | Sort-Object StartupType, Status, DisplayName

	#old output:
	#$GalaxisServices | Format-Table -Property Status, DisplayName -AutoSize 

    # Output the services with color-coded status
	write-host "
 Status DisplayName
 ------ -----------" -ForegroundColor Green
	
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
	[CmdletBinding()] 
		param (
			#params not used at the moment, maybe which service or where to log
			$log,
			$logFile = "C:\modulus\logs\serviceLog.txt",
			$logDir  = "C:\modulus\logs"
		)

	#first log entry
	#mod-log "Hello World!"
	#mod-log "Starting all Galaxis related services!"
	#mod-log "-------------------------------------"

	#mod-log "Starting RabbitMQ!"
	#$RMQ = Get-Service -Name "RabbitMQ" -ErrorAction SilentlyContinue
	#if($RMQ) {
	#	Start-Service $RMQ
	#	write-host 'RabbitMQ started!'
	#}
	
	#mod-log("Starting nginx if we have it!")
	#Get-Service -Name "nginx" | Start-Service						-ErrorAction SilentlyContinue
	#write-host 'nginx started!'
	#mod-log "Starting GalaxisStartupService!"
	$GSS = Get-Service -Name "GalaxisStartupService" -ErrorAction SilentlyContinue
	if($GSS) {
		Start-Service $GSS
		write-host 'GalaxisStartupService started!'
	} else {
		$pinit = Get-Service -Name "pinit" -ErrorAction SilentlyContinue
		if ($pinit) {
			Start-Service $pinit
			write-host "pinit started!"
		}
	}

	#giving the services some time to breath
	Start-Sleep -Seconds 5
	
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
				Write-Output $output
				#log entry
				#mod-log $output
			}
		}
	}
	
	#final log entry
	#mod-log "All Galaxis related services are stopped!"
	#mod-log "-----------------------------------------"
}

function Stop-MOD-Services {
	[CmdletBinding()] 
		param (
			#params not used at the moment, maybe which service or where to log
			$log,
			$logFile = "C:\modulus\logs\serviceLog.txt",
			$logDir  = "C:\modulus\logs"
		)
		
	#first log entry
	#mod-log "Hello World!"
	#mod-log "Stopping all Galaxis related services!"
	#mod-log "-------------------------------------"

	#mod-log "Stopping RabbitMQ!"
	$RMQ = Get-Service -Name "RabbitMQ" -ErrorAction SilentlyContinue
	if($RMQ) {
		Stop-Service $RMQ
		write-host 'RabbitMQ stopped!'
	}
	
	#mod-log("Stopping nginx if we have it!")
	#Get-Service -Name "nginx" | Stop-Service						-ErrorAction SilentlyContinue
	#write-host 'nginx stopped!'
	
	#wsl --shutdown
	
	#mod-log "Stopping GalaxisStartupService!"
	$GSS = Get-Service -Name "GalaxisStartupService" -ErrorAction SilentlyContinue
	if ($GSS)
	{
		Stop-Service $GSS
		write-host 'GalaxisStartupService stopped!'
	} else {
		$pinit = Get-Service -name "pinit" -ErrorAction SilentlyContinue
		if ($pinit) {
			Stop-Service $pinit
			write-host "pinit stopped!"
		}
	}

	
	#giving the services some time to breath
	Start-Sleep -Seconds 5
	
	$GLXservices = Get-Service -displayName "Galaxis*"

	foreach ($service in $GLXservices)
	{
		$status = (Get-Service -name $service.name).status 
		if ($status -eq "Running")
		{
			Stop-Service -Name $service.name
			$output =  "Stopped " + $service.name + "!"
			Write-Output $output
			#log entry
			#mod-log $output
		}
	}
	
	#final log entry
	#mod-log "All Galaxis related services are stopped!"
	#mod-log "-----------------------------------------"
}
#endregion

#TODO: rework, check missing stuff? use mod-compnent.json maybe? fill using this?
#region --- Open-* functions
function Open-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('ALL','hosts','Oracle','inittab','QB','JPApps','inittab','GDC','RTDS','AlarmServer','TransactionServer','SlotMachineServer','AddressBook','AML','AuthenticationService','Bus','BusHO','CashWalletManager','CashWalletService','Database','Datamart','MarketingDatamart','Messenger','QPonCash','Report','SlotDataExporter','TBL','triggermemberdataserver','CasinoSyncService','nginx','AMLService','GalaxisAPI','LicenseService','MessengerService','NotificationService','TableSetupService','JPS','Web')]
        [string]$Config
    )

    if ($Config -eq "ALL") {
       #list all of them?
       write-host " > Not implemented yet. Sorry!"
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
            Default { throw "Invalid Config: $Config" }
        }
    }
}

<# commented 14.10.2024 - do we need?
function Test-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('ALL','hosts','sqlnet.ora','tnsnames.ora','inittab','QB','JP-Applications','JP-Reporting','SecurityServerConfig','GDC','AlarmServer','TransactionServer','SlotMachineServer','AddressBook','AML','AuthenticationService','Bus','BusHO','CashWalletManager','CashWalletService','Database','Datamart','MarketingDatamart','Messenger','QPonCash','Report','SlotDataExporter','TBL','triggermemberdataserver','AMLService','GalaxisAPI','LicenseService','MessengerService','NotificationService','TableSetupService','nginx','reverse-proxy','JPS','Web')]
        [string]$Config
        #removed for now:
        #'CasinoSyncService'
        #TODO:
        #grouping:
        # - oracle
        # - RTDS
        # - JPApps
        # - CasinoSync
    )

    $serverScope = (Get-Config).$env:MODULUS_SERVER

    #grouping 
    #switch($Config) {
    #    "RTDS"      { 
    #        
    #        $serverScope | Where-Object { $_.child.type -like "*RTDS*" }
    #    
    #    }
    #    "JPApps"    {
    #
    #    }
    #    "CasinoSync"
    #    Default { throw "Invalid Config: $Config" }
    #}
    
    $reqConfig   = $serverScope.$Config

    if ($Config -eq "ALL") {
       #list all of them?
       write-host "Not implemented yet. Sorry!"
    } else {

        if (!(Test-Path $reqConfig.config)) {
            $file = $reqConfig.config
            write-host "Configuration file $file does not exist!"
            Return
        }
        if ($reqConfig.edit -eq 'np++') { np $reqConfig.config }
        if ($reqConfig.edit -eq 'bat')  { Invoke-Expression $reqConfig.config }
    }
}
#>

#TODO: rework, check missing stuff? use mod-compnent.json maybe? fill using this?
<#
function Open-ConfigFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('hosts','sqlnet.ora','tnsnames.ora','inittab','QB','JP-Applications','JP-Reporting','SecurityServerConfig','GDC','AlarmServer','TransactionServer','SlotMachineServer','AddressBook','AML','AuthenticationService','Bus','BusHO','CashWalletManager','CashWalletService','Database','Datamart','MarketingDatamart','Messenger','QPonCash','Report','SlotDataExporter','TBL','triggermemberdataserver','AMLService','GalaxisAPI','LicenseService','MessengerService','NotificationService','TableSetupService','nginx','reverse-proxy','JPS')]
        [string]$Config
    )
    $serverScope = (Get-Config).$env:MODULUS_SERVER
    $reqConfig   = $serverScope.$Config

    if (Test-Path $reqConfig.folder) { Invoke-Item $reqConfig.folder }

}
#>
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
       write-host "Not implemented yet. Sorry!"
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

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-IniContent $config
    $address = $content.SecurityServerConfig.Address
    $port    = $content.SecurityServerConfig.Port
    $connTO  = $content.SecurityServerConfig.ConnectionTimeOut 

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force
    Write-host "-"
    Write-host "JPApplicationSettings.ini:"
    Write-host "-"
    write-host "[SecurityServerConfig]"
    write-host "Address=$address"
    write-host "Port=$port"
    write-host "ConnectionTimeout=$connTO"
    write-host "-"
}

function Get-JPReporting-Config {
    #check if component is installed maybe?

    $config = get-MOD-Component-Config "Jackpot Reporting" "JPReportSettings.ini"

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-IniContent $config
    $address = $content.SecurityServerConfig.Address
    $port    = $content.SecurityServerConfig.Port
    $connTO  = $content.SecurityServerConfig.ConnectionTimeOut 

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force
    Write-host "-"
    Write-host "JPReportSettings.ini:"
    Write-host "-"
    write-host "[SecurityServerConfig]"
    write-host "Address=$address"
    write-host "Port=$port"
    write-host "ConnectionTimeout=$connTO"
    write-host "-"
}

function Get-SecurityServerConfig-Config {
    #check if component is installed maybe?

    $config = get-MOD-Component-Config "SecurityServer Configuration" "SecurityApplications.ini"

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content    = Get-IniContent $config
    $address    = $content.SecurityServerConfig.Address
    $port       = $content.SecurityServerConfig.Port
    $connTO     = $content.SecurityServerConfig.ConnectionTimeOut 
    $user       = $content.user.username
    $casino_id  = $content.DEFAULT_CASINO.ext_casino_id

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force
    Write-host "-"
    Write-host "SecurityApplicationSettings.ini:"
    Write-host "-"
    write-host "[SecurityServerConfig]"
    write-host "Address=$address"
    write-host "Port=$port"
    write-host "ConnectionTimeout=$connTO"
    write-host "-"
    write-host "[User]"
    write-host "UserName=$user"
    write-host "[DEFAULT_CASINO]"
    write-host "ext_casino_id=$casino_id"
}
#endregion

#region --- FS config
function Show-FS-Config {

    $fscfg = get-MOD-Component-Config "Floorserver" "fscfg.tcl85"

    if(Test-Path -Path $fscfg) {
        Write-host " > Opening $fscfg !" -ForegroundColor Green
        Invoke-Item $fscfg
    } else {
        write-host ">"
        write-host " > $fscfg cannot be found, please verify you are on a FS!" -ForegroundColor Red
    }
}
#endregion

#region --- AML - first test jörg
function Get-AML-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Getting            " -ForegroundColor Yellow
    write-host "         AML config!         " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow

    $config = get-MOD-Component-Config "Galaxis/SYSTM" "Aml.ini"

    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    $content    = Get-IniContent $config
    $provider   = $content.CONNECTION.PROVIDER
    $datasource = $content.CONNECTION.datasource
    $schema     = $content.CONNECTION.schema
    $username   = $content.CONNECTION.username
    $pw         = $content.CONNECTION.password

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force

    Write-host "-"
    Write-host "AML.ini:"
    Write-host "-"
    write-host "[CONNECTION]"
    write-host "PROVIDER=$provider"
    write-host "DATASOURCE=$datasource"
    write-host "SCHEMA=$schema"
    write-host "USERNAME=$username"
    write-host "PASSWORD=$pw"
    write-host "-"
    write-host "-----------------------------" -ForegroundColor Green
}

function Set-AML-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Getting            " -ForegroundColor Yellow
    write-host "         AML config!         " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow

    $config = get-MOD-Component-Config "Galaxis/SYSTM" "Aml.ini"

    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    $general_settings = Get-MOD-GeneralSettings
    $DB = $general_settings.databases.GLX_DB
    $DBofficeIP = (Get-MOD-DB-OFFICE-NIC).IPAddress

    $content = Get-IniContent $config

    #$content.SecurityServerConfig.Address = $serverConfig.networkAdapters.OFFICE.IP
    #$content.SecurityServerConfig.Port = 1666
    #$content.SecurityServerConfig.ConnectionTimeOut = 21
    #$content.CONNECTION.PROVIDER = ''

    $content.CONNECTION.datasource = "//" + $DBofficeIP + ":1521/" + $DB

    write-host "TODO: credential management!" -ForegroundColor Red

    #$content.CONNECTION.schema
    #$content.CONNECTION.username
    #$content.CONNECTION.password

    Out-IniFile -InputObject $content -FilePath $config -Force
    write-host "-----------------------------" -ForegroundColor Green
}

#endregion

#region --- DataBase.ini - second test Jörg
function Get-DatabaseINI-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Getting            " -ForegroundColor Yellow
    write-host "       Database.ini!         " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "Database.ini"

    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    $content = Get-IniContent $config
    #[CONNEXION]
    $datasource  = $content.CONNEXION.DATASOURCE
    $nombde = $content.CONNEXION.NOMBDE
    $TYPEDEBASE = $content.CONNEXION.TYPEDEBASE
    $BIBLIOTHEQUEBASE = $content.CONNEXION.BIBLIOTHEQUEBASE
    $BIBLIOTHEQUEFIDELIS = $content.CONNEXION.BIBLIOTHEQUEFIDELIS
    $BIBLIOTHEQUECLIENT = $content.CONNEXION.BIBLIOTHEQUECLIENT
    $BIBLIOTHEQUEJEUX = $content.CONNEXION.BIBLIOTHEQUEJEUX
    $BIBLIOTHEQUEBASECOMMUN = $content.CONNEXION.BIBLIOTHEQUEBASECOMMUN
    $BIBLIOTHEQUEFIDELISCOMMUN = $content.CONNEXION.BIBLIOTHEQUEFIDELISCOMMUN
    $BIBLIOTHEQUEJEUXCOMMUN = $content.CONNEXION.BIBLIOTHEQUEJEUXCOMMUN
    $BIBLIOTHEQUECLIENTCOMMUN = $content.CONNEXION.BIBLIOTHEQUECLIENTCOMMUN
    $USERNAME = $content.CONNEXION.'USER NAME'
    $PASSWORD = $content.CONNEXION.PASSWORD
    $NOMSERVEURCOM = $content.CONNEXION.NOMSERVEURCOM
    $NOMPROCEDURESTOCKEEMOUVEMENT = $content.CONNEXION.NOMPROCEDURESTOCKEEMOUVEMENT
    $CASINOID = $content.CONNEXION.CASINOID

    #[GENERAL]
    $SOCIETE = $content.GENERAL.SOCIETE
    $ETABLISSEMENT = $content.GENERAL.ETABLISSEMENT

    #[CASHLESS]
    $NOMBDECL = $content.CASHLESS.NOMBDECL
    $TYPEDEBASECL = $content.CASHLESS.TYPEDEBASECL
    $USERNAMECL = $content.CASHLESS.USERNAMECL
    $PASSWORDCL = $content.CASHLESS.PASSWORDCL
    $NORMALTIMEOUT = $content.CASHLESS.NORMALTIMEOUT
    $EXTENDEDTIMEOUT = $content.CASHLESS.EXTENDEDTIMEOUT

    #$content.SecurityServerConfig.ConnectionTimeOut  = 20
    #Out-IniFile -InputObject $content -FilePath $config -Force

    Write-host "-"
    Write-host "Database.ini:"
    Write-host "-"
    write-host "[CONNEXION]"
    write-host "DATASOURCE = $datasource"
    write-host "NOMBDE = $nombde"    
    write-host "TYPEDEBASE = $TYPEDEBASE"
    write-host "BIBLIOTHEQUEBASE = $BIBLIOTHEQUEBASE"
    write-host "BIBLIOTHEQUEFIDELIS = $BIBLIOTHEQUEFIDELIS"
    write-host "BIBLIOTHEQUECLIENT = $BIBLIOTHEQUECLIENT"
    write-host "BIBLIOTHEQUEJEUX = $BIBLIOTHEQUEJEUX"
    write-host "BIBLIOTHEQUEBASECOMMUN = $BIBLIOTHEQUEBASECOMMUN"
    write-host "BIBLIOTHEQUEFIDELISCOMMUN = $BIBLIOTHEQUEFIDELISCOMMUN"
    write-host "BIBLIOTHEQUEJEUXCOMMUN = $BIBLIOTHEQUEJEUXCOMMUN"
    write-host "BIBLIOTHEQUECLIENTCOMMUN = $BIBLIOTHEQUECLIENTCOMMUN"
    write-host "USERNAME = $USERNAME"
    write-host "PASSWORD = $PASSWORD"
    write-host "NOMSERVEURCOM = $NOMSERVEURCOM"
    write-host "NOMPROCEDURESTOCKEEMOUVEMENT = $NOMPROCEDURESTOCKEEMOUVEMENT"
    write-host "CASINOID = $CASINOID"
    write-host "-"
    write-host "[GENERAL]"
    write-host "SOCIETE = $SOCIETE"
    write-host "ETABLISSEMENT = $ETABLISSEMENT"
    write-host "-"
    write-host "[CASHLESS]"
    write-host "NOMBDECL = $NOMBDECL"
    write-host "TYPEDEBASECL = $TYPEDEBASECL"
    write-host "USERNAMECL = $USERNAMECL"
    write-host "PASSWORDCL = $PASSWORDCL"
    write-host "NORMALTIMEOUT = $NORMALTIMEOUT"
    write-host "EXTENDEDTIMEOUT = $EXTENDEDTIMEOUT"
    write-host "-----------------------------" -ForegroundColor Green
}

function Set-DatabaseINI-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "       Database.ini!         " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "Database.ini"

    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    $general_settings = Get-MOD-GeneralSettings
    $DBofficeIP       = (Get-MOD-DB-OFFICE-NIC).IPAddress
    $APPhostname      = Get-MOD-APP-hostname
    $USERS            = Get-DB-Credentials

    $content = Get-IniContent $config
    #$content.SecurityServerConfig.Address = $serverConfig.networkAdapters.OFFICE.IP
    #$content.SecurityServerConfig.Port = 1666
    #$content.SecurityServerConfig.ConnectionTimeOut = 21

    #[CONNEXION]
    $content.CONNEXION.DATASOURCE = "//" +$DBofficeIP+ ":1521/" + $general_settings.databases.GLX_DB
    $content.CONNEXION.NOMBDE = $general_settings.databases.GLX_DB
    $content.CONNEXION.TYPEDEBASE = "ORACLE"
    $content.CONNEXION.BIBLIOTHEQUEBASE = $general_settings.specifics.sp_schema
    $content.CONNEXION.BIBLIOTHEQUEFIDELIS = $general_settings.specifics.sp_schema
    $content.CONNEXION.BIBLIOTHEQUECLIENT = $general_settings.specifics.sp_schema
    $content.CONNEXION.BIBLIOTHEQUEJEUX = $general_settings.specifics.sp_schema
    $content.CONNEXION.BIBLIOTHEQUEBASECOMMUN = "GALAXIS"
    $content.CONNEXION.BIBLIOTHEQUEFIDELISCOMMUN = "GALAXIS"
    $content.CONNEXION.BIBLIOTHEQUEJEUXCOMMUN = "GALAXIS"
    $content.CONNEXION.BIBLIOTHEQUECLIENTCOMMUN = "GALAXIS"
    $content.CONNEXION.'USER NAME' = $USERS.mis.username
    $content.CONNEXION.PASSWORD = $USERS.mis.password
    $content.CONNEXION.NOMSERVEURCOM = $APPhostname+":1773"
    $content.CONNEXION.NOMPROCEDURESTOCKEEMOUVEMENT = "MOUVEMENT"
    $content.CONNEXION.CASINOID = $general_settings.specifics.casinoID

    #[GENERAL]
    $content.GENERAL.SOCIETE = $general_settings.specifics.societ
    $content.GENERAL.ETABLISSEMENT = $general_settings.specifics.etabli

    #[CASHLESS]
    $content.CASHLESS.NOMBDECL = $general_settings.databases.GLX_DB
    $content.CASHLESS.TYPEDEBASECL = "ORACLE"
    $content.CASHLESS.USERNAMECL = "as_cldb"
    $content.CASHLESS.PASSWORDCL = "T0rz9o033JEvAa2WRluxnw=="
    $content.CASHLESS.NORMALTIMEOUT = "0"
    $content.CASHLESS.EXTENDEDTIMEOUT = "0"

    Out-IniFile -InputObject $content -FilePath $config -Force
    write-host "-----------------------------" -ForegroundColor Green
}

#endregion

#region --- Al Bundy
function Invoke-MOD-Blooper {
    $path = "https://www.youtube.com/watch?v=Y2fdDGE3e8E"
    Start-Process "chrome.exe" "`"$path`"" 
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

#region --- component config handling
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
    $items = @()

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
    $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\mod-components.json"

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

    # Load JSON data
    $jsonContent = Get-Components
    if (-not $jsonContent) {
        throw "Failed to load JSON data from Get-Components."
    }

    $updatesMade = $false

    foreach ($category in $jsonContent.PSObject.Properties.Name) {
        $components = $jsonContent.$category

        foreach ($component in $components) {
            $componentName = $component.name
            $isInstalled = $false
            $updateVersion = $null

            if (-not $Silent) {
                Write-Host "Checking $componentName in category $category..."
            }

            # Check if the path exists
            if (Test-Path -Path $component.path) {
                $isInstalled = $true

                # Check for binary if the property exists
                if ($component.PSObject.Properties["binary"] -and $component.binary) {
                    if (Test-Path -Path $component.binary) {
                        $binaryVersion = Get-BinaryVersion -binaryPath $component.binary
                        if ($binaryVersion) {
                            $updateVersion = $binaryVersion -replace ',', '.'
                        }
                    } else {
                        $updateVersion = "-"
                    }
                } else {
                    $updateVersion = "-"  # No binary field
                }

                # Check for service if the property exists
                if ($component.PSObject.Properties["service"] -and $component.service) {
                    $serviceExists = Get-Service -Name $component.service -ErrorAction SilentlyContinue
                    if (-not $serviceExists) {
                        $isInstalled = $false
                    }
                }
            }

            # Get component for updates
            $jsonComponent = $jsonContent.$category | Where-Object { $_.name -eq $componentName }

            # Update the installed flag or version if needed
            if ($jsonComponent.installed -ne $isInstalled -or ($updateVersion -and $jsonComponent.version -ne $updateVersion)) {
                $jsonComponent.installed = $isInstalled
                if ($updateVersion -and $jsonComponent.version -ne $updateVersion) {
                    $jsonComponent.version = $updateVersion
                }
                $updatesMade = $true

                if (-not $Silent) {
                    Write-Host "    Updated $componentName with installed: $isInstalled, version: $updateVersion" -ForegroundColor Yellow
                }
            } elseif (-not $Silent) {
                Write-Host "    No changes needed for $componentName." -ForegroundColor Green
            }
        }
    }

    # Save changes back to the JSON file
    if ($updatesMade) {
        $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\mod-components.json"
        Write-Host "Finished updating components!" -ForegroundColor DarkMagenta
    } else {
        Write-Host "No changes detected." -ForegroundColor DarkGray
    }
}
#endregion

#region --- some weird handling to hide the toolkit
function Modulus-Out {
    $TK    = "C:\Program Files\PowerShell\Modules\modulus-toolkit\TK.key"
    $SP    = "C:\Program Files\PowerShell\Modules\modulus-toolkit\SP.key"
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

    Confirm-Deletion $TK
    Confirm-Deletion $SP
    Confirm-Deletion $token

    # Ask before reloading the profile
    $reloadResponse = Read-Host "Do you want to reload the profile? (Y/N)"
    if ($reloadResponse -match "^[Yy]$") {
        Reload-Profile
        Write-Host "Profile reloaded." -ForegroundColor Green
    } else {
        Write-Host "Profile was not reloaded." -ForegroundColor Red
    }

    cls
    #Exit
}
#endregion

#region --- Helper-functions
function Get-MOD-GeneralSettings {
    $VMConfig = Get-VMConfig
    Return $VMConfig.general_settings
}

function Get-MOD-TimeZone {
    $VMConfig = Get-VMConfig
    Return $VMConfig.general_settings.timezone
}

function Get-MOD-DB {
    $VMConfig = Get-VMConfig
    $system   = $VMConfig.general_settings.system
    switch ($system) {
        "1VM" {
            $DB = $VMConfig.servers | Where-Object {$_.name -eq "1VM"}
        }
        "3VM" {
            $DB = $VMConfig.servers | Where-Object {$_.name -eq "DB"}
        }
    }
    Return $DB    
}

function Get-MOD-APP {
    $VMConfig = Get-VMConfig
    $system   = $VMConfig.general_settings.system
    switch ($system) {
        "1VM" {
            $APP = $VMConfig.servers | Where-Object {$_.name -eq "1VM"}
        }
        "3VM" {
            $APP = $VMConfig.servers | Where-Object {$_.name -eq "APP"}
        }
    }
    Return $APP  
}

function Get-MOD-FS {
    $VMConfig = Get-VMConfig
    $system   = $VMConfig.general_settings.system
    switch ($system) {
        "1VM" {
            $FS = $VMConfig.servers | Where-Object {$_.name -eq "1VM"}
        }
        "3VM" {
            $FS = $VMConfig.servers | Where-Object {$_.name -eq "FS"}
        }
    }
    Return $FS  
}

function Get-MOD-1VM {
    $VMConfig = Get-VMConfig
    $1VM = $VMConfig.servers | Where-Object {$_.name -eq "1VM"} 
    Return $1VM 
}

function Get-MOD-Server {
    switch ($ENV:MODULUS_SERVER) {
        "DB"  { $server = Get-MOD-DB  }
        "APP" { $server = Get-MOD-APP }
        "FS"  { $server = Get-MOD-FS  }
        "1VM" { $server = Get-MOD-1VM } 
    }
    Return $server   
}

function Get-MOD-DB-hostname {
    $DB = Get-MOD-DB
    Return $DB.hostname
}

function Get-MOD-APP-hostname {
    $APP = Get-MOD-APP
    Return $APP.hostname
}

function Get-MOD-FS-hostname {
    $FS = Get-MOD-FS
    Return $FS.hostname
}

function Get-MOD-1VM-hostname {
    $1VM = Get-MOD-1VM
    Return $1VM.hostname
}

function Get-MOD-hostname {
    switch ($ENV:MODULUS_SERVER) {
        "DB"  { $hostname = Get-MOD-DB-hostname  }
        "APP" { $hostname = Get-MOD-APP-hostname }
        "FS"  { $hostname = Get-MOD-FS-hostname  }
        "1VM" { $hostname = Get-MOD-1VM-hostname }
        #"1VM" { $hostname = Get-MOD-DB-hostname  } #should return the correct one depending on the 1VM vs 3VM system-line in the json
    }
    Return $hostname
}

function Get-MOD-DesiredENVVARs {
    $desired = (Get-ENVConfig).environments.$ENV:MODULUS_SERVER
    Return $desired
}

function Get-MOD-DB-OFFICE-NIC {
    $DB = Get-MOD-DB
    $OFFICE = $DB.networkAdapters | Where-Object {$_.AdapterName -eq "OFFICE" }
    Return $OFFICE
}

function Get-MOD-APP-OFFICE-NIC {
    $APP = Get-MOD-APP
    $OFFICE = $APP.networkAdapters | Where-Object {$_.AdapterName -eq "OFFICE" }
    Return $OFFICE
}

function Get-MOD-FS-OFFICE-NIC {
    $FS = Get-MOD-FS
    $OFFICE = $FS.networkAdapters | Where-Object {$_.AdapterName -eq "OFFICE" }
    Return $OFFICE
}

function Get-MOD-DB-MODULUS-NIC {
    $DB = Get-MOD-DB
    $MODULUS = $DB.networkAdapters | Where-Object {$_.AdapterName -eq "MODULUS" }
    Return $MODULUS
}

function Get-MOD-APP-MODULUS-NIC {
    $APP = Get-MOD-APP
    $MODULUS = $APP.networkAdapters | Where-Object {$_.AdapterName -eq "MODULUS" }
    Return $MODULUS
}

function Get-MOD-FS-MODULUS-NIC {
    $FS = Get-MOD-FS
    $MODULUS = $FS.networkAdapters | Where-Object {$_.AdapterName -eq "MODULUS" }
    Return $MODULUS
}

function Get-MOD-FS-FLOOR-NIC {
    $FS = Get-MOD-FS
    $FLOOR = $FS.networkAdapters | Where-Object {$_.AdapterName -eq "FLOOR" }
    Return $FLOOR
}

function Get-MOD-FS-DHCP-Ranges {
    $FS = Get-MOD-FS
    $DHCP = $FS.DHCPranges 
    Return $DHCP
}

#endregion

#region --- 7z functions to be used for deployment functions

#function for extracting with 7z
function Extract-7ZipFile {
    param (
        [string]$SourceFolder,
        [string]$TargetFolder,
        [string]$FilePattern = "*.7z",   # Default pattern to match .7z files
        [string]$Subfolder = "",         # Optionally specify subfolder within the archive
        [string]$7ZipPath = "7z"         # Path to the 7z executable (assumed to be in PATH)
    )

    # Find the first matching file
    $file = Get-ChildItem -Path $SourceFolder -Filter $FilePattern | Select-Object -First 1

    if (-not $file) {
        Write-Warning "No files found matching pattern '$FilePattern' in folder '$SourceFolder'." 
        return $false
    }

    #Initialize-Tools

    # Construct the extraction command
    $extractCommand = "$7ZipPath x `"$($file.FullName)`" -o`"$TargetFolder`" $Subfolder -y"

    # Initialize progress bar
    $progressActivity = "Extracting 7-Zip File"
    $progressStatus = "Extracting: $($file.Name)"
    Write-Progress -Activity $progressActivity -Status $progressStatus -PercentComplete 0 

    try {
        # Execute the extraction command
        $output = Invoke-Expression $extractCommand 2>&1

        # Check for any errors in the output
        if ($LASTEXITCODE -eq 0) {
            Write-Progress -Activity $progressActivity -Status "Extraction Complete" -PercentComplete 100
            Write-Host "Extraction of '$($file.Name)' completed successfully." -ForegroundColor Green
            #write-host "Extracted folder can be found at $TargetFolder" -ForegroundColor Yellow
            return $true
        } else {
            Write-Host "Extraction failed with errors." -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Error "An error occurred during extraction: $_" 
        return $false
    } finally {
        Write-Progress -Activity $progressActivity -Status "Complete" -PercentComplete 100 -Completed
    }
}
#endregion

#region --- imp. copy function with progress bar
function mod-copy {
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
    Write-Verbose -Message 'Analyzing robocopy job ...';
    $StagingLogPath = '{0}\temp\{1} robocopy staging.log' -f $env:windir, (Get-Date -Format 'yyyy-MM-dd HH-mm-ss');

    $StagingArgumentList = '"{0}" "{1}" /LOG:"{2}" /L {3}' -f $Source, $Destination, $StagingLogPath, $CommonRobocopyParams;
    Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList);
    Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -NoNewWindow;
    # Get the total number of files that will be copied
    $StagingContent = Get-Content -Path $StagingLogPath;
    $TotalFileCount = $StagingContent.Count - 1;

    # Get the total number of bytes to be copied
    [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | % { $BytesTotal = 0; } { $BytesTotal += $_.Value; };
    Write-Verbose -Message ('Total bytes to be copied: {0}' -f $BytesTotal);
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
    Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList);
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
        Write-Verbose -Message ('Bytes copied: {0}' -f $BytesCopied);
        Write-Verbose -Message ('Files copied: {0}' -f $LogContent.Count);
        $Percentage = 0;
        if ($BytesCopied -gt 0) {
           $Percentage = (($BytesCopied/$BytesTotal)*100)
        }
        Write-Progress -Activity Robocopy -Status ("Copied {0} of {1} files; Copied {2} of {3} bytes" -f $CopiedFileCount, $TotalFileCount, $BytesCopied, $BytesTotal) -PercentComplete $Percentage
    }
    #endregion Progress loop

    #region Function output
    [PSCustomObject]@{
        BytesCopied = $BytesCopied;
        FilesCopied = $CopiedFileCount;
    };
    #endregion Function output
}
#endregion

#region --- backup config files 
function Backup-ConfigFiles {

    $BackupDirectory = "I:\ConfigBACKUP"

    # Load JSON data
    $jsonData = Get-Components

    # Define a helper function to backup each config file
    function Backup-File {
        param (
            [string]$ComponentType,
            [string]$ComponentName,
            [object]$ConfigFile
        )

        $HN = hostname
        
        
        # Check if config file exists and copy it
        if (Test-Path -Path $ConfigFile.path) {

            # Create backup path based on component type and name
            $componentBackupDir = Join-Path -Path $BackupDirectory -ChildPath "$HN\$ComponentType\$ComponentName"
            if (!(Test-Path -Path $componentBackupDir)) {
                New-Item -Path $componentBackupDir -ItemType Directory -Force | Out-Null
             }
        
            Copy-Item -Path $ConfigFile.path -Destination $componentBackupDir -Force
            Write-Host "Backed up '$($ConfigFile.name)' to '$componentBackupDir'" -ForegroundColor Green
        } else {
            Write-Host "File '$($ConfigFile.name)' not found at path '$($ConfigFile.path)'" -ForegroundColor yellow
        }
    }

    # Loop through each category and backup config files
    foreach ($category in @('databases', 'tools', 'modules')) {
        foreach ($component in $jsonData.$category) {
            $componentName = $component.name
            foreach ($configFile in $component.configFiles) {
                Backup-File -ComponentType $category -ComponentName $componentName -ConfigFile $configFile
            }
        }
    }
}
#endregion