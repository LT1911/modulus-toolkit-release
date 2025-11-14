#tlukas, 22.10.2024

#write-host "Loading 6-devops-admin.psm1!" -ForegroundColor Green

#region --- helper functionality for finding the correct and up2date sources
function Resolve-ArchiveCandidates {
    <#
      .SYNOPSIS
        Returns all archives matching a pattern, with parsed Version and tie-breaker metadata.
      .PARAMETER Directory
        Folder to scan (your sources dir).
      .PARAMETER Pattern
        File name filter, e.g. 'Galaxis*Config*.7z'
      .PARAMETER VersionRegex
        Regex to extract a version from file name (default is forgiving).
        First capture group should be the version string.
      .OUTPUTS
        [pscustomobject] with: Name, File, Version ([version] or $null), LastWriteTime, Length
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $Pattern,
        [string] $VersionRegex = '([0-9]+(?:\.[0-9]+){1,3})(?:[^\d]|$)' # 1.2 / 1.2.3 / 1.2.3.4
    )

    if (-not (Test-Path $Directory -PathType Container)) {
        throw "Directory '$Directory' does not exist."
    }

    $files = Get-ChildItem -Path $Directory -Filter $Pattern -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $ver = $null
        $m = [regex]::Match($f.Name, $VersionRegex)
        if ($m.Success) {
            # Try parse to [version]; if 4-part is missing, .NET still handles 2-3 parts
            try { $ver = [version]$m.Groups[1].Value } catch { $ver = $null }
        }

        [pscustomobject]@{
            Name          = $f.Name
            File          = $f.FullName
            Version       = $ver
            LastWriteTime = $f.LastWriteTimeUtc
            Length        = $f.Length
        }
    }
}

function Select-NewestArchive {
    <#
      .SYNOPSIS
        Picks the newest archive from candidates with a version-first policy.
      .DESCRIPTION
        Prefers the highest parsed Version. If some files have no version, or versions tie,
        falls back to LastWriteTimeUtc (descending) as a stable tie-breaker.
      .OUTPUTS
        [pscustomobject] with Candidate and All (the full list you can inspect/log)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Candidates
    )

    if (-not $Candidates) { return $null }

    $withVer    = $Candidates | Where-Object { $_.Version -ne $null }
    $withoutVer = $Candidates | Where-Object { $_.Version -eq $null }

    $ordered =
        if ($withVer) {
            # Sort by Version desc, then LastWriteTime desc
            $withVer | Sort-Object Version, LastWriteTime -Descending
        } else {
            # No versions? Use LastWriteTime desc only
            $Candidates | Sort-Object LastWriteTime -Descending
        }

    [pscustomobject]@{
        Candidate = $ordered | Select-Object -First 1
        All       = $Candidates
    }
}

function Expand-LatestArchive {
    <#
      .SYNOPSIS
        Finds latest archive by pattern in Sources, warns if multiple exist, then extracts.
      .PARAMETER Sources
        Sources directory to scan.
      .PARAMETER TargetFolder
        Where to extract to.
      .PARAMETER FilePattern
        Archive file filter (e.g., 'Galaxis*Config*.7z').
      .PARAMETER Subfolder
        Optional subfolder within the archive to extract (e.g., 'Server\Galaxis\*').
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Sources,
        [Parameter(Mandatory)] [string] $TargetFolder,
        [Parameter(Mandatory)] [string] $FilePattern,
        [string] $Subfolder
    )

    Write-Log "Scanning sources for '$FilePattern' in '$Sources'..." INFO

    $candidates = Resolve-ArchiveCandidates -Directory $Sources -Pattern $FilePattern
    if (-not $candidates) {
        Write-Log "No archives match '$FilePattern' in '$Sources'." WARNING
        return $null
    }

    $selection = Select-NewestArchive -Candidates $candidates
    $pick      = $selection.Candidate

    # Nudging the user to clean up (when multiple possible updates are present)
    if (($selection.All | Measure-Object).Count -gt 1) {
        $names = ($selection.All | Sort-Object Version, LastWriteTime -Descending | Select-Object -ExpandProperty Name)
        Write-Log "Multiple matching archives found. Using newest: '$($pick.Name)'. Consider cleaning the folder:" WARNING
        foreach ($n in $names) { Write-Log " - $n" DEBUG }
    }

    Write-Log ("Selected archive: {0} (Version: {1}; Modified: {2:yyyy-MM-dd HH:mm}Z)" -f `
        $pick.Name, ($pick.Version ?? "<none>"), $pick.LastWriteTime) DEBUG

    if ($PSCmdlet.ShouldProcess($TargetFolder, "Extract $($pick.Name)")) {
        # Ensure target exists / is empty enough for your workflow
        if (-not (Test-Path $TargetFolder)) { New-Item -ItemType Directory -Path $TargetFolder | Out-Null }

        Expand-7ZipFile -SourceFolder $pick.File -TargetFolder $TargetFolder -FilePattern $FilePattern -Subfolder $Subfolder
        return $pick
    }
}

function Initialize-PrepDir {
    <#
      .SYNOPSIS
        Makes sure a directory is empty before use.
      .DESCRIPTION
        If the directory exists, logs a warning and clears it.
        If it doesn’t exist, creates it.
      .PARAMETER Path
        The directory path to ensure.
      .OUTPUTS
        [string] The resolved full path (useful for chaining).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $full = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)?.Path ?? $Path

    if (Test-Path $full -PathType Container) {
        Write-Log "Target folder already exists: $full" WARNING

        if ($PSCmdlet.ShouldProcess($full, "Clear directory")) {
            try {
                Remove-Item -Path $full -Recurse -Force -ErrorAction Stop
                Write-Log "Cleared old content in $full" INFO
            }
            catch {
                Write-Log "Failed to clear $full" ERROR 
                write-log "$_" ERROR
                throw
            }
        }
    }

    if (-not (Test-Path $full)) {
        if ($PSCmdlet.ShouldProcess($full, "Create directory")) {
            New-Item -ItemType Directory -Path $full -Force | Out-Null
            Write-Log "Created directory: $full" DEBUG
        }
    }

    return $full
}
#endregion

#region --- Galaxis-related cleanup functions
function Remove-1097-Artifacts {
    Write-Log "Remove-1097-Artifacts" -Header

    if ((Get-MOD-Server).name -ne 'APP' -and (Get-MOD-Server).name -ne '1VM') {
        Write-Log "Not on APP or 1VM, skipping cleanup!" -Level WARNING
        return
    } 

    Write-Log 'Clearing out some old stuff that its no longer used in 1097 going forward!' DEBUG
    Write-Log 'Clearing out D:\Galaxis\Program\bin\GlxPublicApi\ recursively!' DEBUG
	Write-Log 'Clearing out D:\Galaxis\Program\bin\nginx\public-api-reverse-proxy.conf!' DEBUG
	Write-Log 'Clearing out D:\Galaxis\Program\bin\nginx\api-keys.conf!' DEBUG
	Write-Log 'Clearing out D:\Galaxis\Program\bin\WinSW\GlxPublic*-stuff!' DEBUG
    
    Remove-Item -path "D:\Galaxis\Program\bin\GlxPublicApi\" -Recurse -ErrorAction SilentlyContinue
	Remove-Item -path "D:\Galaxis\Program\bin\nginx\modulus\public-api-reverse-proxy.conf" -ErrorAction SilentlyContinue
    remove-item -path "D:\Galaxis\Program\bin\nginx\modulus\api-keys.conf" -ErrorAction SilentlyContinue
	Get-ChildItem -path "D:\Galaxis\Program\bin\WinSW\GlxPublic*" | remove-item -ErrorAction SilentlyContinue
	
    write-log "Remove-1097-Artifacts completed!" -Level INFO
}
#endregion

#region --- Closing file access on Galaxis directory
function Close-GLXDirAccess {
    Write-Log "Close-GLXDirAccess" -Header

    #TODO: limit usage on APP, 1VM
	$galaxisDir = Get-GalaxisPath

	if(!(Test-Path $galaxisDir))
	{
		write-Log '$galaxisDir does not exist!' -Level ERROR
		exit
	}
	
	$openFiles = Get-SmbOpenFile | Where-Object Path -Like "$galaxisDir*"
	
	write-Log "Closing all open files in $galaxisDir"
	
	foreach($file in $openFiles)
	{
		Close-SmbOpenFile -FileId $file.FileId -force
	}

	write-log "Close-GLXDirAccess completed!" -Level INFO
}

function Disable-M-Share {
    write-log "Disable-M-Share" -Header
   
    if($env:MODULUS_SERVER -notin ('APP','1VM')) {
        Write-Log "Not on APP or 1VM, skipping share removal!" -Level WARNING
        return
    }

	$shareName = 'Galaxis'
	$galaxisShare = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue

	if($null -ne $galaxisShare)
	{
		Write-Log 'Disabling the sharing of D:\Galaxis!'
		Remove-SmbShare -Name $shareName -Force
	}

    write-log "Disable-M-Share completed!" -Level INFO
}

function Enable-M-Share {
    Write-Log "Enable-M-Share" -Header

    if((Get-MOD-Server).name -ne 'APP') {
        Write-Log "Not on APP, aborting!" -Level WARNING
        return
    }

	$shareName = 'Galaxis'
	$folderPath = 'D:\Galaxis'

	$galaxisShare = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue

	if($null -eq $galaxisShare)
	{
		Write-Log 'Enabling the sharing of D:\Galaxis!'
		New-SmbShare -Name $shareName -Path $folderPath -FullAccess "Everyone" | Out-Null
	} else {
		Write-Log 'D:\Galaxis is already shared!'
	}

    write-log "Enable-M-Share completed!" -Level INFO
}
#endregion

#region --- Galaxis cleanup scripts
function Clear-GLXLogs {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

    Write-Log "Clear-GLXLogs" -Header

	if ($AskIf) {
        $confirm = Read-Host "Are you sure you want to clear the logs? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Log "Clear-GLXLogs operation cancelled." -Level WARNING
            return
        }
    }
    
	$sizeBefore = Get-ChildItem -Path "D:\Galaxis" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}

	
    #region directly deleting
	#cleaning out C:\Galaxis\GalaxisTemp\*
	Write-Log "Cleaning out C:\Galaxis\GalaxisTemp\* .." DEBUG
	Remove-Item -Path C:\Galaxis\GalaxisTemp\* -Recurse -ErrorAction SilentlyContinue
    
    # clean RTDS logs
	# ALARM SERVER
	Write-Log  "Cleaning out ALARM SERVER logs .." DEBUG
	Remove-Item -Path D:\Galaxis\Application\OnLine\AlarmServer\Current\dat -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\Galaxis\Application\OnLine\AlarmServer\Current\log -Recurse -ErrorAction SilentlyContinue
	# SLOT MACHINE SERVER
	Write-Log  "Cleaning out SLOT MACHINE SERVER logs .." DEBUG
	Remove-Item -Path D:\Galaxis\Application\OnLine\SlotMachineServer\Current\dat -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\Galaxis\Application\OnLine\SlotMachineServer\Current\log -Recurse -ErrorAction SilentlyContinue
	# TRANSACTION SERVER
	Write-Log  "Cleaning out TRANSACTION SERVER logs .." DEBUG
	Remove-Item -Path D:\Galaxis\Application\OnLine\TransactionServer\Current\dat -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\Galaxis\Application\OnLine\TransactionServer\Current\log -Recurse -ErrorAction SilentlyContinue

	# clean GDC logs
	Write-Log  "Cleaning out GDC logs .." DEBUG
	Get-ChildItem -Path D:\Galaxis -Filter FullLog*.txt | Remove-Item -Recurse -ErrorAction SilentlyContinue -Force
	Get-ChildItem -Path D:\Galaxis -Filter ShortLog*.txt| Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 

	# clean GALAXIS logs
	Write-Log  "Cleaning out Galaxis logs .." DEBUG
	Remove-Item -Path D:\Galaxis\Log\* -Recurse -ErrorAction SilentlyContinue

	# delete all *.err-files in D:\Galaxis
	Write-Log "Cleaning out *.err-files from D:\Galaxis .." DEBUG
	Get-ChildItem -Path D:\Galaxis -Filter *.err -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item

	# delete all BDESC*-files in D:\Galaxis 
	Write-Log "Cleaning out BDESC*-files from D:\Galaxis .." DEBUG
	Get-ChildItem -Path D:\Galaxis -Filter BDESC* -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item

	# delete all *minidump*-files in D:\Galaxis 
	Write-Log "Cleaning out *minidump*-files from D:\Galaxis .." DEBUG
	Get-ChildItem -Path D:\Galaxis -Filter *minidump* -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item 


	# todo JPS & SMOI -logs
	#mod-log "Cleaning out JPS and SMOI logs .."
	Get-ChildItem -Path D:\Galaxis\Program\StarSlots -Filter JPS-LogFile* | Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 
	Get-ChildItem -Path D:\Galaxis\Program\StarSlots -Filter JPS-Error-LogFile*  | Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 
	Get-ChildItem -Path D:\Galaxis\Program\StarSlots -Filter SMOI-LogFile*  | Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 
    Get-ChildItem -Path D:\Galaxis\Program\StarSlots -Filter SMOI-Error-LogFile*  | Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force
    
	$sizeAfter = Get-ChildItem -Path "D:\Galaxis" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}
              
    $sizeBeforeMB = $sizeBefore.'size(MB)'
    $sizeAfterMB = $sizeAfter.'size(MB)'

    write-log "Size of D:\Galaxis before cleaning (in MB):  $sizeBeforeMB" DEBUG           
	write-log "Size of D:\Galaxis after cleaning (in MB):   $sizeAfterMB" DEBUG
	$saved = $sizeBeforeMB - $sizeAfterMB
	write-log "Cleaned out (in MB): $saved"
    write-host ""
}

function Clear-OnlineDataLogs {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

    Write-log "Clear-OnlineDataLogs" -Header

	if ($AskIf) {
        $confirm = Read-Host "Are you sure you want to clear the logs? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Log "Clear-OnlineDataLogs operation cancelled." -Level WARNING 
            return
        }
    }

	$sizeBefore = Get-ChildItem -Path "D:\OnlineData" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}

    Write-Log "Cleaning out logfiles from D:\OnlineData\logs\" DEBUG
    write-log "Cleaning out logfiles from D:\OnlineData\nginx\logs\" DEBUG
    Write-Log "Cleaning out logfiles from D:\OnlineData\Relay\logs\" DEBUG        
	Write-Log "Cleaning out logfiles from D:\OnlineData\Dbx\logs\" DEBUG  
    Write-Log "Cleaning out logfiles from D:\OnlineData\Server\logs\" DEBUG  
    Remove-Item -Path D:\OnlineData\log\ -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\OnlineData\nginx\logs\ -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\OnlineData\Relay\Logs\ -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\OnlineData\Dbx\log -Recurse -ErrorAction SilentlyContinue
	Get-ChildItem -Path D:\OnlineData\Server -Filter server*.log -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item 
	
	$sizeAfter = Get-ChildItem -Path "D:\OnlineData" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}
              
    $sizeBeforeMB = $sizeBefore.'size(MB)'
    $sizeAfterMB = $sizeAfter.'size(MB)'

    write-log "Size of D:\OnlineData before cleaning (in MB):  $sizeBeforeMB" DEBUG                
	write-log "Size of D:\OnlineData after cleaning (in MB):   $sizeAfterMB" DEBUG
	$saved = $sizeBeforeMB - $sizeAfterMB
	write-log "Cleaned out (in MB): $saved"
    write-host ""
}
#endregion

#region --- check for OEM Java and uninstall #TODO - needs to be part of deployment/prereq handling
function Find-OEMJava {
    Write-Log "Find-OEMJava" -Header
    Write-Log "Finding OEM Java installations!"

	$count = 0
	$java = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Java SE Development Kit 8 Update 72"}
	$upd = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Java 8 Update 72"}

	if ($java) {
		Write-Host ' > Java SE Development Kit 8 Update 72 is still installed!'
		$count = $count + 1
		if ($upd) {
			Write-Host ' > Java 8 Update 72 is still installed!'
			$count = $count + 1
		}
	}
	if ($count -eq 0) {
		Write-Host ' > No OEM Java installations found - all good!'
	} else {
		Write-Host ' > These features should be deinstalled before going into production!'
		Write-Host ' > Use function "Unintall-OEMJava" to uninstall these features!'
	}
}

function Uninstall-OEMJava {

	Write-Host '>'
    Write-Host '> Uninstalling OEM Java (if installed)!'
	$count = 0

	$upd= Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Java 8 Update 72"}
	if($upd) { 
		$count = $count + 1
		Write-Host ' > Uninstalling Java 8 Update 72!'
		$upd.Uninstall()
	}
	

	$java = Get-WmiObject -Class Win32_Product | Where-Object{$_.Name -eq "Java SE Development Kit 8 Update 72"}
	if($java) {
		$count = $count + 1
		Write-Host ' > Uninstalling Java SE Development Kit 8 Update 72!'
		$java.Uninstall()
	}

	if($count -eq 0) {
		Write-Host ' > No OEM Java installations found - all good!'	
	}
	
}
#endregion

#region --- service-related functions
function Install-MOD-Services {
    Write-Log "Install-MOD-Services" -Header
	
	D:
	$WinSW = "D:\Galaxis\Program\bin\WinSW\"
	Set-Location $WinSW

	#should be in order of released services
	$nginx 		= Get-Service -displayName "nginx"			  -ErrorAction SilentlyContinue
	$aml	    = Get-Service -displayName "Galaxis AML S*"	  -ErrorAction SilentlyContinue
	$glxapi   	= Get-Service -displayName "Galaxis API*"	  -ErrorAction SilentlyContinue
	$notif		= Get-Service -displayName "Galaxis Notif*"	  -ErrorAction SilentlyContinue
	$license 	= Get-Service -displayName "Galaxis Licen*"	  -ErrorAction SilentlyContinue
	$tablesetup	= Get-Service -displayName "Galaxis Table*"	  -ErrorAction SilentlyContinue
	$glxpublic	= Get-Service -displayName "Galaxis Publ*"	  -ErrorAction SilentlyContinue
	$glxpartner = Get-Service -displayName "Galaxis Partner*" -ErrorAction SilentlyContinue
	$loyality   = Get-Service -displayName "Galaxis Loyalty*" -ErrorAction SilentlyContinue
	$outbox     = Get-Service -displayName "Galaxis Outbox*"  -ErrorAction SilentlyContinue
	$playerSer  = Get-Service -displayName "Galaxis Player S*"-ErrorAction SilentlyContinue
    $DataSetSer = Get-Service -displayName "Galaxis Assets S*" -ErrorAction SilentlyContinue
    $assetSer   = Get-Service -displayName "Galaxis DataS*" -ErrorAction SilentlyContinue
    #10.99
    $amlKiosk   = Get-Service -displayName "Galaxis AML K*" -ErrorAction SilentlyContinue
    $epay       = Get-Service -displayName "Galaxis ePayGate" -ErrorAction SilentlyContinue
    #10.100
    $junkSer   = Get-Service -displayName "Galaxis Junket S*" -ErrorAction SilentlyContinue
    $junkCon   = Get-Service -displayName "Galaxis Junket C*" -ErrorAction SilentlyContinue


    if(!$nginx)
	{
        if (!(Test-Path "nginx.exe")) {
            Write-Log "nginx.exe not found, cannot install nginx service!" -Level ERROR
        } else {
            Write-Log "Installing nginx service and configuring StartupType Manual!" DEBUG
            .\nginx.exe install nginx.xml
		    $nginx | Set-Service -StartupType Manual
        }
	}

	if(!$aml)
	{
        if (!(Test-Path "amlservice.exe")) {
            Write-Log "amlservice.exe not found, cannot install amlservice service!" -Level ERROR
        } else {
            Write-Log "Installing amlservice service and configuring StartupType Manual!" DEBUG
           .\amlservice.exe install amlservice.xml
		    $aml | Set-Service -StartupType Manual
        }
	}
	
	if(!$glxapi)
	{
        if (!(Test-Path "glxapi.exe")) {
            Write-Log "glxapi.exe not found, cannot install glxapi service!" -Level ERROR
        } else {
            Write-Log "Installing glxapi service and configuring StartupType Manual!" DEBUG
           .\glxapi.exe install glxapi.xml
		    $glxapi | Set-Service -StartupType Manual
        }
	}

	if(!$notif)
	{
        if (!(Test-Path "notificationservice.exe")) {
            Write-Log "notificationservice.exe not found, cannot install notificationservice service!" -Level ERROR
        } else {
            Write-Log "Installing notificationservice service and configuring StartupType Manual!" DEBUG
           .\notificationservice.exe install notificationservice.xml
		    $notif | Set-Service -StartupType Manual
        }
	}
	
	if(!$license)
	{
        if (!(Test-Path "licenseservice.exe")) {
            Write-Log "licenseservice.exe not found, cannot install licenseservice service!" -Level ERROR
        } else {
            Write-Log "Installing notificationservice service and configuring StartupType Manual!" DEBUG
           .\licenseservice.exe install licenseservice.xml
		    $license | Set-Service -StartupType Manual
        }
	}

	if(!$tablesetup)
	{
        if (!(Test-Path "TableSetup.WindowsService.exe")) {
            Write-Log "TableSetup.WindowsService.exe not found, cannot install TableSetup.WindowsService service!" -Level ERROR
        } else {
            Write-Log "Installing TableSetup.WindowsService service and configuring StartupType Manual!" DEBUG
           .\TableSetup.WindowsService.exe install TableSetup.WindowsService.xml
		    $tablesetup| Set-Service -StartupType Manual
        }
	}

    #10.97 - Galaxis Public API is replaced with 10.97 version, so removing old service if exists
	<#if(!$glxpublic)
	{
		.\GlxPublicApi.exe install GlxPublicApi.xml
		$glxpublic | Set-Service -StartupType Manual
	}
	#>

	if($glxpublic)
	{
		Write-Log "Removing Galaxis Public API service, it has been replaced by Galaxis Partner API with 10.97!" DEBUG
		Remove-Service  $glxpublic.name 
	}

	if(!$glxpartner)
	{
		.\GlxPartnerApi.exe install GlxPartnerApi.xml
		$glxpartner | Set-Service -StartupType Manual
	}

	if(!$loyality)
	{
        if (!(Test-Path "LoyaltyService.WindowsService.exe")) {
            Write-Log "LoyaltyService.WindowsService.exe not found, cannot install LoyaltyService.WindowsService service!" -Level ERROR
        } else {
            Write-Log "Installing LoyaltyService.WindowsService service and configuring StartupType Manual!" DEBUG
           .\LoyaltyService.WindowsService.exe install LoyaltyService.WindowsService.xml
		    $loyality | Set-Service -StartupType Manual
        }
	}

	if(!$outbox)
	{
        if (!(Test-Path "OutboxService.WindowsService.exe")) {
            Write-Log "OutboxService.WindowsService.exe not found, cannot install OutboxService.WindowsService service!" -Level ERROR
        } else {
            Write-Log "Installing OutboxService.WindowsService service and configuring StartupType Manual!" DEBUG
           .\OutboxService.WindowsService.exe install OutboxService.WindowsService.xml
		    $outbox | Set-Service -StartupType Manual
        }
	}

	if(!$playerSer)
	{
        if (!(Test-Path "PlayerService.WindowsService.exe")) {
            Write-Log "PlayerService.WindowsService.exe not found, cannot install PlayerService.WindowsService service!" -Level ERROR
        } else {
            Write-Log "Installing PlayerService.WindowsService service and configuring StartupType Manual!" DEBUG
           .\PlayerService.WindowsService.exe install PlayerService.WindowsService.xml
		    $playerSer | Set-Service -StartupType Manual
        }
	}

    if(!$DataSetSer)
	{
        if (!(Test-Path "DataSetupService.WindowsService.exe")) {
            Write-Log "DataSetupService.WindowsService.exe not found, cannot install DataSetupService.WindowsService service!" -Level ERROR
        } else {
            Write-Log "Installing DataSetupService.WindowsService service and configuring StartupType Manual!" DEBUG
           .\DataSetupService.WindowsService.exe install DataSetupService.WindowsService.xml
		    $DataSetSer | Set-Service -StartupType Manual
        }
	}
    
    if(!$AssetSer) 
	{
        if (!(Test-Path "assetsservice.exe")) {
            Write-Log "assetsservice.exe not found, cannot install assetsservice service!" -Level ERROR
        } else {
            Write-Log "Installing assetsservice service and configuring StartupType Manual!" DEBUG
           .\assetsservice.exe install assetsservice.xml
		    $AssetSer | Set-Service -StartupType Manual
        }
	}

    #10.99
    if(!$amlKiosk) 
	{
        if (!(Test-Path "AMLKioskConnector.exe")) {
            Write-Log "AMLKioskConnector.exe not found, cannot install AMLKioskConnector service!" -Level ERROR
        } else {
            Write-Log "Installing AMLKioskConnector service and configuring StartupType Disabled (default)!" DEBUG
           .\AMLKioskConnector.exe install AMLKioskConnector.xml
		    $amlKiosk | Set-Service -StartupType Disabled
        }
	}

    if(!$epay) 
	{
        if (!(Test-Path "ePayGate.WindowsService.exe")) {
            Write-Log "ePayGate.WindowsService.exe not found, cannot install ePayGate.WindowsService service!" -Level ERROR
        } else {
            Write-Log "Installing ePayGate.WindowsService service and configuring StartupType Disabled (default)!" DEBUG
           .\ePayGate.WindowsService.exe install ePayGate.WindowsService.xml
		    $epay | Set-Service -StartupType Disabled
        }
	}

    #10.100
    if(!$junkSer) 
    {
        if (!(Test-Path "junketservice.exe")) {
            Write-Log "junketservice.exe not found, cannot install junketservice service!" -Level ERROR
        } else {
            Write-Log "Installing junketservice service and configuring StartupType Disabled (default)!" DEBUG
           .\junketservice.exe install junketservice.xml
            $junkSer | Set-Service -StartupType Disabled
        }
    }

    if(!$junkCon) 
    {
        if (!(Test-Path "JunketConnector.exe")) {
            Write-Log "JunketConnector.exe not found, cannot install JunketConnector service!" -Level ERROR
        } else {
            Write-Log "Installing JunketConnector service and configuring StartupType Disabled (default)!" DEBUG
           .\JunketConnector.exe install JunketConnector.xml
            $junkCon | Set-Service -StartupType Disabled
        }
        
    }

	Set-Location ~
    Write-Log "Install-MOD-Services completed!" -Level INFO
}
#endregion

#region --- preparing Galaxis binaries for deployment
function Prep-Galaxis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Executables","Config","Other","Install","ALL")] 
        [string]$Task,
        [switch]$AskIf
    )

    #Write-Log "Prep-Galaxis $Task" -Header

    if ($AskIf) {
        $confirm = Read-Host "Do you want to prepare $Task (Y/N)?"
        if ($confirm -ne "Y") {
            Write-Log "Preparation skipped!" -Level WARNING
            return
        }
    }

    if ($Task -eq "ALL") {
        Prep-Executables
        Prep-Config
        Prep-Other
    } else {
        switch ($Task) {
            "Executables"{ Prep-Executables }
            "Config"    { Prep-Config }
            "Other"     { Prep-Other }
            "Install"   { Prep-Install }
            Default { throw "Invalid task: $Task"; write-log "Invalid task: $Task" -Level ERROR }
        }
    }
}

function Prep-SYSTM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Executables","Config","ALL")] 
        [string]$Task,
        [switch]$AskIf
    )

    #Write-Log "Prep-SYSTM $Task" -Header

    if ($AskIf) {
        $confirm = Read-Host "Do you want to prepare $Task (Y/N)?"
        if ($confirm -ne "Y") {
            Write-Log "Preparation skipped!" -Level WARNING
            return
        }
    }

    if ($Task -eq "ALL") {
        Prep-SYSTM-Executables
        Prep-SYSTM-Config
    } else {
        switch ($Task) {
            "Executables"{ Prep-SYSTM-Executables }
            "Config"    { Prep-SYSTM-Config }
            Default { throw "Invalid task: $Task" ; write-log "Invalid task: $Task" -Level ERROR }
        }
    }
}

function Prep-Executables {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-Executables" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $filePattern = 'Galaxis*(Executable only).7z'
    $targetRoot  = Initialize-PrepDir -Path (Join-Path $prep 'GALAXIS Executable only')

    # 1) Extract newest matching archive (and warn if multiple exist)
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern `
                                 -Subfolder 'Server\Galaxis\*'

    if (-not $pick) {
        Write-Log "Prep-Executables aborted: no matching archive found." WARNING
        return
    }

    # 2) Post-extraction cleanup (idempotent, safe with ShouldProcess)
    if ($PSCmdlet.ShouldProcess($targetRoot, "Post-extraction cleanup")) {
        $serverPath  = Join-Path $targetRoot 'Server'
        $galaxisSrc  = Join-Path $serverPath 'Galaxis\*'
        $dockerPath  = Join-Path $targetRoot 'Docker'
        $installPath = Join-Path $targetRoot 'Install'
        $batchPath   = Join-Path $installPath 'Batch'

        if (Test-Path $galaxisSrc) { Move-Item   $galaxisSrc  $targetRoot -Force -ErrorAction SilentlyContinue }
        if (Test-Path $serverPath) { Remove-Item $serverPath  -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dockerPath) { Remove-Item $dockerPath  -Recurse -Force -ErrorAction SilentlyContinue }

        $installDocker = Join-Path $installPath 'Docker'
        if (Test-Path $installDocker) { Remove-Item $installDocker -Recurse -Force -ErrorAction SilentlyContinue }

        $inittab = Join-Path $installPath 'inittab'
        if (Test-Path $inittab) { Remove-Item $inittab -Force -ErrorAction SilentlyContinue }

        $idapi = Join-Path $batchPath 'IDAPI32.cfg'
        if (Test-Path $idapi) { Remove-Item $idapi -Force -ErrorAction SilentlyContinue }

        $tns = Join-Path $batchPath 'tnsnames.ora'
        if (Test-Path $tns) { Remove-Item $tns -Force -ErrorAction SilentlyContinue }

        $winscard = Join-Path $targetRoot 'Program\bin\WinSCard.dll'
        if (Test-Path $winscard) { Remove-Item $winscard -Force -ErrorAction SilentlyContinue }
    }

    #Write-Log "Prep-Executables completed!" INFO
}

