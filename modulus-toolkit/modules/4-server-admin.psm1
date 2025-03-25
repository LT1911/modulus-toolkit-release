# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 22.10.2024

#check if toolkit is in elevated state
if (Get-ElevatedState) {
    #Write-Host "Loading 4-server-admin.psm1!" -ForegroundColor Cyan
    #Continue loading the psm1
} else {
    #Skipping the rest of the file
    Return;
}

<#INFO
- Init
- Network
- Restart w/ prompt
- substO
#>

#region --- Initialization scripts
function Initialize-VM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("DB","APP","FS","1VM","WS")]
        [string]$VM
    )

    switch ($VM) {
        "DB"    { Initialize-DB }
        "APP"   { Initialize-APP }
        "FS"    { Initialize-FS }
        "1VM"   { Initialize-1VM }
        "WS"    { Initialize-WS }
        Default { throw "Invalid VM: $VM" }
    }
}

function Initialize-DB {
    write-host "> "
    write-host " > Initialize FS!"

    $hostname = Get-MOD-DB-hostname
    
    #setting hostname
    Rename-Computer -NewName $hostname -Force

    Set-MOD-ENVVARs

    #setting up network
    #Set-NIC-Names
    #Set-NIC-IPs

    #mapping M&I-shares, keep in mind APP server needs to be setup first!
    #Map-M-share
    Map-I-share
    
    Write-warning " > The changes made need a reboot to be effective!"
    Restart-VMWithPrompt
}

function Initialize-APP {
    write-host "> "
    write-host " > Initialize APP!"

    $hostname = Get-MOD-APP-hostname
    
    #setting hostname
    Rename-Computer -NewName $hostname -Force

    Set-MOD-ENVVARs

    #setting up network
    #Set-NIC-Names
    #Set-NIC-IPs
    
    #mapping M&I-shares, keep in mind APP server needs to be setup first!
    #Map-I-share
    Map-M-Share
    Set-SubstO-autostart
  
    Write-warning " > The changes made need a reboot to be effective!"
    Write-warning " > Do not forget to run D:\GALAXIS\Install\Batch\SERVER.bat after the hostname has been changed!"
    Restart-VMWithPrompt
}

function Initialize-FS {
    write-host "> "
    write-host " > Initialize FS!"

    $hostname = Get-MOD-FS-hostname
    
    #setting hostname
    Rename-Computer -NewName $hostname -Force

    Set-MOD-ENVVARs
    
    #setting up network
    #Set-NIC-Names
    #Set-NIC-IPs

    #mapping M&I-shares, keep in mind APP server needs to be setup first!
    #Map-M-share
    Map-I-share

    Write-warning " > The changes made need a reboot to be effective!"
    Restart-VMWithPrompt
}

function Initialize-1VM {
    Write-Host "Not implemented yet!" -ForegroundColor Red
}

function Initialize-WS {
    Write-Host "Not implemented yet!" -ForegroundColor Red
}

#endregion

#region --- restart VM after initializing
function Restart-VMWithPrompt {
    $response = Read-Host " > Do you want to reboot the VM now? (Yes/No)"
    if ($response.ToLower() -eq "yes") {
        Restart-Computer -Force
    } else 
    {
        Return $False
    }
}
#endregion

#region --- one time things after sysprep?!
function Set-SubstO-autostart {
    write-host ">"
    write-host " > Checking if substO.bat is already in autostart!"
    
    $substO  = "I:\Other\substO.bat"

    if (Test-Path -path $substO) {
        $startup = "C:\Users\Administrator\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\substO.bat"
        if (!(Test-Path -path $startup)) {
            copy-item -Path $substO -Destination $startup
            write-host " > Added substO.bat to autostart!"
            invoke-item $substO
            write-host " > Executed $substO!"
        }
    } else {
        write-warning " > $substo does not exist!"
        write-warning " > Aborting!"
    }
}
#endregion

