#tlukas, 12.11.2025

#write-host "Loading grafana.psm1!" -ForegroundColor Green

#region --- handle alloy service
function Stop-Alloy {
    Write-Log "Stopping Alloy..."
    Stop-Service -Name "Alloy" -ErrorAction SilentlyContinue
}

function Start-Alloy {
    Write-Log "Starting Alloy..."
    Start-Service -Name "Alloy" -ErrorAction SilentlyContinue
}
#endregion

#region --- setting BASE config.alloy according to server type
function Set-AlloyConfig {
    $root   = "C:\Program Files\GrafanaLabs\Alloy\"
    $config = Join-Path -path $root -ChildPath "config.alloy"

    switch($env:MODULUS_SERVER) {
        "DB"  { $template = "config.alloy.DB_base" ; $suffix = "DB_base"  }
        "APP" { $template = "config.alloy.APP_base"; $suffix = "APP_base" }
        "FS"  { $template = "config.alloy.FS_base" ; $suffix = "FS_base"  }
        "1VM" { Write-Log "Not implemented yet." WARNING; Return }
    }

    Write-Log "Using $template to create a new $config on $($env:MODULUS_SERVER)!"
    Invoke-PlaceholderReplacement `
        -BasePath "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates\alloy" `
        -Include $template `
        -OutputRoot $root `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets

    #TODO: works, but isn't elegant, need to rework the placeholder replacement to support direct output file naming
    #backup existing config
    if (Test-Path $config) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backup = "$config.bak_$timestamp"
        Write-Log "Backing up existing config.alloy to $backup"
        rename-item $config $backup -Force
    }
    $generatedconfig = Join-Path -path $root -ChildPath $template
    Write-Log "Deploying generated config.alloy from $generatedconfig to $config"
    rename-Item $generatedconfig $config -Force
}
#endregion

#region --- config helper
function Open-AlloyConfig {
    $alloyConfig    = "C:\Program Files\GrafanaLabs\Alloy\config.alloy"
    if(Test-Path $alloyConfig) {
        np $alloyConfig
    } else {
        write-log "$alloyConfig does not exist!" ERROR
    }
}
#endregion

#region --- installing alloy using offline installer
function Install-Grafana-Offline {
    # Requires running as Administrator
    Write-Log "Install-Grafana-Offline" -Header
    try {
        $InstallerPath = "I:\Tools\3rd_party_software\Grafana\alloy-installer-windows-amd64.exe"
        Write-Log "Starting silent installation of Grafana Alloy..."
        Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -Verb RunAs
        Write-Log "Grafana Alloy offline installation complete."    
    }
    catch {
        Write-Log "ERROR during Alloy installation: $($_.Exception.Message)"
    }
}
#endregion

#region --- installing alloy using an internet connection and IWR
function Install-Grafana-Online {
    # Requires running as Administrator
    Write-Log "Install-Grafana-Online" -Header
    if(-not (Test-InternetConnection)) {
        Write-log "No internet connectivity - Aborting!"
        Return
    }

    #region --- original one-liner
    <#
    Invoke-WebRequest "https://storage.googleapis.com/cloud-onboarding/alloy/scripts/install-windows.ps1" `
       -OutFile "install-windows.ps1" && powershell -executionpolicy Bypass -File ".\install-windows.ps1" `
       -GCLOUD_HOSTED_METRICS_URL "https://prometheus-prod-24-prod-eu-west-2.grafana.net/api/prom/push" `
       -GCLOUD_HOSTED_METRICS_ID "1786329" -GCLOUD_SCRAPE_INTERVAL "60s" -GCLOUD_HOSTED_LOGS_URL "https://logs-prod-012.grafana.net/loki/api/v1/push" `
       -GCLOUD_HOSTED_LOGS_ID "992451" -GCLOUD_RW_API_KEY "glc_eyJvIjoiMTIxOTAzNSIsIm4iOiJzdGFjay0xMDM0NjcxLWludGVncmF0aW9uLWFjY2VwdGFuY2UtYXBwIiwiayI6IjNUMzF6Z2NYMDJubjZ4WjRvMjlWQllLOSIsIm0iOnsiciI6InByb2QtZXUtd2VzdC0yIn19"
    #>
    #endregion

    $cwd = Get-Location
    $wd  = "C:\temp"
    Set-Location $wd
    $outFile = Join-Path -Path $wd -ChildPath "install-windows.ps1"
    $uri     = "https://storage.googleapis.com/cloud-onboarding/alloy/scripts/install-windows.ps1"

    try {
        #removed because of public repo, will be handled by encrypted blob in future
    } catch {
        Write-Log "ERROR during Alloy installation: $($_.Exception.Message)"
    } finally {
        Remove-Item $outFile -ErrorAction SilentlyContinue
        Set-Location $cwd
    }
}
#endregion

#region --- Deploying Grafana alloy, creating the user in both databases and 
function Deploy-Grafana {
    param(
        [switch]$Online
    )
    Write-Log "Deploy-Grafana" -Header
    Stop-Alloy
    if($Online) {
        Install-Grafana-Online
    } else {
        Install-Grafana-Offline
    }
    Stop-Alloy  #just in case
    Set-GLX-Grafanau-user
    Set-JKP-Grafanau-user
    Set-AlloyConfig
    Start-Alloy
}
#endregion


#TODO:

#need elevation check
#need installer-check
#need to check if on correct server 1VM or ?
#need to check if installed alrady
#need different config packages (TIER1,2,3)