function Prep-Other {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-Other" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $filePattern = 'Galaxis*(Other only).7z'
    $targetRoot  = Initialize-PrepDir -Path (Join-Path $prep 'GALAXIS Other only')

    # 1) Extract newest matching archive (and warn if multiple exist)
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern `
                                 -Subfolder 'Server\Galaxis\*'

    if (-not $pick) {
        Write-Log "Prep-Other aborted: no matching archive found." WARNING
        return
    }

    # 2) Post-extraction cleanup (idempotent, safe with ShouldProcess)
    if ($PSCmdlet.ShouldProcess($targetRoot, "Post-extraction cleanup")) {
        $serverPath   = Join-Path $targetRoot 'Server'
        $galaxisSrc   = Join-Path $serverPath 'Galaxis\*'
        $dockerPath   = Join-Path $targetRoot 'Docker'
        $installPath  = Join-Path $targetRoot 'Install'
        $installDock  = Join-Path $installPath 'Docker'
        $oldShortcut  = Join-Path $targetRoot 'Shortcut-Old organization'

        if (Test-Path $galaxisSrc) { Move-Item   $galaxisSrc  $targetRoot -Force -ErrorAction SilentlyContinue }
        if (Test-Path $serverPath) { Remove-Item $serverPath  -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dockerPath) { Remove-Item $dockerPath  -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $installDock){ Remove-Item $installDock -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $oldShortcut){ Remove-Item $oldShortcut -Recurse -Force -ErrorAction SilentlyContinue }
    }

    #Write-Log "Prep-Other completed!" INFO
}

function Prep-Config {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-Config" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $filePattern = 'Galaxis*(Config Only).7z'
    $targetRoot = Initialize-PrepDir -Path (Join-Path $prep 'GALAXIS Config only')

    # 1) Extract newest matching archive (and warn if multiple exist)
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern `
                                 -Subfolder 'Server\Galaxis\*'

    if (-not $pick) {
        Write-Log "Prep-Config aborted: no matching archive found." WARNING
        return
    }

    # 2) Post-extraction cleanup (idempotent, safe with ShouldProcess)
    if ($PSCmdlet.ShouldProcess($targetRoot, "Post-extraction cleanup")) {
        $serverPath = Join-Path $targetRoot 'Server'
        $galaxisSrc = Join-Path $serverPath 'Galaxis\*'
        $dockerPath = Join-Path $targetRoot 'Docker'

        if (Test-Path $galaxisSrc) {
            Move-Item $galaxisSrc $targetRoot -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $serverPath) {
            Remove-Item $serverPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $dockerPath) {
            Remove-Item $dockerPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    #Write-Log "Prep-Config completed!" INFO
}

function Prep-SYSTM-Executables {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-SYSTM-Executables" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $filePattern = 'SYSTM*(Executable only).7z'
    $targetRoot  = Initialize-PrepDir -Path (Join-Path $prep 'SYSTM Executable only')

    # 1) Extract newest matching archive (and warn if multiple exist)
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern `
                                 -Subfolder 'Server\Galaxis\*'

    if (-not $pick) {
        Write-Log "Prep-SYSTM-Executables aborted: no matching archive found." WARNING
        return
    }

    # 2) Post-extraction cleanup (idempotent, safe with ShouldProcess)
    if ($PSCmdlet.ShouldProcess($targetRoot, "Post-extraction cleanup")) {
        $serverPath = Join-Path $targetRoot 'Server'
        $galaxisSrc = Join-Path $serverPath 'Galaxis\*'

        if (Test-Path $galaxisSrc) {
            Move-Item $galaxisSrc $targetRoot -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $serverPath) {
            Remove-Item $serverPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    #Write-Log "Prep-SYSTM-Executables completed!" INFO
}

function Prep-SYSTM-Config {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-SYSTM-Config" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $filePattern = 'SYSTM*(Config only).7z'
    $targetRoot  = Initialize-PrepDir -Path (Join-Path $prep 'SYSTM Config only')

    # 1) Extract newest matching archive (and warn if multiple exist)
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern `
                                 -Subfolder 'Server\Galaxis\*'

    if (-not $pick) {
        Write-Log "Prep-SYSTM-Config aborted: no matching archive found." WARNING
        return
    }

    # 2) Post-extraction cleanup (idempotent, safe with ShouldProcess)
    if ($PSCmdlet.ShouldProcess($targetRoot, "Post-extraction cleanup")) {
        $serverPath = Join-Path $targetRoot 'Server'
        $galaxisSrc = Join-Path $serverPath 'Galaxis\*'
        #$dockerPath = Join-Path $targetRoot 'Docker'  # optional, keep commented if not needed

        if (Test-Path $galaxisSrc) { Move-Item $galaxisSrc $targetRoot -Force -ErrorAction SilentlyContinue }
        if (Test-Path $serverPath) { Remove-Item $serverPath -Recurse -Force -ErrorAction SilentlyContinue }
        # if (Test-Path $dockerPath) { Remove-Item $dockerPath -Recurse -Force -ErrorAction SilentlyContinue }
    }

    #Write-Log "Prep-SYSTM-Config completed!" INFO
}

function Prep-Install {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-Install" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $filePattern = 'UnCompressOnGalaxisHomeInstall*.7z'
    $targetRoot  = Initialize-PrepDir -Path (Join-Path $prep 'Install only')

    # 1) Extract newest matching archive (and warn if multiple exist)
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern
                                 # (no -Subfolder: extract whole package)

    if (-not $pick) {
        Write-Log "Prep-Install aborted: no matching archive found." WARNING
        return
    }

    # 2) Post-extraction cleanup (idempotent, safe with ShouldProcess)
    if ($PSCmdlet.ShouldProcess($targetRoot, "Post-extraction cleanup")) {
        $dockerPath = Join-Path $targetRoot 'Docker'
        if (Test-Path $dockerPath) {
            Remove-Item $dockerPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    #Write-Log "Prep-Install completed!" INFO
}

function Prep-Web {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-Web" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    # Target: ...\Web only\Web\SYSTM
    $targetRoot = Initialize-PrepDir -Path (Join-Path $prep 'Web only\Web\SYSTM')

    # 1) Main web package (exclude *Configuration* by pattern)
    $filePattern = 'GalaxisWeb.1*.7z'   # e.g. GalaxisWeb.10.101.00.175.7z (won't match 'GalaxisWeb.Configuration...')
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern
                                 # (no -Subfolder: extract whole package)

    if (-not $pick) {
        Write-Log "Prep-Web aborted: no GalaxisWeb.* package found." WARNING
        return
    }

    # 2) Post-extraction cleanup: flatten optional "browser" subfolder
    $browser = Join-Path $targetRoot 'browser'
    if (Test-Path -Path $browser -PathType Container) {
        if ($PSCmdlet.ShouldProcess($targetRoot, "Flatten 'browser' folder")) {
            Write-Log "Post-extraction: moving 'browser' contents up and removing the folder." DEBUG
            Write-Log "Why not deliver it without the 'browser' folder to begin with, like 2 versions ago?!" WARNING
            Move-Item (Join-Path $browser '*') $targetRoot -Force -ErrorAction SilentlyContinue
            Remove-Item $browser -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3) Overlay configuration package (if present)
    $cfgPattern = 'GalaxisWeb.Configuration*.7z'
    $cfgPick = Expand-LatestArchive -Sources $sources `
                                    -TargetFolder $targetRoot `
                                    -FilePattern $cfgPattern
                                    # (no -Subfolder)

    # (No need to error if config is missing; it’s optional for some builds)
    if ($cfgPick) {
        Write-Log ("Applied config package: {0}" -f $cfgPick.Name) INFO
    } else {
        Write-Log "No GalaxisWeb.Configuration package found – continuing without it." DEBUG
    }

    #Write-Log "Prep-Web completed!" INFO
}

function Prep-PlayerApp {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-PlayerApp" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    # Target: ...\PlayerApp only\Web\PlayerApp
    $targetRoot = Initialize-PrepDir -Path (Join-Path $prep 'PlayerApp only\Web\PlayerApp')

    # 1) Main PlayerApp package (e.g., PlayerApp.10.*.7z)
    $mainPattern = 'PlayerApp.1*.7z'
    $mainPick = Expand-LatestArchive -Sources $sources `
                                     -TargetFolder $targetRoot `
                                     -FilePattern $mainPattern
                                     # (no -Subfolder: extract whole package)

    if (-not $mainPick) {
        Write-Log "Prep-PlayerApp aborted: no PlayerApp.* package found." WARNING
        return
    }

    # 2) Optional configuration overlay (e.g., PlayerApp.Configuration... if named C*)
    $cfgPattern = 'PlayerApp.C*.7z'
    $cfgPick = Expand-LatestArchive -Sources $sources `
                                    -TargetFolder $targetRoot `
                                    -FilePattern $cfgPattern
                                    # (no -Subfolder)

    if ($cfgPick) {
        Write-Log ("Applied PlayerApp config package: {0}" -f $cfgPick.Name) INFO
    } else {
        Write-Log "No PlayerApp.C* configuration package found – continuing without it." DEBUG
    }

    #Write-Log "Prep-PlayerApp completed!" INFO
}

function Prep-HFandLib {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Optional: delete scripts with version lower than this (e.g. 10.98)
        [version] $MinVersion,

        # Default 'en'; if 'fr' is chosen, *_en.sql files are removed
        [ValidateSet('en','fr')]
        [string] $Language = 'en'
    )

    Write-Log "Prep-HFandLib" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $filePattern = 'Galaxis*(Executable only).7z'
    $targetRoot  = Initialize-PrepDir -Path (Join-Path $prep 'HFandLib')

    # 1) Extract newest matching archive (Database subfolder only)
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern `
                                 -Subfolder 'Database\*'

    if (-not $pick) {
        Write-Log "Prep-HFandLib aborted: no matching archive found." WARNING
        return
    }

    # 2) Stage wanted files, then drop the Database tree
    if ($PSCmdlet.ShouldProcess($targetRoot, "Post-extraction staging")) {
        $scriptGlob = Join-Path $targetRoot 'Database\Program Files\MIS\Program\Database\Script\Script*.sql'
        $jarPath    = Join-Path $targetRoot 'Database\Program Files\MIS\Program\Database\lib\galaxisoracle.jar'
        $dbRoot     = Join-Path $targetRoot 'Database'

        if (Test-Path $scriptGlob) { Move-Item $scriptGlob $targetRoot -Force -ErrorAction SilentlyContinue }
        if (Test-Path $jarPath)    { Move-Item $jarPath    $targetRoot -Force -ErrorAction SilentlyContinue }
        if (Test-Path $dbRoot)     { Remove-Item $dbRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # 3) Clean scripts by MinVersion and Language
    $scriptFiles = Get-ChildItem -LiteralPath $targetRoot -Filter 'Scripts *.sql' -File -ErrorAction SilentlyContinue
    if ($scriptFiles) {
        # local helpers
        function _Parse-Version([string] $name) {
            $m = [regex]::Match($name, '^Scripts\s+(?<v>\d+(?:\.\d+){1,3})', 'IgnoreCase')
            if ($m.Success) {
                try { return [version]$m.Groups['v'].Value } catch { return $null }
            }
            return $null
        }
        function _Lang-Suffix([string] $name) {
            $m = [regex]::Match($name, '_(?<lang>en|fr)\.sql$', 'IgnoreCase')
            if ($m.Success) { return $m.Groups['lang'].Value.ToLower() }
            return $null
        }

        $removed = 0
        foreach ($f in $scriptFiles) {
            $remove = $false

            # Version rule: if MinVersion given, remove anything lower (when parseable)
            if ($MinVersion) {
                $v = _Parse-Version $f.Name
                if ($v -ne $null -and $v -lt $MinVersion) { $remove = $true }
            }

            # Language rule: if file has _en/_fr suffix, remove the opposite of chosen language
            if (-not $remove) {
                $suffix = _Lang-Suffix $f.Name
                if ($suffix -and $suffix -ne $Language) { $remove = $true }
            }

            if ($remove) {
                if ($PSCmdlet.ShouldProcess($f.FullName, "Remove non-matching script")) {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                    $removed++
                }
            }
        }

        Write-Log ("Cleaned scripts (Language={0}{1}): removed {2}" -f `
            $Language, ($MinVersion ? ", MinVersion=$MinVersion" : ""), $removed) INFO
    } else {
        Write-Log "No 'Scripts *.sql' files found in $targetRoot." DEBUG
    }

    Write-Log "Scripts can be found at $targetRoot\" INFO
}
#endregion

#region --- prepare MBoxUI package
function Prep-MBoxUI {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-MBoxUI" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    # Target: ...\MBoxUI
    $targetRoot = Initialize-PrepDir -Path (Join-Path $prep 'MBoxUI')

    # 1) Main MBoxUI package
    $mainPattern = 'MBoxUI.1*.7z'
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $mainPattern
                                 # (no -Subfolder)

    if (-not $pick) {
        Write-Log "Prep-MBoxUI aborted: no MBoxUI.* package found." WARNING
        return
    }

    # 2) Optional configuration overlay
    $cfgPattern = 'MBoxUI.Configuration*.7z'
    $cfgPick = Expand-LatestArchive -Sources $sources `
                                    -TargetFolder $targetRoot `
                                    -FilePattern $cfgPattern
                                    # (no -Subfolder)

    if ($cfgPick) {
        Write-Log ("Applied MBoxUI config package: {0}" -f $cfgPick.Name) INFO
    } else {
        Write-Log "No MBoxUI.Configuration package found – continuing without it." DEBUG
    }

    #Write-Log "Prep-MBoxUI completed!" INFO
}
#endregion

#region --- prepare PlayWatch package
function Prep-PlayWatch {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "Prep-PlayWatch" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $processRoot = Initialize-PrepDir -Path (Join-Path $prep 'PlayWatch\Process')
    $websiteRoot = Initialize-PrepDir -Path (Join-Path $prep 'PlayWatch\Website')

    # 1) Process package
    $procPattern = 'RgMonitorProcess*.7z'
    $procPick = Expand-LatestArchive -Sources $sources `
                                     -TargetFolder $processRoot `
                                     -FilePattern $procPattern
    if ($procPick) {
        Write-Log ("Applied PlayWatch Process package: {0}" -f $procPick.Name) INFO
    } else {
        Write-Log "No RgMonitorProcess*.7z package found." WARNING
    }

    # 2) Website package
    $webPattern = 'RgMonitorWebsite*.7z'
    $webPick = Expand-LatestArchive -Sources $sources `
                                    -TargetFolder $websiteRoot `
                                    -FilePattern $webPattern
    if ($webPick) {
        Write-Log ("Applied PlayWatch Website package: {0}" -f $webPick.Name) INFO
    } else {
        Write-Log "No RgMonitorWebsite*.7z package found." WARNING
    }

    #Write-Log "Prep-PlayWatch completed!" INFO
}
#endregion

#region --- deploying already prepared Galaxis packages into Live Galaxis
function Deploy-Galaxis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Executables","Config","Other","Install","ALL")]
        [string]$Task,
        [switch]$AskIf
    )

    Write-Log "Deploy-Galaxis $Task" -Header

    if ($AskIf) {
        $confirm = Read-Host "Do you want to deploy $Task (Y/N)?"
        if ($confirm -ne "Y") {
            Write-Log "Deployment skipped!" -Level WARNING
            return
        }
    }

    if ($Task -eq "ALL") {
        Deploy-Executables
        Deploy-Config
        Deploy-Other
    } else {
        switch ($Task) {
            "Executables"{ Deploy-Executables }
            "Config"    { Deploy-Config }
            "Other"     { Deploy-Other }
            "Install"   { Deploy-Install }
            Default { throw "Invalid task: $Task" ; write-log "Invalid task: $Task" -Level ERROR }
        }
    }
}

