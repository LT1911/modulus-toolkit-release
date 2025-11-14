#jzoetsch, 01.04.2025

#write-host "Loading guidedupdate.psm1!" -ForegroundColor Green

#region --- attempt to create the first guided update for each VM
function Update-DB-with-Guide {

    write-host ">" -ForegroundColor DarkYellow
    write-host " > Updating DB components! Pinit Service will be stopped" -ForegroundColor DarkYellow
    
	if(!(CoA)) { Return }
		
    Stop-MOD-Services
    Show-MOD-Services
    #pinit needs to be stopped

    Write-Host "Pinit stopped on DB server!" -ForegroundColor DarkYellow
	
    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "Now move to the Floorserver and type Update-FS-with-Guide!" -ForegroundColor Red 
	Write-Host "Don't close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan
    
    if(!(CoA)) { Return }

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
        Return 
    } else {
        write-host " > DB services are up and running again!" -ForegroundColor Green

        $border = "**************************************************"
        Write-Host "`n$border" -ForegroundColor Cyan
        Write-Host "Now continue on APPSERVER" -ForegroundColor Red 
        Write-Host "DB Server finished! You can close this PWSH window!" -ForegroundColor Red 
        Write-Host "$border`n" -ForegroundColor Cyan
    }
}

function Update-APP-with-Guide {
   
    write-host ">" -ForegroundColor DarkYellow
    write-host " > Updating APP components!" -ForegroundColor DarkYellow

    Show-CurrentGLXVersion
    
    write-host "    "
    write-host "    "
    write-host "Make sure you provided the correct sources:" -ForegroundColor DarkYellow
    #Show-SourcesDir
    Show-NewestSources
    Write-Host "Services will be stopped" -ForegroundColor Red 

    #asking if really wanted
    if (-not (Confirm-YesNo -Message "Do you want to start applying the update?" -Default "Yes")) {
        Write-Log "Stopping update! No changes were made!" -Level WARNING
        Return
    }
    Write-Log "Proceeding with update..."
    
    Stop-MOD-Services 
    Show-MOD-Services 
    #Show-PrepDir
    Clear-PrepDir
    write-host "Previously prepared binaries have been cleared!" -ForegroundColor DarkYellow

    Clear-GLXLogs -AskIF
    Backup-GLXDir -AskIF
    write-host "Logs and gargabe has been removed, Backup-task was triggered!" -ForegroundColor DarkYellow

    if(!(CoA)) { Return }

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
	
	Write-Host "$border`n" -ForegroundColor Cyan
    if(!(CoA)) { Return }



    write-host "Check if all Services are stopped.Then continue with deployment!" -ForegroundColor Red
    
    if(!(CoA)) { Return }

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
    
    if(!(CoA)) { Return }
    Install-MOD-Services
    Remove-1097-Artifacts

    #leaving rabbitMQ out of this for now, since it might interrupt the script

     Open-MOD-Manual Manual

  
    $border = "*********************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "Now the additional manual steps needed to be done!" -ForegroundColor DarkYellow 
	Write-Host "Open another powershell prompt and do them there! " -ForegroundColor DarkYellow 
    Write-Host "Don't close this PWSH window - continue here after manual steps " -ForegroundColor DarkYellow 
	Write-Host "$border`n" -ForegroundColor Cyan

    if(!(CoA)) { Return }

  
    $border = "**********************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "Now the database scripts need to be executed!" -ForegroundColor DarkYellow 
	Write-Host "Open another powershell prompt and do them there! " -ForegroundColor DarkYellow 
    Write-Host "Don't close this PWSH window - continue here after scripts and galaxisoracle.jar are done " -ForegroundColor DarkYellow 
	Write-Host "$border`n" -ForegroundColor Cyan

    Prep-HFandLib



    if(!(CoA)) { Return }

    Compile-GLX-Serial
    #Compile-GLX-Serial
    Show-GLX-Invalids   


    Install-QueryBuilder -AskIF

    Uninstall-JPApps -AskIf
    Install-JPApps -AskIf
    Set-JP-Config -AskIF

    if(!(CoA)) { Return }

    Show-CurrentGLXVersion
    Enable-M-share

    
    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
	Write-Host "APP components have been updated" -ForegroundColor Green 
    Write-Host "Please continue on the Floorserver!!" -ForegroundColor DarkYellow 
	Write-Host "Don't close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan

    if(!(CoA)) { Return }

    Start-MOD-Services
    Show-MOD-Services

    write-host " > Update is done. All Service should run. Please verify and check the system" -ForegroundColor Green
}

