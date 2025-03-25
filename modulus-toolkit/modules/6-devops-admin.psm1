# PSScriptAnalyzer disable PSAvoidUnapprovedVerbs

#tlukas, 22.10.2024

#check if toolkit is in elevated state
if (Get-ElevatedState) {
    #Write-Host "Loading 6-devops-admin.psm1!" -ForegroundColor Cyan
    #Continue loading the psm1
} else {
    #Skipping the rest of the file
    Return;
}

#rest of the file

#region --- Galaxis-related cleanup functions
function Recycle-GLX-1097 {

    #TODO rework:
    #should be limited to app-server:
    #if $ENV:MODULUS_SERVER -in (APP,1VM)

    Write-Host '>'
    Write-Host '> Clearing out some old stuff that its no longer used in 1097 going forward!'
    Write-Host '> Clearing out D:\Galaxis\Program\bin\GlxPublicApi\ recursively!'
	write-host '> Clearing out D:\Galaxis\Program\bin\nginx\public-api-reverse-proxy.conf!'
	write-host '> Clearing out D:\Galaxis\Program\bin\nginx\api-keys.conf!'
	write-host '> Clearing out D:\Galaxis\Program\bin\WinSW\GlxPublic*-stuff!'
    
    Remove-Item -path "D:\Galaxis\Program\bin\GlxPublicApi\" -Recurse -ErrorAction SilentlyContinue
	Remove-Item -path "D:\Galaxis\Program\bin\nginx\modulus\public-api-reverse-proxy.conf" -ErrorAction SilentlyContinue
    remove-item -path "D:\Galaxis\Program\bin\nginx\modulus\api-keys.conf" -ErrorAction SilentlyContinue
	Get-ChildItem -path "D:\Galaxis\Program\bin\WinSW\GlxPublic*" | remove-item -ErrorAction SilentlyContinue
	
    write-host " > Finished!"
}
#endregion

#region --- Closing file access on Galaxis directory
function Close-GLXDirAccess {

    #TODO: limit usage on APP, 1VM
	$galaxisDir = Get-GLXDir

	if(!(Test-Path $galaxisDir))
	{
		#write-Log -Level INFO -Message '$galaxisDir does not exist!'
		exit
	}
	
	$openFiles = Get-SmbOpenFile | Where-Object Path -Like "$galaxisDir*"
	
	#write-Log -Level INFO -Message 'Closing all open files in $galaxisDir'
	
	foreach($file in $openFiles)
	{
		Close-SmbOpenFile -FileId $file.FileId -force
	}

	#-Force not tested yet
	#without -Force a user-input is prompted
}

function Disable-M-Share {
    #TODO: limit usage on APP, 1VM
	$galaxisDir = Get-GLXDir
	$shareName = 'Galaxis'

	$galaxisShare = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue

	if($galaxisShare -ne $null)
	{
		Write-host 'Disabling the sharing of D:\Galaxis!'
		Remove-SmbShare -Name $shareName -Force
	}
}

function Enable-M-Share {
    #TODO: limit usage on APP, 1VM
	$galaxisDir = Get-GLXDir
	$shareName = 'Galaxis'
	$folderPath = 'D:\Galaxis'

	$galaxisShare = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue

	if($galaxisShare -eq $null)
	{
		Write-host 'Enabling the sharing of D:\Galaxis!'
		New-SmbShare -Name $shareName -Path $folderPath -FullAccess "Everyone"
	} else {
		Write-host 'D:\Galaxis is already shared!'
	}
}
#endregion

#region --- Galaxis cleanup scripts
function Clear-GLXLogs {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

	if ($AskIf) {
        $confirm = Read-Host "Are you sure you want to clear the logs? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Output "Clear-GLXLogs operation cancelled."
            return
        }
    }

	$sizeBefore = Get-ChildItem -Path "D:\Galaxis" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}

	write-host '-----------------------------------------------'
	write-host 'Size of D:\Galaxis before cleaning (in MB):  '$sizeBefore.'size(MB)'

	# clean RTDS logs
	# ALARM SERVER
	#mod-log "Cleaning out ALARM SERVER logs .."
	Remove-Item -Path D:\Galaxis\Application\OnLine\AlarmServer\Current\dat -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\Galaxis\Application\OnLine\AlarmServer\Current\log -Recurse -ErrorAction SilentlyContinue
	# SLOT MACHINE SERVER
	#mod-log "Cleaning out SLOT MACHINE SERVER logs .."
	Remove-Item -Path D:\Galaxis\Application\OnLine\SlotMachineServer\Current\dat -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\Galaxis\Application\OnLine\SlotMachineServer\Current\log -Recurse -ErrorAction SilentlyContinue
	# TRANSACTION SERVER
	#mod-log "Cleaning out TRANSACTION SERVER logs .."
	Remove-Item -Path D:\Galaxis\Application\OnLine\TransactionServer\Current\dat -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\Galaxis\Application\OnLine\TransactionServer\Current\log -Recurse -ErrorAction SilentlyContinue

	# clean GDC logs
	#mod-log "Cleaning out GDC logs .."
	Get-ChildItem -Path D:\Galaxis -Filter FullLog*.txt | Remove-Item -Recurse -ErrorAction SilentlyContinue -Force
	Get-ChildItem -Path D:\Galaxis -Filter ShortLog*.txt| Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 

	# clean GALAXIS logs
	#mod-log "Cleaning out Galaxis logs .."
	Remove-Item -Path D:\Galaxis\Log\* -Recurse -ErrorAction SilentlyContinue

	# todo JPS & SMOI -logs
	#mod-log "Cleaning out JPS and SMOI logs .."
	Get-ChildItem -Path D:\Galaxis\Program\StarSlots -Filter JPS-LogFile* | Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 
	Get-ChildItem -Path D:\Galaxis\Program\StarSlots -Filter JPS-Error-LogFile*  | Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 
	Get-ChildItem -Path D:\Galaxis\Program\StarSlots -Filter SMOI-LogFile*  | Remove-Item  -Recurse -ErrorAction SilentlyContinue -Force 

	#mod-log "Cleaning the APP server finished."
	#mod-log "---------------------------------"
	
	$sizeAfter = Get-ChildItem -Path "D:\Galaxis" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}
	
	
	write-host 'Size of D:\Galaxis after cleaning (in MB): '$sizeAfter.'size(MB)'
	write-host '-----------------------------------------------'
	
	$saved = $sizeBefore.'size(MB)' - $sizeAfter.'size(MB)'

	write-host 'Cleaned out (in MB): '$saved
	write-host '-----------------------------------------------'
}
#endregion

function Clear-GLXGarbage {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

	if ($AskIf) {
        $confirm = Read-Host "Are you sure you want to clear out the garbage? :D (Y/N)"
        if ($confirm -ne "Y") {
            Write-Output "Clear-GLXGarbage operation cancelled."
            return
        }
    }

	$sizeBefore = Get-ChildItem -Path "D:\Galaxis" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}

	write-host '-----------------------------------------------'
	write-host 'Size of D:\Galaxis before cleaning (in MB):  '$sizeBefore.'size(MB)'

	#region directly deleting
	#cleaning out C:\Galaxis\GalaxisTemp\*
	#mod-log "Cleaning out C:\Galaxis\GalaxisTemp\* .."
	Remove-Item -Path C:\Galaxis\GalaxisTemp\* -Recurse -ErrorAction SilentlyContinue

	# delete all *.err-files in D:\Galaxis
	#mod-log "Cleaning out *.err-files from D:\Galaxis .."
	Get-ChildItem -Path D:\Galaxis -Filter *.err -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item

	# delete all BDESC*-files in D:\Galaxis 
	#mod-log "Cleaning out BDESC*-files from D:\Galaxis .."
	Get-ChildItem -Path D:\Galaxis -Filter BDESC* -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item

	# delete all *minidump*-files in D:\Galaxis 
	#mod-log "Cleaning out *minidump*-files from D:\Galaxis .."
	Get-ChildItem -Path D:\Galaxis -Filter *minidump* -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item 
	
	$sizeAfter = Get-ChildItem -Path "D:\Galaxis" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}
	
	write-host 'Size of D:\Galaxis after cleaning (in MB): '$sizeAfter.'size(MB)'
	write-host '-----------------------------------------------'
	
	$saved = $sizeBefore.'size(MB)' - $sizeAfter.'size(MB)'

	write-host 'Cleaned out (in MB): '$saved
	write-host '-----------------------------------------------'
}

function Clear-OnlineDataLogs {
	[CmdletBinding()]
    param (
        [Parameter()]
        [switch]$AskIf
    )

	if ($AskIf) {
        $confirm = Read-Host "Are you sure you want to clear the logs? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Output "Clear-OnlineDataLogs operation cancelled."
            return
        }
    }

	$sizeBefore = Get-ChildItem -Path "D:\OnlineData" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}

	write-host '-----------------------------------------------'
	write-host 'Size of D:\OnlineData before cleaning (in MB):  '$sizeBefore.'size(MB)'

	
	Remove-Item -Path D:\OnlineData\log\ -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\OnlineData\nginx\logs\ -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\OnlineData\Relay\Logs\ -Recurse -ErrorAction SilentlyContinue
	Remove-Item -Path D:\OnlineData\Dbx\log -Recurse -ErrorAction SilentlyContinue
	Get-ChildItem -Path D:\OnlineData\Server -Filter server*.log -Recurse -ErrorAction SilentlyContinue -Force | Remove-Item 

	#mod-log "Cleaning the APP server finished."
	#mod-log "---------------------------------"
	
	$sizeAfter = Get-ChildItem -Path "D:\OnlineData" -Recurse -Force -ErrorAction SilentlyContinue | 
					Measure-Object -Property Length -Sum | 
					Select-Object @{Name="Size(MB)";Expression={$_.Sum/1mb}}
	
	
	write-host 'Size of D:\OnlineData after cleaning (in MB): '$sizeAfter.'size(MB)'
	write-host '-----------------------------------------------'
	
	$saved = $sizeBefore.'size(MB)' - $sizeAfter.'size(MB)'

	write-host 'Cleaned out (in MB): '$saved
	write-host '-----------------------------------------------'
}
#endregion

