#tlukas, 16.05.2023

#write-host "Loading 9-sysprep.psm1!" -ForegroundColor Green

#region --- Get- and Set-functions for sysprep-functionality
function Get-Sysprep-Status {
    $statusFile = Join-Path (Get-ModulePath) "config\sysprep.json"
    if (Test-Path $statusFile) {
        return Get-Content $statusFile -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $statusFile"
    }
}

function Set-Sysprep-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('legacy','registry','msdtc','restart','sysprep','disks','NICs','init','RESET')]
        [string]$Status
    )

    $statusFilePath = Join-Path (Get-ModulePath) "config\sysprep.json"
    if (Test-Path $statusFilePath) {
        $statusFile = Get-Content $statusFilePath -Raw | ConvertFrom-Json
    } else {
        throw "Config file not found: $statusFilePath"
    }

    switch ($Status) {
        "legacy"    { $statusFile.Status.legacy     = $True }
        "registry"  { $statusFile.Status.registry   = $True }
        "msdtc"     { $statusFile.Status.msdtc      = $True }
        "restart"   { $statusFile.Status.restart    = $True }
        "sysprep"   { $statusFile.Status.sysprep    = $True }
        "disks"     { $statusFile.Status.disks      = $True }
        "NICs"      { $statusFile.Status.NICs       = $True }
        "init"      { $statusFile.Status.init       = $True }
        "RESET"     {
            $statusFile.Status.legacy   = $False
            $statusFile.Status.registry = $False
            $statusFile.Status.msdtc    = $False
            $statusFile.Status.restart  = $False
            $statusFile.Status.sysprep  = $False
            $statusFile.Status.disks    = $False
            $statusFile.Status.NICs     = $False
            $statusFile.Status.init     = $False
        }
    }

   $statusFile | ConvertTo-Json | set-content $statusFilePath
}
#endregion

#region --- Scripts to check if machine is ready for sysprep and prep it for sysprep
function Set-ServicesToManual {
    Write-Log "Set-ServicesToManual" -Header

    #stopping services just to be sure
    Stop-MOD-Services
    
    Write-Log "Changing startupType to Manual for all relevant services!"
    #changing startupType to Manual so that they will not automatically start after the restart of the server
    $GSS =   Get-Service -name GalaxisStartupService  -ErrorAction SilentlyContinue
    $RMQ =   Get-Service -name RabbitMQ               -ErrorAction SilentlyContinue
    $pinit = Get-Service -name pinit                  -ErrorAction SilentlyContinue
    $nginx = Get-Service -name nginx                  -ErrorAction SilentlyContinue

    if($GSS) { Set-Service -name GalaxisStartupService -startupType Manual }
    if($RMQ) { Set-Service -name RabbitMQ -startupType Manual }
    if($pinit) { Set-Service -name pinit -startupType Manual }
    if($nginx) { Set-Service -name nginx -startupType Manual }
      
    Write-Log "Services are prepared and will not start automatically upon restart!" -ForegroundColor Green
    Write-Log "Set-ServicesToManual completed!" INFO  
    Return $True
}

