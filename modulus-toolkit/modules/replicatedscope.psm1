#tlukas, 10.11.2025

#write-host "Loading replicatedscope.psm1!" -ForegroundColor Green

#region --- json helpers

#endregion

#region --- replicatedscope.ora
function Set-ReplicatedScopeOra {
	$JsonFile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$DefaultPort = "1521"
	$OutputFile = "C:\Oracle\client32\network\admin\replicatedscope.ora"

    # Check if the JSON file exists
    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }

    Write-Host "--- Starting generation of $OutputFile ---"

    # Read the JSON file and convert it to a PowerShell object (array of PSCustomObjects)
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Initialize array to hold all TNS entries
    $TnsContent = @()

    $TnsContent += "# replicatedscope.ora for:"
	$TnsContent += "# - SRADDINDB Replication"
	$TnsContent += "# - CasinoSyncronizationService"
    $TnsContent += "# created by modulus-toolkit"
    $TnsContent += "# casinos defined: $($replicatedscope.Count)"
    $TnsContent += "" # Add a blank line

    # Iterate through each casino entry
    foreach ($casino in $replicatedscope) {
        try {
            # Extract and format required fields
            $TNS 	 = $casino.tns.ToUpper()
			$name    = $casino.name.ToUpper()
            $ip 	 = $casino.ip
            $service = $casino.service.ToUpper() 
            $HO      = $casino.is_head_office

            # Construct the TNS entry string using a here-string for readability
            $TnsEntry = @"
$TNS =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $ip)(PORT = $DefaultPort))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $service)
    )
  )
"@
            
            # Add the generated entry and an extra newline for separation
            if ($HO) {
                $TnsContent += "# Headoffice $($name):"
            } else {
                $TnsContent += "# Casino $($name):"
            }
            $TnsContent += $TnsEntry.Trim()
            $TnsContent += ""

            Write-Host "Generated entry $TNS for: $name"
            
        } catch {
            Write-Warning "Error processing one casino entry (missing property?). Skipping. Details: $($_.Exception.Message)"
        }
    }
    
    # Remove the trailing empty line if one exists
    if ($TnsContent[-1] -eq "") {
        $TnsContent = $TnsContent[0..($TnsContent.Count - 2)]
    }

    # Write the entire content array to the output file
    try {
        $TnsContent | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
        Write-Host ""
        Write-Host "Successfully created $OutputFile with $($replicatedscope.Count) entries." -ForegroundColor Green
        
        if (Test-path "D:\Oracle\Ora19c\network\admin\") {
            $OutputFile = "D:\Oracle\Ora19c\network\admin\replicatedscope.ora"
            $TnsContent | Out-File -FilePath $OutputFile -Encoding UTF8 -Force
            Write-Host ""
            Write-Host "Successfully created $OutputFile with $($replicatedscope.Count) entries." -ForegroundColor Green
        }
        
    } catch {
        Write-Error "Error writing to file: $($_.Exception.Message)"
    }
}
#endregion