#region --- check for OEM Java and uninstall #TODO - needs to be part of deployment/prereq handling
function Check-OEMJava {

	Write-Host '>'
    Write-Host '> Checking for OEM Java installations!'

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
	
	D:
	$WinSW = "D:\Galaxis\Program\bin\WinSW\"
	cd $WinSW

	#should be in order of released services
	$nginx 		= Get-Service -displayName "nginx"			  -ErrorAction SilentlyContinue
	$aml	    = Get-Service -displayName "Galaxis AML*"	  -ErrorAction SilentlyContinue
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

    if(!$nginx)
	{
		.\nginx.exe install nginx.xml
		$nginx | Set-Service -StartupType Manual
	}

	if(!$aml)
	{
		.\amlservice.exe install amlservice.xml
		$aml | Set-Service -StartupType Manual
	}
	
	if(!$glxapi)
	{
		.\glxapi.exe install glxapi.xml
		$glxapi | Set-Service -StartupType Manual
	}

	if(!$notif)
	{
		.\notificationservice.exe install notificationservice.xml
		$notif | Set-Service -StartupType Manual
	}
	
	if(!$license)
	{
		.\licenseservice.exe install licenseservice.xml
		$license | Set-Service -StartupType Manual
	}

	if(!$tablesetup)
	{
		.\TableSetup.WindowsService.exe install TableSetup.WindowsService.xml
		$ngtablesetup| Set-Service -StartupType Manual
	}

	<#if(!$glxpublic)
	{
		.\GlxPublicApi.exe install GlxPublicApi.xml
		$glxpublic | Set-Service -StartupType Manual
	}
	#>

	if($glxpublic)
	{
		write-host "Removing Galaxis Public API service, it has been replaced with 10.97!"
		Remove-Service  $glxpublic.name 
	}

	<#
	if(!$glxpartner)
	{
		.\GlxPartnerApi.WindowsService.exe install GlxPartnerApi.WindowsService.xml
		$glxpartner | Set-Service -StartupType Manual
	}
	#>

	if(!$loyality)
	{
		.\LoyaltyService.WindowsService.exe install LoyaltyService.WindowsService.xml
		$loyality | Set-Service -StartupType Manual
	}

	if(!$outbox)
	{
		.\OutboxService.WindowsService.exe install OutboxService.WindowsService.xml
		$outbox | Set-Service -StartupType Manual
	}

	if(!$playerSer)
	{
		.\PlayerService.WindowsService.exe install PlayerService.WindowsService.xml
		$playerSer | Set-Service -StartupType Manual
	}

    if(!$DataSetSer)
	{
		.\DataSetupService.WindowsService.exe install DataSetupService.WindowsService.xml
		$DataSetSer | Set-Service -StartupType Manual
	}
    
    if(!$AssetSer) 
	{
		.\assetsservice.exe install assetsservice.xml
		$AssetSer | Set-Service -StartupType Manual
	}

	cd ~
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

    if ($AskIf) {
        $confirm = Read-Host "Do you want to prepare $Task (Y/N)?"
        if ($confirm -ne "Y") {
            Write-Output "Preparation skipped!"
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
            Default { throw "Invalid task: $Task" }
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

    if ($AskIf) {
        $confirm = Read-Host "Do you want to prepare $Task (Y/N)?"
        if ($confirm -ne "Y") {
            Write-Output "Preparation skipped!"
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
            Default { throw "Invalid task: $Task" }
        }
    }
}

function Prep-Executables {
    Write-host "Prepping Galaxis Executables!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep
    
    #old
    #$file = Get-ChildItem $sources *Executable*.7z
    #7z x $file.FullName -o"$prep\Executable only" Server\Galaxis\* #| write-verbose

    #new
    $filePattern = 'Galaxis*Executable*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\Executable only" -FilePattern $filePattern -Subfolder "Server\Galaxis\*"

    #post-extraction cleanup
    Move-Item $prep"\Executable Only\Server\Galaxis\*" $prep"\Executable only\"
    Remove-Item $prep"\Executable Only\Server\" -Recurse 
    Remove-Item $prep"\Executable Only\Docker\" -Recurse 
    Remove-Item $prep"\Executable Only\Install\Docker\" -Recurse 
    Remove-Item $prep"\Executable only\Install\inittab"
    Remove-Item $prep"\Executable only\Install\Batch\IDAPI32.cfg"
    Remove-Item $prep"\Executable only\Install\Batch\tnsnames.ora"
    Remove-Item $prep"\Executable only\Program\bin\WinSCard.dll"
    #Remove-Item $prep"\Executable only\Install\Batch\sqlnet.ora"

}

function Prep-Other {
    Write-Host "Prepping Galaxis Other!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    #old
    #$file = Get-ChildItem $sources *Other*.7z
    #7z x $file.FullName -o"$prep\Other only" Server\Galaxis\* #| write-verbose

    #new
    $filePattern = 'Galaxis*Other*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\Other only" -FilePattern $filePattern -Subfolder "Server\Galaxis\*"

    #post-extraction cleanup
    Move-Item $prep"\Other only\Server\Galaxis\*" $prep"\Other only\"
    Remove-Item $prep"\Other only\Server\" -Recurse
    Remove-Item $prep"\Other only\Docker\" -Recurse
    Remove-Item $prep"\Other only\Install\Docker\" -Recurse
    Remove-Item $prep"\Other only\Shortcut-Old organization" -Recurse
}

function Prep-Config {
    Write-host "Prepping Galaxis Config!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    #old
    #$file = Get-ChildItem $sources Galaxis*Config*.7z
    #7z x $file.FullName -o"$prep\Config only" Server\Galaxis\* #| write-verbose

    #new
    $filePattern = 'Galaxis*Config*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\Config only" -FilePattern $filePattern -Subfolder "Server\Galaxis\*"

    #post-extraction cleanup
    Move-Item $prep"\Config only\Server\Galaxis\*" $prep"\Config only\"
    Remove-Item $prep"\Config only\Server\" -Recurse
    Remove-Item $prep"\Config only\Docker\" -Recurse
}

function Prep-SYSTM-Executables {
    Write-Host "Prepping SYSTM Executables!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep
    
    #old
    #$file = Get-ChildItem $sources SYSTM*Executable*.7z
    #7z x $file.FullName -o"$prep\SYSTM Executable only" Server\Galaxis\* #| write-verbose

    #new
    $filePattern = 'SYSTM*Executable*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\SYSTM Executable only" -FilePattern $filePattern -Subfolder "Server\Galaxis\*"

    #post-extraction cleanup
    Move-Item $prep"\SYSTM Executable Only\Server\Galaxis\*" $prep"\SYSTM Executable only\"
    Remove-Item $prep"\SYSTM Executable Only\Server\" -Recurse 
}

function Prep-SYSTM-Config {
    Write-Host "Prepping SYSTM Config!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    #old
    #$file = Get-ChildItem $sources SYSTM*Config*.7z
    #7z x $file.FullName -o"$prep\SYSTM Config only" Server\Galaxis\* #| write-verbose

    #new
    $filePattern = 'SYSTM*Config*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\SYSTM Config only" -FilePattern $filePattern -Subfolder "Server\Galaxis\*"

    #post-extraction cleanup
    Move-Item $prep"\SYSTM Config only\Server\Galaxis\*" $prep"\SYSTM Config only\"
    Remove-Item $prep"\SYSTM Config only\Server\" -Recurse
    #Remove-Item $prep"\SYSTM Config only\Docker\" -Recurse
}

function Prep-Install {
    Write-Host "Prepping Install!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    #old
    #$file = Get-ChildItem $sources *Install*.7z
    #7z x $file.FullName -o"$prep\Install only\Install" #| write-verbose

    #new
    $filePattern = 'UnCompressOnGalaxisHomeInstall*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\Install Only" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"
    
    #post-extraction cleanup
    Remove-Item $prep"\Install Only\Docker\" -Recurse
}

#not really used anymore:
function Prep-Web {
    Write-Host "Prepping Galaxis Web!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    $filePattern = 'GalaxisWeb.1*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\Web only\Web\SYSTM" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"
    $filePattern = 'GalaxisWeb.Configuration*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\Web only\Web\SYSTM" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"

}

<#not really used anymore
function Prep-Docker {
    Write-Output "Prepping Docker!"

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    $file = Get-ChildItem $sources *Docker*.7z

    7z x $file.FullName -o"$prep\Docker only\Docker" #| write-verbose
}
#>

<#not really used anymore
function Prep-Classic {
    Write-Output "Prepping Classic!"

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    #check for Classic folder
    if(Test-Path -Path $sources"\Classic\" -PathType Container) {

        Write-Information "Classic folder exists, moving contents to sources directory!"
         
        Move-Item $sources"\Classic\Galaxis Classic v*.7z" -Destination $sources
        Remove-Item $sources"\Classic\" -Recurse
    }

    #if 7z is already in place - extract 7z
    if (Test-Path -Path $sources"\Galaxis Classic*.7z" -PathType Leaf) {
        
        Write-Information "Extracting Galaxis Classic*.7z!"
        
        $file = Get-ChildItem $sources "Galaxis Classic*.7z"

        7z x $file.FullName -o"$prep\Classic only\" 

        #post-extraction cleanup
        #pre 10.96-solution
        #Get-ChildItem $prep"\Classic only" $file.BaseName | Rename-Item -NewName "bin"
        #10.96 fix
        Get-ChildItem $prep"\Classic only" "Galaxis Classic*" | Rename-Item -NewName "bin"        

    } else {
        
        write-warning " "
        Write-Warning "No Galaxis Classic*.7z detected, looking for Classic folder or Classic.zip!"
        write-warning " "

        #if no 7z is in place, look for zip
        if(Test-Path -Path $sources"\Classic.zip" -PathType Leaf) {

            Write-Information "Extracting Classic.zip!"
            
            $file = Get-ChildItem $sources Classic.zip
            7z e $file.FullName -o"$prep\Classic only" #7z e to not extract the full folder-structure, I only need the 7z(and the txt)

            $file = Get-ChildItem $prep"\Classic only\" *Classic*.7z
            7z x $file.FullName -o"$prep\Classic only" 

            #post-extaction cleanup
            Remove-Item $prep"\Classic only\CheckSum.txt"
            Remove-Item $file.FullName
            Get-ChildItem $prep"\Classic only" $file.BaseName | Rename-Item -NewName "bin"

        }
        else {
            write-warning " "
            Write-Warning "No Classic.zip detected, aborting script!"
            write-warning " "
            exit;
        }
    }

    #extract nginx
    if(Test-Path -Path $sources"\nginx-*.zip" -PathType Leaf) {
        
        Write-Information "Extracting *nginx-*.zip!"
        
        $file = Get-ChildItem $sources *nginx-*.zip
        7z x $file.FullName -o"$prep\Classic only" 

        #post-extaction cleanup
        #TODO: weird logic, could be cleaner -> move and overwrite?!
        Get-ChildItem $prep"\Classic only" $file.BaseName | Rename-Item -NewName "nginx"
        Remove-Item $prep"\Classic only\nginx\conf\nginx.conf"
        Move-Item $prep"\Classic only\nginx\conf\*" $prep"\Classic only\bin\nginx\conf" 
        Remove-item $prep"\Classic only\nginx\conf" -Recurse
        Move-Item $prep"\Classic only\nginx\*" $prep"\Classic only\bin\nginx" 
        Remove-Item $prep"\Classic only\nginx" -Recurse
     
    } else {
        write-warning " "
        Write-Warning "No *nginx-*.zip detected, please provide an nginx-version!"
        write-warning " "
        #exit;
    }

    #Classic only done.
    #nginx done.
    
    #Now for the individual services:
    $AmlService             = "$prep\Classic only\bin\AmlService"
    $GalaxisApi             = "$prep\Classic only\bin\GalaxisApi"
    $LicenseService         = "$prep\Classic only\bin\LicenseService"
    $NotificationService    = "$prep\Classic only\bin\NotificationService"
    $TableSetupService      = "$prep\Classic only\bin\TableSetupService"
    $GlxPublicAPi           = "$prep\Classic only\bin\GlxPublicApi"

    #prepare AMLService-folder
    ##########################
    $binaries = Get-ChildItem $AmlService AmlService.1*.7z
    $config   = Get-ChildItem $AmlService AmlService.Config*.7z
    
    7z x $binaries.FullName -o"$AmlService"
    7z x $config.FullName   -o"$AmlService" appsettings.json

    #post-extraction cleanup
    Remove-Item $binaries.FullName  
    Remove-Item $config.FullName
    

    #prepare GalaxisApi-folder
    ##########################
    $binaries = Get-ChildItem $GalaxisApi GlxApi.1*.7z
    $config   = Get-ChildItem $GalaxisApi GlxApi.Config*.7z
    
    7z x $binaries.FullName -o"$GalaxisApi" 
    7z x $config.FullName   -o"$GalaxisApi" appsettings.json

    #post-extraction cleanup
    Remove-Item $binaries.FullName  
    Remove-Item $config.FullName


    #prepare LicenseService-folder
    ##############################
    $binaries = Get-ChildItem $LicenseService LicenseServer.1*.7z
    $config   = Get-ChildItem $LicenseService LicenseServer.Config*.7z
    
    7z x $binaries.FullName -o"$LicenseService" 
    7z x $config.FullName   -o"$LicenseService" appsettings.json

    #post-extraction cleanup
    Remove-Item $binaries.FullName  
    Remove-Item $config.FullName


    #prepare NotificationService-folder
    ###################################
    $binaries = Get-ChildItem $NotificationService NotificationService.1*.7z
    $config   = Get-ChildItem $NotificationService NotificationService.Config*.7z
    
    7z x $binaries.FullName -o"$NotificationService" 
    7z x $config.FullName   -o"$NotificationService" appsettings.json

    #post-extraction cleanup
    Remove-Item $binaries.FullName  
    Remove-Item $config.FullName


    #added with 10.91
    #prepare TableSetupService-folder
    #################################
    $binaries = Get-ChildItem $TableSetupService TableSetupService.1*.7z
    $config   = Get-ChildItem $TableSetupService TableSetupService.Config*.7z
    
    7z x $binaries.FullName -o"$TableSetupService" 
    7z x $config.FullName   -o"$TableSetupService" appsettings.json

    #post-extraction cleanup
    Remove-Item $binaries.FullName  
    Remove-Item $config.FullName

    
    #added with 10.94
    #prepare GlxPublicAPi-folder
    #################################
    $binaries = Get-ChildItem $GlxPublicAPi .1*.7z
    $config   = Get-ChildItem $GlxPublicAPi GlxPublicApi.Config*.7z
    
    7z x $binaries.FullName -o"$GlxPublicAPi" 
    7z x $config.FullName   -o"$GlxPublicAPi" appsettings.json

    #post-extraction cleanup
    Remove-Item $binaries.FullName  
    Remove-Item $config.FullName
    

    #finalizing Galaxis-conform folder structure
    md $prep"\Classic only\Program"
    Move-Item $prep"\Classic only\bin\" $prep"\Classic only\Program\."
    Remove-Item $prep"\Classic Only\Program\bin\ServicesToStart.xml" -ErrorAction SilentlyContinue
    Remove-Item $prep"\Classic Only\Program\bin\nginx\modulus\public-api-reverse-proxy.conf" -ErrorAction SilentlyContinue

}
#>

function Prep-HFandLib {
    Write-Host "Prepping Hotfix scripts and Java library!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep
    
    #old
    #$file = Get-ChildItem $sources *Executable*.7z
    #7z x $file.FullName -o"$prep\HFandLib" "Database\Program Files\MIS\Program\Database\lib\galaxisoracle.jar" #| write-verbose
    #7z x $file.FullName -o"$prep\HFandLib" "Database\Program Files\MIS\Program\Database\Script\Script*.sql" #| write-verbose

    #new
    $filePattern = 'Galaxis*Executable*.7z'                                                                    # "'  double apostrophe  '" is important here
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\HFandLib" -FilePattern $filePattern -Subfolder "'Database\Program Files\MIS\Program\Database\*'"
     
    #post-extraction cleanup
    Move-Item "$prep\HFandLib\Database\Program Files\MIS\Program\Database\Script\Script*.sql" $prep"\HFandLib\"
    Move-Item "$prep\HFandLib\Database\Program Files\MIS\Program\Database\lib\galaxisoracle.jar" $prep"\HFandLib\"
    Remove-Item $prep"\HFandLib\Database\" -Recurse 

    write-host "Output can be found in HFandLib, only a few files were taken from above mentioned 7z!" -ForegroundColor Green
    
}

#endregion

#region --- prepare MBoxUI package
function Prep-MBoxUI {
    Write-Host "Prepping MboxUI!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    <#i will no longer handle the folders, people need to know what the toolkit exepcts
    #check for MboxUI folder
    if(Test-Path -Path $sources"\MboxUI\" -PathType Container) {

        Write-Information "MboxUI folder exists, moving contents to sources directory!"
        
        #new-item $sources"\MboxUI\" -ItemType Directory -ErrorAction SilentlyContinue
        move-Item $sources"\MboxUI\*" -Destination $sources
        Remove-Item $sources"\MboxUI\" -Recurse
    } elseif (Test-Path -Path $sources"\MboxUI*.zip" -PathType Leaf) { 
       
        $file = Get-ChildItem $sources *MboxUI*.zip
        
        7z x $file.FullName -o"$sources" #| write-verbose
        move-Item $sources"\MboxUI\*" -Destination $sources
        Remove-Item $file.FullName -ErrorAction SilentlyContinue
        Remove-Item $sources"\MboxUI\" -Recurse -ErrorAction SilentlyContinue
    }
    #>

    #old
    #extract binaries + config together
    #$folder = Get-ChildItem $sources MBoxUI*.7z
    #
    #foreach($archive in $folder)
    #{
    #    7z x $archive.FullName -o"$prep\MBoxUI"  
    #    #Remove-Item $archive.FullName
    #}

    #new
    $filePattern = 'MBoxUI.1*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\MBoxUI" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"
    $filePattern = 'MBoxUI.Configuration*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\MBoxUI" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"

}

#endregion

#region --- prepare PlayWatch package
function Prep-PlayWatch {
    Write-host "Prepping PlayWatch!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep

    <#folder handling no longer supported
    #check for MboxUI folder
    if(Test-Path -Path $sources"\PlayWatch\" -PathType Container) {

        Write-Information "PlayWatch folder exists, moving contents to sources directory!"
        
        #new-item $sources"\PlayWatch\" -ItemType Directory -ErrorAction SilentlyContinue
        move-Item $sources"\PlayWatch\*" -Destination $sources
        Remove-Item $sources"\PlayWatch\" -Recurse
    } elseif (Test-Path -Path $sources"\PlayWatch*.zip" -PathType Leaf) { 
       
        $file = Get-ChildItem $sources *PlayWatch*.zip
        
        7z x $file.FullName -o"$sources" #| write-verbose
        move-Item $sources"\PlayWatch\*" -Destination $sources -ErrorAction SilentlyContinue
        Remove-Item $file.FullName -ErrorAction SilentlyContinue
        Remove-Item $sources"\PlayWatch\" -Recurse -ErrorAction SilentlyContinue
    }

    #>

    #old
    #extract binaries + config together
    #$process = Get-ChildItem $sources RgMonitorProcess*.7z
    #$website = Get-ChildItem $sources RgMonitorWebsite*.7z

    #7z x $process.FullName -o"$prep\PlayWatch\Process"  
    #7z x $website.FullName -o"$prep\PlayWatch\Website"  

    #new
    $filePattern = 'RgMonitorProcess*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\PlayWatch\Process" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"
    $filePattern = 'RgMonitorWebsite*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\PlayWatch\Website" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"

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
        Deploy-Executables
        Deploy-Config
        Deploy-Other
    } else {
        switch ($Task) {
            "Executables"{ Deploy-Executables }
            "Config"    { Deploy-Config }
            "Other"     { Deploy-Other }
            "Install"   { Deploy-Install }
            Default { throw "Invalid task: $Task" }
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
    Write-host "Deploying Executables!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter Executable* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-Executables_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname
    
    <#mod-copy-option
    #$params = '/E /IM /IS /IT'
    #$logname = "$logs\Deploy-Executables"
    mod-copy -Source $package -Destination $Galaxis -CommonRobocopyParams $params -verbose      #very slow
    mod-copy -Source $package -Destination $Galaxis                          #standard params, default logging, does not overwrite (MIR)
    mod-copy -Source $package -Destination $Galaxis -CustomLogPath $logname  #standard params, custom logging, does not overwrite (MIR)
    #>
    
    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

function Deploy-Config {
    Write-host "Deploying Config!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter Config* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-Config_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /XC /XN /XO - only copy non-existing files!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /XC /XN /XO /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

function Deploy-Other {
    write-host "Deploying Other!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter Other* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-Other_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /XC /XN /XO - only copy non-existing files!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /XC /XN /XO /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

function Deploy-Install {
    write-host "Deploying Install!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter Install* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-Install_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

function Deploy-Web {
    write-host "Deploying Web!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    #TODO - Web vs SYSTM handling

    $package = Get-ChildItem $prep -filter Web* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-Web_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}
<#not really used any more
function Deploy-Docker {
    Write-Output "Deploying Docker!"

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter Docker* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-Docker_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    np $logs\$logname

}
#>

function Deploy-SYSTM-Executables {
    write-host "Deploying SYSTM Executables!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter SYSTM*Executable* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-SYSTM-Executables_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname
    
    <#mod-copy-option
    #$params = '/E /IM /IS /IT'
    #$logname = "$logs\Deploy-Executables"
    mod-copy -Source $package -Destination $Galaxis -CommonRobocopyParams $params -verbose      #very slow
    mod-copy -Source $package -Destination $Galaxis                          #standard params, default logging, does not overwrite (MIR)
    mod-copy -Source $package -Destination $Galaxis -CustomLogPath $logname  #standard params, custom logging, does not overwrite (MIR)
    #>

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

function Deploy-SYSTM-Config {
    write-host "Deploying SYSTM Config!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter SYSTM*Config* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-SYSTM-Config_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /XC /XN /XO - only copy non-existing files!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /XC /XN /XO /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

<#not really used any more
function Deploy-Classic {
    Write-Output "Deploying Classic!"

    $prep    = (Get-PSConfig).directories.prep
    $Galaxis = (Get-PSConfig).directories.Galaxis
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter Classic* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-Classic_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $Galaxis /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    np $logs\$logname

}
#>

function Deploy-PlayWatch {
    write-host "Deploying PlayWatch!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep
    $PlayWatch = "D:\PlayWatch"
    $logs    = (Get-PSConfig).directories.logs
    
    $package = Get-ChildItem $prep -filter PlayWatch* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-PlayWatch_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $PlayWatch /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

#endregion

#region --- preparing Floorserver binaries for deployment
function Prep-CRYSTALControl {
    [CmdletBinding()]
    param(
        [switch]$withoutConfig
    )

    Write-host "Prepping CRYSTAL Control!" -ForegroundColor Yellow

    $sources = (Get-PSConfig).directories.sources
    $prep    = (Get-PSConfig).directories.prep 
    
    #old
    #$file = Get-ChildItem $sources *Crystal_Control*.7z
    #7z x $file.FullName -o"$prep\Control"  # Server\Galaxis\* #| write-verbose

    #new
    $filePattern = 'Crystal_Control*.7z'
    Extract-7ZipFile -SourceFolder $sources -TargetFolder "$prep\Control" -FilePattern $filePattern #-Subfolder "Server\Galaxis\*"

    #post-extraction cleanup if withoutConfig-flag is given
    if ($withoutConfig) {
        Remove-Item $prep"\Control\bin\control\ControlLauncher.exe.config" 
        Remove-Item $prep"\Control\bin\control\log4net.config" 
        write-host "Info: withoutConfig flag was given, the 2 configuration files were therefore removed!" -ForegroundColor Yellow
    }

}
#endregion

#region --- deploying already prepared Floorserver packages into Live
function Deploy-CRYSTALControl {
    write-host "Deploying CRYSTAL Control!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow

    $prep    = (Get-PSConfig).directories.prep 
    $OLData  = (Get-PSConfig).directories.OnlineData
    $logs    = (Get-PSConfig).directories.logs

    $package = Get-ChildItem $prep -filter Control* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-CRYSTAL_Control_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    robocopy $package $OLData /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

function Deploy-MBoxUI {
    write-host "Deploying MBoxUI!" -ForegroundColor Yellow
    write-host "Full logs are available at:" -ForegroundColor Yellow


    $prep       = (Get-PSConfig).directories.prep
    $OnlineData = (Get-PSConfig).directories.OnlineData+'/IIS/MBoxUI/'
    $logs       = (Get-PSConfig).directories.logs
    
    #TODO - Web vs SYSTM handling

    $package = Get-ChildItem $prep -filter MBoxUI* -Attributes Directory | % { $_.FullName }
    $logname = 'Deploy-MBoxUI_'+(Get-Date -Format 'yyyy-MM-dd-hh-mm')+'.log'

    #robocopy-option
    #									           /IM /IS /IT - overwrite everything!
    robocopy $package $OnlineData /E /Z /ZB /R:5 /W:5 /IM /IS /IT /ndl /Log:$logs\$logname

    Write-Host "Please verify the deployment result:" -ForegroundColor Green
    get-content $logs\$logname -tail 11

}

#endregion

#region --- uninstalling/installing JP applications 
function Uninstall-JPApps {
    [CmdletBinding()]
    param(
        [switch]$AskIf
    )

    $count = 0

    $JPApp = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Applications'
    if ($JPApp) {
        $name    = $JPApp.Name
        $version = $JPApp.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }
    
    $JPRep = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Reporting'
    if ($JPRep) {
        $name    = $JPRep.Name
        $version = $JPRep.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    $SecSrv = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT SecurityServer Configuration'
    if ($SecSrv) {
        $name    = $SecSrv.Name
        $version = $SecSrv.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    if($count -eq 0) {
        Write-host "No JP Apps installed!"
        Return
    }

    if ($AskIf) {
        write-host "Deinstalling JP Applications:"
        write-host "-----------------------------"
        write-host "We will uninstall (if installed) the following applications:"
        write-host " - JP Applications"
        write-host " - JP Reporting"
        write-host " - SecurityServer Configuration"
        write-host "-----------------------------"
        $confirm = Read-Host "Do you want to proceed with the deinstallation?"
        if ($confirm -ne "Y") {
            Write-Output "Deinstallation aborted!"
            write-host "-------------------------"
            return
        }
    }

    if ($JPApp) {
        $name    = $JPApp.Name
        $version = $JPApp.version
        Write-host "Deinstalling $name, version $version!"
        
        Invoke-CimMethod -InputObject $JPApp -name Uninstall
        
        $folder = (Get-MOD-Component -module "Jackpot Configuration").path
        if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
    }
    
    if ($JPRep) {
        $name    = $JPRep.Name
        $version = $JPRep.version
        Write-host "Deinstalling $name, version $version!"
        
        Invoke-CimMethod -InputObject $JPRep -name Uninstall

        $folder = (Get-MOD-Component -module "Jackpot Reporting").path
        if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
    }

    if ($SecSrv) {
        $name    = $SecSrv.Name
        $version = $SecSrv.version
        Write-host "Deinstalling $name, version $version!"

        Invoke-CimMethod -InputObject $SecSrv -name Uninstall

        $folder = (Get-MOD-Component -module "SecurityServer Configuration").path
        if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
    }
    write-host "--------------------------"
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

    #check if we have inis in sources
    $sources = (Get-PSConfig).directories.sources
    $logs    = (Get-PSConfig).directories.logs
    $logs    = $logs.Replace('/','\')
    $JPApps_msi = Get-ChildItem $sources SetupJPApplications.msi
    $JPRep_msi = Get-ChildItem $sources SetupJPReporting.msi
    $SecSrv_msi = Get-ChildItem $sources SetupSecurityServerConfig.msi

    $count = 0
    if($JPApps_msi) { $count = $count + 1 }
    if($JPRep_msi)  { $count = $count + 1 }
    if($SecSrv_msi) { $count = $count + 1 }

    if ($count -eq 0) { 
        write-host "We did not find any JP-related .msi's in $sources! Please provide the installers and try again!"
        Return
    }

    if ($AskIf) {
        write-host "Installing JP Applications:"
        write-host "---------------------------"
        write-host "We will install the following applications:"
        if($JPApps_msi){ write-host " - JP Applications:              "$JPApps_msi.Name }
        if($JPRep_msi) { write-host " - JP Reporting:                 "$JPRep_msi.Name }
        if($JPRep_msi) { write-host " - SecurityServer Configuration: "$SecSrv_msi.Name }
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

    $count = 0

    $JPApp = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Applications'
    if ($JPApp) {
        $name    = $JPApp.Name
        $version = $JPApp.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    $JPRep = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Reporting'
    if ($JPRep) {
        $name    = $JPRep.Name
        $version = $JPRep.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    $SecSrv = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT SecurityServer Configuration'
    if ($SecSrv) {
        $name    = $SecSrv.Name
        $version = $SecSrv.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }
    write-host "--------------------------"

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
    
    write-host "JP APPS Installation finished!"
    if ($Result) { 
        $JPApp = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Applications'
        if ($JPApp) {
            $name    = $JPApp.Name
            $version = $JPApp.version
            Write-host "Currently installed: $name, version $version!"
            $count = $count + 1
        }

        $JPRep = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT Jackpot Reporting'
        if ($JPRep) {
            $name    = $JPRep.Name
            $version = $JPRep.version
            Write-host "Currently installed: $name, version $version!"
            $count = $count + 1
        }

        $SecSrv = Get-CimInstance -class win32_product | Where-Object name -eq 'IGT SecurityServer Configuration'
        if ($SecSrv) {
            $name    = $SecSrv.Name
            $version = $SecSrv.version
            Write-host "Currently installed: $name, version $version!"
            $count = $count + 1
        }
        write-host "--------------------------"
    }
    #cleaning start menu
    $IGT_startmenu    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IGT'
    $Spielo_startmenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Spielo'
    if(Test-Path $IGT_startmenu)    { Remove-Item $IGT_startmenu -Recurse -Force }
    if(Test-path $Spielo_startmenu) { Remove-Item $Spielo_startmenu -Recurse -Force }
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


    #check if we have inis in sources
    $sources = (Get-PSConfig).directories.sources
    $logs    = (Get-PSConfig).directories.logs
    $logs    = $logs.Replace('/','\')
    
    $FS_msi = Get-ChildItem $sources Floorserver-Setup*.msi

    $count = 0
    if($FS_msi) { $count = $count + 1 }

    if ($count -eq 0) { 
        write-host "We did not find any FS related .msi's in $sources! Please provide the installers and try again!"
        Return
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
}

function Install-QueryBuilder {
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
    $sources = (Get-PSConfig).directories.sources
    $logs    = (Get-PSConfig).directories.logs
    $logs    = $logs.Replace('/','\')
    
    $QB_msi = Get-ChildItem $sources QueryBuilder-Setup*.msi

    $count = 0
    if($QB_msi)  { $count = $count + 1 }

    if ($count -eq 0) { 
        write-host "We did not find any QB related .msi's in $sources! Please provide the installers and try again!"
        Return
    }

    if ($AskIf) {
        write-host "Installing/updating QB!"
        write-host "-----------------------"
        write-host "We will install the following applications:"
        if($QB_msi) { write-host " - QueryBuilder:             "$QB_msi.Name }
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

    $count = 0

    $QB_install = Get-CimInstance -class win32_product | Where-Object name -eq 'GTECH Query Builder'
    if ($QB_install) {
        $name    = $QB_install.Name
        $version = $QB_install.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }
    write-host "Updating Query Builder to new version"

    #Query Builder
    $folder = (Get-MOD-Component -Tool "QueryBuilder").path
    $folder = $folder.Replace('/','\')
    $log    = $logs + "\QueryBuilder_log.txt"
    #$ArgumentsMSI ='/i ' + '"' + $JPRep_msi.FullName + '" ' + '/qn ' + 'SITEURL=xxx SELECTED_xx_ENVIRONMENT=xxxcom ADMIN_xx_EDITBOX_VALUE=xxx IS_ENCRYPTED=0 LOGOFILE=xxx SSPR_URL=xxx SSO_ENABLED=0 PASSWORD_SYNC_ENABLED=1 TECUNIFY_CHECKBOX_STATE=0 UPS_ENABLED=0 UTM_ENABLED=0 LOCALUSER=1 DOMAINUSER=1 MICROSOFTUSER=1 AZUREUSER=1 PKPENABLE=xx OFFLINE_ENABLED=1 FAILOPEN=0 OFFLINE_MAX_TRIES_LIMIT=5 SELECTED_UAC_OPTION=1 CONTACT_INFO=xxx'
    $ArgumentsMSI ='/i ' + '"' + $QB_msi.FullName + '" ' + '/qn ' + 'INSTALLDIR="' + $folder + '" /L* ' + $log
    #write-host 'Output arguments and verify first'
    #Write-Host $ArgumentsMSI
    Start-Process -FilePath "msiexec.exe" -Wait -ArgumentList $ArgumentsMSI
    
    write-host "QB Installation finished!"
    if ($Result) { 
    
        $QB_install = Get-CimInstance -class win32_product | Where-Object name -eq 'GTECH Query Builder'
        if ($QB_install) {
            $name    = $QB_install.Name
            $version = $QB_install.version
            Write-host "Currently installed: $name, version $version!"
            $count = $count + 1
        }
        write-host "--------------------------"
    }
    #cleaning start menu
    $IGT_startmenu    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IGT'
    $Spielo_startmenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Spielo'
    if(Test-Path $IGT_startmenu)    { Remove-Item $IGT_startmenu -Recurse -Force }
    if(Test-path $Spielo_startmenu) { Remove-Item $Spielo_startmenu -Recurse -Force }

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
    cd D:\Galaxis\Install\Batch\

    .\SETUP_RABBITMQ.bat %GALAXIS_HOME%\Install\Batch\
    #wait for rabbitmq running
    Start-Sleep 10
    .\SETUP_RABBITMQ_MANAGEMENT.bat mis mis
    #todo: variable for mis-pw, since not all customers do have mis/mis :D
    
    Set-Service -Name "RabbitMQ" -StartupType Automatic

    cd $cwd

    write-host "Reinstallation finished!"

}

#endregion

#region --- uninstalling/installing CFCS
function Uninstall-CFCS {
    [CmdletBinding()]
    param(
        [switch]$AskIf
    )

    $count = 0

    $CFCS = Get-CimInstance -class win32_product | Where-Object name -eq 'Spielo CRYSTAL Floor Communication Service'
    if ($CFCS) {
        $name    = $CFCS.Name
        $version = $CFCS.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }

    if($count -eq 0) {
        Write-host "No CFCS installed!"
        Return
    }

    if ($AskIf) {
        write-host "Deinstalling CFCS:"
        write-host "-----------------------------"
        write-host "We will uninstall (if installed) the following applications:"
        write-host " - Spielo CRYSTAL Floor Communication Service"
        write-host "-----------------------------"
        $confirm = Read-Host "Do you want to proceed with the deinstallation?"
        if ($confirm -ne "Y") {
            Write-Output "Deinstallation aborted!"
            write-host "-------------------------"
            return
        }
    }

    $name    = $CFCS.Name
    $version = $CFCS.version
    Write-host "Deinstalling $name, version $version!"
    
    Invoke-CimMethod -InputObject $CFCS -name Uninstall

    $folder = (Get-MOD-Component -module "CRYSTAL Floor Communication Service").path
    if(Test-Path $folder) { Remove-Item $folder -Recurse -Force}
   
    write-host "--------------------------"
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

    #check if we have inis in sources
    $sources = (Get-PSConfig).directories.sources
    $logs    = (Get-PSConfig).directories.logs
    $logs    = $logs.Replace('/','\')
    $CFCS_msi = Get-ChildItem $sources 'CRYSTAL Floor Communication Service*.msi'


    $count = 0
    if($CFCS_msi) { $count = $count + 1 }
 

    if ($count -eq 0) { 
        write-host "We did not find a CFCS*.-msi in $sources! Please provide the installers and try again!"
        Return
    }

    if ($AskIf) {
        write-host "Installing CFCS:"
        write-host "----------------"
        write-host "We will install the following applications:"
        if($CFCS_msi){ write-host " - CFCS:              "$CFCS_msi.Name }
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

    $count = 0

    $CFCS = Get-CimInstance -class win32_product | Where-Object name -eq 'Spielo CRYSTAL Floor Communication Service'
    if ($CFCS) {
        $name    = $CFCS.Name
        $version = $CFCS.version
        Write-host "Currently installed: $name, version $version!"
        $count = $count + 1
    }
    write-host "--------------------------"

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

    
    write-host "Installation finished!"
    if ($Result) { 
        $CFCS = Get-CimInstance -class win32_product | Where-Object name -eq 'Spielo CRYSTAL Floor Communication Service'
        if ($CFCS) {
            $name    = $CFCS.Name
            $version = $CFCS.version
            Write-host "Currently installed: $name, version $version!"
            $count = $count + 1
        }
        write-host "--------------------------"
    }

    #cleaning start menu
    $IGT_startmenu    = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\IGT'
    $Spielo_startmenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Spielo'
    if(Test-Path $IGT_startmenu)    { Remove-Item $IGT_startmenu -Recurse -Force }
    if(Test-path $Spielo_startmenu) { Remove-Item $Spielo_startmenu -Recurse -Force }

    write-host "--------------------------"
}

#endregion

#region --- mapping modulus shares
function Map-I-share {
    
    $hostname = Get-MOD-APP-hostname
    $sharePath = "\\"+$hostname+"\I"
    $connected = Test-Path I: -ErrorAction SilentlyContinue

    #todo: add installation directory variable

    if (-not $connected) {
        Write-Host "> Mapping the I: share!"
        New-PSDrive -Name I -PSProvider FileSystem -Root $sharePath -Persist -Scope Global
        if (Test-Path I:) {
            Write-Host " > I: share mapped successfully."
        } else {
            Write-Host " > Failed to map I: share!"
        }
    } else {
        Write-Host " > The I: share is already mapped."
    } 
}
function Map-M-share {

    $hostname = Get-MOD-APP-hostname
    $sharePath = "\\"+$hostname+"\Galaxis"
    $connected = Test-Path M: -ErrorAction SilentlyContinue

    if (-not $connected) {
        Write-Host "> Mapping the M: share!"
        New-PSDrive -Name M -PSProvider FileSystem -Root $sharePath -Persist -Scope Global
        if (Test-Path M:) {
            Write-Host " > M: share mapped successfully."
        } else {
            Write-Host " > Failed to map M: share!"
        }
    } else {
        Write-Host " > The M: share is already mapped."
    } 
}
#endregion

#region --- toolkit/tnsnames.ora/sqlnet.ora/QB-config -> deploy to APP/FS
function Deploy-Toolkit {

    Write-Host '>'
    Write-Host '> Deploying modulus-toolkit from DB to APP and FS!'

    $APPserver = Get-MOD-APP-hostname
    $APPserver = "\\$APPserver\"

    $FServer   = Get-MOD-FS-hostname
    $FServer   = "\\$FServer\"

    $source      = 'C:\Program Files\PowerShell\Modules\modulus-toolkit\*'
    $destination = 'C$\Program Files\PowerShell\Modules\modulus-toolkit\'

    write-host " > Copying modulus-toolkit from $source to:"
    "  > $APPserver$destination"
    "  > $FServer$destination" 
    "  > C$\Program Files\PowerShell\Modules\modulus-toolkit\"

    copy-item -path $source -Destination "$APPserver$destination" -Recurse -Force 
    copy-item -path $source -Destination "$FServer$destination" -Recurse -Force
    " > Finished!"
}

function Deploy-Oracle-Config {

    Write-Host '>'
    Write-Host '> Deploying Oracle configuration from DB to APP and FS!'

    $APPserver = Get-MOD-APP-hostname
    $APPserver = "\\$APPserver\"

    $FServer   = Get-MOD-FS-hostname
    $FServer   = "\\$FServer\"

    $source      = 'C:\Oracle\client32\network\admin\*.ora'
    $destination = 'C$\Oracle\client32\network\admin\'

    write-host " > Copying Oracle configuration from $source to:"
    "  > $APPserver$destination"
    "  > $FServer$destination" 
    "  > D:\Oracle\Ora19c\network\admin\"

    copy-item -path $source -Destination "$APPserver$destination" -Recurse -Force 
    copy-item -path $source -Destination "$FServer$destination" -Recurse -Force
    copy-item -path $source -Destination "$APPserver\D$\Galaxis\Install\Batch\" -Force

    #late addition
    copy-item -path $source -Destination "D:\Oracle\Ora19c\network\admin\" -Force

    " > Finished!"
}

function Deploy-hosts {

    Write-Host '>'
    Write-Host '> Deploying Windows hosts file from DB to APP and FS!'

    $APPserver = Get-MOD-APP-hostname
    $APPserver = "\\$APPserver\"

    $FServer   = Get-MOD-FS-hostname
    $FServer   = "\\$FServer\"

    $source      = 'C:\Windows\System32\drivers\etc\hosts'
    $destination = 'C$\Windows\System32\drivers\etc\'

    write-host " > Copying Windows hosts file from $source to:"
    "  > $APPserver$destination"
    "  > $FServer$destination" 

    copy-item -path $source -Destination "$APPserver$destination" -Recurse -Force 
    copy-item -path $source -Destination "$FServer$destination" -Recurse -Force

    " > Finished!"
        
}

function Deploy-QB-Config {

    Write-Host '>'
    Write-Host '> Deploying Query Builder config file from DB to APP and FS!'

    $APPserver = Get-MOD-APP-hostname
    $APPserver = "\\$APPserver\"

    $FServer   = Get-MOD-FS-hostname
    $FServer   = "\\$FServer\"

    $source      = 'D:\OnlineData\cfg\qb.cfg'
    $destination = 'D$\OnlineData\cfg\'

    write-host " > Copying Query Builder config file from $source to:"
    "  > $APPserver$destination"
    "  > $FServer$destination" 

    copy-item -path $source -Destination "$APPserver$destination" -Recurse -Force 
    copy-item -path $source -Destination "$FServer$destination" -Recurse -Force

    " > Finished!"
        
}

#endregion

#region --- configure DB server "modules"
function Set-SecurityServer-Config {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "Configuring SecurityServer!" -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow

    $DBhostname = Get-MOD-DB-hostname
    $DBofficeIP = (Get-MOD-DB-OFFICE-NIC).IPAddress
    $DBalias    = (Get-MOD-GeneralSettings).databases.JKP_DB
    $DBuser     = (Get-MOD-GeneralSettings).database_users.security

    $config = Get-MOD-Component-Config "SecurityServer" "Server.Properties"

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-Content -Path $config

    # Iterate over each line and find the line containing the property
    for ($i = 0; $i -lt $content.Count; $i++) {
        
        $line = $content[$i]
        #user
        if ($line -match "^user\s*=") {
            # Modify the value of the property
                          #"max_connections     = 10"
            $content[$i] = "user                = $DBuser"
            Write-Host ' > Setting user ='$DBuser -ForegroundColor Green
            #break
        }
        #thin_connect
        if ($line -match "^thin_connect\s*=") {
            # Modify the value of the property
                          #"max_connections     = 10"
            $content[$i] = "thin_connect        = jdbc:oracle:thin:@"+$DBhostname+":1521:"+$DBalias
            Write-Host ' > Setting thin_connect ='$DBhostname':1521:'$DBalias -ForegroundColor Green
            #break
        }
        #boss_address
        if ($line -match "^boss_address\s*=") {
            # Modify the value of the property
                          #"max_connections     = 10
            $content[$i] = "boss_address        = $DBofficeIP"
            Write-Host ' > Setting boss_address ='$DBofficeIP -ForegroundColor Green
            #break
        }
    }

    # Write the modified contents back to the file
    $content | Set-Content -Path $config
    write-host "---------------------------" -ForegroundColor Green
	
}

function Encrypt-SecurityServer-Password {

    $cwd    = (Get-Location).Path
    $wd     = 'D:\OnlineData\server'
    $configExists = Test-Path 'D:\OnlineData\server\password.properties'

    # Define the paths
    $classpath = "..\server\classes.jar"
    $class = "com.grips.util.EncodeProperty"
    $password = "password"
    $propertiesFile = "..\server\Password.properties"

    If ($configExists) {
        Write-Host "Encrypting a new SecurityServer password to D:\OnlineData\server\Password.properties!" -ForegroundColor Green
        Set-Location $wd
        # Execute the Java command
        java -classpath $classpath $class $password $propertiesFile
        Set-Location $cwd
    } else {
        Write-Host "D:\OnlineData\server\Password.properties does not exist, aborting encryption process!" -ForegroundColor Red
    }
}

function Set-DBX-Config {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "      Configuring DBX!     " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    
    $DBhostname = Get-MOD-DB-hostname
    $DBalias    = (Get-MOD-GeneralSettings).databases.JKP_DB
    $DBuser     = (Get-MOD-GeneralSettings).database_users.dbx
    $config = Get-MOD-Component-Config "DBX" "dbprops"

    if(!$config) { Write-host " > File does not exist!"; Exit }
    
    $content = Get-Content -Path $config

    # Iterate over each line and find the line containing the property
    for ($i = 0; $i -lt $content.Count; $i++) {
        
        $line = $content[$i]
        #user
        if ($line -match "^instance\s*=") {
            # Modify the value of the property
            $content[$i] = "instance=$DBalias"
            Write-Host ' > Setting instance ='$DBalias -ForegroundColor Green
            #break
        }
        #user
        if ($line -match "^user\s*=") {
            # Modify the value of the property
            $content[$i] = "user=$DBuser"
            Write-Host ' > Setting user ='$DBuser -ForegroundColor Green
            #break
        }
        #host=ModulusDB
        if ($line -match "^host\s*=") {
            # Modify the value of the property
            $content[$i] = "host=$DBhostname"
            Write-Host ' > Setting host ='$DBhostname -ForegroundColor Green
            #break
        }
    }

    # Write the modified contents back to the file
    $content | Set-Content -Path $config
    write-host "---------------------------" -ForegroundColor Green

}

function Set-TriggerMDS-Properties {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "   Recreating config for   " -ForegroundColor Yellow
    write-host "  TriggerMemberDataServer !" -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    
    $config = Get-MOD-Component-Config "GLX" "triggermemberdataserver.properties"
    $APPofficeIP = (Get-MOD-APP-OFFICE-NIC).IPAddress
    
    if(Test-Path $config) { 
        Write-Host " > Deleting config file, it will be recreated shortly!" -ForegroundColor Yellow
        Remove-item $config -ErrorAction SilentlyContinue
        $null = New-Item $config 
    }

    $content = Get-IniContent $config

    #$content.TMDS.CUSTOMER_DATA_SERVER_IP = $app_IP
    #$content.TMDS.TCPDEBUG = $app_IP

    $content.CUSTOMER_DATA_SERVER_IP = $APPofficeIP
    $content.CUSTOMER_DATA_SERVER_PORT = 3737
    $content.USE_TCPDEBUG="NO"
    $content.TCPDEBUG = $APPofficeIP

    Write-Host " > triggermemberdataserver.properties recreated using $APPofficeIP!" -ForegroundColor Green
    Out-IniFile -InputObject $content -FilePath $config -Force
    write-host "---------------------------" -ForegroundColor Green
}
#endregion

#region --- Set-Functions for JP configuration files
function Set-JP-Config {
    Set-JPApps-Config
    Set-JPReporting-Config
    Set-SecurityServerConfig-Config
}

function Set-JPApps-Config {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "          Setting          " -ForegroundColor Yellow
    write-host " JPApplicationSettings.ini " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    
    $config = get-MOD-Component-Config "Jackpot Configuration" "JPApplicationSettings.ini"
    $DBofficeIP = (Get-MOD-DB-OFFICE-NIC).IPAddress

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-IniContent $config
    $content.SecurityServerConfig.Address = $DBofficeIP
    $content.SecurityServerConfig.Port = 1666
    $content.SecurityServerConfig.ConnectionTimeOut = 21

    Out-IniFile -InputObject $content -FilePath $config -Force
    write-host "---------------------------" -ForegroundColor Green
}

function Set-JPReporting-Config {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "          Setting          " -ForegroundColor Yellow
    write-host "    JPReportSettings.ini   " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow

    $config = get-MOD-Component-Config "Jackpot Reporting" "JPReportSettings.ini"
    $DBofficeIP = (Get-MOD-DB-OFFICE-NIC).IPAddress

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-IniContent $config
    $content.SecurityServerConfig.Address = $DBofficeIP
    $content.SecurityServerConfig.Port = 1666
    $content.SecurityServerConfig.ConnectionTimeOut = 21

    Out-IniFile -InputObject $content -FilePath $config -Force
    write-host "---------------------------" -ForegroundColor Green
}

function Set-SecurityServerConfig-Config {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "          Setting          " -ForegroundColor Yellow
    write-host " SecurityApplications.ini  " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow

    $config = get-MOD-Component-Config "SecurityServer Configuration" "SecurityApplications.ini"
    $DBofficeIP = (Get-MOD-DB-OFFICE-NIC).IPAddress
    $casino_id   = (Get-MOD-GeneralSettings).specifics.casinoID

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }

    $content = Get-IniContent $config
    $content.SecurityServerConfig.Address = $DBofficeIP
    $content.SecurityServerConfig.Port = 1666
    $content.SecurityServerConfig.ConnectionTimeOut = 21

    $content.User.UserName = "as_config_interface"

    $content.DEFAULT_CASINO.ext_casino_id = $casino_id

    Out-IniFile -InputObject $content -FilePath $config -Force
    write-host "---------------------------" -ForegroundColor Green
}
#endregion 

#region --- Reconfigure GALAXIS functionality (slightly improved)
function Reconfigure-GLX {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "       Reconfiguring       " -ForegroundColor Yellow
    write-host "        D:\Galaxis         " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    #checking correct server
    $server = $env:MODULUS_SERVER
    if ($server -notin ("APP","1VMM")) { Write-host "You are on the wrong server - exiting script!" -ForegroundColor Red; Return }

    #ask for user confirmation
    $confirm = Read-Host "Do you want to proceed with the reconfiguration of your Galaxis folder? (Y/N)"
    if ($confirm -ne "Y") {
        write-host "Reconfiguration aborted!"
        write-host "-----------------------"
        Exit
    }

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
    $shortname_old = ''
    $longname_old  = ''
    $shortname_new = ''
    $longname_new  = ''
    
    #getting NEW values from configuration jsons 
    $general_settings = Get-MOD-GeneralSettings

    #new IPs
    $DB_newIP  = (Get-MOD-DB-OFFICE-NIC).IPAddress
    $APP_newIP = (Get-MOD-APP-OFFICE-NIC).IPAddress
    $FS_newIP  = (Get-MOD-FS-OFFICE-NIC).IPAddress

    #new hostnames
    $DB_newHN  = Get-MOD-DB-hostname
    $APP_newHN = Get-MOD-APP-hostname
    $FS_newHN  = Get-MOD-FS-hostname

    #new DB service names
    $GLX_new = $general_settings.databases.GLX_DB
    $JKP_new = $general_settings.databases.JKP_DB

    #new casino specifics
    $societ_new    = $general_settings.specifics.SOCIET
    $betabli_new   = $general_settings.specifics.etabli
    $casinoID_new  = $general_settings.specifics.casinoID
    $specific_new  = $general_settings.specifics.sp_schema
    
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

    Write-host "Please confirm all your input:"
    write-host "---"
    write-host "IPs: "
    write-host "FROM ________ to ________!"
    Write-host "FROM $DB_oldIP to $DB_newIP !"
    Write-host "FROM $APP_oldIP to $APP_newIP !"
    Write-host "FROM $FS_oldIP to $FS_newIP !"
    write-host "---"
    Write-host "Hostnames:"
    write-host "---"
    write-host "FROM ________ to ________!"
    Write-host "FROM $DB_oldHN to $DB_newHN !"
    Write-host "FROM $APP_oldHN to $APP_newHN !"
    Write-host "FROM $FS_oldHN to $FS_newHN !"
    write-host "---"
    Write-host "Specifics:"
    write-host "---"
    write-host "FROM ________ to ________!"
    Write-host "FROM $GLX_old to $GLX_new !"
    Write-host "FROM $JKP_old to $JKP_new !"
    Write-host "FROM $societ_long_old to $societ_long_new !"
    Write-host "FROM $betabli_long_old to $betabli_long_new !"
    Write-host "FROM $FloorTcpIp0_old to $FloorTcpIp0_new !"
    Write-host "FROM $CasinoId0_old to $CasinoId0_new !"
    write-host "---"

    Start-Sleep -Seconds 5
    $confirm = Read-Host "If all the input is correct, please confirm you want to continue with the reconfiguration: (Y/N)"
    if ($confirm -ne "Y") {
        write-host "Reconfiguration aborted!"
        write-host "-----------------------"
        Exit
    }


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
    

    #remove previous log and start logging
    remove-item I:\modulus-toolkit\logs\10_reconfigure_GLX_log.txt
    start-transcript I:\modulus-toolkit\logs\10_reconfigure_GLX_log.txt

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
            Write-Host "Working on:" 
            Write-Host ">-"$file
            Write-Host ">--- Changes made:"
            foreach ($change in $changes)
            {
                Write-Host ">----- "$change
            }
        }
        
        #writing changes to current $workingFile
        $workingFile | Set-Content $file.PSPath

    }
    stop-transcript
    write-host "---------------------------" -ForegroundColor Green
}
#endregion 

#region --- Set-Functions for Web/nginx configuration files
function Set-Web-Config {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "          Setting          " -ForegroundColor Yellow
    write-host "        config.json        " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "config.json"
    $APPofficeIP = (Get-MOD-APP-OFFICE-NIC).IPAddress

    if(-not (Test-path $config)) { Write-host "File does not exist!"; Return }
    
    $content = Get-Content $config -Raw | ConvertFrom-Json
    $content.apiUrl = 'http://'+ $APPofficeIP +':4445/api/'
    $content | ConvertTo-Json | Set-Content $config
    
    #output
    write-host "Changed $config!"
    write-host "New IP: "+$content.apiUrl
    write-host "---------------------------" -ForegroundColor Green
    #logging
}

function Set-Reverse-Proxy-Config {
    write-host "---------------------------" -ForegroundColor Yellow
    write-host "          Setting          " -ForegroundColor Yellow
    write-host "   reverse-proxy.config    " -ForegroundColor Yellow
    write-host "---------------------------" -ForegroundColor Yellow
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "reverse-proxy.conf"
    $APPofficeIP = (Get-MOD-APP-OFFICE-NIC).IPAddress
    $FSofficeIP  = (Get-MOD-FS-OFFICE-NIC).IPAddress

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

    #output
    write-host "Changed $config!" -ForegroundColor Green
    write-host "Setting APP server OFFICE IP!" -ForegroundColor Green
    write-host "Setting FLOOR server OFFICE IP!"-ForegroundColor Green
    write-host "---------------------------" -ForegroundColor Green
    #logging
}

function Set-Public-Api-Reverse-Proxy-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "public-api-reverse-proxy.conf" -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow
    
    $config = get-MOD-Component-Config "Galaxis/SYSTM" "public-api-reverse-proxy.conf"
    $APPofficeIP = (Get-MOD-APP-OFFICE-NIC).IPAddress

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
    write-host "Changed $config!"
    write-host "Set server_name to localhost"
    write-host "Setting APP server OFFICE IP!"
    write-host "-----------------------------" -ForegroundColor Yellow
    #logging
}

#endregion

#region --- PlayWatch Process/Website
function Set-PlayWatch-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "      PlayWatch config!      " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow

    #need to configure PlayWatch.exe.config!
    #need to configure log4net.config
    #need to configure web.config

    $process = get-MOD-Component-Config "PlayWatch" "PlayWatch.exe.config"
    $log4net = get-MOD-Component-Config "PlayWatch" "log4net.config"
    $website = get-MOD-Component-Config "PlayWatch" "web.config"
    
    if(-not (Test-path $process)) { Write-host "$config_File does not exist!" -ForegroundColor Red; Return }
    if(-not (Test-path $log4net)) { Write-host "$log4net does not exist!" -ForegroundColor Red; Return }
    if(-not (Test-path $website)) { Write-host "$website does not exist!" -ForegroundColor Red; Return }

    $DBofficeIP = (Get-MOD-DB-OFFICE-NIC).IPAddress
    write-host "TODO - credential management missing!" -ForegroundColor Red
    $GLX_DB      = 'GLX'
    $RG_user     = 'RG'
    $RG_password = 'uqC74WXxKNUG3Jn90IA95Q=='

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
    write-host "-----------------------------" -ForegroundColor Green
}

#endregion

#region --- FS def.cfg attempt
function Set-FS-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "   FS config into def.cfg!   " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow
    
    $config     = get-MOD-Component-Config "Floorserver" "def.cfg"
    $FSfloorIP  = (Get-MOD-FS-FLOOR-NIC).IPAddress
    $dhcpranges = Get-MOD-FS-DHCP-Ranges
    
    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    $configContent = Get-Content -Path $config -Raw

    #interface
    $interface = $FSfloorIP
    write-host " > Setting FLOOR interface IP to $interface" -ForegroundColor Yellow
    #CMOD
    $dhcpserverlow =  $dhcpranges.CMOD.from
    $dhcpserverhigh = $dhcpranges.CMOD.to
    write-host " > Setting CMOD DHCP range from $dhcpserverlow to $dhcpserverhigh" -ForegroundColor Yellow
    #MDC
    $dhcplow =        $dhcpranges.MDC.from
    $dhcphigh =       $dhcpranges.MDC.to
    write-host " > Setting MDC DHCP range from $dhcplow to $dhcphigh" -ForegroundColor Yellow
   

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
    write-host " > " -ForegroundColor Yellow
    write-host " > Please verify by opening fscfg.tcl85 !" -ForegroundColor Yellow
    write-host " > or type 'Show-FS-Config'!" -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Green
}
#endregion

#region --- Set-Functions for CRYSTAL Control configuration files
function Set-CRYSTALControl-Config {

    #only need to configure ..\control\ControlLauncher.exe.config since log4net.xml is always correct out of the box!
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "   CRYSTAL Control config!   " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow
   
    $config = get-MOD-Component-Config "CRYSTAL Control" "ControlLauncher.exe.config"

    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    $CONTROL_config = New-Object System.XML.XMLDocument
    $CONTROL_config.Load($config)
 
    #$officeNIC = $FSConfig.OFFICE.name - no extra variable for just the name at the moment, but OFFICE should be the same each time.
    $FSofficeIP  = (Get-MOD-FS-OFFICE-NIC).IPAddress
    #$FSfloorIP   = (Get-MOD-FS-FLOOR-NIC).IPAddress 

    #fetching current config
    $appSettings = $CONTROL_config.SelectSingleNode("configuration/appSettings").ChildNodes

    $OfficeNetworkInterface = $appSettings  | Where-Object {$_.key -eq "OfficeNetworkInterface"}
    $OfficeNetworkInterface.value = 'OFFICE'
    Write-Host 'Setting OfficeNetworkInterface="OFFICE"' -ForegroundColor Yellow

    $PreferredIpAddress = $appSettings  | Where-Object {$_.key -eq "PreferredIpAddress"}
    $PreferredIpAddress.value = $FSofficeIP
    Write-Host 'Setting PreferredIpAddress="'$FSofficeIP'"' -ForegroundColor Yellow

    $floorServerIpOnOfficeNetworkInterface = $appSettings  | Where-Object {$_.key -eq "floorServerIpOnOfficeNetworkInterface"}
    $floorServerIpOnOfficeNetworkInterface.value = $FSofficeIP
    Write-Host 'Setting floorServerIpOnOfficeNetworkInterface="'$FSofficeIP'"' -ForegroundColor Yellow
    
    $CONTROL_config.Save($config)
    Write-Host "Saving ControlLauncher.exe.config!" -ForegroundColor Green
    write-host "-----------------------------" -ForegroundColor Green
    #CRYSTAL Control config saved!
    #logging
}

#endregion

#region --- Set-Functions for CFCS configuration files
function Set-CFCS-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "        CFCS config!         " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow
       
    #need to configure CFCS.exe.config as well as log4net.xml since it is delivered with a shit logging path!

    $config  = get-MOD-Component-Config "CRYSTAL Floor Communication Service" "CRYSTAL Floor Communication Service.exe"
    
    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    $general_settings = Get-MOD-GeneralSettings
    #fetch config from mod-VM-config.json
    $casinoID     = $general_settings.specifics.casinoID 
    $CAWA         = $general_settings.specifics.CAWA 
    $IPSEC        = $general_settings.specifics.IPSEC
    $APP_officeIP = (Get-MOD-APP-OFFICE-NIC).IPAddress
    $FS_officeIP  = (Get-MOD-FS-OFFICE-NIC).IPAddress
    #$GDP          = $general_settings.specifics.GDP 
    $GDP          = $False #no GamingDayProvider change at the end of the file

    #$R4R          = $general_settings.specifics.GDP 
    $R4R          = $False

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
    Write-host "Configuring: $address"

    #Promotion Service
    $PromotionService = $client_endpoints | Where-Object {$_.name -eq "Promotion Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/PromotionsService"
    $PromotionService.address = $address
    Write-host "Configuring: $address"

    #KioskConfiguration Service
    $KioskConfigurationService = $client_endpoints | Where-Object {$_.name -eq "KioskConfiguration Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/KioskConfigurationService"
    $KioskConfigurationService.address = $address
    Write-host "Configuring: $address"

    #Rewards Service
    $RewardsService = $client_endpoints | Where-Object {$_.name -eq "Rewards Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/RewardsService"
    $RewardsService.address = $address
    Write-host "Configuring: $address"

    #Loyalty Club Service
    $LoyalityClubService = $client_endpoints | Where-Object {$_.name -eq "Loyalty Club Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/LoyaltyClubService"
    $LoyalityClubService.address = $address
    Write-host "Configuring: $address"

    #Player Preferences Service
    $PlayerPreferencesService = $client_endpoints | Where-Object {$_.name -eq "Player Preferences Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/PlayerPreferencesService"
    $PlayerPreferencesService.address = $address
    Write-host "Configuring: $address"

    #Voucher Service
    $VoucherService = $client_endpoints | Where-Object {$_.name -eq "Voucher Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/VoucherService"
    $VoucherService.address = $address
    Write-host "Configuring: $address"

    #Campaign Service
    $CampaignService = $client_endpoints | Where-Object {$_.name -eq "Campaign Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8082/StarMarketing/MarketingIntelligence/CampaignService"
    $CampaignService.address = $address
    Write-host "Configuring: $address"

    #NetTcpBinding_Item Service
    $NetTcpBinding_ItemService = $client_endpoints | Where-Object {$_.name -eq "NetTcpBinding_Item Service"}
    $address = "net.tcp://"+ $APP_officeIP +":8093/PlayerServices/MyBar/ItemService"
    $NetTcpBinding_ItemService.address = $address
    Write-host "Configuring: $address"

    #Default
    $Default = $client_endpoints | Where-Object {$_.name -eq "Default"}
    $address = "net.tcp://"+ $APP_officeIP +":8093/PlayerServices/MyBar/OrderService"
    $Default.address = $address
    Write-host "Configuring: $address"

    #DefaultControlServiceEndpoint
    $DefaultControlServiceEndpoint = $client_endpoints | Where-Object {$_.name -eq "DefaultControlServiceEndpoint"}
    $address = "net.tcp://"+ $APP_officeIP +":9083/"
    $DefaultControlServiceEndpoint.address = $address
    Write-host "Configuring: $address"

    #DefaultControlServiceEndpoint1
    $DefaultControlServiceEndpoint1 = $client_endpoints | Where-Object {$_.name -eq "DefaultControlServiceEndpoint1"}
    $address = "net.tcp://"+ $APP_officeIP +":9084/"
    $DefaultControlServiceEndpoint1.address = $address
    Write-host "Configuring: $address"

    #endregion
 
    #<system.serviceModel><services><service>
    $MyMultiGameService = ($CFCS_config.configuration.'system.serviceModel'.services.service | Where-Object {$_.name -eq "Atronic.CrystalFloor.MyMultiGameService"}).endpoint
    $address = "net.tcp://"+ $FS_officeIP +":9066/MultiGameService/mex"
    $MyMultiGameService.address = $address
    Write-host "Configuring: $address"

    $Rub4RichesService = ($CFCS_config.configuration.'system.serviceModel'.services.service | Where-Object {$_.name -eq "CFCS.Services.Rub4Riches.Rub4RichesService"}).endpoint
    $address = "net.tcp://"+ $FS_officeIP +":9066/Rub4Riches/mex"
    $Rub4RichesService.address = $address
    Write-host "Configuring: $address"

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
    Write-host "Configuring: $address"

    #DefaultServiceBehaviour
    $DefaultServiceBehaviour = $service_endpoints | Where-Object {$_.name -eq "DefaultServiceBehaviour"}
    $address = "http://"+ $FS_officeIP +":9065/BalanceNotification/mex"
    $DefaultServiceBehaviour.serviceMetadata.httpGetUrl = $address
    Write-host "Configuring: $address"


    #<appSettings>
    $appSettings = $CFCS_config.SelectSingleNode("configuration/appSettings").add
   

    if ($CAWA) {

       $CashWalletAddress = $appSettings | Where-Object {$_.key -eq "CashWalletAddress"}
       $address = "http://"+$APP_officeIP+":16266/B0C78A8F-1908-42B5-ABBD-ABD080A741D1"
       $CashWalletAddress.value = $address
       Write-host "Configuring: $address"

       $AuthAddress = $appSettings | Where-Object {$_.key -eq "AuthAddress"}
       $address = "http://"+$APP_officeIP+":16264/B0C78A8F-1908-42B5-ABBD-ABD080A741D1"
       $AuthAddress.value = $address
       Write-host "Configuring: $address"

       $PropertyId = $appSettings | Where-Object {$_.key -eq "PropertyId"}
       $PropertyId.value = $casinoID
       Write-host "Configuring casinoID: $casinoID"

       if($R4R)
       {
        #handle R4R config if wanted
       }
    }
   

    $OfficeNetworkInterface = $appSettings  | Where-Object {$_.key -eq "OfficeNetworkInterface"}
    $OfficeNetworkInterface.value = $FS_officeNIC
    write-host "Configuring OfficeNetworkInterface: $FS_officeNIC"
    
    #$PreferredIpAddress = $appSettings | Where-Object {$_.key -eq "PreferredIpAddress"}
    #$PreferredIpAddress.value = 
    # 								^
    # 								what to set?

    $HTTPServerAddress = $appSettings | Where-Object {$_.key -eq "HTTPServerAddress"}
    $HTTPServerAddress.value = "http://"+$APP_officeIP+":801"
    write-host "Configuring HTTPServerAddress: "+$HTTPServerAddress.value


    if($GDP)
    {
        #<castle><components>
        #$components = $CFCS_config.configuration.castle.components.'#comment'
        #when do we use which option of this thingy?
    }
    #endregion

    #Saving CFCS.exe.config!
    $CFCS_config.Save($config)
    Write-Host "CFCS configuration file was configured!" -ForegroundColor Green
    #------------------------------

    $config = get-MOD-Component-Config "CRYSTAL Floor Communication Service" "log4net.xml"
    if(-not (Test-path $config)) { Write-host "$config does not exist!" -ForegroundColor Red; Return }

    #log4net.xml 
    $log4net_config = New-Object System.XML.XMLDocument
    $log4net_config.Load($config)

    $appenders = $log4net_config.log4net.Appender

    #Communication.log
    $logfile = $appenders | Where-Object {$_.name -eq "logfile"}
    $logfile.file.conversionPattern.value = $CommLog
    write-host "Configuring log-dir: $CommLog"

    $logfile.maxSizeRollBackups.value = "100"
    write-host "Setting maximum log files to 100!"

    $logfile.maximumFileSize.value = "10000KB"
    write-host "Setting maximum log file size to 10000KB!"

    #CommunicationKeepAlive.log
    $logfile = $appenders | Where-Object {$_.name -eq "keepalivelogfile"}
    $logfile.file.conversionPattern.value = $CommKALog
    write-host "Configuring log-dir: $CommKALog"

    <#
    $logfile.maxSizeRollBackups.value = "100"
    write-host "Setting maximum log files to 100!"

    $logfile.maximumFileSize.value = "10000KB"
    write-host "Setting maximum log file size to 10000KB!"
    #>

    #Saving log4net.xml
    $log4net_config.Save($config)
    Write-Host "CFCS log4net.xml file was configured!" -ForegroundColor Green
    #------------------------------
    write-host "-----------------------------" -ForegroundColor Green
}

#endregion

#region --- Relay
function Set-Relay-Config {
    write-host "-----------------------------" -ForegroundColor Yellow
    write-host "          Setting            " -ForegroundColor Yellow
    write-host "        Relay config!        " -ForegroundColor Yellow
    write-host "-----------------------------" -ForegroundColor Yellow

    #need to configure TCPIPServerIn.xml
    #need to configure TCPIPServerOut.xml

    $tcpin  = get-MOD-Component-Config "Star Display Relay" "TCPIPServerIn.xml"
    $tcpout = get-MOD-Component-Config "Star Display Relay" "TCPIPServerIn.xml"

    if(-not (Test-path $tcpin)) { Write-host "$tcpin does not exist!" -ForegroundColor Red; Return }
    if(-not (Test-path $tcpout)) { Write-host "$tcpout does not exist!" -ForegroundColor Red; Return }

    $FSofficeIP = (Get-MOD-FS-OFFICE-NIC).IPAddress
    $NIC      = 'OFFICE'

    #TCPIPServerIn.xml
    $tcpin_config = New-Object System.XML.XMLDocument
    $tcpin_config.Load($tcpin)
    #<TCPIPServerConfig>
    $tcpin_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strName = $NIC
    $tcpin_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strIPAddress = $FSofficeIP
    $tcpin_config.Save($tcpin)
    write-host " > TCPIPServerIn.xml was configured!" -ForegroundColor Green
    Write-host " > $NIC and $FSofficeIP!" -ForegroundColor Green
    #------------------------------

    #TCPIPServerOut.xml
    $tcpout_config = New-Object System.XML.XMLDocument
    $tcpout_config.Load($tcpout)
    #<TCPIPServerConfig>
    $tcpout_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strName = $NIC
    $tcpout_config.ArrayOfTCPIPServerConfig.TCPIPServerConfig[0].strIPAddress = $FSofficeIP
    $tcpout_config.Save($tcpout)
    write-host " > TCPIPServerOut.xml was configured!" -ForegroundColor Green
    Write-host " > $NIC and $FSofficeIP!" -ForegroundColor Green
    write-host "-----------------------------" -ForegroundColor Green
}

#endregion

#region --- attempt to create the first 3VM update-scripts for each VM
function Update-DB {

    write-host ">" -ForegroundColor DarkYellow
    write-host " > Updating DB components! Pinit Service will be stopped" -ForegroundColor DarkYellow
    
	if(!(CoA)) { exit }
		
    #import-module modulus-toolkit -DisableNameChecking -Force

    #manually cleared out toolkit-directory on APP and FS, only because huge version gap
    # Deploy-Toolkit

    Stop-MOD-Services
    Show-MOD-Services
    #pinit needs to be stopped

    Write-Host "Pinit stopped on DB server!" -ForegroundColor DarkYellow
	
    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "Now move to the Floorserver and type Update-FS!" -ForegroundColor Red 
	Write-Host "Don't close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan
    
    if(!(CoA)) { exit }

    #DB update was done on APP server
    Start-MOD-Services
    Show-MOD-Services

    #check JPCC
    Write-Host "Verify that JPCC is starting up as it should!"
    get-content -path "D:\OnlineData\JPChecksumCalculator\Log\JPChecksumCalculator.log" | select-string -pattern "Type is check succeeded"

    #2024-08-28 14:05:52,318|INFO |JPChecksumCalculator.ComponentVerification|Type is check succeeded
    #-->looks good!
    write-host "Only needed if JP Checksumm Calculator is used" -ForegroundColor DarkYellow

    if(!(CoA)) { 
        exit 
    } else {
        write-host " > DB services are up and running again!" -ForegroundColor Green

        $border = "**************************************************"
        Write-Host "`n$border" -ForegroundColor Cyan
        Write-Host "Now continue on APPSERVER" -ForegroundColor Red 
        Write-Host "DB Server finished! You can close this PWSH window!" -ForegroundColor Red 
        Write-Host "$border`n" -ForegroundColor Cyan
    }
}

function Update-APP {
   
    write-host ">" -ForegroundColor DarkYellow
    write-host " > Updating APP components!" -ForegroundColor DarkYellow

    Show-ScriptDisclaimer
    Show-CurrentGLXVersion
    
    write-host "    "
    write-host "    "
    write-host "Make sure you provided the correct sources:" -ForegroundColor DarkYellow
    Show-SourcesDir
    if(!(Confirm-GLXHotfix)) { exit }
    
    #Show-PrepDir
    Clear-PrepDir
    write-host "Previously prepared binaries have been cleared!" -ForegroundColor DarkYellow

    Clear-GLXLogs -AskIF
    Clear-GLXGarbage #-AskIf
    Backup-GLXDir -AskIF
    write-host "Logs and gargabe has been removed, Backup-task was triggered!" -ForegroundColor DarkYellow

    if(!(CoA)) { exit }

    write-host "Starting to prepare all needed sources!" -ForegroundColor DarkYellow
    write-host "    "
    write-host "Prep-Galaxis ALL" -ForegroundColor DarkYellow
    Prep-Galaxis ALL -AskIF
    write-host "Prep-SYSTM ALL" -ForegroundColor DarkYellow
    Prep-SYSTM ALL -AskIF
    write-host "Prep-Playwatch" -ForegroundColor DarkYellow
    Prep-PlayWatch 
    write-host "Prep-Web" -ForegroundColor DarkYellow
    Prep-Web
    Show-PrepDir

   
    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "Preparation finished. Do you want to start deploying?" -ForegroundColor Green 
	Write-Host "Services will be stopped" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan
    if(!(CoA)) { exit }

    Stop-MOD-Services 
    Show-MOD-Services 

    write-host "Check if all Services are stopped.Then continue with deployment!" -ForegroundColor Red
    
    if(!(CoA)) { exit }

    Close-GLXDirAccess
    Disable-M-Share
    
    write-host "Deploy-Galaxis ALL" -ForegroundColor DarkYellow
    Deploy-Galaxis ALL -AskIf
    write-host "Deploy-SYSTM ALL" -ForegroundColor DarkYellow
    Deploy-SYSTM ALL -AskIf
    write-host "Deploy-Web" -ForegroundColor DarkYellow
    Deploy-Web
    write-host "Deploy-Playwatch if needed" -ForegroundColor DarkYellow
    Deploy-PlayWatch -AskIF
    write-host "Set Playwatch Config if needed" -ForegroundColor DarkYellow
    Set-PlayWatch-Config
    write-host "Set Web Config " -ForegroundColor DarkYellow
    Set-Web-Config
    write-host "Set Reverse-Proxy Config " -ForegroundColor DarkYellow
    Set-Reverse-Proxy-Config

    write-host "All prepared sources have been deployed! Please verify!" -ForegroundColor Green
    Show-CurrentGLXVersion
    
    if(!(CoA)) { exit }
    Install-MOD-Services
    Recycle-GLX-1097

    #leaving rabbitMQ out of this for now, since it might interrupt the script

  
    #live
    $path = "C:\Program Files\PowerShell\Modules\modulus-toolkit\manuals\1097_manual.md"
    Start-Process "chrome.exe" "`"$path`""
    
    Open-MOD-Manual 1097

  
    $border = "*********************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "Now the additional manual steps needed to be done!" -ForegroundColor DarkYellow 
	Write-Host "Open another powershell prompt and do them there! " -ForegroundColor DarkYellow 
    Write-Host "Don't close this PWSH window - continue here after manual steps " -ForegroundColor DarkYellow 
	Write-Host "$border`n" -ForegroundColor Cyan

    if(!(CoA)) { exit }

  
    $border = "**********************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "Now the database scripts need to be executed!" -ForegroundColor DarkYellow 
	Write-Host "Open another powershell prompt and do them there! " -ForegroundColor DarkYellow 
    Write-Host "Don't close this PWSH window - continue here after scripts and galaxisoracle.jar are done " -ForegroundColor DarkYellow 
	Write-Host "$border`n" -ForegroundColor Cyan

    Prep-HFandLib



    if(!(CoA)) { exit }

    Compile-GLX-Serial
    #Compile-GLX-Serial
    Show-GLX-Invalids   


    Install-QueryBuilder -AskIF

    Uninstall-JPApps -AskIf
    Install-JPApps -AskIf
    Set-JP-Config -AskIF

    if(!(CoA)) { exit }

    Show-CurrentGLXVersion
    Enable-M-share

    
    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "APP components have been updated" -ForegroundColor Green 
    Write-Host "Please continue on the Floorserver!!" -ForegroundColor DarkYellow 
	Write-Host "Don't close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan

    if(!(CoA)) { exit }

    Start-MOD-Services
    Show-MOD-Services

    write-host " > Update is done. All Service should run. Please verify and check the system" -ForegroundColor Green
}

function Update-FS {

    write-host ">" -ForegroundColor DarkYellow
    write-host " > Updating FS components!" -ForegroundColor DarkYellow

    write-host "If you continue all Services will be stopped" -ForegroundColor Red

    if(!(CoA)) { exit }

    Stop-MOD-Services
    net stop nginx
    Show-MOD-Services
    
    Write-Host "Please clear out D:\OnlineData\Logs\* manually and then continue!" -ForegroundColor DarkYellow
    Backup-OnlineData -AskIF

   
    if(!(CoA)) { exit }

    write-host "Services are stopped and a backup was made!" -ForegroundColor Green
    Write-Host "Next step will prepare Crystal Control and MBoxUI"
    if(!(CoA)) { exit }
    
    #Check-OEMJava
    #Uninstall-OEMJava
    
    Prep-CRYSTALControl -AskIF
    Prep-MBoxUI -AskIF

    write-host "Prepared CRYSTALControl and MBoxUI" -ForegroundColor Green
    Write-Host "Next step will Uninstall and Install CFCS" -ForegroundColor DarkYellow
    if(!(CoA)) { exit }

    Uninstall-CFCS
    Install-CFCS
    Set-CFCS-Config

    write-host "CFCS installed and configured" -ForegroundColor Green
    write-host "Please edit CFCS.exe.config depending on wether you need a GDCProvider or not!" -ForegroundColor Red
    write-host "Next step will open the CFCS config file" -ForegroundColor Red
    #GDCProvider yes?
    if(!(CoA)) { exit }
    np "D:\OnlineData\CRYSTAL.Net\CRYSTAL Floor Communication Service\CRYSTAL Floor Communication Service.exe.config"
    
    write-host "Continue with deploy CRYSTAL Control" -ForegroundColor DarkYellow
    if(!(CoA)) { exit }
    
    
    Deploy-CRYSTALControl -AskIF
    Set-CRYSTALControl-Config

    write-host "CRYSTALControl was updated and configured!" -ForegroundColor Green
    Deploy-MBoxUI

    write-host "MoxUI was deployed!" -ForegroundColor Green
    
    if(!(CoA)) { exit }
    
    Install-QueryBuilder -AskIf
    write-host "QB was updated!" -ForegroundColor Green
    Install-Floorserver -AskIF
    Set-FS-Config
    write-host "FS was updated and configured! Please verify!" -ForegroundColor Green 
    Show-FS-Config

    
    write-host " > Next step will set the reverse-proxy" -ForegroundColor DarkYellow

    if(!(CoA)) { exit }

    Set-Reverse-Proxy-Config
    write-host "nginx reverse-proxy.conf was edited, please verify and continue!" -ForegroundColor Red
    np "D:/OnlineData/nginx/modulus/reverse-proxy.conf"

    if(!(CoA)) { exit }

   
    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
    Write-Host "FS update finished!" -ForegroundColor Green 
	Write-Host "Continue on APP Server!" -ForegroundColor Red 
	Write-Host "Don't close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan

    if(!(CoA)) { exit }

    net start nginx
    Start-MOD-Services
    Show-MOD-Services

    

    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
    Write-host "FS update is finished!" -ForegroundColor Green
	Write-Host "Continue on DB Server!" -ForegroundColor Red 
	Write-Host "you can close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan
}
#endregion

#region --- Update 3VM from APP

function Update-3VM {

    #preparing sessions
    Open-DB-Session
    Open-FS-Session

    $sessDB = $global:open_sessDB
    $sessFS = $global:open_sessFS

    #stopping services
    Stop-MOD-Services   #APP
    Show-MOD-Services


    Invoke-Command -Session $sessDB -ScriptBlock { 
        Write-host " "
        Write-Host "Now working on DATABASE server!" -ForegroundColor Yellow
        Stop-MOD-Services   #DB
        Show-MOD-Services
    }
    Invoke-Command -Session $sessFS -ScriptBlock { 
        Write-host " "
        Write-Host "Now working on FLOOR server!" -ForegroundColor Yellow

        Stop-MOD-Services   #FS
        Show-MOD-Services   
    }
    Write-host " "
    write-host "Update-3VM done."
    
}

#endregion

#region --- log-filtering-logic

#endregion