function Test-LegacyIssues {
   Write-log "Test-LegacyIssues" -Header
   Write-log "Testing for existing legacy issues!" DEBUG
        
    #check for legacy blocking issues:
    $issueCounter = 0
    $legacyIssues = ""
    #if (get-appxpackage -allusers | where {$_.name -like "*Secondary*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | Where-Object {$_.name -like "*Secondary*"})
    {
        $legacyIssues += "Secondary "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*Xbox*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | Where-Object {$_.name -like "*Xbox*"})
    {
        $legacyIssues += "Xbox, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*Assigned*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | Where-Object {$_.name -like "*Assigned*"})
    {
        $legacyIssues += "Assigned, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*MiracastView*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | Where-Object {$_.name -like "*MiracastView*"})
    {
        $legacyIssues += "MiracastView, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*Cortana*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | Where-Object {$_.name -like "*Cortana*"})
    {
        $legacyIssues += "Cortana, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*SecondaryTile*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | Where-Object {$_.name -like "*SecondaryTile*"})
    {
        $legacyIssues += "SecondaryTile, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*PPIProjection*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | Where-Object {$_.name -like "*PPIProjection*"})
    {
        $legacyIssues += "PPIProjection, "
        $issueCounter = $issueCounter + 1
    }

    <# check
    if (get-appxpackage -allusers | where {$_.name -like "Windows.CBSPreview"})
    {
        $legacyIssue += "Windows.CBSPreview"
    }
    $legacyIssue 
    #>
    
    if ($issueCounter -ne 0)
    {
        Write-Log "Test-LegacyIssues failed!" ERROR
        Return $False
    }else
    {
        Write-Log "Test-LegacyIssues passed!" INFO
        Return $True
    }
}

function Test-Registry {
    Write-Log "Test-Registry" -Header
    Write-Log "Testing for existing registry issues!" DEBUG
    
    #removing Upgrade registry entry	
    $Upgrade = Test-Path 'HKLM:\SYSTEM\Setup\Upgrade'
    if ($Upgrade)
    {
        Write-Log "Removing 'HKLM:\SYSTEM\Setup\Upgrade'" DEBUG
        Remove-Item -Path 'HKLM:\SYSTEM\Setup\Upgrade' -Force -Recurse -Verbose
    }
        
    #check registry for needed settings:
    $SysprepStatus = Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus'
    if ($SysprepStatus.GeneralizationState)
    {
        if ($SysprepStatus.GeneralizationState -ne "7")
        {
            Write-Log  "Setting GeneralizationState to 7" DEBUG
            Set-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name GeneralizationState -Value 7
        }
    }else
    {
        Write-Log "Creating GeneralizationState and setting to 7" DEBUG
        New-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name GeneralizationState -PropertyType DWORD -Value 7
    }
    
    if ($SysprepStatus.CleanupState)
    {
        if ($SysprepStatus.CleanupState -ne "2")
        {
            Write-Log "Setting CleanupState to 2" DEBUG
            Set-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name CleanupState -Value 2
        }
    }else
    {
        Write-Log "Creating CleanupState and setting to 2" DEBUG
        New-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name CleanupState -PropertyType DWORD -Value 2
    }
    
    $SoftwareProtectionPlatform = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    if ($SoftwareProtectionPlatform.SkipRearm)
    {
        if ($SoftwareProtectionPlatform.SkipRearm -ne "1")
        {
            Write-Log "Setting SkipRearm to 1" DEBUG
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -Name SkipRearm -Value 1
        }
    }else
    {
        Write-Log "Creating SkipRearm and setting to 1" DEBUG
        #I don't know why this is executed eventhough the Item already exists (see if($SoftwareProtectionPlatform.SkipRearm)
        #New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -Name SkipRearm -PropertyType DWORD -Value 1
    }
    
    Write-Log "Test-Registry passed!" INFO
    Return $True
}

function Reset-MSDTC {
    Write-Log "Reset-MSDTC" -Header
    Write-log "Reinstalling MSDTC for a Reset!" DEBUG
    #Reset = un- and reinstall
    msdtc -uninstall
    Write-Log "msdtc -uninstall done."
    Write-Log "Waiting 10 seconds..."
    Start-Sleep -Seconds 10
    msdtc -install
    Write-Log "msdtc -install done."
    Write-Log "Waiting 5 seconds..."
    Start-Sleep -Seconds 5
    
    Write-Log "Reset-MSDTC completed!" INFO
    Write-Log "System needs to be restarted!" WARNING
    Return $True
}
#endregion

#region --- actual sysprep and scripts to be executed after sysprep 
function New-SysprepUser {
    Write-Log "New-SysprepUser" -Header
    $password = ConvertTo-SecureString "Sys#prep#123" -AsPlainText -Force
    #New-LocalUser -Name "SysprepUser" -Description "Temporary user for sysprep" -FullName "Sysprep User"
    New-LocalUser -Name "SysprepUser" -Password $Password -Description "Temporary user for sysprep" -FullName "Sysprep User"
    $adminGroup = Get-LocalGroup | Where-Object { $_.Name -eq "Administrators" }
    Add-LocalGroupMember -Group $adminGroup.Name -Member "SysprepUser"
    Write-Log "User 'SysprepUser' created and added to local administrators group!" INFO
    Write-Log "Do not forget to remove the user after Sysprep using 'Remove-SysprepUser'!" WARNING
    Write-Log "New-SysprepUser completed!" INFO
}

function Remove-SysprepUser {
    Write-Log "Remove-SysprepUser" -Header
    $userExists = Get-LocalUser -Name "SysprepUser" -ErrorAction SilentlyContinue
    if ($userExists) {
        Write-Log "Removing SysprepUser from local administrators group!" INFO
        Remove-LocalGroupMember -Group 'Administrators' -Member "SysprepUser"
    } else {
        Write-Log "SysprepUser does not exist!" INFO
    }
    Remove-LocalUser -Name "SysprepUser"
    Write-Log "Remove-SysprepUser completed!" INFO
}

function Disable-DnFW {
    Set-MpPreference -DisableRealtimeMonitoring $true
    Set-MpPreference -EnableControlledFolderAccess Disabled
    #Set-MpPreference -DisableAntiSpyware $true
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
}

function Enable-DnFW {
    Set-MpPreference -DisableRealtimeMonitoring $false
    Set-MpPreference -EnableControlledFolderAccess Enabled
    #Set-MpPreference -DisableAntiSpyware $false
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
}

function Sysprep {
    Write-Log "Sysprep" -Header

    $unattendXML = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\Unattend.xml" 
    Write-Log "Using $unattendXML for unattended installation!"
    
    #disable windows defender real-time protection
    Disable-DnFW

    #unattended:
    C:\Windows\system32\sysprep\sysprep.exe /oobe /generalize /reboot /unattend:$unattendXML
    Exit
}
#endregion

function Start-MOD-Sysprep {

    #TODO:
    #   only do sysprep if certain environment variable is set, then i can have only 1 startup.ps1

    Write-Log "Start-MOD-Sysprep" -Header
    Write-Log "Starting Sysprep process!" INFO
    
    #getting current status
    $status = Get-Sysprep-Status

    #checking each status in order, aborting when issues arise
    
    #1 - legacy
    if ($status.status.legacy -eq $False)
    {
        $legacy = Test-LegacyIssues
        if ($legacy) { 
            Set-ServicesToManual
            Set-Sysprep-Status legacy
        } else {
            Write-Log "Aborting, Test-LegacyIssues returned issues!" ERROR
            Return $False
        }
    }

    #2 - registry 
    if ($status.status.registry -eq $False)
    {
        $registry = Test-Registry
        if ($registry) { 
            Set-Sysprep-Status registry
        } else {
            Write-Log "Aborting, Test-Registry returned issues!" ERROR
            Return $False
        }
    }

    #3 - msdtc
    if ($status.status.msdtc -eq $False)
    {
        $msdtc = Reset-MSDTC
        if ($msdtc) { 
            Set-Sysprep-Status msdtc
        } else {
            Write-Log "Aborting, Reset-MSDTC returned issues!" ERROR
            Return $False
        }
    }

    #4 - restart
    if ($status.status.restart -eq $False)
    {
        Set-Sysprep-Status restart
        Restart-Computer -Force
        Exit
    }

    #5 - sysprep 
    if ($status.status.sysprep -eq $False)
    {
        Set-Sysprep-Status sysprep
        Sysprep
        Exit
    }

    #6 - disks
    if ($status.status.disks -eq $False)
    {
        $disks = Initialize-Disks
        if ($disks) { 
            Set-Sysprep-Status disks
        } else {
            Write-Log "Aborting, Initialize-Disks returned issues!" ERROR
            Return $False
        }
    }

    #7 - NICs
    if ($status.status.NICs -eq $False)
    {
        $renamed = Rename-MOD-NetAdapters
        if($renamed) {
            $removed = Clear-NetAdapterConfig -Force   #reworked
        }
        if($removed) {
           $NICs =  Set-MOD-Network -Force
        }
        if ($NICs) { 
            Set-Sysprep-Status NICs

            #TODO:
            #create function to have OracleHomeUser-handling in additional step that can be checked for
            #maybe add Sysprep-User handling here as well - if logged in as administrator, get rid of sysprep-user
            $userExists = Get-LocalUser -Name "OracleHomeUser" -ErrorAction SilentlyContinue
            if ($userExists) {
                write-Log "Adding OracleHomeUser back to local administrator group."
                #$userInAdminGroup = Get-LocalGroupMember -Group 'Administrators' | Where-Object { $_.Name -eq $username }
                Add-LocalGroupMember -Group 'Administrators' -Member "OracleHomeUser"
            }

        } else {
            Write-Log "Aborting, Manage-NICs returned issues!" ERROR
            Return $False
        }        
    }

    #pseude break point for testing
    #start-sleep -seconds 100

    Write-Log "Start-MOD-Sysprep completed!" INFO
    Write-Log "Verify your disk volumes!" WARNING
    Write-Log "Verify your network adapters!" WARNING
 
    Initialize-VM
}

#Export-ModuleMember -Function * -Alias * -Variable *