#region --- D:\Galaxis\Program\bin\CasinoSynchronizationService\Config
#region --- \ConnectionStrings-Settings.config
function Set-ConnectionStrings {
    Write-Host "--- Starting configuration of $ConfigPath ---"

	# --- Configuration ---
	$JsonFile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"

	# Passwords taken from the sample XML provided by the user
	$PasswordSBC = Get-DbEnCred-sbc
	$PasswordMKT = Get-DbEnCred-mis
	
	$ConfigPath = "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\ConnectionStrings-Settings.config"
	
    # --- 1. Load Data and Target Files ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }

    # Ensure the Config directory exists
    if (-not (Test-Path (Split-Path $ConfigPath))) {
        New-Item -Path (Split-Path $ConfigPath) -ItemType Directory | Out-Null
        Write-Host "Created missing 'Config' directory."
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
        Write-Host "Successfully loaded $($replicatedscope.Count) casino entries."
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load XML document
    try {
        [xml]$xml = Get-Content -Path $ConfigPath
    } catch {
        Write-Error "Error loading XML file '$ConfigPath'. Ensure it exists and is valid XML."
        exit 1
    }

    # --- 2. Clear Existing Connection Strings ---

    $connectionStringsNode = $xml.connectionStrings
    if (-not $connectionStringsNode) {
        Write-Error "Could not find the <connectionStrings> node in the XML file."
        exit 1
    }

    # Remove all child nodes (i.e., all existing <add> tags)
    $connectionStringsNode.RemoveAll()
    Write-Host "Cleared existing connection strings."
    
    # Add an XML comment for clarity
    $commentSBC = $xml.CreateComment(" as_sbc Connections (Generated) ")
    $connectionStringsNode.AppendChild($commentSBC) | Out-Null

    # --- 3. Define Generation Templates (Two Loops) ---
    
    # Define the two user configurations to loop through
    $UserConfigs = @(
        @{ Prefix = "MS_SBC"; User = "as_sbc"; Password = $PasswordSBC },
        @{ Prefix = "MS_MKT"; User = "mis"; Password = $PasswordMKT }
    )

    # --- 4. Generate New Connection Strings ---

    foreach ($config in $UserConfigs) {
        
        $UserPrefix = $config.Prefix
        $UserID = $config.User
        $UserPassword = $config.Password
        
        Write-Host "Generating entries for user: $UserID"
        
        # Add a comment for separation between user groups
        if ($UserPrefix -eq "MS_MKT") {
            $commentMKT = $xml.CreateComment(" mis Connections (Generated) ")
            $connectionStringsNode.AppendChild($commentMKT) | Out-Null
        }

        foreach ($casino in $replicatedscope) {
            
            # Use the $casino.name and $casino.tns fields
            $TNSAlias = $casino.tns.ToUpper()
            $CasinoName = $casino.name.ToUpper()
            
            # 1. Create the new <add> element
            $addNode = $xml.CreateElement("add")
            
            # 2. Set the 'name' attribute
            $addNode.SetAttribute("name", "$($UserPrefix)_$($CasinoName)")
            
            # 3. Construct and set the 'connectionString' attribute
            $connString = "Data Source=$TNSAlias;User Id=$UserID;Password=$UserPassword;Pooling=false;"
            $addNode.SetAttribute("connectionString", $connString)
            
            # 4. Append the new node to <connectionStrings>
            $connectionStringsNode.AppendChild($addNode) | Out-Null
            
            Write-Host "  -> Added $($UserPrefix)_$($CasinoName)"
        }
    }

    # --- 5. Save Changes ---
    
    # Save the modified XML file
    try {
        $xml.Save($ConfigPath)
        Write-Host ""
        Write-Host "Successfully regenerated connection strings in $ConfigPath." -ForegroundColor Green
    } catch {
        Write-Error "Error saving XML file: $($_.Exception.Message)"
    }
}
#endregion
#region --- \Marketing-Settings.config
function Set-MarketingSettings {
    Write-Host "--- Starting configuration of $ConfigPath ---"

	# --- Configuration ---
	$JsonFile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$ConfigPath = "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\Marketing-Settings.config"

    # --- 1. Load Data and Target Files ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }

    # Ensure the Config directory exists
    if (-not (Test-Path (Split-Path $ConfigPath))) {
        New-Item -Path (Split-Path $ConfigPath) -ItemType Directory | Out-Null
        Write-Host "Created missing 'Config' directory."
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
        Write-Host "Successfully loaded $($replicatedscope.Count) casino entries."
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load XML document
    try {
        # Force XML type casting for DOM manipulation
        [xml]$xml = Get-Content -Path $ConfigPath
    } catch {
        Write-Error "Error loading XML file '$ConfigPath'. Ensure it exists and is valid XML."
        exit 1
    }

    # --- 2. Identify Head Office ---

    $HeadOfficeData = $replicatedscope | Where-Object { $_.is_head_office -eq $true } | Select-Object -First 1

    if (-not $HeadOfficeData) {
        Write-Warning "No Head Office found in JSON. Skipping HeadOffice node configuration."
    }

    # --- 3. Configure HeadOffice Node ---
    
    $hoNode = $xml.SelectSingleNode("//HeadOffice")
    if ($hoNode -and $HeadOfficeData) {
        $hoNode.SetAttribute("casinoid", $HeadOfficeData.casinoid)
        $hoNode.SetAttribute("connectionstringname", "MS_MKT_$($HeadOfficeData.name.ToUpper())")
        Write-Host "Configured HeadOffice node for $($HeadOfficeData.name.ToUpper())."
    } elseif (-not $hoNode) {
        Write-Warning "Could not find the <HeadOffice> node in the XML file."
    }

    # --- 4. Clear and Regenerate CasinoSettings Entries ---

    $casinoSettingsNode = $xml.SelectSingleNode("//CasinoSettings")
    if (-not $casinoSettingsNode) {
        Write-Error "Could not find the <CasinoSettings> node in the XML file. Cannot proceed."
        exit 1
    }

    # Remove all child nodes (i.e., all existing <add> tags)
    $casinoSettingsNode.RemoveAll()
    Write-Host "Cleared existing CasinoSettings entries."

    foreach ($casino in $replicatedscope) {
        
        $CasinoName = $casino.name.ToUpper()
        $CasinoID = $casino.casinoid
        
        # 1. Create the new <add> element
        $addNode = $xml.CreateElement("add")
        
        # 2. Set attributes
        $addNode.SetAttribute("casinoid", $CasinoID)
        $addNode.SetAttribute("connectionstringname", "MS_MKT_$($CasinoName)")
        
        # 3. Append the new node to <CasinoSettings>
        $casinoSettingsNode.AppendChild($addNode) | Out-Null
        
        Write-Host "  -> Added Casino ID $CasinoID for $($CasinoName)"
    }

    # --- 5. Save Changes ---
    
    try {
        # Save the modified XML file
        $xml.Save($ConfigPath)
        Write-Host ""
        Write-Host "Successfully regenerated Marketing settings in $ConfigPath." -ForegroundColor Green
    } catch {
        Write-Error "Error saving XML file: $($_.Exception.Message)"
    }
}
#endregion
#region --- \SmibNotification-Settings.config
function Set-SmibNotificationSettings {
    Write-Host "--- Starting configuration of $ConfigPath ---"
	
	$ConfigPath = "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\SmibNotification-Settings.config"
	$JsonFile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"

    # --- 1. Load Data and Target Files ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }

    # Ensure the Config directory exists
    if (-not (Test-Path (Split-Path $ConfigPath))) {
        New-Item -Path (Split-Path $ConfigPath) -ItemType Directory | Out-Null
        Write-Host "Created missing 'Config' directory."
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
        Write-Host "Successfully loaded $($replicatedscope.Count) casino entries."
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load XML document
    try {
        # Force XML type casting for DOM manipulation
        [xml]$xml = Get-Content -Path $ConfigPath
    } catch {
        Write-Error "Error loading XML file '$ConfigPath'. Ensure it exists and is valid XML."
        exit 1
    }

    # --- 2. Identify Head Office ---

    $HeadOfficeData = $replicatedscope | Where-Object { $_.is_head_office -eq $true } | Select-Object -First 1

    if (-not $HeadOfficeData) {
        Write-Warning "No Head Office found in JSON. Cannot configure HeadOffice node."
    }

    # --- 3. Configure HeadOffice Node ---
    
    $hoNode = $xml.SelectSingleNode("//HeadOffice")
    if ($hoNode -and $HeadOfficeData) {
        $CasinoName = $HeadOfficeData.name.ToUpper()
        
        $hoNode.SetAttribute("casinoid", $HeadOfficeData.casinoid)
        $hoNode.SetAttribute("connectionstringname", "MS_SBC_$($CasinoName)")
        Write-Host "Configured HeadOffice node for $($CasinoName) using connection MS_SBC_$($CasinoName)."
    } elseif (-not $hoNode) {
        Write-Warning "Could not find the <HeadOffice> node in the XML file."
    }

    # --- 4. Ensure CasinoSettings Node Exists (Self-closing is maintained if it was empty) ---

    $casinoSettingsNode = $xml.SelectSingleNode("//CasinoSettings")
    if (-not $casinoSettingsNode) {
        Write-Warning "Could not find the <CasinoSettings> node, but we will proceed as it should be empty."
    } else {
        # Optional: ensure it's empty, though the template should handle this.
        $casinoSettingsNode.RemoveAll()
    }


    # --- 5. Save Changes ---
    
    try {
        # Save the modified XML file
        $xml.Save($ConfigPath)
        Write-Host ""
        Write-Host "Successfully regenerated SMIB Notification settings in $ConfigPath." -ForegroundColor Green
    } catch {
        Write-Error "Error saving XML file: $($_.Exception.Message)"
    }
}
#endregion
#region --- \CaWa-Settings.config
function Set-CaWaSettings {
    Write-Host "--- Starting configuration of $ConfigPath ---"

	$ConfigPath = "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\CaWa-Settings.config"
	$JsonFile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$ConnectionPrefix = "MS_SBC"

    # --- 1. Load Data and Target Files ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }

    # Ensure the Config directory exists
    if (-not (Test-Path (Split-Path $ConfigPath))) {
        New-Item -Path (Split-Path $ConfigPath) -ItemType Directory | Out-Null
        Write-Host "Created missing 'Config' directory."
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
        Write-Host "Successfully loaded $($replicatedscope.Count) casino entries."
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load XML document
    try {
        # Force XML type casting for DOM manipulation
        [xml]$xml = Get-Content -Path $ConfigPath
    } catch {
        Write-Error "Error loading XML file '$ConfigPath'. Ensure it exists and is valid XML."
        exit 1
    }

    # --- 2. Identify Head Office ---

    $HeadOfficeData = $replicatedscope | Where-Object { $_.is_head_office -eq $true } | Select-Object -First 1

    if (-not $HeadOfficeData) {
        Write-Warning "No Head Office found in JSON. Skipping HeadOffice node configuration."
    }

    # --- 3. Configure HeadOffice Node ---
    
    $hoNode = $xml.SelectSingleNode("//HeadOffice")
    if ($hoNode -and $HeadOfficeData) {
        $CasinoName = $HeadOfficeData.name.ToUpper()
        
        $hoNode.SetAttribute("casinoid", $HeadOfficeData.casinoid)
        $hoNode.SetAttribute("connectionstringname", "$($ConnectionPrefix)_$($CasinoName)")
        Write-Host "Configured HeadOffice node for $($CasinoName) using connection $($ConnectionPrefix)_$($CasinoName)."
    } elseif (-not $hoNode) {
        Write-Warning "Could not find the <HeadOffice> node in the XML file."
    }

    # --- 4. Clear and Regenerate CasinoSettings Entries ---

    $casinoSettingsNode = $xml.SelectSingleNode("//CasinoSettings")
    if (-not $casinoSettingsNode) {
        Write-Error "Could not find the <CasinoSettings> node in the XML file. Cannot proceed."
        exit 1
    }

    # Remove all child nodes (i.e., all existing <add> tags)
    $casinoSettingsNode.RemoveAll()
    Write-Host "Cleared existing CasinoSettings entries."

    foreach ($casino in $replicatedscope) {
        
        $CasinoName = $casino.name.ToUpper()
        $CasinoID = $casino.casinoid
        
        # 1. Create the new <add> element
        $addNode = $xml.CreateElement("add")
        
        # 2. Set attributes
        $addNode.SetAttribute("casinoid", $CasinoID)
        $addNode.SetAttribute("connectionstringname", "$($ConnectionPrefix)_$($CasinoName)")
        
        # 3. Append the new node to <CasinoSettings>
        $casinoSettingsNode.AppendChild($addNode) | Out-Null
        
        Write-Host "  -> Added Casino ID $CasinoID for $($CasinoName)"
    }

    # --- 5. Save Changes ---
    
    try {
        # Save the modified XML file
        $xml.Save($ConfigPath)
        Write-Host ""
        Write-Host "Successfully regenerated CaWa settings in $ConfigPath." -ForegroundColor Green
    } catch {
        Write-Error "Error saving XML file: $($_.Exception.Message)"
    }
}
#endregion
#region --- \CasinoSynchronization-Settings.config
function Set-CasinoSyncSettings {
    Write-Host "--- Starting configuration of $ConfigPath ---"
    Write-Host "Dynamic Interface: '$NetworkInterface'"
	
	$ConfigPath = "D:\Galaxis\Program\bin\CasinoSynchronizationService\Config\CasinoSynchronization-Settings.config"
	$JsonFile = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$NetworkInterface = "OFFICE" 

    # --- 1. Load Data and Target Files ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }

    # Ensure the Config directory exists
    if (-not (Test-Path (Split-Path $ConfigPath))) {
        New-Item -Path (Split-Path $ConfigPath) -ItemType Directory | Out-Null
        Write-Host "Created missing 'Config' directory."
    }

    # Load JSON data
    try {
        # Note: We must check if the file is accessible before using Get-Content
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load XML document
    try {
        [xml]$xml = Get-Content -Path $ConfigPath
    } catch {
        Write-Error "Error loading XML file '$ConfigPath'. Ensure it exists and is valid XML."
        exit 1
    }

    # --- 2. Identify Head Office and Calculate Dynamic Values ---

    $HeadOfficeData = $replicatedscope | Where-Object { $_.is_head_office -eq $true } | Select-Object -First 1

    if (-not $HeadOfficeData) {
        Write-Error "No Head Office found in JSON. Cannot calculate REP_ADMIN_SCHEMA."
        exit 1
    }
    
    $HOName = $HeadOfficeData.name.ToUpper()
    $RepAdminSchema = "REP_ADMIN_$($HOName)"
    Write-Host "Calculated HeadOffice RepAdmin Schema: $RepAdminSchema"

    # --- 3. Define ALL Settings (Static + Dynamic) ---
    
    # Using [Ordered] Dictionary to maintain key sequence
    $Settings = [Ordered]@{
        "UseDiscoveryService"                               = "false";
        "OfficeNetworkInterface"                            = $NetworkInterface;
        "PreferredIpAddress"                                = "";
        "AddressBookIdentifiers"                            = "CasinoSynchronizationService";
        "UseSmibNotificationService"                        = "false";
        "SmibNotificationServiceAddressBookIdentifiers"     = "SmibNotificationService";
        "SmibNotificationServiceRelativePath"               = "SmibNotification";
        "BalanceNotificationServiceAddressBookIdentifiers"  = "BalanceNotificationService";
        "BalanceNotificationServiceRelativePath"            = "BalanceNotification";
        "HeadOfficeRepAdminSchema"                          = $RepAdminSchema;
    }
    
    # Define comments to match original structure (order must match keys above)
    $Comments = [Ordered]@{
        "UseDiscoveryService" = " DISCOVERY SERVICE SETTINGS";
        "AddressBookIdentifiers" = " ADDRESSBOOK SERVICE SETTINGS";
        "UseSmibNotificationService" = " SmibNotificationService";
        "HeadOfficeRepAdminSchema" = " HO REP ADMIN SCHEMA - SRADDINDB";
    }

    # --- 4. Clear and Regenerate <appSettings> Entries ---

    $appSettingsNode = $xml.SelectSingleNode("//appSettings")
    if (-not $appSettingsNode) {
        Write-Error "Could not find the <appSettings> node in the XML file. Cannot proceed."
        exit 1
    }

    # Remove all existing child nodes (add tags and comments)
    $appSettingsNode.RemoveAll()
    Write-Host "Cleared existing appSettings entries."

    # Loop is now guaranteed to process keys in the order defined in $Settings
    foreach ($key in $Settings.Keys) {
        
        $value = $Settings[$key]
        
        # FIX: Using .Keys.Contains() method which works correctly for OrderedDictionary
        if ($Comments.Keys.Contains($key)) {
            $comment = $xml.CreateComment($Comments[$key])
            $appSettingsNode.AppendChild($comment) | Out-Null
        }
        
        # 1. Create the new <add> element
        $addNode = $xml.CreateElement("add")
        
        # 2. Set attributes
        $addNode.SetAttribute("key", $key)
        $addNode.SetAttribute("value", $value)
        
        # 3. Append the new node to <appSettings>
        $appSettingsNode.AppendChild($addNode) | Out-Null
        
        Write-Host "  -> Added key: $key = '$value'"
    }

    # --- 5. Save Changes ---
    
    try {
        # Save the modified XML file
        $xml.Save($ConfigPath)
        Write-Host ""
        Write-Host "Successfully regenerated Casino Synchronization settings in $ConfigPath." -ForegroundColor Green
    } catch {
        Write-Error "Error saving XML file: $($_.Exception.Message)"
    }
}
#endregion
#region --- FULLY configure CasinoSynchronization
function Set-CasinoSyncConfig {
    $server = $ENV:MODULUS_SERVER
    if ($server -notin ("APP","1VM")) {
        Write-Log "Not on application server, exiting!" ERROR
        Return
    }

    write-log "Set-CasinoSyncConfig" -Header
    Set-ConnectionStrings
    Set-MarketingSettings
    Set-SmibNotificationSettings
    Set-CaWaSettings
    Set-CasinoSyncSettings
}
#endregion
#endregion

#region --- SRADDINDB folder config
#region --- BasicAddinConfig
function New-BasicAddinConfig {
	#Configuration
	$JsonFile       = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$TemplateFile   = "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates\SRADDINDB\basicaddin_config.sql.template"
	$BaseReleaseDir = "D:\SRADDINDB_Release\config"
	$TargetSubPath  = "basicaddindb\config.sql"

    Write-Host "--- Starting generation of basicaddindb\config.sql files ---"

    # --- 1. Load Data and Template ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }
    if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {
        Write-Error "Template file '$TemplateFile' not found. Cannot proceed."
        exit 1
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load Template Content
    $TemplateContent = Get-Content -Path $TemplateFile -Raw
    
    # --- New: Define Tablespace Placeholder Values ---
    # These values can be changed here if you need them to be dynamic later
    $TbsUser = 'grips_user'
    $TbsIndex = 'grips_index'
    $TbsTemp = 'grips_temp'
    # ------------------------------------------------

    # --- 2. Iterate and Generate Files ---
    
    $index = 0
    foreach ($casino in $replicatedscope) {
        
        $CasinoNameUpper = $casino.name.ToUpper()
        $CasinoNameLower = $casino.name.ToLower()
        
        # Calculate the folder prefix (e.g., '00', '01')
        $Prefix = "{0:D2}" -f $index
        
        # Calculate the full dynamic folder name (e.g., '00_MUC')
        $FolderID = "$($Prefix)_$($CasinoNameUpper)"
        
        # Build the full target file path
        $TargetDir = Join-Path -Path $BaseReleaseDir -ChildPath $FolderID
        $TargetFile = Join-Path -Path $TargetDir -ChildPath $TargetSubPath
        
        Write-Host "Processing Casino: $($FolderID)"

        # 3. Token Replacement
        # Replace all tokens using the calculated values, including the new tablespace placeholders
        $NewContent = $TemplateContent -replace '{{FOLDER_ID}}', $FolderID `
                                     -replace '{{CASINO_NAME_LOWER}}', $CasinoNameLower `
                                     -replace '{{TBS_USER}}', $TbsUser `
                                     -replace '{{TBS_INDEX}}', $TbsIndex `
                                     -replace '{{TBS_TEMP}}', $TbsTemp
                                     
        # 4. Ensure Target Directory Exists
        if (-not (Test-Path -Path $TargetDir)) {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $TargetDir"
        }
        
        # 5. Write Content to File
        try {
            $NewContent | Out-File -FilePath $TargetFile -Encoding UTF8 -Force
            Write-Host "  -> Successfully written to: $TargetFile"
        } catch {
            Write-Error "Error writing file for $($FolderID): $($_.Exception.Message)"
        }
        
        # Increment index for the next casino
        $index++
    }

    Write-Host ""
    Write-Host "Finished configuring all $($replicatedscope.Count) basicaddindb\config.sql files." -ForegroundColor Green
}
#endregion
#region --- ClAddinConfig
function New-ClAddinConfig {
    #Configuration
	$JsonFile       = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$TemplateFile   = "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates\SRADDINDB\claddin_config.sql.template"
	$BaseReleaseDir = "D:\SRADDINDB_Release\config"
	$TargetSubPath  = "claddindb\config.sql"

    Write-Host "--- Starting generation of $TargetSubPath files ---"
	
	# --- 1. Load Data and Template ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }
    if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {
        Write-Error "Template file '$TemplateFile' not found. Cannot proceed."
        exit 1
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load Template Content
    $TemplateContent = Get-Content -Path $TemplateFile -Raw
    
    # --- Define Tablespace Placeholder Values (Consistent with basicaddindb) ---
    $TbsUser = 'grips_user'
    $TbsIndex = 'grips_index'
    $TbsTemp = 'grips_temp'
    # --------------------------------------------------------------------------

    # --- 2. Iterate and Generate Files ---
    
    $index = 0
    foreach ($casino in $replicatedscope) {
        
        $CasinoNameUpper = $casino.name.ToUpper()
        $CasinoNameLower = $casino.name.ToLower()
        
        # Calculate the folder prefix (e.g., '00', '01')
        $Prefix = "{0:D2}" -f $index
        
        # Calculate the full dynamic folder name (e.g., '00_MUC')
        $FolderID = "$($Prefix)_$($CasinoNameUpper)"
        
        # Build the full target file path
        $TargetDir = Join-Path -Path $BaseReleaseDir -ChildPath $FolderID
        $TargetFile = Join-Path -Path $TargetDir -ChildPath $TargetSubPath
        
        Write-Host "Processing Casino: $($FolderID)"

        # 3. Token Replacement
        $NewContent = $TemplateContent -replace '{{FOLDER_ID}}', $FolderID `
                                     -replace '{{CASINO_NAME_LOWER}}', $CasinoNameLower `
                                     -replace '{{TBS_USER}}', $TbsUser `
                                     -replace '{{TBS_INDEX}}', $TbsIndex `
                                     -replace '{{TBS_TEMP}}', $TbsTemp
                                     
        # 4. Ensure Target Directory Exists
        if (-not (Test-Path -Path $TargetDir)) {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $TargetDir"
        }
        
        # 5. Write Content to File
        try {
            $NewContent | Out-File -FilePath $TargetFile -Encoding UTF8 -Force
            Write-Host "  -> Successfully written to: $TargetFile"
        } catch {
            Write-Error "Error writing file for $($FolderID): $($_.Exception.Message)"
        }
        
        # Increment index for the next casino
        $index++
    }

    Write-Host ""
    Write-Host "Finished configuring all $($replicatedscope.Count) $TargetSubPath files." -ForegroundColor Green
}
#endregion
#region --- OwnerAddinConfig
function New-OwnerAddinConfig {
	#Configuration
	$JsonFile       = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$TemplateFile   = "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates\SRADDINDB\owneraddin_config.sql.template"
	$BaseReleaseDir = "D:\SRADDINDB_Release\config"
	$TargetSubPath  = "owneraddindb\config.sql"

    Write-Host "--- Starting generation of $TargetSubPath files ---"

    # --- 1. Load Data and Template ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }
    if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {
        Write-Error "Template file '$TemplateFile' not found. Cannot proceed."
        exit 1
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load Template Content
    $TemplateContent = Get-Content -Path $TemplateFile -Raw
    
    # --- 2. Iterate and Generate Files ---
    
    $index = 0
    foreach ($casino in $replicatedscope) {
        
        $CasinoNameUpper = $casino.name.ToUpper()
        $CasinoNameLower = $casino.name.ToLower()
        
        # Calculate the folder prefix (e.g., '00', '01')
        $Prefix = "{0:D2}" -f $index
        
        # Calculate the full dynamic folder name (e.g., '00_MUC')
        $FolderID = "$($Prefix)_$($CasinoNameUpper)"
        
        # Build the full target file path
        $TargetDir = Join-Path -Path $BaseReleaseDir -ChildPath $FolderID
        $TargetFile = Join-Path -Path $TargetDir -ChildPath $TargetSubPath
        
        Write-Host "Processing Casino: $($FolderID)"

        # 3. Token Replacement
        # Only replace FOLDER_ID and CASINO_NAME_LOWER
        $NewContent = $TemplateContent -replace '{{FOLDER_ID}}', $FolderID `
                                     -replace '{{CASINO_NAME_LOWER}}', $CasinoNameLower
                                     
        # 4. Ensure Target Directory Exists
        if (-not (Test-Path -Path $TargetDir)) {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $TargetDir"
        }
        
        # 5. Write Content to File
        try {
            $NewContent | Out-File -FilePath $TargetFile -Encoding UTF8 -Force
            Write-Host "  -> Successfully written to: $TargetFile"
        } catch {
            Write-Error "Error writing file for $($FolderID): $($_.Exception.Message)"
        }
        
        # Increment index for the next casino
        $index++
    }

    Write-Host ""
    Write-Host "Finished configuring all $($replicatedscope.Count) $TargetSubPath files." -ForegroundColor Green
}
#endregion
#region --- SrAddinConfig
function New-SrAddinConfig {
    #Configuration
	$JsonFile       = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$TemplateFile   = "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates\SRADDINDB\sraddindb_config.sql.template"
	$BaseReleaseDir = "D:\SRADDINDB_Release\config"
	$TargetSubPath  = "sraddindb\config.sql"
	
	Write-Host "--- Starting generation of $TargetSubPath files ---"

    # --- 1. Load Data and Template ---

    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }
    if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {
        Write-Error "Template file '$TemplateFile' not found. Cannot proceed."
        exit 1
    }

    # Load JSON data
    try {
        $replicatedscope = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load Template Content
    $TemplateContent = Get-Content -Path $TemplateFile -Raw
    
    # --- 2. Iterate and Generate Files ---
    
    $index = 0
    foreach ($casino in $replicatedscope) {
        
        $CasinoNameUpper = $casino.name.ToUpper()
        $CasinoNameLower = $casino.name.ToLower()
        
        # Calculate the folder prefix (e.g., '00', '01')
        $Prefix = "{0:D2}" -f $index
        
        # Calculate the full dynamic folder name (e.g., '00_MUC')
        $FolderID = "$($Prefix)_$($CasinoNameUpper)"
        
        # Build the full target file path
        $TargetDir = Join-Path -Path $BaseReleaseDir -ChildPath $FolderID
        $TargetFile = Join-Path -Path $TargetDir -ChildPath $TargetSubPath
        
        Write-Host "Processing Casino: $($FolderID)"

        # 3. Token Replacement
        # Only replace FOLDER_ID and CASINO_NAME_LOWER
        $NewContent = $TemplateContent -replace '{{FOLDER_ID}}', $FolderID `
                                     -replace '{{CASINO_NAME_LOWER}}', $CasinoNameLower
                                     
        # 4. Ensure Target Directory Exists
        if (-not (Test-Path -Path $TargetDir)) {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $TargetDir"
        }
        
        # 5. Write Content to File
        try {
            $NewContent | Out-File -FilePath $TargetFile -Encoding UTF8 -Force
            Write-Host "  -> Successfully written to: $TargetFile"
        } catch {
            Write-Error "Error writing file for $($FolderID): $($_.Exception.Message)"
        }
        
        # Increment index for the next casino
        $index++
    }

    Write-Host ""
    Write-Host "Finished configuring all $($replicatedscope.Count) $TargetSubPath files." -ForegroundColor Green
}
#endregion
#region --- SrAddinConfigSite
function New-SrAddinConfigSite {
	#Configuration
	$JsonFile       = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$TemplateFile   = "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates\SRADDINDB\sraddindb_mkt_rep_config_site.sql.template"
	$BaseReleaseDir = "D:\SRADDINDB_Release\config"
	$TargetSubPath  = "sraddindb\mkt_rep\config_site.sql"
	
	# Fixed Schema Names to be Replicated
	$Schemas = @('GALAXIS', 'AS_AUTH', 'AS_SBC', 'SLOT', 'SITE', 'TBL')
	
    Write-Host "--- Starting generation of HO config_site.sql file (ID by is_head_office: true) ---"

    # --- 1. Load Data and Template ---
    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }
    if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {
        Write-Error "Template file '$TemplateFile' not found. Cannot proceed."
        exit 1
    }

    # Load JSON data
    try {
        $AllCasinos = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load Template Content
    $TemplateContent = Get-Content -Path $TemplateFile -Raw
    
    # --- 2. Locate HO and Filter Client Casinos ---
    
    # Find the HO casino using the boolean flag
    $HoEntry = $AllCasinos | Where-Object { $_.is_head_office -eq $true } | Select-Object -First 1

    if (-not $HoEntry) {
        Write-Error "Head Office casino (is_head_office: true) not found in $JsonFile. Cannot proceed."
        exit 1
    }
    
    # Filter out the HO casino, leaving only the clients
    $ClientCasinos = $AllCasinos | Where-Object { $_.is_head_office -ne $true }
    
    # Define HO variables for file metadata and path
    $HoCasinoName = $HoEntry.name
    $HoCasinoNameUpper = $HoCasinoName.ToUpper()
    $MasterSiteUser = "mkt_rep_ho"
    
    # Define the final target path using the fixed "00_" prefix
    $FolderID = "00_$($HoCasinoNameUpper)"
    $TargetDir = Join-Path -Path $BaseReleaseDir -ChildPath $FolderID
    $TargetFile = Join-Path -Path $TargetDir -ChildPath $TargetSubPath

    Write-Host "Processing HO Configuration for: $($FolderID)"

    # --- 3. Build the SITE_REGISTRATIONS and SCHEMA_OWNERSHIPS blocks ---
    
    $SiteRegistrations = New-Object System.Text.StringBuilder
    $SchemaOwners = New-Object System.Text.StringBuilder
    $RegistrationCount = 0
    $TotalSchemaLineCount = 0

    # Indent for generated lines
    $Indent = "    "
    
    # --- A. Build grips_rep_config.register_site statements ---
    foreach ($ClientCasino in $ClientCasinos) {
        
        $ClientCasinoNameLower = $ClientCasino.name.ToLower()
        $ClientCasinoTnsAlias = $ClientCasino.tns
        
        if ([string]::IsNullOrEmpty($ClientCasinoTnsAlias)) {
             Write-Warning "Skipping client casino $($ClientCasino.name) because 'tns' field is missing. Please check the JSON data."
             continue
        }
        
        $RegistrationCount++
        
        $SiteUser = "mkt_rep_$($ClientCasinoNameLower)"
        $LinkName = "$($ClientCasinoNameLower).glx_ho"
        $RemoteRepAdmin = "rep_admin_$($ClientCasinoNameLower)"
        $Password = "geheim"

        # Padding must be applied outside of the single quotes to keep the data clean.
        $Field1 = "'$SiteUser',"
        $Field2 = " '$LinkName',"
        $Field3 = " '$RemoteRepAdmin',"
        $Field4 = " '$Password',"

        # Fixed width formatting applied to fields for perfect column alignment:
        $SiteLine = [string]::Format(
            "{0}grips_rep_config.register_site ({1,-18}{2,-19}{3,-22}{4,-12} '{5}');",
            $Indent, $Field1, $Field2, $Field3, $Field4, $ClientCasinoTnsAlias
        )
        [void]$SiteRegistrations.AppendLine($SiteLine)
    }
    
    # --- B. Build grips_rep_config.set_site_owner statements ---
    foreach ($ClientCasino in $ClientCasinos) {
        
        $ClientCasinoNameLower = $ClientCasino.name.ToLower()
        $SiteUser = "mkt_rep_$($ClientCasinoNameLower)"

        # Add an empty line between sites' schema owners
        if ($TotalSchemaLineCount -gt 0) {
             [void]$SchemaOwners.AppendLine()
        }

        foreach ($Schema in $Schemas) {
            $TotalSchemaLineCount++

            # Padding must be applied outside of the single quotes to keep the data clean.
            $FieldA = "'$Schema',"
            $FieldB = " '$SiteUser',"
            $FieldC = " '$Schema'"
            
            # Fixed width formatting applied to fields for perfect column alignment:
            $SchemaLine = [string]::Format(
                "{0}grips_rep_config.set_site_owner({1,-15}{2,-19}{3});",
                $Indent, $FieldA, $FieldB, $FieldC
            )
            [void]$SchemaOwners.AppendLine($SchemaLine)
        }
    }

    # --- 4. Final Token Replacement and File Writing ---
    
    $NewContent = $TemplateContent -replace '{{CASINO_NAME_UPPER}}', $HoCasinoNameUpper `
                                 -replace '{{MASTER_SITE_USER}}', $MasterSiteUser `
                                 -replace '{{REGISTRATION_COUNT}}', $RegistrationCount `
                                 -replace '{{SITE_REGISTRATIONS}}', $SiteRegistrations.ToString().Trim() `
                                 -replace '{{SCHEMA_OWNERSHIPS}}', $SchemaOwners.ToString().Trim()
                                 
    # Ensure Target Directory Exists
    $TargetSubDir = Join-Path -Path $TargetDir -ChildPath "sraddindb\mkt_rep"
    if (-not (Test-Path -Path $TargetSubDir)) {
        New-Item -Path $TargetSubDir -ItemType Directory -Force | Out-Null
    }
    
    # Write Content to File
    try {
        $NewContent | Out-File -FilePath $TargetFile -Encoding UTF8 -Force
        Write-Host "  -> Successfully written HO config to: $TargetFile" -ForegroundColor Green
    } catch {
        Write-Error "Error writing file for $($HoCasinoNameUpper): $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Finished HO config generation." -ForegroundColor Green
}
#endregion
#region --- DatabaseConfig
function New-DatabaseConfig {
    Write-Host "--- Starting generation of $TargetSubPath files for all casinos ---"

	#Configuration
	$JsonFile       = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\replicatedscope.json"
	$TemplateFile   = "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates\SRADDINDB\database_config.sql.template"
	$BaseReleaseDir = "D:\SRADDINDB_Release\config\database"
	$TargetSubPath  = "config.sql"

    # --- 1. Load Data and Template ---
    if (-not (Test-Path -Path $JsonFile -PathType Leaf)) {
        Write-Error "Configuration file '$JsonFile' not found. Cannot proceed."
        exit 1
    }
    if (-not (Test-Path -Path $TemplateFile -PathType Leaf)) {
        Write-Error "Template file '$TemplateFile' not found. Cannot proceed."
        exit 1
    }

    # Load JSON data
    try {
        $AllCasinos = Get-Content -Path $JsonFile | ConvertFrom-Json
    } catch {
        Write-Error "Error parsing JSON file: $($_.Exception.Message)"
        exit 1
    }

    # Load Template Content
    $TemplateContent = Get-Content -Path $TemplateFile -Raw
    
    # --- 2. Loop through all casinos and generate files ---
    
    for ($i = 0; $i -lt $AllCasinos.Count; $i++) {
        $Casino = $AllCasinos[$i]
        
        # Determine Folder Path (e.g., 00_MUC, 01_VIE)
        $Prefix = "{0:D2}" -f $i
        $CasinoNameUpper = $Casino.name.ToUpper()
        $FolderID = "$($Prefix)_$($CasinoNameUpper)" # e.g., 00_MUC
        
        # TargetDir is now SRADDINDB_Release\config\database\00_MUC
        $TargetDir = Join-Path -Path $BaseReleaseDir -ChildPath $FolderID
        $TargetFile = Join-Path -Path $TargetDir -ChildPath $TargetSubPath # config.sql
        
        Write-Host "Processing Casino: $($FolderID)"

        # Data extraction (using dot notation for clarity)
        $TnsAlias = $Casino.tns
        $Service = $Casino.service
        $IP = $Casino.ip

        # --- 3. Final Token Replacement and File Writing ---
        
        # IP must NOT be surrounded by single quotes in the SQL output
        $NewContent = $TemplateContent -replace '{{FOLDER_ID}}', $FolderID `
                                     -replace '{{TNS_ALIAS}}', $TnsAlias `
                                     -replace '{{SERVICE}}', $Service `
                                     -replace '{{IP}}', $IP
                                     
        # Ensure Target Casino ID Directory Exists (e.g., 00_MUC)
        if (-not (Test-Path -Path $TargetDir)) {
            New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
        }
        
        # Write Content to File
        try {
            $NewContent | Out-File -FilePath $TargetFile -Encoding UTF8 -Force
            Write-Host "  -> Successfully written config to: $TargetFile"
        } catch {
            Write-Error "Error writing file for $($FolderID): $($_.Exception.Message)"
        }
    }

    Write-Host ""
    Write-Host "Finished configuring all $($AllCasinos.Count) $TargetSubPath files." -ForegroundColor Green
}
#endregion
#region --- FULLY configure CasinoSynchronization
function Set-SRADDINDBConfig {
    $server = $ENV:MODULUS_SERVER
    if ($server -notin ("DB","1VM")) {
        Write-Log "Not on on DB server, exiting!" ERROR
        Return
    }

    write-log "Set-SRADDINDBConfig" -Header
    New-BasicAddinConfig
    New-ClAddinConfig
    New-OwnerAddinConfig
    New-SrAddinConfig
    New-SrAddinConfigSite
    New-DatabaseConfig
}
#endregion
#endregion

#region --- exporting functions per server
$server = $ENV:MODULUS_SERVER
if ($server -in ("APP","1VM")) {
    Export-ModuleMember -Function @('Set-CasinoSyncConfig','Set-ReplicatedScopeOra')
}
if ($server -eq "DB") {
    Export-ModuleMember -Function @('Set-SRADDINDBConfig','Set-ReplicatedScopeOra')
}
#endregion