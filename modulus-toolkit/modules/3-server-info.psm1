#tlukas, 07.10.2024

#write-host "Loading 3-server-info.psm1!" -ForegroundColor Green

#region --- environment variables
function Get-MOD-ENVVARs {
    # Get the environment variables from the JSON
    $desiredENVVARs = (Get-MOD-DesiredENVVARs).environmentvariables

    # Get current environment variables that match the keys in $scope
    $actualENVVARs = Get-ChildItem Env: | Where-Object { $_.Name -in $desiredENVVARs.psobject.Properties.Name }

    Write-log "Get-MOD-ENVVARs" -Header
    
    # Output each environment variable in green
    foreach ($envVar in $actualENVVARs) {
        Write-Host "$($envVar.Name) = $($envVar.Value)" #-ForegroundColor Gray
    }
}

function Compare-MOD-ENVVARs {        
    Write-Log "Compare-MOD-ENVVARs" -Header

    $PH_TIMEZONE     = Get-GeneralTimezone
    $PH_APPSERVER_HN = Get-MOD-APP-hostname
    $PH_DBSERVER_HN  = Get-MOD-DB-hostname
    
    $desiredENVVARs  = Get-MOD-DesiredENVVARs
    
    # Initialize an array to store comparison results
    $comparisonResults = @()

    foreach ($envVar in $desiredENVVARs.EnvironmentVariables.PSObject.Properties) {
        # Replace placeholders in the desired state
        $desiredValue = $envVar.Value `
            -replace '{{PH_APPSERVER_HN}}', $PH_APPSERVER_HN `
            -replace '{{PH_DBSERVER_HN}}' , $PH_DBSERVER_HN `
            -replace '{{PH_TIMEZONE}}'    , $PH_TIMEZONE
        
        # Get the live environment variable value
        $liveValue = [System.Environment]::GetEnvironmentVariable($envVar.Name, [System.EnvironmentVariableTarget]::Machine)
        
        # Compare desired value to live value
        if ($liveValue -eq $desiredValue) {
            $comparisonResults += "$($envVar.Name): MATCH"
			Write-Host "$($envVar.Name): MATCH" -ForegroundColor Green
        } elseif ($liveValue -eq $null) {
            $comparisonResults += "$($envVar.Name): MISSING in live environment"
			Write-Host "$($envVar.Name): MISSING in live environment" -ForegroundColor Red
        } else {
            $comparisonResults += "$($envVar.Name): MISMATCH (Desired: $desiredValue, Live: $liveValue)"
			Write-Host "$($envVar.Name): MISMATCH (Desired: $desiredValue, Live: $liveValue)" -ForegroundColor Yellow
        }
    }
}
#endregion

#region --- network adapters
function Get-MOD-NetworkAdaptersConfig {
    <#
    .SYNOPSIS
        Retrieves and transforms network adapter configuration for the current server
        into a standardized PowerShell object format (matching Get-NetIPConfiguration).
    .DESCRIPTION
        Reads the configuration for the current server (via Get-MOD-Server) and converts
        the JSON structure (IP, SNM, DG) into a flat array of standardized objects
        (IPAddress, PrefixLength, NextHop).
    .OUTPUTS
        [PSCustomObject[]] - Array of standardized network configuration objects.
    #>
    [CmdletBinding()]
    param()

    # --- Internal Helper for Subnet Mask Conversion ---
    function Convert-SubnetMaskToPrefixLength {
        param(
            [Parameter(Mandatory=$true)][string]$SubnetMask
        )
        # Handle the case where the mask is empty or invalid
        if ([string]::IsNullOrWhiteSpace($SubnetMask) -or $SubnetMask -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            return $null
        }
        
        try {
            $prefix = 0
            $maskBytes = $SubnetMask.Split('.')

            foreach ($byteString in $maskBytes) {
                # Convert the byte string (e.g., "255") to a byte (255)
                [byte]$byte = [byte]::Parse($byteString) 

                # Convert the byte to its binary string (e.g., "11111111")
                # and count the '1' characters
                $binaryString = [System.Convert]::ToString($byte, 2).PadLeft(8, '0')
                
                # Count the '1' characters in the binary string
                $prefix += ($binaryString -split '' | Where-Object { $_ -eq '1' }).Count
            }
            return $prefix
        } catch {
            # Removed Write-Warning to keep the output stream clean, assuming caller handles errors
            return $null
        }
    }
    # ----------------------------------------------------------------------


    # 1. Get the current server's configuration block using the existing helper.
    $serverConfig = Get-MOD-Server

    if (-not $serverConfig) {
        throw "Get-MOD-Server failed to return configuration."
    }

    # 2. Access the networkAdapters hashtable directly.
    $networkAdaptersHash = $serverConfig.networkAdapters

    if (-not $networkAdaptersHash) {
        Write-Warning "No 'networkAdapters' key found in the current server's configuration."
        return @()
    }

    # 3. Transform the hashtable values into the standardized array structure.
    $standardizedConfig = $networkAdaptersHash.Values | ForEach-Object {
        $adapterConfig = $_
        
        # Convert SNM (dotted decimal) to PrefixLength (integer)
        $prefixLength = Convert-SubnetMaskToPrefixLength -SubnetMask $adapterConfig.SNM

        # Clean the DNS array by filtering out empty/whitespace values
        $cleanDNSServers = @(
            $adapterConfig.DNS | 
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
        )

        [PSCustomObject]@{
            # Standard PowerShell Network Properties
            InterfaceAlias = $adapterConfig.name
            IPAddress      = $adapterConfig.IP
            PrefixLength   = $prefixLength
            NextHop        = $adapterConfig.DG
            DNSServer      = $cleanDNSServers 
            
            # Other JSON properties (kept for completeness)
            VLAN           = $adapterConfig.VLAN
            DhcpEnabled    = $adapterConfig.DHCP
        }
    }
    
    return $standardizedConfig
}

function Get-MOD-Network {
    Write-Log "Get-MOD-Network" -Header

    # 1. Get the standardized desired configuration from the JSON helper
    $desiredAdapters = Get-MOD-NetworkAdaptersConfig
    
    if (-not $desiredAdapters) {
        Write-Warning "No desired network adapter configurations were retrieved."
        return
    }

    # 2. Filter live adapters based on the InterfaceAlias names found in the config
    $adapterNames = $desiredAdapters.InterfaceAlias
    
    $liveAdapters = Get-NetAdapter | Where-Object { 
        $adapterNames -contains $_.Name
    } | Sort-Object InterfaceDescription

    $output = @()

    # 3. Iterate over the live adapters and merge with desired config
    foreach ($liveAdapter in $liveAdapters) {
        $adapterName = $liveAdapter.Name
        
        # Get the current live IP configuration
        $liveConfig = Get-NetIPConfiguration -InterfaceAlias $adapterName
        
        # Get the desired configuration object for this adapter
        $desiredConfig = $desiredAdapters | Where-Object { $_.InterfaceAlias -eq $adapterName } | Select-Object -First 1

        # Extract live values
        $liveIPv4 = ($liveConfig.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', '
        $livePrefix = ($liveConfig.IPv4Address | ForEach-Object { $_.PrefixLength }) -join ', '
        $liveGateway = ($liveConfig.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
        $liveDNS = ($liveConfig.DnsServer | ForEach-Object { $_.ServerAddresses }) -join ', '

        # Format the output object
        $output += [PSCustomObject]@{
            'Adapter Name'      = $adapterName
            # Desired Configuration
            'Desired IP'        = $desiredConfig.IPAddress
            'Desired Prefix'    = $desiredConfig.PrefixLength
            'Desired Gateway'   = $desiredConfig.NextHop
            'Desired DNS'       = $desiredConfig.DNSServer -join ', '
            # Live Configuration
            'Live IP'           = $liveIPv4
            'Live Prefix'       = $livePrefix
            'Live Gateway'      = $liveGateway
            'Live DNS'          = $liveDNS
            'DHCP Enabled'      = ($liveConfig.IPv4Interface -ne $null -and $liveConfig.IPv4Interface.Dhcp -eq 'Enabled')
            'Status'            = $liveAdapter.Status
        }
    }
    
    # 4. Output the combined object array
    return $output
}

function Compare-MOD-Network {
    #[CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$InterfaceAlias,

        [Parameter(Mandatory=$false)]
        [switch]$Silent,

        [Parameter(Mandatory=$false)]
        $DesiredConfig = (Get-MOD-NetworkAdaptersConfig),
        
        [Parameter(Mandatory=$false)]
        [switch]$FullScope # <-- NEW: Allows explicit override to check all adapters
    )

    # Helper function for conditional logging
    function Write-CompareLog {
        param(
            [string]$Message,
            [string]$Level,
            [switch]$Header
        )
        if (-not $Silent) {
            if ($Header) {
                Write-Log -Message $Message -Header
            } else {
               Write-Log -Message $Message -Level $Level
            }
        }
    }

    Write-CompareLog -Message "Compare-MOD-Network" -Level INFO -Header

    if (-not $DesiredConfig) {
        Write-Log "No desired network adapter configurations were retrieved." -Level ERROR
        return @()
    }

    # --- NEW: Determine Default Scope Based on Server Role ---
    $serverRole = $env:MODULUS_SERVER
    $defaultScope = @() # Initialize empty scope

    if (-not [string]::IsNullOrWhiteSpace($serverRole)) {
        switch ($serverRole.ToUpper()) {
            "DB" { $defaultScope = @("OFFICE") } 
            "APP" { $defaultScope = @("OFFICE") } 
            "FS" { $defaultScope = @("OFFICE", "FLOOR") } 
            "1VM" { $defaultScope = @("OFFICE", "FLOOR") } 
            default {
                Write-Log "Unrecognized server role '$serverRole'. Cannot determine default scope. Falling back to Full Scope." -Level WARNING
                $FullScope = $true # Force full scope if role is unknown
            }
        }
    } else {
        Write-Log "MODULUS_SERVER environment variable not set. Falling back to Full Scope." -Level WARNING
        $FullScope = $true # Force full scope if role is missing
    }
    # --- END Scope Determination ---

    $adaptersToProcess = @()

    # --- MODIFIED: Filtering Logic to use the determined scope ---
    if ($InterfaceAlias) {
        # 1. Highest Priority: Specific aliases provided (still use -in for array handling)
        Write-CompareLog "Targeting specific adapter(s) from input: $($InterfaceAlias -join ', ')" -Level DEBUG
        $adaptersToProcess = $DesiredConfig | Where-Object { $_.InterfaceAlias -in $InterfaceAlias }
    } elseif ($FullScope) {
        # 2. Full scope requested or forced by role check
        Write-CompareLog "Processing ALL desired adapters." -Level DEBUG
        $adaptersToProcess = $DesiredConfig
    } else {
        # 3. Default scope (based on role)
        Write-CompareLog "Using default scope for role '$serverRole'. Adapters: $($defaultScope -join ', ')" -Level DEBUG
        $adaptersToProcess = $DesiredConfig | Where-Object { $_.InterfaceAlias -in $defaultScope }
    }
    # --- END Filtering Logic ---
    
    if ($adaptersToProcess.Count -eq 0) {
        # Note: If $InterfaceAlias was an array, we show the joined string of the array.
        $aliasString = if ($InterfaceAlias -is [System.Collections.IEnumerable] -and $InterfaceAlias -isnot [string]) {
            $InterfaceAlias -join ', '
        } else {
            $InterfaceAlias
        }
        Write-CompareLog "No desired configuration found for alias(es) '$aliasString'. Assuming match." -Level WARNING
        return @()
    }

    $changesRequired = @()

    # 2. Iterate through the desired configuration objects
    foreach ($desiredConfig in $adaptersToProcess) {
        $alias = $desiredConfig.InterfaceAlias
        $mismatchedComponents = @()

        Write-CompareLog "Checking adapter: $alias" -Level INFO

        $liveAdapter = Get-NetAdapter -Name $alias -ErrorAction SilentlyContinue

        if (-not $liveAdapter) {
            Write-CompareLog "Adapter '$alias' MISSING in live configuration. Critical setup required." -Level ERROR
            $changesRequired += [PSCustomObject]@{
                InterfaceAlias = $alias
                ChangeRequired = $true
                Reasons        = @("AdapterMissing", "DHCP", "IP", "Gateway", "DNS")
            }
            continue
        }

        $liveIPInterface = Get-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $liveIPConfig = Get-NetIPConfiguration -InterfaceAlias $alias -ErrorAction SilentlyContinue

        # --- 1. DHCP Status Comparison ---
        $desiredDhcpState = if ($desiredConfig.DhcpEnabled) { "Enabled" } else { "Disabled" }
        $liveDhcpState = $liveIPInterface.Dhcp

        if ($liveDhcpState -ne $desiredDhcpState) {
             Write-CompareLog "  DHCP Status: MISMATCH (Desired: $desiredDhcpState, Live: $liveDhcpState)" -Level ERROR
             $mismatchedComponents += "DHCP"
        } else {
             Write-CompareLog "  DHCP Status: MATCH ($liveDhcpState)" -Level SUCCESS
        }

        # --- Static IP/Gateway/DNS Comparisons (Only run if static IP is desired) ---
        if (-not $desiredConfig.DhcpEnabled) {

            # 2. IP Address & Prefix Length Comparison
            $liveIPv4Address = $liveIPConfig.IPv4Address | Where-Object {$_.PrefixLength -eq $desiredConfig.PrefixLength -and $_.IPAddress -ne "127.0.0.1"} | Select-Object -First 1

            if ($liveIPv4Address -and $liveIPv4Address.IPAddress -eq $desiredConfig.IPAddress -and $liveIPv4Address.PrefixLength -eq $desiredConfig.PrefixLength) {
                Write-CompareLog "  Static IP/Prefix: MATCH ($($liveIPv4Address.IPAddress)/$($liveIPv4Address.PrefixLength))" -Level SUCCESS
            } else {
                Write-CompareLog "  Static IP/Prefix: MISMATCH (Desired: $($desiredConfig.IPAddress)/$($desiredConfig.PrefixLength), Live: $($liveIPv4Address.IPAddress)/$($liveIPv4Address.PrefixLength))" -Level ERROR
                $mismatchedComponents += "IP"
            }

            # 3. Default Gateway comparison
            $liveGateway = $liveIPConfig.IPv4DefaultGateway.NextHop | Select-Object -First 1
            $desiredGateway = $desiredConfig.NextHop

            $liveGatewayNorm = [string]$liveGateway
            $desiredGatewayNorm = [string]$desiredGateway

            # Check if both are empty/null (expected for no gateway)
            if ([string]::IsNullOrWhiteSpace($liveGatewayNorm) -and [string]::IsNullOrWhiteSpace($desiredGatewayNorm)) {
                Write-CompareLog "  Default Gateway: MATCH (Both Empty)" -Level SUCCESS
            }
            # Check if both are matching explicit IPs
            elseif ($liveGatewayNorm -ceq $desiredGatewayNorm) {
                Write-CompareLog "  Default Gateway: MATCH ($liveGatewayNorm)" -Level SUCCESS
            }
            # All other cases are a mismatch
            else {
                Write-CompareLog "  Default Gateway: MISMATCH (Desired: $($desiredGatewayNorm -replace '^$', 'Empty'), Live: $($liveGatewayNorm -replace '^$', 'Empty'))" -Level WARNING
                $mismatchedComponents += "Gateway"
            }
        }

        # 4. DNS comparison (Checked for both DHCP and Static)
        $liveDNSArray = @(Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne "127.0.0.1" } |
                            Sort-Object

        $desiredDNSArray = $desiredConfig.DNSServer | Sort-Object

        $desiredDNSString = $desiredDNSArray -join ', '
        $liveDNSString = $liveDNSArray -join ', '

        if ($desiredDNSString -ceq $liveDNSString) {
            Write-CompareLog "  DNS Servers: MATCH ($liveDNSString)" -Level SUCCESS
        } else {
            Write-CompareLog "  DNS Servers: MISMATCH (Desired: $desiredDNSString, Live: $liveDNSString)" -Level WARNING
            $mismatchedComponents += "DNS"
        }

        # If any component mismatched, add a change object to the output
        if ($mismatchedComponents.Count -gt 0) {
            $changesRequired += [PSCustomObject]@{
                InterfaceAlias = $alias
                ChangeRequired = $true
                Reasons        = $mismatchedComponents
            }
        } else {
            Write-CompareLog "Adapter '$alias': Configuration is fully correct." -Level SUCCESS
        }
    }

    # 3. Final Summary & Output
    if ($changesRequired.Count -eq 0) {
        Write-CompareLog "Network configuration: OK - All desired adapters match live state." -Level SUCCESS
    } else {
        Write-CompareLog "Network configuration: MISMATCHES FOUND. Returning $($changesRequired.Count) required change object(s)." -Level ERROR
    }

    # Output the list of required changes to the pipeline regardless of $Silent
    return $changesRequired
}
#endregion

#region --- log-level helpers (json, xml, unified)
function Get-ServiceMapping {
    [CmdletBinding()]
    param()

    $jsonPath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\mod-loglevels.json"
    if (-not (Test-Path $jsonPath)) {
        throw "JSON mapping file not found at $jsonPath."
    }
    try {
        $jsonContent = Get-Content -Path $jsonPath -Raw
        $mapping = $jsonContent | ConvertFrom-Json
        return $mapping.services
    }
    catch {
        throw "Failed to load or parse JSON mapping file: $_"
    }
}

function Get-LoggingLevelFromXmlConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,
        [Parameter(Mandatory)]
        [string]$LoggingXPath
    )

    if (-not (Test-Path $ConfigFilePath)) {
        return "File not found"
    }
    try {
        [xml]$xmlConfig = Get-Content -Path $ConfigFilePath -ErrorAction Stop
        $node = $xmlConfig.SelectSingleNode($LoggingXPath)
        if ($node -and $node.Attributes["value"]) {
            return $node.Attributes["value"].Value
        }
        else {
            return "XPath not found or missing 'value' attribute"
        }
    }
    catch {
        return "Error reading file: $_"
    }
}

function Set-LoggingLevelInXmlConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,
        [Parameter(Mandatory)]
        [string]$LoggingXPath,
        [Parameter(Mandatory)]
        [string]$NewLevel
    )

    if (-not (Test-Path $ConfigFilePath)) {
        throw "Configuration file not found: $ConfigFilePath"
    }
    try {
        [xml]$xmlConfig = Get-Content -Path $ConfigFilePath -ErrorAction Stop
        $node = $xmlConfig.SelectSingleNode($LoggingXPath)
        if ($node -and $node.Attributes["value"]) {
            $node.Attributes["value"].Value = $NewLevel
            $xmlConfig.Save($ConfigFilePath)
            return $true
        }
        else {
            throw "XPath '$LoggingXPath' not found or missing 'value' attribute in $ConfigFilePath."
        }
    }
    catch {
        throw "Error updating config file '$ConfigFilePath': $_"
    }
}

function Get-LoggingLevelFromJsonConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,
        [Parameter(Mandatory)]
        [string]$JsonKeyPath
    )

    if (-not (Test-Path $ConfigFilePath)) {
        return "File not found"
    }
    try {
        $jsonContent = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
        $keys = $JsonKeyPath.Split('.')
        $currentObj = $jsonContent
        foreach ($key in $keys) {
            if ($currentObj.PSObject.Properties[$key]) {
                $currentObj = $currentObj.$key
            }
            else {
                return "Key path not found"
            }
        }
        return $currentObj
    }
    catch {
        return "Error reading JSON file: $_"
    }
}

function Set-LoggingLevelInJsonConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,
        [Parameter(Mandatory)]
        [string]$JsonKeyPath,
        [Parameter(Mandatory)]
        [string]$NewLevel
    )

    if (-not (Test-Path $ConfigFilePath)) {
        throw "Configuration file not found: $ConfigFilePath"
    }
    try {
        $jsonContent = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
        $keys = $JsonKeyPath.Split('.')
        $currentObj = $jsonContent
        for ($i = 0; $i -lt $keys.Length - 1; $i++) {
            $key = $keys[$i]
            if ($currentObj.PSObject.Properties[$key]) {
                $currentObj = $currentObj.$key
            }
            else {
                throw "Key path not found in JSON: $JsonKeyPath"
            }
        }
        $finalKey = $keys[-1]
        if ($currentObj.PSObject.Properties[$finalKey]) {
            $currentObj.$finalKey = $NewLevel
        }
        else {
            throw "Final key '$finalKey' not found in JSON: $JsonKeyPath"
        }
        # Save the updated JSON (using a sufficient depth for nested objects)
        $jsonContent | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Force
        return $true
    }
    catch {
        throw "Error updating JSON config file '$ConfigFilePath': $_"
    }
}

function Get-LoggingLevelFromConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,
        [Parameter(Mandatory)]
        [string]$LoggingKey,  # This is either an XPath or a JSON key path
        [Parameter(Mandatory)]
        [string]$Type         # "xml" or "json"
    )
    if ($Type -eq "json") {
        return Get-LoggingLevelFromJsonConfig -ConfigFilePath $ConfigFilePath -JsonKeyPath $LoggingKey
    }
    else {
        return Get-LoggingLevelFromXmlConfig -ConfigFilePath $ConfigFilePath -LoggingXPath $LoggingKey
    }
}

function Set-LoggingLevelInConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigFilePath,
        [Parameter(Mandatory)]
        [string]$LoggingKey,  # Either XPath or JSON key path
        [Parameter(Mandatory)]
        [string]$NewLevel,
        [Parameter(Mandatory)]
        [string]$Type         # "xml" or "json"
    )
    if ($Type -eq "json") {
        return Set-LoggingLevelInJsonConfig -ConfigFilePath $ConfigFilePath -JsonKeyPath $LoggingKey -NewLevel $NewLevel
    }
    else {
        return Set-LoggingLevelInXmlConfig -ConfigFilePath $ConfigFilePath -LoggingXPath $LoggingKey -NewLevel $NewLevel
    }
}
#endregion

#region --- log-level info
function Get-MOD-AllLogLevels {
    <#
    .SYNOPSIS
      Retrieves logging information for all services defined in the JSON mapping.
      
    .DESCRIPTION
      For each service defined in C:\temp\services.json, this function iterates over
      the defined config files and their log appender(s), then retrieves the current
      logging level using the appropriate method (XML or JSON).
      
    .EXAMPLE
      Get-AllServicesLoggingInfo
    #>
    [CmdletBinding()]
    param()

    $servicesMapping = Get-ServiceMapping
    $results = @()

    foreach ($svc in $servicesMapping) {
        $serviceName = $svc.serviceName
        $displayName = $svc.displayName
        if ($svc.configFiles -and $svc.configFiles.Count -gt 0) {
            foreach ($cfg in $svc.configFiles) {
                #$fileName = $cfg.fileName
                $configPath = $cfg.path
                $type = $cfg.type  # expect "xml" or "json"
                if ($cfg.logAppenders -and $cfg.logAppenders.Count -gt 0) {
                    foreach ($appender in $cfg.logAppenders) {
                        $appenderName = $appender.name
                        # Choose the appropriate key based on type
                        if ($type -eq "json") {
                            $loggingKey = $appender.jsonKeyPath
                        }
                        else {
                            $loggingKey = $appender.loggingXPath
                        }
                        $currentLevel = Get-LoggingLevelFromConfig -ConfigFilePath $configPath -LoggingKey $loggingKey -Type $type
                        $results += [PSCustomObject]@{
                            ServiceName  = $serviceName
                            DisplayName  = $displayName
                            ConfigFile   = $configPath
                            Appender     = $appenderName
                            LoggingLevel = $currentLevel
                        }
                    }
                }
                else {
                    $results += [PSCustomObject]@{
                        ServiceName  = $serviceName
                        DisplayName  = $displayName
                        ConfigFile   = $configPath
                        Appender     = "N/A"
                        LoggingLevel = "No appender mapping"
                    }
                }
            }
        }
        else {
            $results += [PSCustomObject]@{
                ServiceName  = $serviceName
                DisplayName  = $displayName
                ConfigFile   = "N/A"
                Appender     = "N/A"
                LoggingLevel = "No config files defined"
            }
        }
    }

    #$results 

    return $results | Format-Table serviceName, appender, logginglevel
}

function Get-MOD-ServiceLogLevel {
    <#
    .SYNOPSIS
      Retrieves logging configuration details for a specific service.
    
    .DESCRIPTION
      This function loads the JSON mapping, finds the target service by its serviceName,
      then iterates over its configuration files and log appenders. It uses the appropriate
      helper functions to read the current logging level from each config file and outputs a
      structured view with ServiceName, DisplayName, ConfigFile, Appender, and LoggingLevel.
    
    .PARAMETER ServiceName
      The name of the service (as defined in the JSON mapping) for which to display logging info.
    
    .EXAMPLE
      Get-SpecificServiceLoggingInfo -ServiceName "GalaxisAuthenticationService"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName
    )
    
    $servicesMapping = Get-ServiceMapping
    $targetService = $servicesMapping | Where-Object { $_.serviceName -eq $ServiceName }
    
    if (-not $targetService) {
        Write-Error "Service '$ServiceName' not found in mapping."
        return
    }
    
    $results = @()
    foreach ($cfg in $targetService.configFiles) {
        $type = $cfg.type
        if ($cfg.logAppenders -and $cfg.logAppenders.Count -gt 0) {
            foreach ($appender in $cfg.logAppenders) {
                if ($type -eq "json") {
                    $loggingKey = $appender.jsonKeyPath
                }
                else {
                    $loggingKey = $appender.loggingXPath
                }
                $currentLevel = Get-LoggingLevelFromConfig -ConfigFilePath $cfg.path -LoggingKey $loggingKey -Type $type
                $results += [PSCustomObject]@{
                    ServiceName  = $targetService.serviceName
                    DisplayName  = $targetService.displayName
                    ConfigFile   = $cfg.path
                    Appender     = $appender.name
                    LoggingLevel = $currentLevel
                }
            }
        }
        else {
            $results += [PSCustomObject]@{
                ServiceName  = $targetService.serviceName
                DisplayName  = $targetService.displayName
                ConfigFile   = $cfg.path
                Appender     = "N/A"
                LoggingLevel = "No appender mapping defined"
            }
        }
    }
    
    $results | Format-Table DisplayName, Appender, LoggingLevel 
}
#endregion

#region --- .NET framework info
function Get-DotNet-Info {
    function Get-DotNetOverview {
    [CmdletBinding()]
    param(
        [switch]$IncludePaths,
        [switch]$KeepAllVersions
    )

    function Get-NetFxVersionFromRelease([int]$release) {
        switch ($release) {
            {$_ -ge 533325} { '4.8.1'; break }
            {$_ -ge 528040} { '4.8'   ; break }
            {$_ -ge 461808} { '4.7.2' ; break }
            {$_ -ge 461308} { '4.7.1' ; break }
            {$_ -ge 460798} { '4.7'   ; break }
            {$_ -ge 394802} { '4.6.2' ; break }
            {$_ -ge 394254} { '4.6.1' ; break }
            {$_ -ge 393295} { '4.6'   ; break }
            {$_ -ge 379893} { '4.5.2' ; break }
            {$_ -ge 378675} { '4.5.1' ; break }
            {$_ -ge 378389} { '4.5'   ; break }
            default         { $null   ; break }
        }
    }

    function Parse-VersionOrZero([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return [version]'0.0.0.0' }
        try { return [version]$s } catch { return [version]'0.0.0.0' }
    }

    $rows = New-Object System.Collections.Generic.List[object]

    # --- SDKs ---
    $sdkRows = @()
    try {
        $sdks = & dotnet --list-sdks 2>$null
        if ($sdks) {
            foreach ($line in $sdks) {
                $parts   = $line -split '\s+\['
                $version = $parts[0].Trim()
                $path    = ($parts[1] -replace '\]','').Trim()
                $sdkRows += [pscustomobject]@{ Category='SDK'; Name='SDK'; Version=$version; Release=$null; Path=$path }
            }
        }
    } catch {}

    if (-not $sdkRows) {
        foreach ($p in @('C:\Program Files\dotnet\sdk','C:\Program Files (x86)\dotnet\sdk')) {
            if (Test-Path $p) {
                Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $sdkRows += [pscustomobject]@{ Category='SDK'; Name='SDK'; Version=$_.Name; Release=$null; Path=$p }
                }
            }
        }
    }
    if (-not $sdkRows) {
        $sdkRows += [pscustomobject]@{ Category='SDK'; Name='SDK'; Version='(none)'; Release=$null; Path=$null }
    }
    $rows.AddRange($sdkRows)

    # --- Runtimes ---
    try {
        $rts = & dotnet --list-runtimes 2>$null
        if ($rts) {
            foreach ($line in $rts) {
                $parts = $line -split '\s+\['
                $left  = $parts[0].Trim()
                $path  = ($parts[1] -replace '\]','').Trim()
                $name, $version = $left -split '\s+', 2
                $rows.Add([pscustomobject]@{ Category='Runtime'; Name=$name; Version=$version; Release=$null; Path=$path })
            }
        }
    } catch {}

    # --- .NET Framework (registry) ---
    $ndpRoots = @(
        'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\NET Framework Setup\NDP'
    )

    foreach ($root in $ndpRoots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $majorKey = $_

            Get-ChildItem $majorKey.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                $k = $_
                foreach ($p in @($k.PSPath, (Join-Path $k.PSPath 'Setup'))) {
                    try { $props = Get-ItemProperty -Path $p -ErrorAction Stop } catch { continue }
                    $install = $props.Install
                    $version = $props.Version
                    $release = $props.Release
                    $ipath   = $props.InstallPath

                    $iname  = $k.PSChildName
                    $parent = $majorKey.PSChildName

                    if ($install -ne 1 -and -not $version -and -not $release) { continue }

                    $name = if ($parent -match '^v\d') {
                        if ($iname -match '^(Full|Client)$') { $iname } else { $parent }
                    } else { $iname }

                    $friendly = $version
                    if ($release) {
                        $mapped = Get-NetFxVersionFromRelease $release
                        if ($mapped) { $friendly = $mapped }
                    }

                    if (-not $friendly -and -not $release) { continue }

                    $rows.Add([pscustomobject]@{
                        Category='Framework'; Name=$name; Version=$friendly; Release=$release; Path=$ipath
                    })
                }
            }

            if ($majorKey.PSChildName -eq 'v3.0') {
                foreach ($comp in 'Windows Communication Foundation','Windows Presentation Foundation') {
                    $compKey = Join-Path $majorKey.PSPath "Setup\$comp"
                    if (Test-Path $compKey) {
                        try {
                            $props = Get-ItemProperty -Path $compKey -ErrorAction Stop
                            if ($props.Install -eq 1 -and $props.Version) {
                                $rows.Add([pscustomobject]@{
                                    Category='Framework'; Name=$comp; Version=$props.Version; Release=$null; Path=$props.InstallPath
                                })
                            }
                        } catch {}
                    }
                }
            }
        }
    }

    # --- Normalize & de-dup ---
    $rows = $rows | ForEach-Object {
        $normName = ($_.Name -replace '\s+',' ').Trim()
        $normVer  = if ([string]::IsNullOrWhiteSpace($_.Version)) { $null } else { $_.Version.Trim() }
        $normPath = if ([string]::IsNullOrWhiteSpace($_.Path))    { $null } else { $_.Path.Trim() }
        [pscustomobject]@{
            Category = $_.Category
            Name     = $normName
            Version  = $normVer
            Release  = $_.Release
            Path     = $normPath
        }
    }

    $rows = $rows | Sort-Object Category, Name, Version, Release -Unique

    if (-not $KeepAllVersions) {
        $rows = $rows |
            Group-Object Category, Name |
            ForEach-Object {
                $group = $_.Group
                $group |
                    Sort-Object -Property `
                        @{ Expression = { Parse-VersionOrZero $_.Version }; Descending = $true }, `
                        @{ Expression = { $_.Release -ne $null };          Descending = $true } |
                    Select-Object -First 1
            }
    }

    if ($IncludePaths) {
        $rows | Select-Object Category, Name, Version, Release, Path
    } else {
        $rows | Select-Object Category, Name, Version, Release
    }
}

}
#endregion

#region --- device manager with hidden devices
function Open-DeviceManager {
    # Save the current value of DEVMGR_SHOW_NONPRESENT_DEVICES
    $originalValue = [System.Environment]::GetEnvironmentVariable("DEVMGR_SHOW_NONPRESENT_DEVICES", [System.EnvironmentVariableTarget]::Process)

    try {
        # Set DEVMGR_SHOW_NONPRESENT_DEVICES to 1 for the current process
        [System.Environment]::SetEnvironmentVariable("DEVMGR_SHOW_NONPRESENT_DEVICES", "1", [System.EnvironmentVariableTarget]::Process)

        # Start Device Manager with the /s flag to show hidden devices
        Start-Process -FilePath "devmgmt.msc" -ArgumentList "/s"
    } catch {
        Write-Error "Failed to open Device Manager: $_"
    } finally {
        # Restore the original value of DEVMGR_SHOW_NONPRESENT_DEVICES
        if ($originalValue) {
            [System.Environment]::SetEnvironmentVariable("DEVMGR_SHOW_NONPRESENT_DEVICES", $originalValue, [System.EnvironmentVariableTarget]::Process)
        } else {
            [System.Environment]::SetEnvironmentVariable("DEVMGR_SHOW_NONPRESENT_DEVICES", $null, [System.EnvironmentVariableTarget]::Process)
        }
    }
}
#endregion

#Export-ModuleMember -Function * -Alias * -Variable *