function Update-FS-with-Guide {

    write-host ">" -ForegroundColor DarkYellow
    write-host " > Updating FS components!" -ForegroundColor DarkYellow

    write-host "If you continue all Services will be stopped" -ForegroundColor Red

    if(!(CoA)) { Return }

    Stop-MOD-Services
    net stop nginx
    Show-MOD-Services
    
    Write-Host "Please clear out D:\OnlineData\Logs\* before run the backup" -ForegroundColor DarkYellow
    Clear-OnlineDataLogs -AskIf
    Backup-OnlineData -AskIF

   
    if(!(CoA)) { Return }

    write-host "Services are stopped and a backup was made!" -ForegroundColor Green
    Write-Host "Next step will prepare Crystal Control and MBoxUI"
    if(!(CoA)) { Return }
    
    #Check-OEMJava
    #Uninstall-OEMJava
    
    Prep-CRYSTALControl 
    Prep-MBoxUI 

    write-host "Prepared CRYSTALControl and MBoxUI" -ForegroundColor Green
    Write-Host "Next step will Uninstall and Install CFCS" -ForegroundColor DarkYellow
    if(!(CoA)) { Return }

    Uninstall-CFCS
    Install-CFCS
    Set-CFCS-Config

    write-host "CFCS installed and configured" -ForegroundColor Green
    write-host "Please edit CFCS.exe.config depending on wether you need a GDCProvider or not!" -ForegroundColor Red
    write-host "Next step will open the CFCS config file" -ForegroundColor Red
    #GDCProvider yes?
    if(!(CoA)) { Return }
    np "D:\OnlineData\CRYSTAL.Net\CRYSTAL Floor Communication Service\CRYSTAL Floor Communication Service.exe.config"
    
    write-host "Continue with deploy CRYSTAL Control" -ForegroundColor DarkYellow
    if(!(CoA)) { Return }
    
    
    Deploy-CRYSTALControl -AskIF
    Set-CRYSTALControl-Config

    write-host "CRYSTALControl was updated and configured!" -ForegroundColor Green
    Deploy-MBoxUI

    write-host "MBoxUI was deployed!" -ForegroundColor Green
    
    if(!(CoA)) { Return }
    
    Install-QueryBuilder -AskIf
    write-host "QB was updated!" -ForegroundColor Green
    Install-Floorserver -AskIF
    Set-FS-Config
    write-host "FS was updated and configured! Please verify!" -ForegroundColor Green 
    Show-FS-Config

    
    write-host " > Next step will set the reverse-proxy" -ForegroundColor DarkYellow

    if(!(CoA)) { Return }

    Set-Reverse-Proxy-Config
    write-host "nginx reverse-proxy.conf was edited, please verify and continue!" -ForegroundColor Red
    np "D:/OnlineData/nginx/modulus/reverse-proxy.conf"

    if(!(CoA)) { Return }

   
    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
    Write-Host "FS update finished!" -ForegroundColor Green 
	Write-Host "Continue on APP Server!" -ForegroundColor Red 
	Write-Host "Don't close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan

    if(!(CoA)) { Return }

    net start nginx
    Start-MOD-Services
    Show-MOD-Services

    

    $border = "**************************************************"
	Write-Host "`n$border" -ForegroundColor Cyan
    Write-host "FS update is finished!" -ForegroundColor Green
	Write-Host "Continue on DB Server!" -ForegroundColor Red 
	Write-Host "You can close this PWSH window!" -ForegroundColor Red 
	Write-Host "$border`n" -ForegroundColor Cyan
}
#endregion

#Export-ModuleMember -Function @('Update-DB-with-Guide','Update-APP-with-Guide','Update-FS-with-Guide')