#region -- CHANGE environment variables
function Set-MOD-ENVVARs {    
    $PH_TIMEZONE     = Get-MOD-TimeZone
    $PH_APPSERVER_HN = Get-MOD-APP-hostname
    $PH_DBSERVER_HN  = Get-MOD-DB-hostname
    
    $desiredENVVARs  = Get-MOD-DesiredENVVARs
    
    write-host "---------------------------" -ForegroundColor Green
    write-host "  Setting Modulus ENVVARs"   -ForegroundColor Green
    write-host "---------------------------" -ForegroundColor Green
    # Iterate over the environment variables and set them
    foreach ($envVar in $desiredENVVARs.EnvironmentVariables.PSObject.Properties) {
        # Replace placeholders in the variable value
        $variableValue = $envVar.Value `
            -replace '{PH_APPSERVER_HN}', $PH_APPSERVER_HN `
            -replace '{PH_DBSERVER_HN}',  $PH_DBSERVER_HN `
            -replace '{PH_TIMEZONE}',     $PH_TIMEZONE

        # Set the environment variable
        [System.Environment]::SetEnvironmentVariable($envVar.Name, $variableValue, [System.EnvironmentVariableTarget]::Machine)
        Write-Host "Set environment variable '$($envVar.Name)' to '$variableValue'."
    }
    write-host "---------------------------" -ForegroundColor Green
}
#endregion

#region --- CHANGE network adapters
function Rename-MOD-NICs {
    Write-host "---------------------------" -ForegroundColor Yellow
    Write-host "       Rename NICs        !" -ForegroundColor Yellow
    Write-host "---------------------------" -ForegroundColor Yellow

    # Get all network adapters
    $networkAdapters = Get-NetAdapter | Sort-Object InterfaceDescription

    # Check the number of adapters
    $adapterCount = $networkAdapters.Count
    Write-Host "Found $adapterCount network adapter(s)." -ForegroundColor Yellow

    switch ($adapterCount) {
        2 {
            Write-host "Setting up 2 network adapters (OFFICE, MODULUS)" -ForegroundColor Yellow
            # Rename the first adapter to 'OFFICE' and the second to 'MODULUS'
            $networkAdapters[0] | Rename-NetAdapter -NewName 'OFFICE'  -ErrorAction SilentlyContinue
            $networkAdapters[1] | Rename-NetAdapter -NewName 'MODULUS' -ErrorAction SilentlyContinue
        }
        3 {
            Write-host "Setting up 3 network adapters (OFFICE, FLOOR, MODULUS)" -ForegroundColor Yellow
            # Rename the first adapter to 'OFFICE', second to 'FLOOR', and third to 'MODULUS'
            $networkAdapters[0] | Rename-NetAdapter -NewName 'OFFICE'  -ErrorAction SilentlyContinue
            $networkAdapters[1] | Rename-NetAdapter -NewName 'FLOOR'   -ErrorAction SilentlyContinue
            $networkAdapters[2] | Rename-NetAdapter -NewName 'MODULUS' -ErrorAction SilentlyContinue
        }
        Default {
            Write-host "Invalid network configuration: Expected 2 or 3 adapters but found $adapterCount" -ForegroundColor Red
            return $false
        }
    }

    Write-host "---------------------------" -ForegroundColor Yellow
    Write-host "       NICs renamed!"        -ForegroundColor Yellow
    Write-host "---------------------------" -ForegroundColor Yellow
    return $true
}

function Remove-MOD-Network {
    Write-host "---------------------------" -ForegroundColor Yellow
    Write-host "   Removing IPv4 config!   " -ForegroundColor Yellow
    Write-host "---------------------------" -ForegroundColor Yellow

    #Get all network adapters
    $networkAdapters = Get-NetAdapter | Sort-Object InterfaceDescription

    foreach($adapter in $networkAdapters) {
        $adapterName = $adapter.InterfaceAlias

        #Removing IPv4 config
        $IPv4 = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($IPv4) {
            write-host "Removing IPv4 config of $adapterName!" -ForegroundColor Yellow
            $IPv4 | Remove-NetIPAddress -Confirm:$false 
        }
        
        #Remove the default gateway for the adapter
        $currentGateway = (Get-NetRoute -InterfaceAlias $adapterName -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }).NextHop
        if ($currentGateway) {
            write-host "Removing gateway of $adapterName as well!"
            Get-NetRoute -InterfaceAlias $adapterName -NextHop $currentGateway -AddressFamily IPv4 | Remove-NetRoute -Confirm:$false
        }

        #Removing DNS
        Set-DnsClientServerAddress -InterfaceAlias $adapterName -ServerAddresses @()
    }

    Write-host "---------------------------" -ForegroundColor Yellow
    Write-host "    Removed IPv4 config!   " -ForegroundColor Yellow
    Write-host "---------------------------" -ForegroundColor Yellow
    return $true 
}

<#
function Set-NIC-IPs {

    write-host ">"
    write-host "> Setting up network adapter IP configurations!"

    $serverConfig =  Get-MOD-Server

    #OFFICE
    $officeNIC = Get-NetAdapter -Name "OFFICE" -ErrorAction SilentlyContinue
    if($officeNIC) {
        if($officeNIC.Status -ne "Up") {
            Write-Information " > Activating OFFICE network adapter! - just in case :)"
            Enable-NetAdapter -Name "OFFICE"
        }
        #$IP = "192.168.1.24"
        $IP = $serverConfig.networkAdapters.OFFICE.IP
        Write-host " > Setting OFFICE network configuration!"
        New-NetIPAddress -InterfaceAlias "OFFICE" -IPAddress $IP -PrefixLength 16 -ErrorAction SilentlyContinue | Out-Null
        #disabling IPv6
        Write-host " > Disabling OFFICE IPv6!"
        Disable-NetAdapterBinding -Name "OFFICE" -ComponentID "ms_tcpip6"
        #$officeNIC
    } else {
      write-host " > OFFICE NIC does not exist!"  
    }

    #FLOOR
    $floorNIC = Get-NetAdapter -Name "FLOOR" -ErrorAction SilentlyContinue
    if($floorNIC) {
        if($floorNIC.Status -ne "Up") {
            Write-Information " > Activating FLOOR network adapter! - just in case :)"
            Enable-NetAdapter -Name "FLOOR"
        }
        #$IP = "10.10.10.1"
        $IP = $serverConfig.networkAdapters.FLOOR.IP
        Write-host " > Setting FLOOR network configuration!"
        New-NetIPAddress -InterfaceAlias "FLOOR" -IPAddress $IP -PrefixLength 16 -ErrorAction SilentlyContinue | Out-Null
        #disabling IPv6
        Write-host " > Disabling FLOOR IPv6!"
        Disable-NetAdapterBinding -Name "FLOOR" -ComponentID "ms_tcpip6"
        #$foorNIC
    } else {
        write-host " > FLOOR NIC does not exist!"  
    }

    #MODULUS
    $modulusNIC = Get-NetAdapter -Name "MODULUS" -ErrorAction SilentlyContinue
    if($modulusNIC) {
        if($modulusNIC.Status -ne "Up") {
            Write-Information " > Activating MODULUS network adapter! - just in case :)"
            Enable-NetAdapter -Name "MODULUS"
        }
        #$IP = "10.10.10.1"
        $IP = $serverConfig.networkAdapters.MODULUS.IP
        Write-host " > Setting MODULUS network configuration!"
        New-NetIPAddress -InterfaceAlias "MODULUS" -IPAddress $IP -PrefixLength 16 -ErrorAction SilentlyContinue | Out-Null
        #disabling IPv6
        Write-host " > Disabling MODULUS IPv6!"
        Disable-NetAdapterBinding -Name "MODULUS" -ComponentID "ms_tcpip6"
        #$modulusNIC
    } else {
        write-host " > MODULUS NIC does not exist!"  
    }
    Start-Sleep -Seconds 3

    write-host " > Please verify the configuration:"
    ipconfig 
    write-host " "
}
#>

function Set-MOD-Network {
  
    $adapterConfig = (Get-MOD-Server).networkAdapters

    #Iterate over each network adapter in the JSON
    foreach ($adapter in $adapterConfig) {
        # Get the adapter by name
        $NIC = Get-NetAdapter | Where-Object { $_.InterfaceAlias -eq $adapter.AdapterName }

        if ($NIC) {
            Write-Host "Configuring network adapter: $($adapter.AdapterName)" -ForegroundColor Green

            #Set the new IP address, subnet mask, and gateway
            Write-Host "Setting IPv4 settings for adapter: $($adapter.AdapterName)"
            New-NetIPAddress `
                -InterfaceAlias $adapter.AdapterName `
                -IPAddress $adapter.IPAddress `
                -PrefixLength (Get-SubnetMaskPrefixLength $adapter.SubnetMask) `
                #-DefaultGateway $adapter.DefaultGateway

            #Set DNS servers if available
            if ($adapter.DNS) {
                Write-Host "Setting DNS servers for adapter: $($adapter.AdapterName)"
                Set-DnsClientServerAddress `
                    -InterfaceAlias $adapter.AdapterName `
                    -ServerAddresses $adapter.DNS
            }

        } else {
            Write-Warning "Adapter with name '$($adapter.AdapterName)' not found."
        }
    }
}
#endregion

#region --- manage disk partitions
function Manage-Disks {
    [CmdletBinding()]
    param()

    Write-Host "====================================================================" -ForegroundColor Yellow
    Write-Host " Managing Disks Post-Sysprep – Assigning Letters by Disk & Partition" -ForegroundColor Yellow
    Write-Host "====================================================================" -ForegroundColor Yellow

    # -------------------------------
    # Step 1: Bring disks online and clear read-only flags.
    # -------------------------------
    Write-Host "`n[Step 1] Bringing disks online and clearing read-only flags..."
    Get-Disk | ForEach-Object {
        if ($_.IsOffline) {
            Set-Disk -Number $_.Number -IsOffline $false -ErrorAction SilentlyContinue
            Write-Host "Disk $($_.Number) brought online." -ForegroundColor Cyan
        }
        if ($_.IsReadOnly) {
            Set-Disk -Number $_.Number -IsReadOnly $false -ErrorAction SilentlyContinue
            Write-Host "Cleared read-only on disk $($_.Number)." -ForegroundColor Cyan
        }
    }

    # -------------------------------
    # Step 2: Check if drive D: is assigned to a DVD-ROM and remove it via DiskPart.
    # -------------------------------
    Write-Host "`n[Step 2] Checking if drive D: is assigned to a DVD-ROM..."
    $dvdVolume = Get-Volume | Where-Object { $_.DriveType -match "CD" -and $_.DriveLetter -eq 'D' }
    if ($dvdVolume) {
        Write-Host "DVD volume found:" -ForegroundColor Cyan
        $dvdVolume | Format-Table DriveLetter, FileSystemLabel, DriveType, SizeRemaining -AutoSize
        Write-Host "`nRemoving drive letter D from DVD-ROM via DiskPart..." -ForegroundColor Cyan
        $dvdDP = @"
select volume $($dvdVolume.Number)
remove letter=D
exit
"@
        $tempDVD = "$env:TEMP\remove_dvd.txt"
        $dvdDP | Out-File -FilePath $tempDVD -Encoding ASCII
        Start-Process -FilePath "diskpart.exe" -ArgumentList "/s $tempDVD" -Wait
        Remove-Item $tempDVD -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "No DVD drive with letter D found; skipping removal." -ForegroundColor Yellow
    }

    # -------------------------------
    # Step 3: Disable automount via DiskPart.
    # -------------------------------
    Write-Host "`n[Step 3] Disabling automount to prevent auto-assignment..."
    $autoDisable = @"
automount disable
exit
"@
    $tempAutoDisable = "$env:TEMP\disable_automount.txt"
    $autoDisable | Out-File -FilePath $tempAutoDisable -Encoding ASCII
    Start-Process -FilePath "diskpart.exe" -ArgumentList "/s $tempAutoDisable" -Wait
    Remove-Item $tempAutoDisable -ErrorAction SilentlyContinue

    # -------------------------------
    # Step 4: Force assign drive letter E to the DVD drive.
    # (Assume this is Volume 0 and is handled by DiskPart.)
    # -------------------------------
    Write-Host "`n[Step 4] Forcing Volume 0 (DVD drive) to letter E..."
    $dpAssignE = @"
select volume 0
assign letter=E
exit
"@
    $tempE = "$env:TEMP\assign_E.txt"
    $dpAssignE | Out-File -FilePath $tempE -Encoding ASCII
    Start-Process -FilePath "diskpart.exe" -ArgumentList "/s $tempE" -Wait
    Remove-Item $tempE -ErrorAction SilentlyContinue

    # -------------------------------
    # Step 5: Determine server type.
    # -------------------------------
    $serverType = $env:MODULUS_SERVER
    if (-not $serverType) {
        Write-Host "MODULUS_SERVER is not set. Exiting." -ForegroundColor Red
        return
    }
    Write-Host "`n[Step 5] Detected server type: $serverType" -ForegroundColor Cyan

    # -------------------------------
    # Step 6: Build mapping by DiskNumber and PartitionNumber.
    # Use Get-Partition (which reliably shows DiskNumber & PartitionNumber).
    # Mapping (adjust these as needed):
    #   - Disk 0, Partition 1 (System Reserved) → $null (unlettered)
    #   - Disk 0, Partition 2 (OS) → leave as is (assumed already C)
    #   - Disk 0, Partition 3 (Recovery/Hidden) → $null
    #   - Disk 1, Partition 1 (Data) → D
    # For additional volumes:
    #   For DB: Disk 2, Partition 1 → F; Disk 3, Partition 1 → G; Disk 4, Partition 1 → H; Disk 5, Partition 1 → S
    #   For 1VM: Disk 2, Partition 1 → F; Disk 3, Partition 1 → G; Disk 4, Partition 1 → H; Disk 5, Partition 1 → I
    #   For APP: Disk 2, Partition 1 → I
    #   For FS: Only the first set (Disk 0-1) are used.
    $mapping = @(
        @{ DiskNumber = 0; PartitionNumber = 1; DesiredLetter = $null },   # System Reserved
        #@{ DiskNumber = 0; PartitionNumber = 2; DesiredLetter = "C" },     # OS partition – skip if already C
        @{ DiskNumber = 0; PartitionNumber = 3; DesiredLetter = $null },   # Recovery/Hidden
        @{ DiskNumber = 1; PartitionNumber = 1; DesiredLetter = "D" }        # Data partition
    )

    switch ($serverType.ToUpper()) {
        "DB" {
            $mapping += @{ DiskNumber = 2; PartitionNumber = 1; DesiredLetter = "F" }
            $mapping += @{ DiskNumber = 3; PartitionNumber = 1; DesiredLetter = "G" }
            $mapping += @{ DiskNumber = 4; PartitionNumber = 1; DesiredLetter = "H" }
            $mapping += @{ DiskNumber = 5; PartitionNumber = 1; DesiredLetter = "S" }
        }
        "1VM" {
            $mapping += @{ DiskNumber = 2; PartitionNumber = 1; DesiredLetter = "F" }
            $mapping += @{ DiskNumber = 3; PartitionNumber = 1; DesiredLetter = "G" }
            $mapping += @{ DiskNumber = 4; PartitionNumber = 1; DesiredLetter = "H" }
            $mapping += @{ DiskNumber = 5; PartitionNumber = 1; DesiredLetter = "I" }
        }
        "APP" {
            $mapping += @{ DiskNumber = 2; PartitionNumber = 1; DesiredLetter = "I" }
        }
        "FS" {
            # Only the first set is used.
        }
        default {
            Write-Host "Unknown server type: $serverType" -ForegroundColor Red
            return
        }
    }

    Write-Host "`nMapping by DiskNumber & PartitionNumber:" -ForegroundColor Magenta
    foreach ($m in $mapping) {
        $target = if ($m.DesiredLetter) { $m.DesiredLetter } else { "(no letter)" }
        Write-Host "Disk $($m.DiskNumber), Partition $($m.PartitionNumber) → $target"
    }

    # -------------------------------
    # Step 7: Assign letters using native PowerShell cmdlets.
    # -------------------------------
    Write-Host "`nAssigning drive letters based on partition mapping..." -ForegroundColor Cyan
    foreach ($m in $mapping) {
        try {

            $part = Get-Partition -DiskNumber $m.DiskNumber -PartitionNumber $m.PartitionNumber -ErrorAction Stop
            # Remove any existing letter if present and desired letter is defined.
            if ($part.DriveLetter -and $m.DesiredLetter) {
                Write-Host "Removing existing letter $($part.DriveLetter) from Disk $($m.DiskNumber), Partition $($m.PartitionNumber)..."
                Remove-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath "$($part.DriveLetter):" -ErrorAction SilentlyContinue
            }
            if ($m.DesiredLetter) {
                Write-Host "Assigning letter $($m.DesiredLetter) to Disk $($m.DiskNumber), Partition $($m.PartitionNumber)..."
                Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $m.DesiredLetter -ErrorAction Stop
                Write-Host "Successfully assigned letter $($m.DesiredLetter)." -ForegroundColor Green
            }
            else {
                Write-Host "Leaving Disk $($m.DiskNumber), Partition $($m.PartitionNumber) unlettered." -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "Error processing Disk $($m.DiskNumber), Partition $($m.PartitionNumber): $_" -ForegroundColor Red
        }
    }

    # -------------------------------
    # Step 8: Re-enable automount via DiskPart.
    # -------------------------------
    Write-Host "`nRe-enabling automount..." -ForegroundColor Cyan
    $autoEnable = @"
automount enable
exit
"@
    $tempAutoEnable = "$env:TEMP\enable_automount.txt"
    $autoEnable | Out-File -FilePath $tempAutoEnable -Encoding ASCII
    Start-Process -FilePath "diskpart.exe" -ArgumentList "/s $tempAutoEnable" -Wait
    Remove-Item $tempAutoEnable -ErrorAction SilentlyContinue

    # -------------------------------
    # Step 9: Refresh disks – cycle offline/online and clear any read-only flags.
    # -------------------------------
    Write-Host "`nRefreshing disks to apply changes..." -ForegroundColor Cyan
    Get-Disk | ForEach-Object {
        try {
            Set-Disk -Number $_.Number -IsOffline $true -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Set-Disk -Number $_.Number -IsOffline $false -ErrorAction SilentlyContinue
            if ($_.IsReadOnly) {
                Set-Disk -Number $_.Number -IsReadOnly $false -ErrorAction SilentlyContinue
                Write-Host "Cleared read-only on Disk $($_.Number)." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Error refreshing Disk $($_.Number): $_" -ForegroundColor Red
        }
    }

    Write-Host "`nFinal drive-letter assignments:" -ForegroundColor Magenta
    Get-Volume | Format-Table DriveLetter, FileSystemLabel, SizeRemaining, DriveType -AutoSize
    return $true
}

#endregion

#region --- Log-level admin
function Set-MOD-ServiceLogLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$NewLevel
    )

    $servicesMapping = Load-ServiceMapping
    $targetService = $servicesMapping | Where-Object { $_.serviceName -eq $ServiceName }
    
    if (-not $targetService) {
        Write-Error "Service '$ServiceName' not found in mapping."
        return
    }

    if (-not $targetService.configFiles -or $targetService.configFiles.Count -eq 0) {
        Write-Error "No config files defined for service '$ServiceName'."
        return
    }

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
                try {
                    Set-LoggingLevelInConfig -ConfigFilePath $cfg.path -LoggingKey $loggingKey -NewLevel $NewLevel -Type $type
                    Write-Verbose "Updated service '$ServiceName' config '$($cfg.path)' (Appender: $($appender.name)) to level '$NewLevel'."
                }
                catch {
                    Write-Warning "Failed to update service '$ServiceName' config '$($cfg.path)' (Appender: $($appender.name)): $_"
                }
            }
        }
        else {
            Write-Verbose "No log appenders defined for service '$ServiceName' in config '$($cfg.path)'."
        }
    }
}