function Deploy-SYSTM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Executables","Config","ALL")]
        [string]$Task,
        [switch]$AskIf
    )

    if ($AskIf) {
        $confirm = Read-Host "Do you want to deploy $Task (Y/N)?"
        if ($confirm -ne "Y") {
            Write-Output "Deployment skipped!"
            return
        }
    }

    #AskIfBackup-param?

    #checklatest backup etc.

    if ($Task -eq "ALL") {
        Deploy-SYSTM-Executables
        Deploy-SYSTM-Config
    } else {
        switch ($Task) {
            "Executables"{ Deploy-SYSTM-Executables }
            "Config"    { Deploy-SYSTM-Config }
            Default { throw "Invalid task: $Task" }
        }
    }
}

function Deploy-Executables {
    Write-Log "Deploy-Executables" -Header
    Write-Log "Full logs are available at:"

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter "GALAXIS Executable*" -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-Executables_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname
    
    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-Executables completed!" -Level INFO
}

function Deploy-Config {
    Write-Log "Deploy-Config" -Header
    Write-Log "Full logs are available at:"

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter "GALAXIS Config*" -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-Config_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /XC /XN /XO /ndl /Log:$logs\$logname

    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-Config completed!" -Level INFO
}

function Deploy-Other {
    Write-Log "Deploy-Other" -Header
    Write-Log "Full logs are available at:"

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter "GALAXIS Other*" -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-Other_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /XC /XN /XO /ndl /Log:$logs\$logname

    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-Other completed!" -Level INFO
}

function Deploy-Install {
    Write-Log "Deploy-Install" -Header
    Write-Log "Full logs are available at:"

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter Install* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-Install_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-Install completed!" -Level INFO
}

function Deploy-Web {
    Write-Log "Deploy-Web" -Header
    Write-Log "Full logs are available at:" 

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath

    $package = Get-ChildItem $prep -filter Web* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-Web_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-Web completed!" -Level INFO
}

function Deploy-PlayerApp {
    Write-Log "Deploy-PlayerApp" -Header
    Write-Log "Full logs are available at:" 

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath

    $package = Get-ChildItem $prep -filter PlayerApp* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-PlayerApp_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-PlayerApp completed!" -Level INFO
}

function Deploy-SYSTM-Executables {
    Write-Log "Deploy-SYSTM-Executables" -Header
    Write-Log "Full logs are available at:" 

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter SYSTM*Executable* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-SYSTM-Executables_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname
    
    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-SYSTM-Executables completed!" -Level INFO
}

function Deploy-SYSTM-Config {
    Write-Log "Deploy-SYSTM-Config" -Header
    Write-Log "Full logs are available at:"

    $prep    = Get-PrepPath
    $Galaxis = Get-GalaxisPath
    $logs    = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter SYSTM*Config* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-SYSTM-Config_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /XC /XN /XO - only copy non-existing files!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /XC /XN /XO /ndl /Log:$logs\$logname

    # Enhanced logging of Robocopy result
    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-SYSTM-Config completed!" -Level INFO
}

function Deploy-PlayWatch {
    Write-Log "Deploy-PlayWatch" -Header
    Write-Log "Full logs are available at:" 

    $prep    = Get-PrepPath
    $PlayWatch = "D:\PlayWatch"
    $logs    = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter PlayWatch* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-PlayWatch_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $PlayWatch /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    # Enhanced logging of Robocopy result
    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-PlayWatch completed!" -Level INFO
}
#endregion

#region --- preparing Floorserver binaries for deployment
function Prep-CRYSTALControl {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch] $WithoutConfig
    )

    Write-Log "Prep-CRYSTALControl" -Header

    $sources = Get-SourcesPath
    $prep    = Get-PrepPath

    $targetRoot  = Initialize-PrepDir -Path (Join-Path $prep 'Control')
    $filePattern = 'Crystal_Control*.7z'

    # 1) Extract newest matching archive
    $pick = Expand-LatestArchive -Sources $sources `
                                 -TargetFolder $targetRoot `
                                 -FilePattern $filePattern
                                 # (no -Subfolder)

    if (-not $pick) {
        Write-Log "Prep-CRYSTALControl aborted: no matching archive found." WARNING
        return
    }

    # 2) Optional: strip config files when requested
    if ($WithoutConfig -and $PSCmdlet.ShouldProcess($targetRoot, "Remove configuration files")) {
        $cfgFiles = @(
            (Join-Path $targetRoot 'bin\control\ControlLauncher.exe.config'),
            (Join-Path $targetRoot 'bin\control\log4net.config')
        )

        foreach ($cfg in $cfgFiles) {
            if (Test-Path $cfg) {
                Remove-Item $cfg -Force -ErrorAction SilentlyContinue
                Write-Log "Removed: $cfg" DEBUG
            } else {
                Write-Log "Config not found (skipped): $cfg" DEBUG
            }
        }

        Write-Log "-WithoutConfig flag supplied — configuration files removed." INFO
    }

    #Write-Log "Prep-CRYSTALControl completed!" INFO
}
#endregion

#region --- deploying already prepared Floorserver packages into Live
function Deploy-CRYSTALControl {
    Write-Log "Deploy-CRYSTALControl" -Header
    write-log "Full logs are available at:"

    $prep       = Get-PrepPath
    $OnlineData = Get-OnlinedataPath
    $logs       = get-LogsPath

    $package = Get-ChildItem $prep -filter Control* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-CRYSTAL_Control_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $OnlineData /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    # Enhanced logging of Robocopy result
    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    Assert-MOD-Components -Silent
    Write-Log "Deploy-CRYSTALControl completed!" -Level INFO
}

function Deploy-MBoxUI {
    Write-Log "Deploy-MBoxUI" -Header
    Write-Log "Full logs are available at:"
    
    $prep       = Get-PrepPath  
    $OnlineData = Get-OnlinedataPath + '/IIS/MBoxUI/'
    $logs       = Get-LogsPath
    
    $package = Get-ChildItem $prep -filter MBoxUI* -Attributes Directory | ForEach-Object { $_.FullName }
    $logname = 'Deploy-MBoxUI_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $OnlineData /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    # Enhanced logging of Robocopy result
    Write-Log "Please verify the deployment result:" DEBUG
    Get-Content $logs\$logname -Tail 11 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        Write-Log $line -Level DEBUG
    }
    #Assert-MOD-Components -Silent
    Write-Log "Deploy-MBoxUI completed!" -Level INFO
}
#endregion

