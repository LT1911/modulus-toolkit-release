# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 16.05.2023

#region --- check if toolkit is in elevated state
if (Get-ElevatedState) {
    $sysprepKey = Test-Path -Path 'C:\Program Files\PowerShell\Modules\modulus-toolkit\SP.key'
    if($sysprepKey) { 
        Write-Host "SP.key found - sysprep functionality enabled!" -ForegroundColor Cyan
    } else {
        Return
    }
} else {
    #Skipping the rest of the file
    Return
}
#endregion

#region --- Get- and Set-functions for sysprep-functionality
function Get-Sysprep-Status {
    $statusFile = Join-Path (Get-ModulePath) "config\mod-sysprep.json"
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

    $statusFilePath = Join-Path (Get-ModulePath) "config\mod-sysprep.json"
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
    #WriteLog("Starting CheckLegacyIssues!")
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "    Stopping services!"      -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow

    #stopping services just to be sure
    Stop-MOD-Services
    
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "Setting services to manual!" -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "Changing startupType to Manual for all relevant services!" -ForegroundColor Yellow
    #changing startupType to Manual so that they will not automatically start after the restart of the server
    
    $GSS =   Get-Service -name GalaxisStartupService  -ErrorAction SilentlyContinue
    $RMQ =   Get-Service -name RabbitMQ               -ErrorAction SilentlyContinue
    $pinit = Get-Service -name pinit                  -ErrorAction SilentlyContinue
    $nginx = Get-Service -name nginx                  -ErrorAction SilentlyContinue

    if($GSS) { Set-Service -name GalaxisStartupService -startupType Manual }
    if($RMQ) { Set-Service -name RabbitMQ -startupType Manual }
    if($pinit) { Set-Service -name pinit -startupType Manual }
    if($nginx) { Set-Service -name nginx -startupType Manual }
      
    write-host "Services are prepared and will not start automatically upon restart!" -ForegroundColor Green
        
    Return $True
}