function Set-MOD-AppenderLogLevel {
    <#
    .SYNOPSIS
      Sets the logging level for a specific appender of a given service.
    
    .DESCRIPTION
      This function loads the JSON mapping, locates the specified service,
      and then searches through all of its config files for the given appender name.
      When a match is found, it updates that appender’s logging level (using the
      appropriate XML or JSON helper function) to the supplied value.
    
    .PARAMETER ServiceName
      The service name (as defined in the JSON mapping) to update.
    
    .PARAMETER AppenderName
      The name of the log appender to target.
    
    .PARAMETER NewLevel
      The new logging level to set (e.g. "ERROR", "DEBUG", etc.).
    
    .EXAMPLE
      Set-SpecificAppenderLogLevel -ServiceName "GalaxisAuthenticationService" -AppenderName "DefaultAppender" -NewLevel "ERROR"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$AppenderName,
        [Parameter(Mandatory)]
        [string]$NewLevel
    )

    $servicesMapping = Load-ServiceMapping
    $targetService = $servicesMapping | Where-Object { $_.serviceName -eq $ServiceName }
    
    if (-not $targetService) {
        Write-Error "Service '$ServiceName' not found in mapping."
        return
    }
    if (-not $targetService.configFiles -or $targetService.configFiles.Count -eq 0) {
        Write-Error "No config files defined for service '$ServiceName'."
        return
    }

    $found = $false
    foreach ($cfg in $targetService.configFiles) {
        $type = $cfg.type
        if ($cfg.logAppenders -and $cfg.logAppenders.Count -gt 0) {
            foreach ($appender in $cfg.logAppenders) {
                if ($appender.name -eq $AppenderName) {
                    $found = $true
                    if ($type -eq "json") {
                        $loggingKey = $appender.jsonKeyPath
                    }
                    else {
                        $loggingKey = $appender.loggingXPath
                    }
                    try {
                        Set-LoggingLevelInConfig -ConfigFilePath $cfg.path -LoggingKey $loggingKey -NewLevel $NewLevel -Type $type
                        Write-Verbose "Updated service '$ServiceName' config '$($cfg.path)' (Appender: $AppenderName) to level '$NewLevel'."
                    }
                    catch {
                        Write-Warning "Failed to update service '$ServiceName' config '$($cfg.path)' (Appender: $AppenderName): $_"
                    }
                }
            }
        }
    }
    if (-not $found) {
        Write-Error "Appender '$AppenderName' not found for service '$ServiceName'."
    }
}