#region --- uninstalling/installing JP applications 
function Uninstall-JPApps {
    [CmdletBinding()]
    param(
        [switch]$AskIf
    )

    $count = 0

    Write-Log "Uninstall-JPApps" -Header

    $JPApp = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Applications'
    if ($JPApp) {
        $name    = $JPApp.Name
        $version = $JPApp.version
        Write-Log "Currently installed: $name, version $version!" DEBUG
        $count = $count + 1
    }
    
    $JPRep = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Reporting'
    if ($JPRep) {
        $name    = $JPRep.Name
        $version = $JPRep.version
        Write-Log "Currently installed: $name, version $version!" DEBUG
        $count = $count + 1
    }

    $SecSrv = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT SecurityServer Configuration'
    if ($SecSrv) {
        $name    = $SecSrv.Name
        $version = $SecSrv.version
        Write-Log "Currently installed: $name, version $version!" DEBUG
        $count = $count + 1
    }

    if($count -eq 0) {
        Write-Log "No JP Apps installed!"
        Return
    }

    if ($AskIf) {
        Write-Log "Deinstalling JP Applications:"
        Write-Log "We will uninstall (if installed) the following applications:"
        Write-Log " - JP Applications"
        Write-Log " - JP Reporting"
        Write-Log " - SecurityServer Configuration"
        $confirm = Read-Host "Do you want to proceed with the deinstallation? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Log "Deinstallation aborted!" WARNING
            return
        }
    }

    if ($JPApp) {
        $name    = $JPApp.Name
        $version = $JPApp.version
        Write-Log "Deinstalling $name, version $version!"
        
        Invoke-CimMethod -InputObject $JPApp -name Uninstall | Out-Null
        
        $folder = (Get-MOD-Component -module "Jackpot Configuration").path
        if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
    }
    
    if ($JPRep) {
        $name    = $JPRep.Name
        $version = $JPRep.version
        Write-Log "Deinstalling $name, version $version!"
        
        Invoke-CimMethod -InputObject $JPRep -name Uninstall | Out-Null

        $folder = (Get-MOD-Component -module "Jackpot Reporting").path
        if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
    }

    if ($SecSrv) {
        $name    = $SecSrv.Name
        $version = $SecSrv.version
        Write-Log "Deinstalling $name, version $version!"

        Invoke-CimMethod -InputObject $SecSrv -name Uninstall | Out-Null

        $folder = (Get-MOD-Component -module "SecurityServer Configuration").path
        if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
    }
    Assert-MOD-Components -Silent
    Write-Log "Uninstall-JPApps completed!" -Level INFO
}

