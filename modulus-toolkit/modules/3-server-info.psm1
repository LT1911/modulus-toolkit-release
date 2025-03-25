# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 07.10.2024

#write-host "Loading 3-server-info.psm1!" -ForegroundColor Green

<#INFO
- INFO and CHECK on environment variables
- INFO and CHECK on network adapters
- IPv4 network helpers
#>

#region --- INFO and CHECK on environment variables
function Get-MOD-ENVVARs {
    # Get the environment variables from the JSON
    $desiredENVVARs = (Get-MOD-DesiredENVVARs).environmentvariables

    # Get current environment variables that match the keys in $scope
    $actualENVVARs = Get-ChildItem Env: | Where-Object { $_.Name -in $desiredENVVARs.psobject.Properties.Name }

    write-host "---------------------------" -ForegroundColor Green
    write-host "     Modulus ENVVARs"        -ForegroundColor Green
    write-host "---------------------------" -ForegroundColor Green
    # Output each environment variable in green
    foreach ($envVar in $actualENVVARs) {
        Write-Host "$($envVar.Name) = $($envVar.Value)" #-ForegroundColor Gray
    }
    write-host "---------------------------" -ForegroundColor Green
}

function Compare-MOD-ENVVARs {        
    write-host "---------------------------" -ForegroundColor Green
    write-host " Checking Modulus ENVVARs"   -ForegroundColor Green
    write-host "---------------------------" -ForegroundColor Green
    
    $PH_TIMEZONE     = Get-MOD-TimeZone
    $PH_APPSERVER_HN = Get-MOD-APP-hostname
    $PH_DBSERVER_HN  = Get-MOD-DB-hostname
    
    $desiredENVVARs  = Get-MOD-DesiredENVVARs
    
    # Initialize an array to store comparison results
    $comparisonResults = @()

    foreach ($envVar in $desiredENVVARs.EnvironmentVariables.PSObject.Properties) {
        # Replace placeholders in the desired state
        $desiredValue = $envVar.Value `
            -replace '{PH_APPSERVER_HN}', $PH_APPSERVER_HN `
            -replace '{PH_DBSERVER_HN}' , $PH_DBSERVER_HN `
            -replace '{PH_TIMEZONE}'    , $PH_TIMEZONE
        
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
    write-host "---------------------------" -ForegroundColor Green
    # Output results
    #return $comparisonResults
}
#endregion

#region --- INFO and CHECK on network adapters
function Get-MOD-Network {
    
    $desiredAdapters = (Get-MOD-Server).networkAdapters

    $networkAdapters = Get-NetAdapter | Where-Object { 
        $adapterName = $_.Name
        $desiredAdapters.AdapterName -contains $adapterName
    } | Sort-Object InterfaceDescription

    # Get IP configuration for each desired adapter
    foreach ($adapter in $networkAdapters) {
        $adapterConfig = Get-NetIPConfiguration -InterfaceAlias $adapter.Name
        $subnetMask    = Get-IPv4SubnetMaskForAdapter -AdapterName $adapter.Name

        # Display the relevant network configuration
        [PSCustomObject]@{
            'Adapter Name'      = $adapter.Name
            #'Interface Index'   = $adapterConfig.InterfaceIndex
            'IPv4 Address'      = ($adapterConfig.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', '
            'IPv4 SNM'          = Convert-PrefixLengthToSubnetMask($subnetMask)
            #'IPv6 Address'      = ($adapterConfig.IPv6Address | ForEach-Object { $_.IPAddress }) -join ', '
            'Default Gateway'   = ($adapterConfig.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
            'DNS Servers'       = ($adapterConfig.DnsServer | ForEach-Object { $_.ServerAddresses }) -join ', '
        }
    }
}

function Compare-MOD-Network {
    write-host "---------------------------" -ForegroundColor Green
    write-host " Checking Modulus Network  " -ForegroundColor Green
    write-host "---------------------------" -ForegroundColor Green
    
    # Retrieve network configuration from JSON
    $config = (Get-MOD-Server).networkAdapters
    
    foreach ($adapter in $config) {
        $adapterName = $adapter.AdapterName
        $desiredIP = $adapter.IPAddress
        $desiredSubnetMask = $adapter.SubnetMask
        $desiredGateway = $adapter.DefaultGateway
        write-host " "
        write-host "Checking adapter:" -ForegroundColor Green
        write-host "$adapterName" -ForegroundColor Yellow

        # Handle empty or null DNS values in JSON
        $desiredDNSArray = @()
        if ($adapter.DNS) {
            $desiredDNSArray = $adapter.DNS | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        }

        # Get live network adapter configuration
        $liveIPConfig = Get-NetIPConfiguration | Where-Object { $_.InterfaceAlias -eq $adapterName }

        if ($liveIPConfig) {
            # IP Address comparison
            $liveIP = $liveIPConfig.IPv4Address.IPAddress
            if ($liveIP -eq $desiredIP) {
                Write-Host "$adapterName IP Address: MATCH" -ForegroundColor Green
            } else {
                Write-Host "$adapterName IP Address: MISMATCH (Desired: $desiredIP, Live: $liveIP)" -ForegroundColor Yellow
            }

            # Subnet Mask comparison
            $prefixLength = Get-IPv4SubnetMaskForAdapter -AdapterName $adapterName
            $liveSubnetMask = Convert-PrefixLengthToSubnetMask -PrefixLength $prefixLength
            if ($liveSubnetMask -eq $desiredSubnetMask) {
                Write-Host "$adapterName Subnet Mask: MATCH" -ForegroundColor Green
            } else {
                Write-Host "$adapterName Subnet Mask: MISMATCH (Desired: $desiredSubnetMask, Live: $liveSubnetMask)" -ForegroundColor Yellow
            }

            # Default Gateway comparison
            $liveGateway = $liveIPConfig.IPv4DefaultGateway.NextHop
            if ([string]::IsNullOrWhiteSpace($desiredGateway) -and [string]::IsNullOrWhiteSpace($liveGateway)) {
                Write-Host "$adapterName Default Gateway: MATCH (Both are empty)" -ForegroundColor Green
            } elseif ($liveGateway -eq $desiredGateway) {
                Write-Host "$adapterName Default Gateway: MATCH" -ForegroundColor Green
            } else {
                Write-Host "$adapterName Default Gateway: MISMATCH (Desired: $desiredGateway, Live: $liveGateway)" -ForegroundColor Yellow
            }

            # DNS comparison
            $liveDNS = Get-IPv4DnsServersForAdapter -AdapterName $adapterName

            # Handle empty or null live DNS
            $liveDNSArray = @()
            if ($liveDNS) {
                $liveDNSArray = $liveDNS | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }

            # Sort and compare both DNS arrays, ensuring they are both sorted and cleaned
            $sortedDesiredDNS = $desiredDNSArray | Sort-Object
            $sortedLiveDNS = $liveDNSArray | Sort-Object
            
            # Convert both arrays into strings for comparison
            $desiredDNSString = $sortedDesiredDNS -join ', '
            $liveDNSString = $sortedLiveDNS -join ', '

            # Compare the sorted and cleaned arrays
            if ($desiredDNSString -eq $liveDNSString) {
                Write-Host "$adapterName DNS Servers: MATCH" -ForegroundColor Green
            } else {
                Write-Host "$adapterName DNS Servers: MISMATCH (Desired: $desiredDNSString, Live: $liveDNSString)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "{$adapterName} MISSING in live configuration" -ForegroundColor Red
        }
    }
    write-host "---------------------------" -ForegroundColor Green
}
#endregion

#region --- IPv4 network helpers
function Convert-PrefixLengthToSubnetMask {
    param (
        [int]$PrefixLength
    )
    $binarySubnetMask = ('1' * $PrefixLength).PadRight(32, '0') -split '(.{8})' | Where-Object { $_ -ne '' } | ForEach-Object { [Convert]::ToInt32($_, 2) }
    return ($binarySubnetMask -join '.')
}

<#
function Get-SubnetMaskPrefixLength {
    param (
        [string]$SubnetMask
    )
    
    return ($SubnetMask -split '\.') | ForEach-Object { [convert]::ToString([int]$_,2).PadLeft(8,'0') } -join '' | ForEach-Object { $_ -eq '1' } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
}
#>

function Get-SubnetMaskPrefixLength {
    param (
        [string]$SubnetMask
    )
    
    # Convert each octet into binary and join them into a single binary string
    $binaryMask = ($SubnetMask -split '\.') | ForEach-Object { [convert]::ToString([int]$_,2).PadLeft(8,'0') }
    $binaryMask = $binaryMask -join ''  # Join the resulting binary strings
    
    # Count the number of '1's in the binary string to get the prefix length
    return ($binaryMask.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

function Get-IPv4SubnetMaskForAdapter {
    param (
        [string]$AdapterName
    )
 
    # Get all network adapters with their IP configurations
    $networkAdapters = Get-NetIPAddress | Where-Object { $_.InterfaceAlias -eq $adapterName } | Where-Object { $_.AddressFamily -eq 'IPv4' }

    # Create an array to hold the results
    $results = @()

    # Loop through each adapter and gather relevant information
    foreach ($adapter in $networkAdapters) {
        # Get the associated network profile
        $profile = Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -eq $adapter.InterfaceAlias }

        # Collect the subnet mask and other relevant details
        $results += [PSCustomObject]@{
            InterfaceAlias  = $adapter.InterfaceAlias
            NetworkProfile   = if ($profile) { $profile.Name } else { "Not Connected" }
            SubnetMask      = $adapter.PrefixLength
            IPAddress       = $adapter.IPAddress
        }
    }

    return $results.SubnetMask

    # Display the results
    #$results | Format-Table -AutoSize
}

function Get-IPv4DnsServersForAdapter {
    param (
        [string]$AdapterName
    )

    # Get the IP configuration for the specified adapter
    $adapterConfig = Get-NetIPConfiguration | Where-Object { $_.InterfaceAlias -eq $AdapterName }

    if ($adapterConfig) {
        # Get the DNS server addresses
        $dnsServers = $adapterConfig.DNSServer.ServerAddresses

        # Filter only IPv4 DNS servers
        $ipv4DnsServers = $dnsServers | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' }

        if ($ipv4DnsServers) {
            #Write-Host "IPv4 DNS Servers for adapter '$AdapterName':" -ForegroundColor Cyan
            #$ipv4DnsServers | ForEach-Object { Write-Host $_ -ForegroundColor Green }
            Return $ipv4DnsServers
        } else {
            #Write-Host "No IPv4 DNS servers configured for adapter '$AdapterName'." -ForegroundColor Yellow
            Return $null
        }
    } else {
        #Write-Host "Adapter '$AdapterName' not found." -ForegroundColor Red
        Return $null
    }
}
#endregion


#region --- Log-level helpers

function Load-ServiceMapping {
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

# --- XML Helpers ---
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

# --- JSON Helpers ---
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

# --- Unified Helpers ---
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

#region --- Log-level info

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

    $servicesMapping = Load-ServiceMapping
    $results = @()

    foreach ($svc in $servicesMapping) {
        $serviceName = $svc.serviceName
        $displayName = $svc.displayName
        if ($svc.configFiles -and $svc.configFiles.Count -gt 0) {
            foreach ($cfg in $svc.configFiles) {
                $fileName = $cfg.fileName
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
    
    $servicesMapping = Load-ServiceMapping
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