function Set-MOD-AllDefaultLogLevels {
    <#
    .SYNOPSIS
      Sets each service's log level to its default value as defined in the JSON mapping.
    
    .DESCRIPTION
      This function loads the JSON mapping file (via Load-ServiceMapping) and iterates over every service,
      then for each configuration file and each log appender defined in the mapping, it reads the defaultLevel
      property and updates the configuration file accordingly using the appropriate XML or JSON helper function.
    
    .EXAMPLE
      Set-AllDefaultLogLevels
    #>
    [CmdletBinding()]
    param()

    $servicesMapping = Load-ServiceMapping

    foreach ($svc in $servicesMapping) {
        if (-not $svc.configFiles -or $svc.configFiles.Count -eq 0) {
            Write-Verbose "No config files defined for service '$($svc.serviceName)'."
            continue
        }
        foreach ($cfg in $svc.configFiles) {
            $type = $cfg.type
            if ($cfg.logAppenders -and $cfg.logAppenders.Count -gt 0) {
                foreach ($appender in $cfg.logAppenders) {
                    $defaultLevel = $appender.defaultLevel
                    if (-not $defaultLevel) {
                        Write-Verbose "No default level defined for service '$($svc.serviceName)' appender '$($appender.name)'."
                        continue
                    }
                    
                    if ($type -eq "json") {
                        $loggingKey = $appender.jsonKeyPath
                    }
                    else {
                        $loggingKey = $appender.loggingXPath
                    }
                    
                    try {
                        Set-LoggingLevelInConfig -ConfigFilePath $cfg.path -LoggingKey $loggingKey -NewLevel $defaultLevel -Type $type
                        Write-Verbose "Set default level for service '$($svc.serviceName)' config '$($cfg.path)' (Appender: $($appender.name)) to '$defaultLevel'."
                    }
                    catch {
                        Write-Warning "Failed to set default level for service '$($svc.serviceName)' config '$($cfg.path)' (Appender: $($appender.name)): $_"
                    }
                }
            }
            else {
                Write-Verbose "No log appenders defined for service '$($svc.serviceName)' in config '$($cfg.path)'."
            }
        }
    }
}

#endregion