function Install-JPApps {
    [CmdletBinding()]
    param(
        [switch]$AskIf,
        [switch]$Force,
        [switch]$Result
    )

    if ($Force) {
        $AskIf = $false
        $Result = $false
        Uninstall-JPApps
    }

    Write-Log "Install-JPApps" -Header

    #check if we have inis in sources
    $sources = Get-SourcesPath
    $logs    = Get-LogsPath
    $logs    = $logs.Replace('/','\')

    $JPApps_msi = Get-ChildItem $sources SetupJPApplications.msi
    $JPRep_msi = Get-ChildItem $sources SetupJPReporting.msi
    $SecSrv_msi = Get-ChildItem $sources SetupSecurityServerConfig.msi

    $count = 0
    if($JPApps_msi) { $count = $count + 1 }
    if($JPRep_msi)  { $count = $count + 1 }
    if($SecSrv_msi) { $count = $count + 1 }

    if ($count -eq 0) { 
        Write-Log "We did not find any JP-related .msi's in $sources! Please provide the installers and try again!" WARNING
        Return
    }

    if ($AskIf) {
        Write-Log "Installing JP Applications:"
        Write-Log "We will install the following applications:"
        if($JPApps_msi){ Write-Log " - JP Applications" }
        if($JPRep_msi) { Write-Log " - JP Reporting" }
        if($JPRep_msi) { Write-Log " - SecurityServer Configuration" }
        $confirm = Read-Host "Do you want to proceed with the installation? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Log "Installation aborted!" WARNING
            return
        }
    }

    $count = 0

    $JPApp = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Applications'
    if ($JPApp) {
        $name    = $JPApp.Name
        $version = $JPApp.version
        Write-Log "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    $JPRep = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Reporting'
    if ($JPRep) {
        $name    = $JPRep.Name
        $version = $JPRep.version
        Write-Log "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    $SecSrv = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT SecurityServer Configuration'
    if ($SecSrv) {
        $name    = $SecSrv.Name
        $version = $SecSrv.version
        Write-Log "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    if ($count -ne 0) {
        Uninstall-JPApps
    }

    
    #JPApps
    $folder = (Get-MOD-Component -module "Jackpot Configuration").path
    $folder = $folder.Replace('/','\')
    $log    = $logs + "\SetupJPApplications_log.txt"
   #$ArgumentsMSI ='/i ' + '"' + $JPApps_msi.FullName + '" ' + '/qn ' + 'SITEURL=xxx SELECTED_xx_ENVIRONMENT=xxxcom ADMIN_xx_EDITBOX_VALUE=xxx IS_ENCRYPTED=0 LOGOFILE=xxx SSPR_URL=xxx SSO_ENABLED=0 PASSWORD_SYNC_ENABLED=1 TECUNIFY_CHECKBOX_STATE=0 UPS_ENABLED=0 UTM_ENABLED=0 LOCALUSER=1 DOMAINUSER=1 MICROSOFTUSER=1 AZUREUSER=1 PKPENABLE=xx OFFLINE_ENABLED=1 FAILOPEN=0 OFFLINE_MAX_TRIES_LIMIT=5 SELECTED_UAC_OPTION=1 CONTACT_INFO=xxx'
    $ArgumentsMSI ='/i ' + '"' + $JPApps_msi.FullName + '" ' + '/qn ' + 'INSTALLDIR="' + $folder + '" /L* ' + $log
    #write-host 'Output arguments and verify first'
    #Write-Host $ArgumentsMSI
    Start-Process -FilePath "msiexec.exe" -Wait -ArgumentList $ArgumentsMSI

    #JPRep
    $folder = (Get-MOD-Component -module "Jackpot Reporting").path
    $folder = $folder.Replace('/','\')
    $log    = $logs + "\SetupJPReporting_log.txt"
   #$ArgumentsMSI ='/i ' + '"' + $JPRep_msi.FullName + '" ' + '/qn ' + 'SITEURL=xxx SELECTED_xx_ENVIRONMENT=xxxcom ADMIN_xx_EDITBOX_VALUE=xxx IS_ENCRYPTED=0 LOGOFILE=xxx SSPR_URL=xxx SSO_ENABLED=0 PASSWORD_SYNC_ENABLED=1 TECUNIFY_CHECKBOX_STATE=0 UPS_ENABLED=0 UTM_ENABLED=0 LOCALUSER=1 DOMAINUSER=1 MICROSOFTUSER=1 AZUREUSER=1 PKPENABLE=xx OFFLINE_ENABLED=1 FAILOPEN=0 OFFLINE_MAX_TRIES_LIMIT=5 SELECTED_UAC_OPTION=1 CONTACT_INFO=xxx'
    $ArgumentsMSI ='/i ' + '"' + $JPRep_msi.FullName + '" ' + '/qn ' + 'INSTALLDIR="' + $folder + '" /L* ' + $log
    #write-host 'Output arguments and verify first'
    #Write-Host $ArgumentsMSI
    Start-Process -FilePath "msiexec.exe" -Wait -ArgumentList $ArgumentsMSI

    #JPRep
    $folder = (Get-MOD-Component -module "SecurityServer Configuration").path
    $folder = $folder.Replace('/','\')
    $log    = $logs + "\SetupSecurityServerConfig_log.txt"
   #$ArgumentsMSI ='/i ' + '"' + $SecSrv_msi.FullName + '" ' + '/qn ' + 'SITEURL=xxx SELECTED_xx_ENVIRONMENT=xxxcom ADMIN_xx_EDITBOX_VALUE=xxx IS_ENCRYPTED=0 LOGOFILE=xxx SSPR_URL=xxx SSO_ENABLED=0 PASSWORD_SYNC_ENABLED=1 TECUNIFY_CHECKBOX_STATE=0 UPS_ENABLED=0 UTM_ENABLED=0 LOCALUSER=1 DOMAINUSER=1 MICROSOFTUSER=1 AZUREUSER=1 PKPENABLE=xx OFFLINE_ENABLED=1 FAILOPEN=0 OFFLINE_MAX_TRIES_LIMIT=5 SELECTED_UAC_OPTION=1 CONTACT_INFO=xxx'
    $ArgumentsMSI ='/i ' + '"' + $SecSrv_msi.FullName + '" ' + '/qn ' + 'INSTALLDIR="' + $folder + '" /L* ' + $log
    #write-host 'Output arguments and verify first'
    #Write-Host $ArgumentsMSI
    Start-Process -FilePath "msiexec.exe" -Wait -ArgumentList $ArgumentsMSI
    
    Write-Log "Installation finished!"
    if ($Result) { 
        $JPApp = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Applications'
        if ($JPApp) {
            $name    = $JPApp.Name
            $version = $JPApp.version
            Write-Log "Currently installed: $name, version $version!"
            $count = $count + 1
        }

        $JPRep = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Reporting'
        if ($JPRep) {
            $name    = $JPRep.Name
            $version = $JPRep.version
            Write-Log "Currently installed: $name, version $version!"
            $count = $count + 1
        }

        $SecSrv = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT SecurityServer Configuration'
        if ($SecSrv) {
            $name    = $SecSrv.Name
            $version = $SecSrv.version
            Write-Log "Currently installed: $name, version $version!"
            $count = $count + 1
        }
    }
    #cleaning start menu
    $IGT_startmenu    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IGT'
    $Spielo_startmenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Spielo'
    if(Test-Path $IGT_startmenu)    { Remove-Item $IGT_startmenu -Recurse -Force }
    if(Test-path $Spielo_startmenu) { Remove-Item $Spielo_startmenu -Recurse -Force }

    Assert-MOD-Components -Silent
    Write-Log "Install-JPApps completed!" -Level INFO
}
#endregion

#region --- install/update FS
function Install-Floorserver {
    [CmdletBinding()]
    param(
        [switch]$AskIf,
        [switch]$Force,
        [switch]$Result
    )

    if ($Force) {
        $AskIf = $false
        $Result = $false
        #uninstalling not needed, it's always updated!
    }

    #check if we have inis in sources
    $sources = Get-SourcesPath
    $logs    = Get-LogsPath
    $logs    = $logs.Replace('/','\')
    
    $FS_msi = Get-ChildItem $sources Floorserver-Setup*.msi

    $count = 0
    if($FS_msi) { $count = $count + 1 }

    if ($count -eq 0) { 
        write-host "We did not find any FS related .msi's in $sources! Please provide the installers and try again!"
        Return
    }

    $version = (Get-MOD-Component -Modules 'Floorserver').version
    if ($FS_msi.name -like "*$version*") {
        #write-log $version
        #write-log $QB_msi.Name
        Write-Log "Floorserver version $version is already installed! No need to install again!" WARNING
        return
    }

    if ($AskIf) {

        write-host "Installing/updating FS!"
        write-host "-----------------------"
        write-host "We will install the following applications:"
        if($FS_msi){ write-host  " - FloorServer:              "$FS_msi.Name }
        write-host "---------------------------"
        $confirm = Read-Host "Do you want to proceed with the installation?"
        if ($confirm -ne "Y") {
            Write-Output "Installation aborted!"
            write-host "-----------------------"
            return
        }
        write-host "Starting the installation!"
        write-host "--------------------------"
    }

    #remove pinit 
    #Check if the service exists
    $pinit = Get-Service -Name "pinit" -ErrorAction SilentlyContinue
    #if the service exists, remove it
    if ($pinit) {
        Stop-Service -Name $pinit.name -Force   # Stop the service if it's running
        Remove-Service -Name $pinit.name 
        Write-Host "Service pinit removed."
    } else {
        Write-Host "Service pinit does not exist."
    }

    $count = 0

    $FS_install = Get-CimInstance -class win32_product | Where-Object name -eq 'GTECH Floorserver'
    if ($FS_install) {
        $name    = $FS_install.Name
        $version = $FS_install.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }
    write-host "--------------------------"

    #FloorServer
    $folder = (Get-MOD-Component -module "Floorserver").path
    $folder = $folder.Replace('/','\')
    $log    = $logs + "\FloorServer_log.txt"
    #$ArgumentsMSI ='/i ' + '"' + $JPApps_msi.FullName + '" ' + '/qn ' + 'SITEURL=xxx SELECTED_xx_ENVIRONMENT=xxxcom ADMIN_xx_EDITBOX_VALUE=xxx IS_ENCRYPTED=0 LOGOFILE=xxx SSPR_URL=xxx SSO_ENABLED=0 PASSWORD_SYNC_ENABLED=1 TECUNIFY_CHECKBOX_STATE=0 UPS_ENABLED=0 UTM_ENABLED=0 LOCALUSER=1 DOMAINUSER=1 MICROSOFTUSER=1 AZUREUSER=1 PKPENABLE=xx OFFLINE_ENABLED=1 FAILOPEN=0 OFFLINE_MAX_TRIES_LIMIT=5 SELECTED_UAC_OPTION=1 CONTACT_INFO=xxx'
    $ArgumentsMSI ='/i ' + '"' + $FS_msi.FullName + '" ' + '/qn ' + 'INSTALLDIR="' + $folder + '" /L* ' + $log
    #write-host 'Output arguments and verify first'
    #Write-Host $ArgumentsMSI
    Start-Process -FilePath "msiexec.exe" -Wait -ArgumentList $ArgumentsMSI
    
    write-host "Installation finished!"
    if ($Result) { 
        $FS_install = Get-CimInstance -class win32_product | Where-Object name -eq 'GTECH Floorserver'
        if ($FS_install) {
            $name    = $FS_install.Name
            $version = $FS_install.version
            Write-host "Currently installed: $name, version $version!"
            $count = $count + 1
        }
        write-host "--------------------------"
    }
    #cleaning start menu
    $IGT_startmenu    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IGT'
    $Spielo_startmenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Spielo'
    if(Test-Path $IGT_startmenu)    { Remove-Item $IGT_startmenu -Recurse -Force -ErrorAction SilentlyContinue }
    if(Test-path $Spielo_startmenu) { Remove-Item $Spielo_startmenu -Recurse -Force -ErrorAction SilentlyContinue }

    # Define service parameters
    $hostname = hostname
    $username = "$hostname\Administrator"
    $password = ConvertTo-SecureString -String "Mod12345" -AsPlainText -Force
    $credential = New-Object -TypeName PSCredential -ArgumentList $username, $password

    # Create a new service with specified credentials
    New-Service -Name "pinit" -DisplayName "pinit" -BinaryPathName "D:\OnlineData\bin\pinit.exe" -Credential $credential
    $pinit = Get-Service -Name "pinit" -ErrorAction SilentlyContinue
    #if the service exists, remove it
    if ($pinit) {
        Write-Host "Service pinit added. Make sure the Service is running as lokal Administrator"
    }
    Assert-MOD-Components -Silent
}
function Install-QueryBuilder {
    [CmdletBinding()]
    param(
        [switch]$AskIf,
        [switch]$Force,
        [switch]$Result
    )

    Write-Log "Install-QueryBuilder" -Header

    if ($Force) {
        $AskIf = $false
        $Result = $false
        #uninstalling not needed, it's always updated!
    }

    #check if we have inis in sources
    $sources = Get-SourcesPath
    $logs    = Get-LogsPath
    $logs    = $logs.Replace('/','\')
    
    $QB_msi = Get-ChildItem $sources QueryBuilder-Setup*.msi
    #checking for installed QueryBuilder version
    $version = (Get-MOD-Component -Modules 'QueryBuilder').version
    if ($QB_msi.name -like "*$version*") {
        #write-log $version
        #write-log $QB_msi.Name
        Write-Log "QueryBuilder version $version is already installed! No need to install again!" WARNING
        return
    }

    $count = 0
    if($QB_msi)  { $count = $count + 1 }

    if ($count -eq 0) { 
        Write-Log "We did not find any QB related .msi's in $sources! Please provide the installers and try again!" WARNING
        Return
    }

    if ($AskIf) {
        Write-Log "The Following QueryBuilder will be installed:"
        if($QB_msi) { Write-Log "Installing {$QB_msi.name}" }
        $confirm = Read-Host "Do you want to proceed?"
        if ($confirm -ne "Y") {
            Write-Log "Installation aborted!" WARNING
            return
        }
    }

    $count = 0

    $QB_install = Get-CimInstance -class win32_product | Where-Object name -eq 'GTECH Query Builder'
    if ($QB_install) {
        $name    = $QB_install.Name
        $version = $QB_install.version
        Write-Log "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    $filename = $QB_msi.name
    Write-Log "Installing $filename"

    #Query Builder
    $folder = (Get-MOD-Component -Tool "QueryBuilder").path
    $folder = $folder.Replace('/','\')
    $log    = $logs + "\QueryBuilder_log.txt"
    #$ArgumentsMSI ='/i ' + '"' + $JPRep_msi.FullName + '" ' + '/qn ' + 'SITEURL=xxx SELECTED_xx_ENVIRONMENT=xxxcom ADMIN_xx_EDITBOX_VALUE=xxx IS_ENCRYPTED=0 LOGOFILE=xxx SSPR_URL=xxx SSO_ENABLED=0 PASSWORD_SYNC_ENABLED=1 TECUNIFY_CHECKBOX_STATE=0 UPS_ENABLED=0 UTM_ENABLED=0 LOCALUSER=1 DOMAINUSER=1 MICROSOFTUSER=1 AZUREUSER=1 PKPENABLE=xx OFFLINE_ENABLED=1 FAILOPEN=0 OFFLINE_MAX_TRIES_LIMIT=5 SELECTED_UAC_OPTION=1 CONTACT_INFO=xxx'
    $ArgumentsMSI ='/i ' + '"' + $QB_msi.FullName + '" ' + '/qn ' + 'INSTALLDIR="' + $folder + '" /L* ' + $log
    #write-host 'Output arguments and verify first'
    #Write-Host $ArgumentsMSI
    Start-Process -FilePath "msiexec.exe" -Wait -ArgumentList $ArgumentsMSI
    
    write-Log "QueryBuilder installation finished!"
    if ($Result) { 
    
        $QB_install = Get-CimInstance -class win32_product | Where-Object name -eq 'GTECH Query Builder'
        if ($QB_install) {
            $name    = $QB_install.Name
            $version = $QB_install.version
            Write-Log "Currently installed: $name, version $version!"
            $count = $count + 1
        }
    }
    #cleaning start menu
    $IGT_startmenu    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IGT'
    $Spielo_startmenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Spielo'
    if(Test-Path $IGT_startmenu)    { Remove-Item $IGT_startmenu -Recurse -Force }
    if(Test-path $Spielo_startmenu) { Remove-Item $Spielo_startmenu -Recurse -Force }

    Assert-MOD-Components -Silent
}
#endregion

#region --- rabbitMQ
function Uninstall-RabbitMQ {

    $RabbitMQ = Get-Service -displayName "RabbitMQ"			-ErrorAction SilentlyContinue
    if ($RabbitMQ) {
        write-host "Stopping RabbitMQ service!"
        Stop-Service $RabbitMQ
        Write-host "RabbitMQ service stopped!"
    } else {
        write-host "Did not find RabbitMQ service!"
    }

    #finding the uninstall-string for RabbitMQ
    $rabbitMQ_server = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"  |
    Get-ItemProperty | Where-Object {$_.DisplayName -like "*RabbitMQ Server*" } | Select-Object -Property DisplayName, UninstallString

    if ($rabbitMQ_server) {
        #uninstalling
        write-host "Starting to uninstall RabbitMQ Server!"
        Start-Process -FilePath $rabbitMQ_server.UninstallString -ArgumentList "/S" -Wait #-NoNewWindow

        #checking if it worked
        $rabbitMQ_server = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"  |
            Get-ItemProperty | Where-Object {$_.DisplayName -like "*RabbitMQ Server*" } | Select-Object -Property DisplayName, UninstallString   
        
        if (!$rabbitMQ_server) {
            write-host "RabbitMQ Server was uninstalled!"
        }
    } else {
        write-host "RabbitMQ Server not installed!"
    }

    #finding the uninstall-string for RabbitMQ
    $Erlang = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"  |
        Get-ItemProperty | Where-Object {$_.DisplayName -like "Erlang OTP*" } | Select-Object -Property DisplayName, UninstallString

    if ($Erlang) {
        #uninstalling
        write-host "Starting to uninstall Erlang OTP!"
        Start-Process -FilePath $Erlang.UninstallString -ArgumentList "/S" -Wait #-NoNewWindow

        #checking if it worked
        $Erlang = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"  |
            Get-ItemProperty | Where-Object {$_.DisplayName -like "Erlang OTP*" } | Select-Object -Property DisplayName, UninstallString
        if (!$Erlang) {
            write-host "Erlang OTP was uninstalled!"
        }
    }else {
        write-host "Erlang OTP not installed!"
    }

    write-host "Clearing out RabbitMQ directories!"
    #clearing out D:\Galaxis\Data\RabbitMQ\Queues\*
    Get-ChildItem D:\Galaxis\Data\RabbitMQ\Queues | Remove-Item -Recurse -Force
    #clearing out C:\Users\Administrator\AppData\Roaming\
    if(Test-Path C:\Users\Administrator\AppData\Roaming\RabbitMQ) {
        Get-ChildItem C:\Users\Administrator\AppData\Roaming\RabbitMQ | Remove-Item -Recurse -Force
    }
    
    write-host "Clearing Ericsson-registry entry!"
    #Removing HKEY_LOCAL_MACHINE\SOFTWARE\Ericsson
    $Ericsson = Test-Path 'HKLM:\SOFTWARE\Ericsson'
    if ($Ericsson)
    {
            Write-Information("Removing 'HKLM:\SOFTWARE\Ericsson'")
            Remove-Item -Path 'HKLM:\SOFTWARE\Ericsson' -Force -Recurse -Verbose
    }
    
}

function Install-RabbitMQ {
    [CmdletBinding()]
    param(
        [switch]$AskIf,
        [switch]$Manual
    )

    if ($AskIf) {
        write-host "Installing RabbitMQ Server"
        write-host "       and Erlang OTP     "
        write-host "--------------------------"
        write-host "The installer will uninstall the previous installation, if existing!"
        write-host "--------------------------"
        $confirm = Read-Host "Do you want to proceed with the installation?"
        if ($confirm -ne "Y") {
            Write-Output "Installation aborted!"
            write-host "-----------------------"
            return
        }
    }
    
    #if Manual switch
    if ($Manual) {
        write-host "Please uninstall RabbitMQ Server and Erlang OTP!"
        start-sleep -Seconds 3
        appwiz.cpl
        Write-Host -NoNewLine 'Press any key to continue after you have uninstalled those 2 features...'
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    } else {
        Uninstall-RabbitMQ 
    }

    write-host "Starting installation..."
    write-host "--------------------------"
 
    $cwd = $PWD

    D:
    Set-Location D:\Galaxis\Install\Batch\

    .\SETUP_RABBITMQ.bat %GALAXIS_HOME%\Install\Batch\
    #wait for rabbitmq running
    Start-Sleep 10
    .\SETUP_RABBITMQ_MANAGEMENT.bat mis mis
    #todo: variable for mis-pw, since not all customers do have mis/mis :D
    
    Set-Service -Name "RabbitMQ" -StartupType Automatic

    Set-Location $cwd

    write-host "Reinstallation finished!"

}
#endregion

#region --- uninstalling/installing CFCS
function Uninstall-CFCS {
    [CmdletBinding()]
    param(
        [switch]$AskIf
    )

    Write-Log "Uninstall-CFCS" -Header

    $count = 0

    $CFCS = Get-CimInstance -class win32_product | Where-Object name -eq 'Spielo CRYSTAL Floor Communication Service'
    if ($CFCS) {
        $name    = $CFCS.Name
        $version = $CFCS.version
        Write-Log "Currently installed: $name, version $version!" DEBUG
        $count = $count + 1
    }

    if($count -eq 0) {
        Write-Log "NO CFCS installed!"
        Return
    }

    if ($AskIf) {
        Write-Log "Deinstalling CFCS:"
        Write-Log "We will uninstall (if installed) the following applications:"
        Write-Log " - Spielo CRYSTAL Floor Communication Service"
        $confirm = Read-Host "Do you want to proceed with the deinstallation?"
        if ($confirm -ne "Y") {
            Write-Log "Deinstallation aborted!" WARNING
            return
        }
    }

    $name    = $CFCS.Name
    $version = $CFCS.version
    Write-Log "Deinstalling $name, version $version!" DEBUG
    
    Invoke-CimMethod -InputObject $CFCS -name Uninstall

    $folder = (Get-MOD-Component -module "CRYSTAL Floor Communication Service").path
    if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
   
    Assert-MOD-Components -Silent
    Write-Log "Uninstall-CFCS completed!" -Level INFO
    
}

function Install-CFCS {
    [CmdletBinding()]
    param(
        [switch]$AskIf,
        [switch]$Force,
        [switch]$Result
    )

    if ($Force) {
        $AskIf = $false
        $Result = $false
        Uninstall-CFCS
    }

    Write-Log "Install-CFCS" -Header

    #check if we have inis in sources
    $sources = Get-SourcesPath
    $logs    = Get-LogsPath
    $logs    = $logs.Replace('/','\')
    $CFCS_msi = Get-ChildItem $sources 'CRYSTAL Floor Communication Service*.msi'
    #checking for installed QueryBuilder version
    
    $count = 0
    if($CFCS_msi) { $count = $count + 1 }
 
    if ($count -eq 0) { 
        write-Log "We did not find a CFCS*.-msi in $sources! Please provide the installers and try again!" ERROR
        Return
    }
    
    $version = (Get-MOD-Component -Modules 'CRYSTAL Floor Communication Service').version
    if ($CFCS_msi.name -like "*$version*") {
        #write-log $version
        #write-log $QB_msi.Name
        Write-Log "CFCS version $version is already installed! No need to install again!" WARNING
        return
    }

    if ($AskIf) {
        Write-Log "Installing CFCS:"
        Write-Log "We will install the following applications:"
        if($CFCS_msi){ Write-Log " - CFCS:              "$CFCS_msi.Name }
        $confirm = Read-Host "Do you want to proceed with the installation?"
        if ($confirm -ne "Y") {
            Write-Log "Installation aborted!" WARNING
            return
        }
        Write-Log "Starting the installation!"
    }

    $count = 0

    $CFCS = Get-CimInstance -class win32_product | Where-Object name -eq 'Spielo CRYSTAL Floor Communication Service'
    if ($CFCS) {
        $name    = $CFCS.Name
        $version = $CFCS.version
        Write-Log "Currently installed: $name, version $version!" DEBUG
        $count = $count + 1
    }

    if ($count -ne 0) {
        Uninstall-CFCS
    }
 
    #CFCS
    $folder = (Get-MOD-Component -module "CRYSTAL Floor Communication Service").path
    $folder = $folder.Replace('/','\')
    $log    = $logs + "\SetupCFCS_log.txt"
   #$ArgumentsMSI ='/i ' + '"' + $JPApps_msi.FullName + '" ' + '/qn ' + 'SITEURL=xxx SELECTED_xx_ENVIRONMENT=xxxcom ADMIN_xx_EDITBOX_VALUE=xxx IS_ENCRYPTED=0 LOGOFILE=xxx SSPR_URL=xxx SSO_ENABLED=0 PASSWORD_SYNC_ENABLED=1 TECUNIFY_CHECKBOX_STATE=0 UPS_ENABLED=0 UTM_ENABLED=0 LOCALUSER=1 DOMAINUSER=1 MICROSOFTUSER=1 AZUREUSER=1 PKPENABLE=xx OFFLINE_ENABLED=1 FAILOPEN=0 OFFLINE_MAX_TRIES_LIMIT=5 SELECTED_UAC_OPTION=1 CONTACT_INFO=xxx'
    $ArgumentsMSI ='/i ' + '"' + $CFCS_msi.FullName + '" ' + '/qn ' + 'INSTALLDIR="' + $folder + '" /L* ' + $log
    #write-host 'Output arguments and verify first'
    #Write-Host $ArgumentsMSI
    Start-Process -FilePath "msiexec.exe" -Wait -ArgumentList $ArgumentsMSI

    if ($Result) { 
        $CFCS = Get-CimInstance -class win32_product | Where-Object name -eq 'Spielo CRYSTAL Floor Communication Service'
        if ($CFCS) {
            $name    = $CFCS.Name
            $version = $CFCS.version
            Write-Log "Currently installed: $name, version $version!" DEBUG
            $count = $count + 1
        }
    }

    #cleaning start menu
    $IGT_startmenu    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IGT'
    $Spielo_startmenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Spielo'
    if(Test-Path $IGT_startmenu)    { Remove-Item $IGT_startmenu -Recurse -Force }
    if(Test-path $Spielo_startmenu) { Remove-Item $Spielo_startmenu -Recurse -Force }

    Assert-MOD-Components -Silent
    Write-Log "Install-CFCS completed!" -Level INFO
}
#endregion

#region --- deploy toolkit from DB to APP/FS
<# i'd prefer if people just use the update functionality via I:
function Deploy-Toolkit {
    Write-Log "Deploy-Toolkit" -Header

    #checking correct server
    $server = $env:MODULUS_SERVER
    if ($server -notin ("DB")) { Write-Log "You are not on the DB server" ERROR ; Return }
    
    Write-Log 'Deploying modulus-toolkit from DB to APP and FS!'

    $APPserver = Get-MOD-APP-hostname
    $APPserver = "\\$APPserver\"

    $FServer   = Get-MOD-FS-hostname
    $FServer   = "\\$FServer\"

    $source      = 'C:\Program Files\PowerShell\Modules\modulus-toolkit\*'
    $destination = 'C$\Program Files\PowerShell\Modules\modulus-toolkit\'

    write-log "Copying modulus-toolkit from $source to:"
    write-log " $APPserver$destination"
    write-log " $FServer$destination" 
    #write-log " C$\Program Files\PowerShell\Modules\modulus-toolkit\"

    copy-item -path $source -Destination "$APPserver$destination" -Recurse -Force 
    copy-item -path $source -Destination "$FServer$destination" -Recurse -Force
    write-log "Deployment finished!"
}
#>
#endregion

#region --- configure DB server "modules"
function Set-SecurityServer-Config {
    Write-log "Set-SecurityServer-Config" -header

    #region - parameters
    $DBhostname = Get-MOD-DB-hostname
    $DBofficeIP = Get-MOD-DB-OFFICE-IP
    $DBalias    = Get-DBTns-GLX
    $DBuser     = Get-DbUser-security
    #maybe rework this into the get-config-function
    $config     = Get-MOD-Component-Config "SecurityServer" "Server.Properties"
    if(-not (Test-path $config)) { write-log "File does not exist!" ERROR ; Return }
    $content = Get-Content -Path $config
    #endregion

    #region - configuring
    #Iterate over each line and find the line containing the property
    for ($i = 0; $i -lt $content.Count; $i++) {
        
        $line = $content[$i]
        #user
        if ($line -match "^user\s*=") {
            # Modify the value of the property
                          #"max_connections     = 10"
            $content[$i] = "user                = $DBuser"
            Write-Log "Setting user = $DBuser" DEBUG
            #break
        }
        #thin_connect
        if ($line -match "^thin_connect\s*=") {
            # Modify the value of the property
                          #"max_connections     = 10"
            $content[$i] = "thin_connect        = jdbc:oracle:thin:@"+$DBhostname+":1521:"+$DBalias
            Write-Log "Setting thin_connect = $($DBhostname):1521:$($DBalias)" DEBUG
            #break
        }
        #boss_address
        if ($line -match "^boss_address\s*=") {
            # Modify the value of the property
                          #"max_connections     = 10
            $content[$i] = "boss_address        = $DBofficeIP"
            Write-Log "Setting boss_address = $DBofficeIP" DEBUG
            #break
        }
    }
    #Write the modified contents back to the file
    $content | Set-Content -Path $config
    #endregion

    Write-log "$config was configured programatically!" DEBUG
    Write-Log "Set-SecurityServer-Config completed!" INFO
}

function Set-SecurityServer-Password {

    $cwd    = (Get-Location).Path
    $wd     = 'D:\OnlineData\server'
    $configExists = Test-Path 'D:\OnlineData\server\password.properties'

    # Define the paths
    $classpath = "..\server\classes.jar"
    $class = "com.grips.util.EncodeProperty"
    $password = "password"
    $propertiesFile = "..\server\Password.properties"

    If ($configExists) {
        Write-Log "Encrypting a new SecurityServer password to D:\OnlineData\server\Password.properties!" DEBUG
        Set-Location $wd
        # Execute the Java command
        java -classpath $classpath $class $password $propertiesFile
        Set-Location $cwd
    } else {
        Write-Log "D:\OnlineData\server\Password.properties does not exist, aborting encryption process!" ERROR
    }
}

function Set-DBX-Config {
    write-log "Set-DBX-Config" -header
    
    #region parameters
    $DBhostname = Get-MOD-DB-hostname
    $DBalias    = Get-DbTNS JKP
    $DBuser     = Get-DbUser as_dbx
    #
    $config = Get-MOD-Component-Config "DBX" "dbprops"
    if(!$config) { Write-Log "File does not exist!" ERROR ; Return }
    $content = Get-Content -Path $config
    #endregion

    #region configuring
    #Iterate over each line and find the line containing the property
    for ($i = 0; $i -lt $content.Count; $i++) {
        
        $line = $content[$i]
        #user
        if ($line -match "^instance\s*=") {
            # Modify the value of the property
            $content[$i] = "instance=$DBalias"
            Write-Log "Setting instance = $DBalias" DEBUG
            #break
        }
        #user
        if ($line -match "^user\s*=") {
            # Modify the value of the property
            $content[$i] = "user=$DBuser"
            Write-Log "Setting user = $DBuser" DEBUG
            #break
        }
        #host=ModulusDB
        if ($line -match "^host\s*=") {
            # Modify the value of the property
            $content[$i] = "host=$DBhostname"
            Write-Log "Setting host = $DBhostname" DEBUG
            #break
        }
    }
    #Write the modified contents back to the file
    $content | Set-Content -Path $config
    #endregion

    Write-log "$config was configured programatically!" DEBUG
    Write-Log "Set-DBX-Config completed!" INFO
}

function Set-TriggerMDS-Properties {
    Write-Log "Set-TriggerMDS-Properties" -Header
    
    #region parameters
    $APPofficeIP = Get-MOD-APP-OFFICE-IP
    $config = Get-MOD-Component-Config "GLX" "triggermemberdataserver.properties"    
    if(Test-Path $config) { 
        Write-Host " > Deleting config file, it will be recreated shortly!" -ForegroundColor Yellow
        Remove-item $config -ErrorAction SilentlyContinue
        $null = New-Item $config 
    }
    $content = Get-IniContent $config
    #endregion

    #region configuring
    $content.CUSTOMER_DATA_SERVER_IP = $APPofficeIP
    $content.CUSTOMER_DATA_SERVER_PORT = 3737
    $content.USE_TCPDEBUG="NO"
    $content.TCPDEBUG = $APPofficeIP
    Out-IniFile -InputObject $content -FilePath $config -Force
    #endregion

    Write-Log "$config was created from scratch!" DEBUG 
    Write-Log "Set-TriggerMDS-Properties completed!" INFO
}
#endregion

#region --- Set-Functions for JP configuration files
function Set-JPApps-Config {
    Write-Log "Set-JPAPPs-Config" -Header
    write-log "JPApplicationSettings.ini" DEBUG
    
    $config = get-MOD-Component-Config "Jackpot Configuration" "JPApplicationSettings.ini"
    $DBofficeIP = Get-MOD-DB-OFFICE-IP

    if(-not (Test-path $config)) { Write-Log "File does not exist!" WARNING ; Return }
    
    $content = Get-IniContent $config
    $content.SecurityServerConfig.Address = $DBofficeIP
    $content.SecurityServerConfig.Port = 1666
    $content.SecurityServerConfig.ConnectionTimeOut = 21

    Out-IniFile -InputObject $content -FilePath $config -Force
}

function Set-JPReporting-Config {
    Write-Log "Set-JPReporting-Config" -Header
    write-log "JPReportSettings.ini" DEBUG

    $config = get-MOD-Component-Config "Jackpot Reporting" "JPReportSettings.ini"
    $DBofficeIP = Get-MOD-DB-OFFICE-IP

    if(-not (Test-path $config)) { Write-Log "File does not exist!" WARNING ; Return }
    
    $content = Get-IniContent $config
    $content.SecurityServerConfig.Address = $DBofficeIP
    $content.SecurityServerConfig.Port = 1666
    $content.SecurityServerConfig.ConnectionTimeOut = 21

    Out-IniFile -InputObject $content -FilePath $config -Force
}

function Set-SecurityServerConfig-Config {
    Write-Log "Set-SecurityServerConfig-Config" -Header
    write-log "SecurityApplications.ini" DEBUG

    $config = get-MOD-Component-Config "SecurityServer Configuration" "SecurityApplications.ini"
    $DBofficeIP = Get-MOD-DB-OFFICE-IP
    $casino_id  = Get-CasinoID

    if(-not (Test-path $config)) { Write-Log "File does not exist!" WARNING ; Return }

    $content = Get-IniContent $config
    $content.SecurityServerConfig.Address = $DBofficeIP
    $content.SecurityServerConfig.Port = 1666
    $content.SecurityServerConfig.ConnectionTimeOut = 21

    $content.User.UserName = "as_config_interface"

    $content.DEFAULT_CASINO.ext_casino_id = $casino_id

    Out-IniFile -InputObject $content -FilePath $config -Force
}

function Set-JP-Config {
    Set-JPApps-Config
    Set-JPReporting-Config
    Set-SecurityServerConfig-Config
}
#endregion 

#region --- Reconfigure GALAXIS functionality (slightly improved)
function Initialize-Galaxis {
    
    Write-Log "Initialize-Galaxis (Reconfigure-Galaxis/Reconfigure-GLX)" -Header

    #checking correct server
    $server = $env:MODULUS_SERVER
    if ($server -notin ("APP","1VM")) { Write-Log "You are on the wrong server - exiting script!" -Level ERROR ; Return }

    #asking if really wanted
    if (-not (Confirm-YesNo -Message "Do you want to proceed with the reconfiguration of your Galaxis folder?" -Default "No")) {
        Write-Log "Initialization/Reconfiguration aborted!" -Level WARNING
        Return
    }
    Write-Log "Proceeding with reconfiguration..."
    
    Backup-GLXDir -AskIf

    #OLD-values new way via json-file
    $reconfigScope = Get-ReconfigurationScope
    #specific:
    $societ_old    = $reconfigScope.specifics.societ
    $betabli_old   = $reconfigScope.specifics.etabli
    $specific_old  = $reconfigScope.specifics.sp_schema
    $casinoID_old  = $reconfigScope.specifics.casinoID
    #databases:
    $GLX_old       = $reconfigScope.databases.GLX_DB
    $JKP_old       = $reconfigScope.databases.JKP_DB 
    #hostnames and IPs
    $DB_oldIP      = $reconfigScope.DB_IP
    $DB_oldHn      = $reconfigScope.DB_HN
    $APP_oldIP     = $reconfigScope.APP_IP
    $APP_oldHN     = $reconfigScope.APP_HN
    $FS_oldIP      = $reconfigScope.FS_IP
    $FS_oldHN      = $reconfigScope.FS_HN
    
    #we do not care about this:
    #$shortname_old = ''
    #$longname_old  = ''
    #$shortname_new = ''
    #$longname_new  = ''
    
    #new IPs
    $DB_newIP  = Get-MOD-DB-OFFICE-IP
    $APP_newIP = Get-MOD-APP-OFFICE-IP
    $FS_newIP  = Get-MOD-FS-OFFICE-IP

    #new hostnames
    $DB_newHN  = Get-MOD-DB-hostname
    $APP_newHN = Get-MOD-APP-hostname
    $FS_newHN  = Get-MOD-FS-hostname

    #new DB service names
    $GLX_new = Get-DBTns GLX
    $JKP_new = Get-DbTns JKP

    #new casino specifics
    $societ_new    = Get-CustomerCode
    $betabli_new   = Get-CasinoCode
    $casinoID_new  = Get-CasinoID
    $specific_new  = Get-DbUser specific
    
    #building some specific strings for replace-logic
    #old specific schema
    $sp_1_old = 'BIBLIOTHEQUEBASE='+$specific_old
    $sp_2_old = 'BIBLIOTHEQUEFIDELIS='+$specific_old
    $sp_3_old = 'BIBLIOTHEQUECLIENT='+$specific_old
    $sp_4_old = 'BIBLIOTHEQUEJEUX='+$specific_old
    $sp_5_old = 'LIBSLOT='+$specific_old
    $sp_5_old = 'LIBBASE='+$specific_old
    $sp_5_old = 'LIBFIDELIS='+$specific_old
    $sp_6_old = 'CasinoDB0='+$specific_old
    #new specific schema
    $sp_1_new = 'BIBLIOTHEQUEBASE='+$specific_new
    $sp_2_new = 'BIBLIOTHEQUEFIDELIS='+$specific_new
    $sp_3_new = 'BIBLIOTHEQUECLIENT='+$specific_new
    $sp_4_new = 'BIBLIOTHEQUEJEUX='+$specific_new
    $sp_5_new = 'LIBSLOT='+$specific_new
    $sp_5_new = 'LIBBASE='+$specific_new
    $sp_5_new = 'LIBFIDELIS='+$specific_new
    $sp_6_new = 'CasinoDB0='+$specific_new

    #old GALAXIS specifics
    $societ_long_old  = 'SOCIETE='+$societ_old
    $betabli_long_old = 'ETABLISSEMENT='+$betabli_old
    #new GALAXIS specifics 
    $societ_long_new  = 'SOCIETE='+$societ_new
    $betabli_long_new = 'ETABLISSEMENT='+$betabli_new

    #old RTDS specifics
    $FloorTcpIp0_old   = 'FloorTcpIp0='+$FS_oldIP
    $PagerServerIp_old = 'PagerServerIp='+$APP_oldIP
    $CasinoId0_old     = 'CasinoId0='+$casinoID_old
    $CasinoId1_old     = 'CASINOID='+$casinoID_old
    $AlarmServerIp_old       = 'AlarmServerIp='+$APP_oldIP
    $SlotMachineServerIp_old = 'SlotMachineServerIp='+$APP_oldIP
    #new RTDS specifics
    $FloorTcpIp0_new   = 'FloorTcpIp0='+$FS_newIP
    $PagerServerIp_new = 'PagerServerIp='+$APP_newIP
    $CasinoId0_new     = 'CasinoId0='+$casinoID_new
    $CasinoId1_new     = 'CASINOID='+$casinoID_new
    $AlarmServerIp_new       = 'AlarmServerIp='+$APP_newIP
    $SlotMachineServerIp_new = 'SlotMachineServerIp='+$APP_newIP

    Write-Log "Please confirm all your input:"
    
    Write-Log "IPs: "
    Write-Log "FROM ________ to ________!"
    Write-Log "FROM $DB_oldIP to $DB_newIP !"
    Write-Log "FROM $APP_oldIP to $APP_newIP !"
    Write-Log "FROM $FS_oldIP to $FS_newIP !"
    
    Write-Log "Hostnames:"
    
    Write-Log "FROM ________ to ________!"
    Write-Log "FROM $DB_oldHN to $DB_newHN !"
    Write-Log "FROM $APP_oldHN to $APP_newHN !"
    Write-Log "FROM $FS_oldHN to $FS_newHN !"
    
    Write-Log "Specifics:"
    
    Write-Log "FROM ________ to ________!"
    Write-Log "FROM $GLX_old to $GLX_new !"
    Write-Log "FROM $JKP_old to $JKP_new !"
    Write-Log "FROM $societ_long_old to $societ_long_new !"
    Write-Log "FROM $betabli_long_old to $betabli_long_new !"
    Write-Log "FROM $FloorTcpIp0_old to $FloorTcpIp0_new !"
    Write-Log "FROM $CasinoId0_old to $CasinoId0_new !"
    

    Start-Sleep -Seconds 2
    #asking if really wanted
    if (-not (Confirm-YesNo -Message "If all the input is correct, please confirm you want to continue with the reconfiguration: (Y/N)" -Default "No")) {
        Write-Log "Initialization/Reconfiguration aborted!" -Level WARNING
        Return
    }
    Write-Log "Proceeding with reconfiguration..."

    #replacement array
    $lookupTable = @{
        #Key					= #Value
        #'localhost' 			= '127.0.0.1'
        #get rid of intraESX
        '192.168.223.10'		= $DB_newIP
        '192.168.223.11'		= $APP_newIP
        '192.168.223.12'		= $FS_newIP
        #IPs
        $DB_oldIP				= $DB_newIP
        $APP_oldIP 				= $APP_newIP
        $FS_oldIP  				= $FS_newIP
        #hostnames
        $DB_oldHN  				= $DB_newHN
        $APP_oldHN 				= $APP_newHN
        $FS_oldHN  				= $FS_newHN
        #services
        $GLX_old				= $GLX_new
        #$JKP_old				= $JKP_new
        #GALAXIS specifics
        $societ_long_old		= $societ_long_new
        $betabli_long_old		= $betabli_long_new
        #RTDS specifics
        $FloorTcpIp0_old			= $FloorTcpIp0_new
        $PagerServerIp_old			= $PagerServerIp_new
        $CasinoId0_old				= $CasinoId0_new
        $CasinoId1_old				= $CasinoId1_new
        $AlarmServerIp_old			= $AlarmServerIp_new
        $SlotMachineServerIp_old 	= $SlotMachineServerIp_new
        
        #specific schema
        $sp_1_old 				= $sp_1_new
        $sp_2_old 				= $sp_2_new
        $sp_3_old 				= $sp_3_new
        $sp_4_old 				= $sp_4_new
        $sp_5_old 				= $sp_5_new
        $sp_6_old 				= $sp_6_new
        
        #Oracle Data Provider
        'System.Data.OracleClient' 	= 'Oracle.DataAccess.Client'
        
        #to see missing 'default' config
        'tobedefined'				= 'RnD needs to fix delivery!'
        
        #TODO
        # need to list all specific configuration like:
        # 	CASHLESSLEVEL 
        #   etc.

        <#
        #change passwords:
        #asdba -> sys.2015--------------------------------------
        'EO/IxE4iEtyTr5AYDSvZGw==' = 'kQ4GFqtkHC1Rh4yFu1W88Q==' 
        #manager -> system.2015---------------------------------
        '5LgYZ+g/G0dylvPgeTSosw==' = 'RQeNx/8ls84sjxXvMZ1Zxw=='
        
        #gam.2015-----------------------------------------------
        #alrmsrv
        'GgEJime4b75SdoxQrIdxdQ=='  = '/+jWtG+68dIAn/+RFHUNyg==' 
        #as_auth
        '/PbNgfaCfpRKVD72AKgYEQ=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #as_sbc
        'CCulmaykfb5xZb5FvmFsqw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #galaxis
        'xdazcgF4LvtMkDdZcbKIJQ=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #junket
        'zIoRMo46Swisj5XMLY0Gkg=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #JUNKET
        'WM/d3mHEnwuZ8WV2a27PTQ=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #marketing
        '7aBQ1hTu13r6dNZhI9bSNw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #MARKTEING
        'rjVRnIOKmfv0OSXv40xCmw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #mis
        '9N/g/CthvvnsO9zo/aPzzw=='  = '/+jWtG+68dIAn/+RFHUNyg==' 
        #mktdtm
        'bX0zQxVOnrsjkt/pINzRlQ=='  = '/+jWtG+68dIAn/+RFHUNyg==' 
        #pagsrv
        '4QnyhYoVS54J7dZr3OZHFA=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #ps
        'qF/j81Gdo0+P1454ZML8MA=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #KARAMBA (qpcash)
        'h6jrLfCyECr1RPVlNbvXhQ=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #site
        '6pBo04HH6ZBdlupJrG5xXA=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #slot
        'vzPVlKQvhcSuNThy2PK3bw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #SLOT
        '9lEzmOR14Htqd6xepruvWw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #slotexp
        'uAL5Vo/sRLeE7EoYlYjm0Q=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #SLOTEXP
        'fQoqvUfm06DgTRDCVSm7wg=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #smsrv
        'EOL7iUQiQRMKEA92o2/QEw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #spa
        'mloCBv6OsfBvdJvT3u0Ohg=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #SPA
        'caJajClmtHLrfkJb8sij/w=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #tbl
        'g0X31FWTCgEnvc0rIAyBew=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #TBL
        '6/exUV/r/O8kK6KgT4X/vQ=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #trnssrv
        'd/kGYMcpSt0eZhsNN+QALQ=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #TRNSSRV
        'Oxn9ZNmXSN1laEDk+0QHuw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        
        #hidden
        'T0rz9o033JEvAa2WRluxnw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #geheim
        'KskH4sUeRFkmHuS4fIKZmw=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #fx
        'BVvlFDGSV9i2d/GlIC6Q3A=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #FX
        'dQUdk9z0vvc/SC/3dBJJsA=='  = '/+jWtG+68dIAn/+RFHUNyg=='
        #>
    }

    ############################################################################


    #directory to search
    #$GLXdir = [string](Get-Location) + "\Config only\"
    #$GLXdir = [string](Get-Location) + "\Galaxis_Full\"
    $GLXdir = "D:\Galaxis\"

    #array for configuration files
    $configFiles = @()

    #add the following extensions to the array $configFiles
    #*.ini
    #*.config
    #*.json
    #*.properties
    #*.xml
    foreach ($file in (get-childitem $GLXdir -recurse))
    {
        #full list:
        if ($file.extension -eq ".ini" -Or $file.extension -eq ".config" -Or $file.extension -eq ".conf" -Or $file.extension -eq ".json" -Or $file.extension -eq ".properties" -Or $file.extension -eq ".xml")
        {
            if (!$file.FullName.Contains('D:\Galaxis\Install\OCI\')) 
            { 
                $configFiles += $file
            }
        }	
    }
    
    #loop through all configuration files
    foreach($file in $configFiles)
    {
        $changed = 0
        $changes = @()
    
        #define file we are working on right now
        $workingFile = (Get-Content $file.PSPath) 
        
        
        $lookupTable.GetEnumerator() | ForEach-Object {
            if ($workingFile -match $_.Key)
            {
                $changed = 1
                $changes += "Replaced "+$_.Key+" with "+$_.Value
                $workingFile =  $workingFile -replace $_.Key, $_.Value
            }
        }
        
        #if changes were made, write into logic
        if ($changed -eq 1)
        {
            Write-Log "Working on:" 
            Write-Log ">- $file"
            Write-Log ">--- Changes made:"
            foreach ($change in $changes)
            {
                Write-Log ">----- $change"
            }
        }
        
        #writing changes to current $workingFile
        $workingFile | Set-Content $file.PSPath

    }

    Write-log "Initialize-Galaxis finished!"

}
Set-Alias -Name Reconfigure-GLX -Value Initialize-Galaxis
Set-Alias -Name Reconfigure-Galaxis -Value Initialize-Galaxis
#endregion 

#region --- Set-Functions for Web/nginx configuration files
function Set-Web-Config {
    Write-Log "Set-Web-Config" -Header
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "SYSTM_config.json"
    $APPofficeIP = Get-MOD-APP-OFFICE-IP
    $FSofficeIP = Get-MOD-FS-OFFICE-IP

    Write-Log "Setting $config"

    if(-not (Test-path $config)) { Write-log "File does not exist!" -Level Error; Return }
    
    $content = Get-Content $config -Raw | ConvertFrom-Json
    $content.apiUrl            = 'http://' + $APPofficeIP + ':4445/api/'
    $content.apiUrlMedia       = 'http://' + $APPofficeIP + ':4445/api/asset/v1/assets'
    $content.httpFileServerUrl = 'http://' + $FSofficeIP + '/'
    $content | ConvertTo-Json | Set-Content $config
}

function Set-PlayerApp-Config {
    Write-Log "Set-PlayerApp-Config" -Header
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "PlayerApp_config.json"
    $APPofficeIP = Get-MOD-APP-OFFICE-IP

    Write-Log "Setting $config"

    if(-not (Test-path $config)) { Write-log "File does not exist!" -Level Error; Return }
    
    $content = Get-Content $config -Raw | ConvertFrom-Json
    $content.apiUrl            = 'http://' + $APPofficeIP + ':4445'
    $content.wslog             = 1
    $content | ConvertTo-Json | Set-Content $config
}

function Set-Reverse-Proxy-Config {
    Write-Log "Set-Reverse-Proxy-Config" -Header
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "reverse-proxy.conf"
    $APPofficeIP = Get-MOD-APP-OFFICE-IP
    $FSofficeIP  = Get-MOD-FS-OFFICE-IP

    Write-Log "Setting $config"

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-Content $config

    $aml_old = 'http://tobedefined:5003'
    $ply_old = 'http://tobedefined:5004'
    $cc_old  = 'http://tobedefined:40105'
    $lic_old = 'http://tobedefined:5399'
    $tbs_old = 'http://tobedefined:5006'

    #currently not supported, can only replace tobedefined
    <#if ($content.Contains('tobedefined')) {
        $aml_old = 'http://tobedefined:5003'
        $ply_old = 'http://tobedefined:5004'
        $cc_old  = 'http://tobedefined:40105'
        $lic_old = 'http://tobedefined:5399'
        $tbs_old = 'http://tobedefined:5006'
    } else 
    {
        Return 
        #$aml_old = 'http://*:5003'
        #$ply_old = 'http://*:5004'
        #$cc_old  = 'http://*:40105'
        #$lic_old = 'http://*:5399'
        #$tbs_old = 'http://*:5006'
    }#>
    
    $aml_new = 'http://'+$APPofficeIP+':5003'
    $ply_new = 'http://'+$APPofficeIP+':5004'
    $cc_new  = 'http://'+$FSofficeIP+':40105'
    $lic_new = 'http://'+$APPofficeIP+':5399'
    $tbs_new = 'http://'+$APPofficeIP+':5006'

    $content = $content -replace $aml_old, $aml_new
    $content = $content -replace $ply_old, $ply_new
    $content = $content -replace $cc_old, $cc_new
    $content = $content -replace $lic_old, $lic_new
    $content = $content -replace $tbs_old, $tbs_new

    $content | Set-Content $config
}
function Set-Public-Api-Reverse-Proxy-Config {
    Write-Log "Set-Public-Api-Reverse-Proxy-Config" -Header
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "public-api-reverse-proxy.conf"
    $APPofficeIP = Get-MOD-APP-OFFICE-IP

    Write-log "Setting $config"

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-Content $config

    $servername_old = 'server_name tobedefined;'
    $servername_new = 'server_name localhost;'
    $path_old       = 'proxy_pass http://tobedefined:5007;'
    $path_new       = 'proxy_pass http://'+$APPofficeIP+':5007;'

    $content = $content -replace $servername_old, $servername_new
    $content = $content -replace $path_old, $path_new

    $content | Set-Content $config

    #output
    #write-host "Changed $config!"
    #write-host "Set server_name to localhost"
    #write-host "Setting APP server OFFICE IP!"
    #write-host "-----------------------------" -ForegroundColor Yellow
    #logging
}
#endregion

#region --- PlayWatch Process/Website
function Set-PlayWatch-Config {
    Write-Log "Set-PlayWatch-Config" -Header
    #need to configure PlayWatch.exe.config!
    #need to configure log4net.config
    #need to configure web.config

    $process = get-MOD-Component-Config "PlayWatch" "PlayWatch.exe.config"
    $log4net = get-MOD-Component-Config "PlayWatch" "log4net.config"
    $website = get-MOD-Component-Config "PlayWatch" "web.config"
    
    if(-not (Test-path $process)) { Write-host "$config_File does not exist!" -ForegroundColor Red; Return }
    if(-not (Test-path $log4net)) { Write-host "$log4net does not exist!" -ForegroundColor Red; Return }
    if(-not (Test-path $website)) { Write-host "$website does not exist!" -ForegroundColor Red; Return }

    $DBofficeIP = Get-MOD-DB-OFFICE-IP
    $GLX_DB      = Get-DBTns-GLX
    $RG_user     = Get-DbUser-rg
    $RG_password = Get-DbEnCred-rg

    #Playwatch.exe.config
    $process_config = New-Object System.XML.XMLDocument
    $process_config.Load($process)
    #<connectionStrings>
    $process_config.configuration.connectionStrings.add.connectionString = "Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$DBofficeIP)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=$GLX_DB)));User Id=$RG_user;Password=$RG_password;"
    $process_config.Save($process)
    Write-Host " > PlayWatch.exe.config was configured!"
    Write-Host " > $DBofficeIP"
    #------------------------------

    #log4net.xml 
    $log4net_config = New-Object System.XML.XMLDocument
    $log4net_config.Load($log4net)
    $appenders = $log4net_config.log4net.Appender
    #appender name="RollingFileAppender"
    $logfile = $appenders | Where-Object {$_.name -eq "RollingFileAppender"}
    $path = '${COMPUTERNAME}'
    $path = "D:\PlayWatch\Log\log-file-$path.txt"
    $logfile.file.value = $path
    $log4net_config.Save($log4net)
    Write-Host " > log4net.config was configured!"
    Write-Host " > D:\PlayWatch\Log\*"
    #------------------------------

    #web.config
    $website_config = New-Object System.XML.XMLDocument
    $website_config.Load($website)
    #<connectionStrings>
    $website_config.configuration.connectionStrings.add.connectionString = "Data Source=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$DBofficeIP)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=$GLX_DB)));User Id=$RG_user;Password=$RG_password;"
    $website_config.Save($website)
    Write-Host " > web.config was configured!"
    Write-Host " > $DBofficeIP"
    #------------------------------
}
#endregion

#region --- FS def.cfg attempt
function Set-FS-Config {
    Write-Log "Set-FS-Config" -Header
    
    $config     = get-MOD-Component-Config "Floorserver" "def.cfg"
    $FSfloorIP  = Get-MOD-FS-FLOOR-IP
    $dhcpranges = Get-MOD-FS-DHCP-Ranges
    $CMODrange  = $dhcpranges | Where-Object { $_.name -eq "range1" }
    $MDCrange   = $dhcpranges | Where-Object { $_.name -eq "range2" }
    
    if(-not (Test-path $config)) { write-log "$config does not exist!" ERROR; Return }

    $configContent = Get-Content -Path $config -Raw

    #interface
    $interface = $FSfloorIP
    write-log "Setting FLOOR interface IP to $interface" DEBUG
    #CMOD
    $dhcpserverlow =  $CMODrange.from
    $dhcpserverhigh = $CMODrange.to
    write-log "Setting CMOD DHCP range from $dhcpserverlow to $dhcpserverhigh" DEBUG
    #MDC
    $dhcplow =        $MDCrange.from
    $dhcphigh =       $MDCrange.to
    write-log "Setting MDC DHCP range from $dhcplow to $dhcphigh" DEBUG

    #mdc settings
    $configContent = $configContent -replace 'definterface="[^"]*"', "definterface=`"$interface`""
    $configContent = $configContent -replace 'dhcplow="[^"]*"', "dhcplow=`"$dhcplow`""
    $configContent = $configContent -replace 'dhcphigh="[^"]*"', "dhcphigh=`"$dhcphigh`""
    #cmod={} settings
    $configContent = $configContent -replace 'dhcpserverlow="[^"]*"', "dhcpserverlow=`"$dhcpserverlow`""
    $configContent = $configContent -replace 'dhcpserverhigh="[^"]*"', "dhcpserverhigh=`"$dhcpserverhigh`""
    $configContent = $configContent -replace 'gateway="[^"]*"', "gateway=`"$interface`""
    $configContent = $configContent -replace 'interface="[^"]*"', "interface=`"$interface`""
    $configContent = $configContent -replace 'logserver="[^"]*"', "logserver=`"$interface`""
    $configContent = $configContent -replace 'resourceserver="[^"]*"', "resourceserver=`"$interface`""
    $configContent = $configContent -replace 'timeserver="[^"]*"', "timeserver=`"$interface`""
   
    #save changes
    $configContent | Set-Content -Path $config
    Write-Log "Please verify by opening fscfg.tcl85 !"
    Write-Log "or type 'Show-FS-Config'!"
}
#endregion

#region --- Set-Functions for CRYSTAL Control configuration files
function Set-CRYSTALControl-Config {
    Write-Log "Set-CRYSTALControl-Config" -Header
   
    $config = get-MOD-Component-Config "CRYSTAL Control" "ControlLauncher.exe.config"

    if(-not (Test-path $config)) { write-log "$config does not exist!" ERROR ; Return }

    $CONTROL_config = New-Object System.XML.XMLDocument
    $CONTROL_config.Load($config)
 
    #$officeNIC = $FSConfig.OFFICE.name - no extra variable for just the name at the moment, but OFFICE should be the same each time.
    $FSofficeIP  = Get-MOD-FS-OFFICE-IP
    #$FSfloorIP   = (Get-MOD-FS-FLOOR-NIC).IPAddress 

    #fetching current config
    $appSettings = $CONTROL_config.SelectSingleNode("configuration/appSettings").ChildNodes

    $OfficeNetworkInterface = $appSettings  | Where-Object {$_.key -eq "OfficeNetworkInterface"}
    $OfficeNetworkInterface.value = 'OFFICE'
    write-log 'Setting OfficeNetworkInterface="OFFICE"' DEBUG

    $floorNetworkInterface = $appSettings  | Where-Object {$_.key -eq "FloorNetworkInterface"}
    $floorNetworkInterface.value = 'FLOOR'
    write-log 'Setting FloorNetworkInterface="FLOOR"' DEBUG

    $PreferredIpAddress = $appSettings  | Where-Object {$_.key -eq "PreferredIpAddress"}
    $PreferredIpAddress.value = $FSofficeIP
    write-log "Setting PreferredIpAddress= $FSofficeIP" DEBUG

    $floorServerIpOnOfficeNetworkInterface = $appSettings  | Where-Object {$_.key -eq "floorServerIpOnOfficeNetworkInterface"}
    $floorServerIpOnOfficeNetworkInterface.value = $FSofficeIP
    write-log "Setting floorServerIpOnOfficeNetworkInterface= $FSofficeIP" DEBUG
    
    $CONTROL_config.Save($config)
    write-log "Set-CRYSTALControl-Config completed!"
}

#endregion

#region --- Set-Functions for CFCS configuration files
function Set-CFCS-Config {
    Write-Log "Set-CFCS-Config" -Header
       
    #need to configure CFCS.exe.config as well as log4net.xml since it is delivered with a shit logging path!

    $config  = get-MOD-Component-Config "CRYSTAL Floor Communication Service" "CRYSTAL Floor Communication Service.exe"
    
    if(-not (Test-path $config)) { Write-log "$config does not exist!" ERROR ; Return }

    $casinoID     = Get-CasinoID
    $CAWA         = Get-CasinoModuleState CAWA
    $IPSEC        = Get-IPSEC
    $APP_officeIP = Get-MOD-APP-OFFICE-IP
    $FS_officeIP  = Get-MOD-FS-OFFICE-IP
    
    #$GDP          = Get-CasinoModuleState GDP #GameDayChangeProvider
    $GDP          = $False #no GamingDayProvider change at the end of the file

    $R4R          = Get-CasinoModuleState R4R

    $FS_officeNIC = 'OFFICE'
    $MeterSessTO  = '00:05:00'
    $GameConfTO   = '00:05:00'
    $commLog      = 'D:\\OnlineData\\Log\\CFCS\\Communication.log'
    $commKALog    = 'D:\\OnlineData\\Log\\CFCS\\CommunicationKeepAlive.log'

    

    #CaWa-fix - fix comment issue for CashWallet-content before we actually start configuring the file
    if ($CAWA) {
        $fileContents = Get-Content -Raw $config

        $startIndex = $fileContents.IndexOf("<!-- Cash Wallet specific configuration. Uncomment id needed.")

        if($startIndex -ne -1) { 
            $endIndex = $fileContents.IndexOf("-->", $startIndex)
            
            #option 1: adding end comment and removing the end comment 4 rows below
            #adding end of comment to the line
            #$fileContents = $fileContents.Insert($startindex + 61,"-->")
            #removeing the end-comment below   
            #$fileContents = $filecontents.Remove($endIndex+3,3)

            $fileContents = $fileContents.Remove($startIndex,61)
            $fileContents = $fileContents.Remove($endIndex-61,3)
        
            $fileContents | Set-Content -Path $config
        }
    }
    #end CaWa-fix

    #$config  = get-MOD-Component-Config "CRYSTAL Floor Communication Service" "CRYSTAL Floor Communication Service.exe"
    #region configuring the file
    $CFCS_config = New-Object System.XML.XMLDocument
    $CFCS_config.Load($config)

    #<S2SConfigurationSection>
    $S2SConfigurationSection = $CFCS_config.SelectSingleNode("configuration/S2SConfigurationSection")
    $S2SConfigurationSection.LocalUri 	= "http://"+$FS_officeIP+":6001/clientCfcs"
    $S2SConfigurationSection.PropertyId = $casinoID 

    #<Boss>
    if ($IPSEC) { 
        $Boss = $CFCS_config.SelectSingleNode("configuration/Boss")
        $Boss.Port = 15666
    } 
    
    #<MultiGame>
    $MultiGame = $CFCS_config.SelectSingleNode("configuration/MultiGame")
    $MultiGame.MeterSessionTimeout 		= $MeterSessTO
    $MultiGame.GameConfigurationTimeout = $GameConfTO

    #region <system.serviceModel><client><endpoint>
    $client_endpoints = $CFCS_config.configuration.'system.serviceModel'.client.endpoint

    #Jackpot Service
    $JackpotService = $client_endpoints | Where-Object {$_.name -eq "Jackpot Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8071/StarSlots/SlotIntelligence/JackpotService"
    $JackpotService.address = $address
    write-log "Configuring: $address" DEBUG

    #Promotion Service
    $PromotionService = $client_endpoints | Where-Object {$_.name -eq "Promotion Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/PromotionsService"
    $PromotionService.address = $address
    write-log "Configuring: $address" DEBUG

    #KioskConfiguration Service
    $KioskConfigurationService = $client_endpoints | Where-Object {$_.name -eq "KioskConfiguration Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/KioskConfigurationService"
    $KioskConfigurationService.address = $address
    write-log "Configuring: $address" DEBUG

    #Rewards Service
    $RewardsService = $client_endpoints | Where-Object {$_.name -eq "Rewards Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/RewardsService"
    $RewardsService.address = $address
    write-log "Configuring: $address" DEBUG

    #Loyalty Club Service
    $LoyalityClubService = $client_endpoints | Where-Object {$_.name -eq "Loyalty Club Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/LoyaltyClubService"
    $LoyalityClubService.address = $address
    write-log "Configuring: $address" DEBUG

    #Player Preferences Service
    $PlayerPreferencesService = $client_endpoints | Where-Object {$_.name -eq "Player Preferences Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/PlayerPreferencesService"
    $PlayerPreferencesService.address = $address
    write-log "Configuring: $address" DEBUG

    #Voucher Service
    $VoucherService = $client_endpoints | Where-Object {$_.name -eq "Voucher Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/VoucherService"
    $VoucherService.address = $address
    write-log "Configuring: $address" DEBUG

    #Campaign Service
    $CampaignService = $client_endpoints | Where-Object {$_.name -eq "Campaign Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/CampaignService"
    $CampaignService.address = $address
    write-log "Configuring: $address" DEBUG

    #NetTcpBinding_Item Service
    $NetTcpBinding_ItemService = $client_endpoints | Where-Object {$_.name -eq "NetTcpBinding_Item Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8093/PlayerServices/MyBar/ItemService"
    $NetTcpBinding_ItemService.address = $address
    write-log "Configuring: $address" DEBUG

    #Default
    $Default = $client_endpoints | Where-Object {$_.name -eq "Default"}
    $address = "net.tcp://"+ $APP_officeIP +":8093/PlayerServices/MyBar/OrderService"
    $Default.address = $address
    write-log "Configuring: $address" DEBUG

    #DefaultControlServiceEndpoint
    $DefaultControlServiceEndpoint = $client_endpoints | Where-Object {$_.name -eq "DefaultControlServiceEndpoint"}
    $address = "net.tcp://"+ $APP_officeIP +":9083/"
    $DefaultControlServiceEndpoint.address = $address
    write-log "Configuring: $address" DEBUG

    #DefaultControlServiceEndpoint1
    $DefaultControlServiceEndpoint1 = $client_endpoints | Where-Object {$_.name -eq "DefaultControlServiceEndpoint1"}
    $address = "net.tcp://"+ $APP_officeIP +":9084/"
    $DefaultControlServiceEndpoint1.address = $address
    write-log "Configuring: $address" DEBUG

    #endregion
 
    #<system.serviceModel><services><service>
    $MyMultiGameService = ($CFCS_config.configuration.'system.serviceModel'.services.service | Where-Object {$_.name -eq "Atronic.CrystalFloor.MyMultiGameService"}).endpoint
    $address = "net.tcp://"+ $FS_officeIP +":9066/MultiGameService/mex"
    $MyMultiGameService.address = $address
    write-log "Configuring: $address" DEBUG

    $Rub4RichesService = ($CFCS_config.configuration.'system.serviceModel'.services.service | Where-Object {$_.name -eq "CFCS.Services.Rub4Riches.Rub4RichesService"}).endpoint
    $address = "net.tcp://"+ $FS_officeIP +":9066/Rub4Riches/mex"
    $Rub4RichesService.address = $address
    write-log "Configuring: $address" DEBUG

    #COMMENT REMOVAL if needed
    <#Atronic.CrystalFloor.CashWallet.BalanceNotificationService
    $BalanceNotificationService = ($CFCS_config.configuration.'system.serviceModel'.services.service | Where-Object {$_.name -eq "Atronic.CrystalFloor.CashWallet.BalanceNotificationService"}).endpoint

    #we need to remove the comment if needed
    #$CFCS_config.configuration.'system.serviceModel'.services.service | Where-Object {$_.name -eq "Atronic.CrystalFloor.CashWallet.BalanceNotificationService"}.'#comment'
    #>

 
    #<system.serviceModel><behaviors>
    $service_endpoints = $CFCS_config.configuration.'system.serviceModel'.behaviors.serviceBehaviors.behavior

    #MultiGameServiceBehavior
    $MultiGameServiceBehavior = $service_endpoints | Where-Object {$_.name -eq "MultiGameServiceBehavior"}
    $address = "http://"+ $FS_officeIP +":4004/MultigameService/mex"
    $MultiGameServiceBehavior.serviceMetadata.httpGetUrl = $address
    write-log "Configuring: $address" DEBUG

    #DefaultServiceBehaviour
    $DefaultServiceBehaviour = $service_endpoints | Where-Object {$_.name -eq "DefaultServiceBehaviour"}
    $address = "http://"+ $FS_officeIP +":9065/BalanceNotification/mex"
    $DefaultServiceBehaviour.serviceMetadata.httpGetUrl = $address
    write-log "Configuring: $address" DEBUG


    #<appSettings>
    $appSettings = $CFCS_config.SelectSingleNode("configuration/appSettings").add
   

    if ($CAWA) {

       $CashWalletAddress = $appSettings | Where-Object {$_.key -eq "CashWalletAddress"}
       $address = "http://"+$APP_officeIP+":16266/B0C78A8F-1908-42B5-ABBD-ABD080A741D1"
       $CashWalletAddress.value = $address
       write-log "Configuring: $address" DEBUG

       $AuthAddress = $appSettings | Where-Object {$_.key -eq "AuthAddress"}
       $address = "http://"+$APP_officeIP+":16264/B0C78A8F-1908-42B5-ABBD-ABD080A741D1"
       $AuthAddress.value = $address
       write-log "Configuring: $address" DEBUG

       $PropertyId = $appSettings | Where-Object {$_.key -eq "PropertyId"}
       $PropertyId.value = $casinoID
       write-log "Configuring casinoID: $casinoID" DEBUG

       if($R4R)
       {
        #handle R4R config if wanted
       }
    }
   

    $OfficeNetworkInterface = $appSettings  | Where-Object {$_.key -eq "OfficeNetworkInterface"}
    $OfficeNetworkInterface.value = $FS_officeNIC
    write-log "Configuring OfficeNetworkInterface: $FS_officeNIC" DEBUG
    
    #$PreferredIpAddress = $appSettings | Where-Object {$_.key -eq "PreferredIpAddress"}
    #$PreferredIpAddress.value = 
    # 								^
    # 								what to set?

    $HTTPServerAddress = $appSettings | Where-Object {$_.key -eq "HTTPServerAddress"}
    $HTTPServerAddress.value = "http://"+$APP_officeIP+":801"
    $outputvalue = $HTTPServerAddress.value
    write-log "Configuring HTTPServerAddress: $outputvalue" DEBUG

    $component = $CFCS_config.configuration.castle.components.component | Where-Object { $_.id -eq "GamingDayProvider" }
    if ($component) {
        if($GDP -eq $False)
        {
            $component.type = "CFCS.Commons.GamingDay.NoGamingDayProvider, CFCS.Commons"
            Write-Log "Changing GamingDayProvider type to 'CFCS.Commons.GamingDay.NoGamingDayProvider, CFCS.Commons'" DEBUG
        } else {
            $component.type = "CFCS.Galaxis.GamingDay.GamingDayProvider, CFCS.Galaxis"
            Write-Log "Changing GamingDayProvider type to 'CFCS.Galaxis.GamingDay.GamingDayProvider, CFCS.Galaxis'" DEBUG
        }
    }
    
    #endregion

    #Saving CFCS.exe.config!
    $CFCS_config.Save($config)
    write-log "CFCS configuration file was configured!"
    #------------------------------

    $config = get-MOD-Component-Config "CRYSTAL Floor Communication Service" "log4net.xml"
    if(-not (Test-path $config)) { write-log "$config does not exist!" ERROR ; Return }

    #log4net.xml 
    $log4net_config = New-Object System.XML.XMLDocument
    $log4net_config.Load($config)

    $appenders = $log4net_config.log4net.Appender

    #Communication.log
    $logfile = $appenders | Where-Object {$_.name -eq "logfile"}
    $logfile.file.conversionPattern.value = $CommLog
    write-log "Configuring log-dir: $CommLog" DEBUG

    $logfile.maxSizeRollBackups.value = "100"
    write-log "Setting maximum log files to 100!" DEBUG

    $logfile.maximumFileSize.value = "10000KB"
    write-log "Setting maximum log file size to 10000KB!" DEBUG

    #CommunicationKeepAlive.log
    $logfile = $appenders | Where-Object {$_.name -eq "keepalivelogfile"}
    $logfile.file.conversionPattern.value = $CommKALog
    write-log "Configuring log-dir: $CommKALog" DEBUG

    <#
    $logfile.maxSizeRollBackups.value = "100"
    write-host "Setting maximum log files to 100!"

    $logfile.maximumFileSize.value = "10000KB"
    write-host "Setting maximum log file size to 10000KB!"
    #>

    #Saving log4net.xml
    $log4net_config.Save($config)
    write-log "CFCS log4net.xml file was configured!"
    write-log "Set-CFCS-Config completed!"
}

#endregion

#region --- Relay
function Set-Relay-Config {
    Write-Log "Set-Relay-Config" -Header

    #need to configure TCPIPServerIn.xml
    #need to configure TCPIPServerOut.xml

    $tcpin  = get-MOD-Component-Config "Star Display Relay" "TCPIPServerIn.xml"
    $tcpout = get-MOD-Component-Config "Star Display Relay" "TCPIPServerIn.xml"

    if(-not (Test-path $tcpin)) { Write-Log "$tcpin does not exist!" ERROR ; Return }
    if(-not (Test-path $tcpout)) { Write-Log "$tcpout does not exist!" ERROR ; Return }

    $FSofficeIP = Get-MOD-FS-OFFICE-IP
    $NIC      = 'OFFICE'

    #TCPIPServerIn.xml
    $tcpin_config = New-Object System.XML.XMLDocument
    $tcpin_config.Load($tcpin)
    #<TCPIPServerConfig>
    $tcpin_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strName = $NIC
    $tcpin_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strIPAddress = $FSofficeIP
    $tcpin_config.Save($tcpin)
    write-log "TCPIPServerIn.xml was configured!" DEBUG
    write-log "$NIC and $FSofficeIP!" DEBUG

    #TCPIPServerOut.xml
    $tcpout_config = New-Object System.XML.XMLDocument
    $tcpout_config.Load($tcpout)
    #<TCPIPServerConfig>
    $tcpout_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strName = $NIC
    $tcpout_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strIPAddress = $FSofficeIP
    $tcpout_config.Save($tcpout)
    write-log "TCPIPServerOut.xml was configured!" DEBUG
    write-log "$NIC and $FSofficeIP!" DEBUG

    Write-Log "Set-Relay-Config completed!"
}
#endregion

#region --- Update 3VM from APP
function Update-3VM {
    Write-Log "Update-3VM" -Header

    if((Get-MOD-Server).name -ne 'APP') {
        Write-Log "Not on APP, aborting!" -Level WARNING
        return
    }

    #session variables
    $DB = Get-Session -Server DB
    $FS = Get-Session -Server FS
    if ($null -eq $DB) { Write-Log "No DB session found!" -Level ERROR; return }
    if ($null -eq $FS) { Write-Log "No FS session found!" -Level ERROR; return }

    Write-Log "Sessions to DB and FLOOR server established!" 

    #region --- stopping all services
    #APP
    Write-Log "Starting with APP server!" -Scope
    Stop-MOD-Services  
    #Show-MOD-Services
    #DB
    Invoke-Command -Session $DB -ScriptBlock { 
        #I-drive
        $app = Get-MOD-APP-hostname
        $uncPath = "\\$app\I"
        $I = Get-PSDrive -Name "I" -ErrorAction SilentlyContinue
        if (-not ($I)) {
            New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $uncPath > $null 2>&1
        }

        Write-Log "Now working on DB server!" -Scope
        Stop-MOD-Services   
        #Show-MOD-Services
    }
    #FS
    Invoke-Command -Session $FS -ScriptBlock { 
        #I-drive
        $app = Get-MOD-APP-hostname
        $uncPath = "\\$app\I"
        $I = Get-PSDrive -Name "I" -ErrorAction SilentlyContinue
        if (-not ($I)) {
            New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $uncPath > $null 2>&1
        }

        Write-Log "Now working on FLOOR server!" -Scope
        Stop-MOD-Services   
        #Show-MOD-Services
    }
    #endregion

    #region --- APP
    Write-Log "Back on APP server!" -Scope

    #cleanup
    Clear-PrepDir
    Clear-GLXLogs    #-AskIF

    #backup
    Backup-GLXDir    #-AskIF

    #stating, preparing files to be deployed
    Prep-Galaxis ALL #-AskIF
    Prep-SYSTM ALL #-AskIF
    Prep-Web
    Prep-PlayerApp
    Prep-HFandLib
    #Prep-PlayWatch 

    Prep-CRYSTALControl 
    Prep-MBoxUI 

    Write-Log "Follow the manual steps in the instructions to prepare binaries for deployment!" -Level INFO
    
    
    Close-GLXDirAccess
    Disable-M-Share

    Deploy-Galaxis ALL #-AskIf
    Deploy-SYSTM ALL #-AskIf
    Deploy-Web
    Deploy-PlayerApp
    #Deploy-PlayWatch
    
    Enable-M-share

    Set-Web-Config
    Set-Reverse-Proxy-Config
    #Set-PlayWatch-Config

    Install-MOD-Services
    Remove-1097-Artifacts

    #RabbitMQ

    Open-MOD-Manual Manual
    
    #Compile-GLX-Serial
    #Show-GLX-Invalids   

    Install-QueryBuilder #-AskIF

    Uninstall-JPApps #-AskIf
    Install-JPApps #-AskIf
    Set-JP-Config #-AskIF
    
    #endregion

    #region --- updating FS
    Invoke-Command -Session $FS -ScriptBlock { 
        #I-drive
        $app = Get-MOD-APP-hostname
        $uncPath = "\\$app\I"
        $I = Get-PSDrive -Name "I" -ErrorAction SilentlyContinue
        if (-not ($I)) {
            New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $uncPath > $null 2>&1
        }

        Write-Log "Now working on FLOOR server!" -Scope

        Stop-MOD-Services
        net stop nginx
        #Show-MOD-Services

        Backup-OnlineData #-AskIF

        
        #not working right now
        #Deploy-CRYSTALControl #-AskIF
        #Deploy-MBoxUI

        #Uninstall-CFCS
        #Install-CFCS
        #Install-QueryBuilder #-AskIf
        #Install-Floorserver #-AskIF
        
        Set-FS-Config
        Set-CFCS-Config
        #fix GDC stuff in CFCS by having a fucking proper default config file that does not include a fucking shit setting for one african village        
        Set-CRYSTALControl-Config
        #again, shit default config file that needs manual steps in order to fix network adapter names because, because why not
        #Set-Reverse-Proxy-Config
    }
    #endregion

    <#nothing to do right now on DB server
    #region --- updating DB
    Invoke-Command -Session $DB -ScriptBlock { 
        #I-drive
        $app = Get-MOD-APP-hostname
        $uncPath = "\\$app\I"
        
        if (-not (Get-PSDrive -Name "I" -ErrorAction SilentlyContinue)) {
            New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $uncPath
        }

        Write-Log "Now working on DB server!" -Header
    }
    #endregion
    #>
    
    #region --- starting FS
    Invoke-Command -Session $FS -ScriptBlock { 
        #I-drive
        $app = Get-MOD-APP-hostname
        $uncPath = "\\$app\I"
        $I = Get-PSDrive -Name "I" -ErrorAction SilentlyContinue
        if (-not ($I)) {
            New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $uncPath > $null 2>&1
        }

        Write-Log "Now working on FLOOR server!" -Scope

        Start-MOD-Services
        net start nginx
    }
    #endregion
    
    #region --- starting DB
    Invoke-Command -Session $DB -ScriptBlock { 
        #I-drive
        $app = Get-MOD-APP-hostname
        $uncPath = "\\$app\I"
        $I = Get-PSDrive -Name "I" -ErrorAction SilentlyContinue
        if (-not ($I)) {
            New-PSDrive -Name "I" -PSProvider "FileSystem" -Root $uncPath > $null 2>&1
        }

        Write-Log "Now working on DB server!" -Scope
        
        Start-MOD-Services
    }
    #endregion
    
    #region --- starting APP
    Write-Log "Now working on APPLICATION server!" -Scope
    
    Show-MOD-Services
    #endregion
    
    Close-Session $DB
    Close-Session $FS
    Write-Log "Done with 3VM update!" -Level INFO
}
#endregion

#region --- Update-VM and Update-DB/Update-APP/Update-FS
function Update-VM {
    $VM = $env:MODULUS_SERVER
    switch ($VM) {
        "DB"    { Update-DB }
        "APP"   { Update-APP }
        "FS"    { Update-FS }
        "1VM"    { Update-1VM }
        Default { throw "Invalid environment variable: $VM" ; Write-Log "Invalid environment variable: $VM" -Level ERROR }
    }
}

function Update-DB {
    Write-Log "Update-DB" -Header
    Write-Log "Starting to update DB server!"

    Assert-MOD-Components -Silent

    #stopping services and cleanup
    Stop-MOD-Services
    Clear-PrepDir
    Clear-OnlineDataLogs
    Backup-OnlineData

    Prep-HFandLib
    Execute-GalaxisOracle-Jar
    Compile-GLX-Serial

    Open-MOD-Manual Manual

    #Install-Floorserver
    Install-QueryBuilder

    Assert-MOD-Components -Silent
    Write-Log "Finished updating DB server!" 
}

function Update-APP {
    Write-Log "Update-APP" -Header
    Write-Log "Starting to update APP server!"

    #stopping services and cleanup
    Stop-MOD-Services
    Clear-PrepDir
    Clear-GLXLogs    #-AskIF
    Backup-GLXDir    #-AskIF
    
    #preparing/staging
    Prep-Galaxis ALL #-AskIF
    Prep-SYSTM ALL #-AskIF
    Prep-Web
    #Prep-PlayerApp
    Prep-HFandLib
    #Prep-PlayWatch 
    
    Open-MOD-Manual Manual

    Close-GLXDirAccess
    Disable-M-Share

    Deploy-Galaxis ALL #-AskIf
    Deploy-SYSTM ALL #-AskIf
    Deploy-Web
    #Deploy-PlayerApp
    #Deploy-PlayWatch

    Enable-M-share

    Set-Web-Config
    #Set-PlayerApp-Config
    Set-Reverse-Proxy-Config
    #Set-PlayWatch-Config

    Install-MOD-Services
    Remove-1097-Artifacts

    Install-QueryBuilder #-AskIF
    Uninstall-JPApps #-AskIf
    Install-JPApps #-AskIf
    Set-JP-Config #-AskIF

    Assert-MOD-Components -Silent
    Write-Log "Finished updating APP server!"
}

function Update-FS {
    Write-Log "Update-FS" -Header
    Write-Log "Starting to update FLOOR server!"

    #stopping services and cleanup
    Stop-MOD-Services
    Clear-PrepDir
    Clear-OnlineDataLogs
    Backup-OnlineData

    #preparing/staging
    Prep-CRYSTALControl
    Prep-MBoxUI
    
    Open-MOD-Manual Manual

    Deploy-CRYSTALControl
    Deploy-MBoxUI

    Uninstall-CFCS
    Install-CFCS

    #Install-Floorserver
    Install-QueryBuilder
    
    Set-CRYSTALControl-Config
    Set-CFCS-Config

    #Set-Reverse-Proxy-Config
    
    Assert-MOD-Components -Silent
    Write-Log "Finished updating FLOOR server!" 
}

function Update-1VM {
    Write-Log "Update-1VM" -Header
    Write-Log "Starting to update 1VM server!"

    #stopping services and cleanup
    Stop-MOD-Services
    Clear-PrepDir
    Clear-GLXLogs    #-AskIF
    Clear-OnlineDataLogs
    Backup-GLXDir    #-AskIF
    Backup-OnlineData
    
    #preparing/staging
    Prep-Galaxis ALL #-AskIF
    Prep-SYSTM ALL #-AskIF
    Prep-Web
    #Prep-PlayerApp
    Prep-HFandLib
    #Prep-PlayWatch 
    
    Open-MOD-Manual Manual

    Close-GLXDirAccess
    Disable-M-Share

    Deploy-Galaxis ALL #-AskIf
    Deploy-SYSTM ALL #-AskIf
    Deploy-Web
    #Deploy-PlayerApp
    #Deploy-PlayWatch

    Deploy-CRYSTALControl
    Deploy-CFCS

    Enable-M-share

    Execute-GalaxisOracle-Jar
    Compile-GLX-Serial

    Set-Web-Config
    #Set-PlayerApp-Config
    Set-Reverse-Proxy-Config
    #Set-PlayWatch-Config

    Install-MOD-Services
    Remove-1097-Artifacts

    Uninstall-CFCS
    Install-CFCS
    Set-CFCS-Config

    Set-CRYSTALControl-Config

    #Install-FloorServer
    #Set-FS-Config

    Install-QueryBuilder #-AskIF
    Uninstall-JPApps #-AskIf
    Install-JPApps #-AskIf
    Set-JP-Config #-AskIF

    Assert-MOD-Components -Silent
    Write-Log "Finished updating 1VM server!"
}
#enregion

#region --- log-filtering-logic

#endregion

#Export-ModuleMember -Function * -Alias * -Variable *