function Check-LegacyIssues {
	
    #WriteLog("Starting CheckLegacyIssues!")
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "Starting CheckLegacyIssues!" -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
        
    #check for legacy blocking issues:
    $issueCounter = 0
    $legacyIssues = ""
    #if (get-appxpackage -allusers | where {$_.name -like "*Secondary*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | where {$_.name -like "*Secondary*"})
    {
        $legacyIssues += "Secondary "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*Xbox*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | where {$_.name -like "*Xbox*"})
    {
        $legacyIssues += "Xbox, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*Assigned*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | where {$_.name -like "*Assigned*"})
    {
        $legacyIssues += "Assigned, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*MiracastView*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | where {$_.name -like "*MiracastView*"})
    {
        $legacyIssues += "MiracastView, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*Cortana*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | where {$_.name -like "*Cortana*"})
    {
        $legacyIssues += "Cortana, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*SecondaryTile*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | where {$_.name -like "*SecondaryTile*"})
    {
        $legacyIssues += "SecondaryTile, "
        $issueCounter = $issueCounter + 1
    }
    #if (get-appxpackage -allusers | where {$_.name -like "*PPIProjection*"})
    if (get-item -path "C:\Program Files\WindowsApps\*" | where {$_.name -like "*PPIProjection*"})
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
        #WriteLog("Legacy check: FAILED!")
        #WriteLog("Error:")
        #WriteLog("---"+$legacyIssue)
        write-host "---------------------------" -ForegroundColor Red
        Write-host "-  Legacy check: FAILED!  -" -ForegroundColor Red
        Write-host "          Failed:          " -ForegroundColor Red
        Write-host $legacyIssues                 -ForegroundColor Red
        write-host "---------------------------" -ForegroundColor Red
        Return $False
    }else
    {
        #WriteLog("Legacy check: OK!")
        write-host "---------------------------" -ForegroundColor Green
        Write-host "-  Legacy check: PASSED!  -" -ForegroundColor Green
        write-host "---------------------------" -ForegroundColor Green
        Return $True
    }
}

function Check-Registry {
	
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "  Starting CheckRegistry!  " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    
    
    #removing Upgrade registry entry	
    $Upgrade = Test-Path 'HKLM:\SYSTEM\Setup\Upgrade'
    if ($Upgrade)
    {
            write-host "Removing 'HKLM:\SYSTEM\Setup\Upgrade'"  -ForegroundColor Yellow
            Remove-Item -Path 'HKLM:\SYSTEM\Setup\Upgrade' -Force -Recurse -Verbose
    }
        
    #check registry for needed settings:
    $SysprepStatus = Get-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus'
    if ($SysprepStatus.GeneralizationState)
    {
        if ($SysprepStatus.GeneralizationState -ne "7")
        {
            write-host  "Setting GeneralizationState to 7" -ForegroundColor Yellow
            Set-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name GeneralizationState -Value 7
        }
    }else
    {
        write-host "Creating GeneralizationState and setting to 7" -ForegroundColor Yellow
        New-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name GeneralizationState -PropertyType DWORD -Value 7
    }
    
    if ($SysprepStatus.CleanupState)
    {
        if ($SysprepStatus.CleanupState -ne "2")
        {
            write-host "Setting CleanupState to 2" -ForegroundColor Yellow
            Set-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name CleanupState -Value 2
        }
    }else
    {
        write-host "Creating CleanupState and setting to 2" -ForegroundColor Yellow
        New-ItemProperty -Path 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -Name CleanupState -PropertyType DWORD -Value 2
    }
    
    $SoftwareProtectionPlatform = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    if ($SoftwareProtectionPlatform.SkipRearm)
    {
        if ($SoftwareProtectionPlatform.SkipRearm -ne "1")
        {
            write-host "Setting SkipRearm to 1" -ForegroundColor Yellow
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -Name SkipRearm -Value 1
        }
    }else
    {
        write-host "Creating SkipRearm and setting to 1" -ForegroundColor Yellow
        #I don't know why this is executed eventhough the Item already exists (see if($SoftwareProtectionPlatform.SkipRearm)
        #New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -Name SkipRearm -PropertyType DWORD -Value 1
    }
    
    #WriteLog("Legacy check: OK!")
    write-host "---------------------------" -ForegroundColor Green
    Write-host "- Registry check: PASSED! -" -ForegroundColor Green
    write-host "---------------------------" -ForegroundColor Green
    Return $True

}

function Reintall-MSDTC {
	
    write-host "Started Reintall-MSDTC!" -ForegroundColor Yellow
    write-host "-----------------------" -ForegroundColor Yellow
    #MSDTC un- and reinstall
    msdtc -uninstall
    write-host "msdtc -uninstall done."
    write-host "Waiting 10 seconds..."
    Start-Sleep -Seconds 10
    msdtc -install
    write-host "msdtc -install done."
    write-host "Waiting 5 seconds..."
    Start-Sleep -Seconds 5
    
    write-host "  MSDTC reinstall OK!  " -ForegroundColor Green
    write-host "-----------------------" -ForegroundColor Green
    write-host "System needs to restart" -ForegroundColor Yellow
    write-host "-----------------------" -ForegroundColor Yellow
    
    Return $True
}
#endregion

#region --- actual sysprep and scripts to be executed after sysprep 
function Create-SysprepUser {
    $password = ConvertTo-SecureString "Sys#prep#123" -AsPlainText -Force
    #New-LocalUser -Name "SysprepUser" -Description "Temporary user for sysprep" -FullName "Sysprep User"
    New-LocalUser -Name "SysprepUser" -Password $Password -Description "Temporary user for sysprep" -FullName "Sysprep User"
    $adminGroup = Get-LocalGroup | Where-Object { $_.Name -eq "Administrators" }
    Add-LocalGroupMember -Group $adminGroup.Name -Member "SysprepUser"
}

function Delete-SysprepUser {
   Remove-LocalUser -Name "SysprepUser"
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
    #echo "sysprep"
    $unattendXML = "C:\Program Files\PowerShell\Modules\modulus-toolkit\config\Unattend.xml" 
    
    Write-Host "Starting SYSPREP now!" -ForegroundColor Yellow
    write-host "Using $unattendXML for unattended installation!" -ForegroundColor Yellow
    
    #disable windows defender real-time protection
    Disable-DnFW

    #unattended:
    C:\Windows\system32\sysprep\sysprep.exe /oobe /generalize /reboot /unattend:$unattendXML
    Exit
}
#endregion

function Modulus-Sysprep {

    #getting current status
    $status = Get-Sysprep-Status

    #checking each status in order, aborting when issues arise
    
    #1 - legacy
    if ($status.status.legacy -eq $False)
    {
        $legacy = Check-LegacyIssues
        if ($legacy) { 
            Set-ServicesToManual
            Set-Sysprep-Status legacy
        } else {
            write-host "Aborting, Check-LegacyIssues returned issues!" -ForegroundColor Red
            Return $False
        }
    }

    #2 - registry 
    if ($status.status.registry -eq $False)
    {
        $registry = Check-Registry
        if ($registry) { 
            Set-Sysprep-Status registry
        } else {
            write-host "Aborting, Check-Registry returned issues!" -ForegroundColor Red
            Return $False
        }
    }

    #3 - msdtc
    if ($status.status.msdtc -eq $False)
    {
        $msdtc = Reintall-MSDTC
        if ($msdtc) { 
            Set-Sysprep-Status msdtc
        } else {
            write-host "Aborting, Reinstall-MSDTC returned issues!" -ForegroundColor Red
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
        $disks = Manage-Disks
        if ($disks) { 
            Set-Sysprep-Status disks
        } else {
            write-host "Aborting, Manage-Disks returned issues!" -ForegroundColor Red
            Return $False
        }
    }

    #7 - NICs
    if ($status.status.NICs -eq $False)
    {
        $renamed = Rename-MOD-NICs
        if($renamed) {
            $removed = Remove-MOD-Network
        }
        if($removed) {
           $NICs =  Set-MOD-Network
        }
        if ($NICs) { 
            Set-Sysprep-Status NICs

            #TODO:
            #create function to have OracleHomeUser-handling in additional step that can be checked for
            #maybe add Sysprep-User handling here as well - if logged in as administrator, get rid of sysprep-user
            $userExists = Get-LocalUser -Name "OracleHomeUser" -ErrorAction SilentlyContinue
            if ($userExists) {
                write-host "Adding OracleHomeUser back to local administrator group." -ForegroundColor Yellow
                $userInAdminGroup = Get-LocalGroupMember -Group 'Administrators' | Where-Object { $_.Name -eq $username }
                Add-LocalGroupMember -Group 'Administrators' -Member "OracleHomeUser"
            }

        } else {
            write-host "Aborting, Manage-NICs returned issues!" -ForegroundColor Red
            Return $False
        }        
    }



    #pseude break point for testing
    #start-sleep -seconds 100
    Write-Host "Sysprep finished!" -ForegroundColor Green
    #Write-Output "Check logs in C:\modulus\sysprep\logs\"
    Write-Host "Verify your disk volumes!" -ForegroundColor Yellow
    Write-host "Verify your network adapters!" -ForegroundColor Yellow
 
    #Initialize-VM $env:MODULUS_SERVER
}