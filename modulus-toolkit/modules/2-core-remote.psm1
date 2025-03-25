# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 10.09.2024

#check if toolkit is in elevated state
if (Get-ElevatedState) {
    #Write-Host "Loading 2-core-remote.psm1!" -ForegroundColor Cyan
    #Continue loading the psm1
} else {
    #Skipping the rest of the file
    Return;
}

<#INFO
- WinRM setup
- PSSessionConfig
- managing PS sessions
- #additional tests for PS sessions
#>

#region --- WinRM setup
<#
function Set-WinRM-tlukas {
    $adapter = Get-NetConnectionProfile -name "modulusAT"
    if ($adapter.NetworkCategory -ne "Private") {
        Set-NetConnectionProfile -Name "modulusAT" -NetworkCategory Private
        Write-Host "Updated network adatper modulusAT to use NetworkCategory Private!" -ForegroundColor Yellow
    }
    
    Write-host "Adding 3VM scope to trusted users!" -ForegroundColor Yellow
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "ModulusDB,ModulusAPP,ModulusFS" -Force
    
    winrm quickconfig
}
#>

function Set-WinRM-VM {

    write-host "If this function throws errors, try running 'Enable-PSRemoting -Force' first and then try again!" -ForegroundColor Green
    #Enable-PSRemoting -Force 

    $adapter = Get-NetConnectionProfile -InterfaceAlias "MODULUS"
    if ($adapter.NetworkCategory -ne "Private") {
        Set-NetConnectionProfile -InterfaceAlias "MODULUS" -NetworkCategory Private
        Write-Host "Updated network adatper MODULUS to use NetworkCategory Private!" -ForegroundColor Yellow
    }

    #Enable-PSRemoting 
    try {
        if (-not (Get-PSSessionConfiguration -name "modulus-PS7" -ErrorAction SilentlyContinue)) {
            Register-PSSessionConfiguration -Name 'modulus-PS7' -StartupScript 'C:\Program Files\PowerShell\Modules\modulus-toolkit\modules\0-startup-remote.ps1'
            Restart-Service -Name "WinRM" -ErrorAction SilentlyContinue
            Write-host "'PSSessionConfiguration' registered!"
        } else {
            Unregister-PSSessionConfiguration -Name 'modulus-PS7' -Force
            Register-PSSessionConfiguration -Name 'modulus-PS7' -StartupScript 'C:\Program Files\PowerShell\Modules\modulus-toolkit\modules\0-startup-remote.ps1'
            Restart-Service -Name "WinRM" -ErrorAction SilentlyContinue
            Write-host "'PSSessionConfiguration' re-registered!"
        }
    } 
    catch {
        Write-Host "Error (re-)registering 'modulus-PS7' PSSessionConfiguation!"
    }
    
    $DB  = Get-MOD-DB-hostname
    $APP = Get-MOD-APP-hostname
    $FS  = Get-MOD-FS-hostname

    if ($DB -eq $FS) {
        $value = "tlukas, tlukasVM"
    } else {
        $value = $DB + "," + $APP + "," + $FS + ",tlukas,tlukasVM"
    }
    
    Write-host "Adding 3VM scope to trusted users!" -ForegroundColor Yellow
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $value -Force
    
    winrm quickconfig

    if (-not (Get-NetFirewallRule -Name "Allow WinRM" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name "Allow WinRM" -DisplayName "Allow WinRM" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985
    } else {
        Write-Output "Firewall rule 'Allow WinRM' already exists."
    }
    
}
#endregion

#region --- managing PS sessions
function Open-DB-Session {
    #variables needed
    $user   = "Administrator"
    $target = Get-MOD-DB-hostname
    #$cred   = Get-CredentialFromVault -User $user -Target $target
    $cred = Get-DatabaseCredentials -User $user -DB $target
    
    #$sessDB = New-PSSession -ComputerName $target -Credential $cred
    $sessDB = New-PSSession -ComputerName $target -Credential $cred -ConfigurationName 'modulus-PS7'
    #$sessDB = New-PSSession -ComputerName $target -Credential $cred -ConfigurationName 'PowerShell.7.4.5'
    
    # Store the session ID or the session object for later use
    $global:open_sessDB = $sessDB

    # Rename the PowerShell window title
    #$windowTitle = "Remote Session: $target"
    #[Console]::Title = $windowTitle

    #enter connection
    #Enter-PSSession $sessDB

    Invoke-Command -Session $sessDB -ScriptBlock {
        Write-Host "Session opened on DATABASE server!" -ForegroundColor Yellow
        Set-Location -Path D:\OnlineData -ErrorAction SilentlyContinue

        # Map the I: drive within the remote session
        $app = Get-MOD-APP-hostname
        $I = '\\' + $app + '\I'
        New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $I -Persist
    }
}

function Open-APP-Session {
    #variables needed
    $user   = "Administrator"
    $target = Get-MOD-APP-hostname
    #$cred   = Get-CredentialFromVault -User $user -Target $target
    $cred = Get-DatabaseCredentials -User $user -DB $target
    
    #$sessAPP = New-PSSession -ComputerName $target -Credential $cred
    $sessAPP = New-PSSession -ComputerName $target -Credential $cred -ConfigurationName 'modulus-PS7'
    #$sessAPP = New-PSSession -ComputerName $target -Credential $cred -ConfigurationName 'PowerShell.7.4.5'

    # Store the session ID or the session object for later use
    $global:open_sessAPP = $sessAPP

    # Rename the PowerShell window title
    #$windowTitle = "Remote Session: $target"
    #[Console]::Title = $windowTitle

    #enter connection
    #Enter-PSSession $sessAPP
    
    Invoke-Command -Session $sessAPP -ScriptBlock {
        Write-Host "Session opened on APPLICATION server!" -ForegroundColor Yellow
        Set-Location -Path D:\Galaxis -ErrorAction SilentlyContinue

        # not needed on APP-server
        # Map the I: drive within the remote session
        #$app = Get-MOD-APP-hostname
        #$I = '\\' + $app + '\I'
        #New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $I -Persist
    }
}

function Open-FS-Session {
    #variables needed
    $user   = "Administrator"
    $target = Get-MOD-FS-hostname
    #$cred   = Get-CredentialFromVault -User $user -Target $target
    $cred = Get-DatabaseCredentials -User $user -DB $target
    
    #$sessFS = New-PSSession -ComputerName $target -Credential $cred
    $sessFS = New-PSSession -ComputerName $target -Credential $cred -ConfigurationName 'modulus-PS7'
    #$sessFS = New-PSSession -ComputerName $target -Credential $cred -ConfigurationName 'PowerShell.7.4.5'

    # Store the session ID or the session object for later use
    $global:open_sessFS = $sessFS

    # Rename the PowerShell window title
    #$windowTitle = "Remote Session: $target"
    #[Console]::Title = $windowTitle

    #enter connection
    #Enter-PSSession $sessFS
    
    Invoke-Command -Session $sessFS -ScriptBlock {
        Write-Host "Session opened on FLOOR server!" -ForegroundColor Yellow
        Set-Location -Path D:\OnlineData -ErrorAction SilentlyContinue

       # Map the I: drive within the remote session
       $app = Get-MOD-APP-hostname
       $I = '\\' + $app + '\I'
       New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $I -Persist
    }
}

function Close-PS-Sessions {
    
    $sessCounter = 0

    if ($global:open_sessDB) {
        $sessCounter = $sessCounter + 1
        $sessName = $global:open_sessDB.ComputerName
        # Remove the PowerShell session
        write-host "Closing session to $sessName!" -ForegroundColor Green
        Remove-PSSession $global:open_sessDB
        # Clear the global variable
        Remove-Variable -Name open_sessDB -Scope Global
    } 
    if ($global:open_sessAPP) {
        $sessCounter = $sessCounter + 1
        $sessName = $global:open_sessAPP.ComputerName
        # Remove the PowerShell session
        write-host "Closing session to $sessName!" -ForegroundColor Green
        Remove-PSSession $global:open_sessAPP
        # Clear the global variable
        Remove-Variable -Name open_sessAPP -Scope Global
        
    } 
    if ($global:open_sessFS) {
        $sessCounter = $sessCounter + 1
        $sessName = $global:open_sessFS.ComputerName
        # Remove the PowerShell session
        write-host "Closing session to $sessName!" -ForegroundColor Green
        Remove-PSSession $global:open_sessFS
        # Clear the global variable
        Remove-Variable -Name open_sessFS -Scope Global
    } 
    if ($sessCounter -eq 0) {
        Write-host "No sessions to close!" -ForegroundColor Yellow
    }
    #[Console]::Title = "tlukas"
}
#endregion