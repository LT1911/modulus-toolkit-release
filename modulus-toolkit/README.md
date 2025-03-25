# modulus-toolkit v1.6.4

## About:

- compatible with **Galaxis 10.97 and up!**
- should only be used by **Modulus staff** since it **could negatively impact the system if improperly used!**
- The toolkit can assist with **preparing and deploying Galaxis and SYSTM updates, installing new Jackpot or Floorserver components.**
- In this readme I try to outline the **different applications of the toolkit - categorized by the different modules** that we have.
- The individual steps can be used stand-alone or in combination in attempt to create an automated update procedure.
- If you have any issues with the toolkit or any specific command - don't hesitate to reach out to me. 
- Testing is much appreciated!

---

## Content

0. [Configuration](#Configuration)
1. [General](#General)
2. [Galaxis/SYSTM](#Galaxis/SYSTM)
3. [Jackpot](#Jackpot)
4. [FS](#FS)
5. [CFCS](#CFCS)
6. [Control](#Control)
7. [PlayWatch](#PlayWatch)
8. [Helpers](#Helpers)
9. [Oracle](#Oracle)
10. [Sysprep/Setup](#Sysprep/Setup)

---

<a name="Configuration"></a>

# Configuration
<details>
<summary>expand for details!</summary>

The configuration for the toolkit can be found in 
**C:\Program Files\PowerShell\Modules\modulus-toolkit\config**:
- **mod-VM-config.json** contains the specifics for the installation such as **customer info (COD_SOCIET,COD_ETABLI,ID_CASINO)** as well as **hostnames and IPs** to be used!
- **mod-PS-config.json** contains the paths for the **working directories** used by the toolkit!
- rest of the configuration files in the directory should not be touched!

</details>

---

<a name="General"></a>

# General

```powershell
import-module modulus-toolkit -DisableNameChecking -force
Loading modulus-base!
Initializing needed modules...
Initializing module vault...
Initializing needed tools...
Loading modulus-core!
Loading modulus-toolkit!

Successfully loaded v1.4!
'Open-MOD-Help' to open README.md!
Finished updating components!

Open-MOD-Help   #opens this README.md - best viewed with Markdown Viewer plugin for Chrome!

Assert-MOD-Components -Silent #checks for installed components

Show-MOD-Databases  #shows installed Databases
Show-MOD-Modules    #shows installed Modules
Show-MOD-Tools      #shows installed Tools

Show-MOD-Components #calls Show-MOD-Databases, Show-MOD-Modules and Show-MOD-Tools
Tools on this server:

name               version
----               -------
7-Zip              23.01
Notepad++          8.6.9
NewDMM             1.0.0.0
FloorPlanDesigner  0.37.3
FloorPlanGenerator 10.93.00.1971
CleanRegistry      1.1.0.0
QueryBuilder       10.95.0.139

Modules on this server:

name                                version
----                                -------
OnlineData                          10.95.0.139
Floorserver                         10.95.0.139
CRYSTAL Control                     7.5.0.1901
CRYSTAL Floor Communication Service 10.97.00.58
Star Display Relay                  3.2.5.806
Reservation Agent                   -
Qsched                              -
Floor Messenger                     -
nginx on Floorserver                -

---

<a name="Galaxis/SYSTM"></a>

# Galaxis/SYSTM

## Managing Galaxis and SYSTM services
```powershell
Show-MOD-Services   # shows the status of Modulus services, Stopped = grey, Running = green 

 Status DisplayName
 ------ -----------
Stopped Galaxis AML Service
Stopped Galaxis Authentication Service
Stopped Galaxis CageIntelligence Service
Stopped Galaxis CashWallet Service
Stopped Galaxis CasinoSynchronization Service
Stopped Galaxis KioskRouter Service
Stopped Galaxis MarketingDataConsolidation Service
Stopped Galaxis MarketingIntelligence Service
Stopped Galaxis MobileApplication Service
Stopped Galaxis myBar Service
Stopped Galaxis PlayerIntelligence Service
Stopped Galaxis qpon cash Service
Stopped Galaxis SlotDataConsolidation Service
Stopped Galaxis SlotIntelligence Service
Stopped Galaxis GalaxisStartup Service
Stopped Galaxis Statutory Service
Stopped Galaxis TableIntelligence Service
Stopped Galaxis TSDRouter Service
Stopped Galaxis UserAuthentication Service
Stopped Galaxis WebJackpot Service
Stopped Galaxis WebMarketing Service
Stopped Galaxis WebPlayer Service
Stopped Galaxis Public API
Stopped Galaxis API
Stopped Galaxis License Service
Stopped Galaxis MemberDataServer service
Stopped Galaxis Notification Service
Stopped Galaxis SlotDataExporterService
Stopped Galaxis TableSetup Service
Stopped Alloy
Stopped pinit
Stopped RabbitMQ
Stopped nginx

Start-MOD-Services  # starts Modulus services (using GalaxisStartup Service or pinit respectively)
Stop-MOD-Services   # stops Modulus services (using GalaxisStartup Service or pinit respectively)
```

## Preparing upgrades
```powershell
Show-PrepDir    # shows contents of the current preparation directory

Name                  LastWriteTime
----                  -------------
Config only           7/29/2024 12:30:23 PM
Executable only       7/29/2024 12:27:44 PM
HFandLib              7/29/2024 12:25:11 PM
Other only            7/29/2024 12:30:02 PM
SYSTM Config only     7/29/2024 2:52:55 PM
SYSTM Executable only 7/29/2024 2:52:51 PM

Show-SourcesDir # shows contents of the current sources directory (where you should put all the 7z and msi files that you want to use!)
Name                                                LastWriteTime
----                                                -------------
CRYSTAL Floor Communication Service 10.97.00.58.msi 1/18/2024 9:18:12 AM
Crystal_Control_v7.5.0.1901.7z                      12/28/2023 12:00:55 PM
Floorserver-Setup 10.95.0.139.msi                   11/3/2023 6:00:58 PM
Galaxis v10.97.00.2926(Config only).7z              7/29/2024 4:39:16 AM
Galaxis v10.97.00.2926(Executable only).7z          7/29/2024 4:38:12 AM
Galaxis v10.97.00.2926(Other only).7z               7/29/2024 4:39:47 AM
MBoxUI.1.4.0.107.7z                                 4/19/2024 5:55:18 PM
MBoxUI.Configuration.1.4.0.107.7z                   4/19/2024 5:55:17 PM
nginx-1.23.1.zip                                    8/2/2022 3:18:59 PM
QueryBuilder-Setup 10.95.0.139.msi                  11/3/2023 6:00:55 PM
RabbitMQ_10.96.7z                                   1/25/2024 4:43:59 PM
RgMonitorProcess.6.3.0.61.7z                        12/20/2023 10:32:00 AM
RgMonitorWebsite.6.3.0.61.7z                        12/20/2023 10:32:00 AM
SetupJPApplications.msi                             6/9/2023 3:37:31 PM
SetupJPReporting.msi                                6/9/2023 3:37:33 PM
SetupSecurityServerConfig.msi                       6/9/2023 3:37:35 PM
SYSTM Classic v10.97.00.2926(Config only).7z        7/29/2024 4:29:17 AM
SYSTM Classic v10.97.00.2926(Executable only).7z    7/29/2024 4:29:14 AM
UnCompressOnGalaxisHomeInstall07.7z                 12/16/2022 1:05:06 PM

Clear-PrepDir   # clears the preparation directory - now we have a clean slate!

# the next steps are only preparation steps that do not affect the current installation
# they are just preparing the different folders for deployment, can be done the day before for example!

Prep-HFandLib   # extracts the HF scripts and the galaxisoralce.jar

Prep-Galaxis Executables # extracts the Galaxis Executables
Prep-Galaxis Config 
Prep-Galaxis Other
Prep-Galaxis Install    
#Prep-Galaxis ALL   # this will extract Executables, Config and Other in one step!

Prep-SYSTM Executables
Prep-SYSTM Config
#Prep-SYSTM ALL     # this will extract Executables and Config in one step!
```

## Deploying upgrades
```powershell
Stop-MOD-Services   # stop all Services
Show-CurrentGLXVersion  # shows the version of BackOfficeSlotOperation.exe as an indicator of the installed Galaxis version!
 - Currently deployed vesion:
------------------------------
  -  10.96.01.2450
------------------------------

Clear-GLXGarbage    # gets rid of *.DMP files from application crashes
-----------------------------------------------
Size of D:\Galaxis before cleaning (in MB):   3736.7676076889
Size of D:\Galaxis after cleaning (in MB):  3736.7676076889
-----------------------------------------------
Cleaned out (in MB):  0
-----------------------------------------------

Clear-GLXLogs   # clears the logs direcories - RTDS included!
-----------------------------------------------
Size of D:\Galaxis before cleaning (in MB):   3736.7676076889
Size of D:\Galaxis after cleaning (in MB):  3736.7676076889
-----------------------------------------------
Cleaned out (in MB):  0
-----------------------------------------------

Backup-GLXDir   # will make a backup of D:\Galaxis to D:\_BACKUP

    Directory: D:\_BACKUP

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d----           7/31/2024 12:34 PM                Galaxis_31072024-1224

 Log File : C:\Windows\temp\2024-07-31 12-34-28 robocopy staging.log
VERBOSE: Performing the operation "Start-Process" on target "C:\Windows\system32\Robocopy.exe "D:/Galaxis" "D:/_BACKUP\Galaxis_31072024-1224" /LOG:"C:\Windows\temp\2024-07-31 12-34-30 robocopy.log" /ipg:200 /MIR /NP /NDL /NC /BYTES /NJH /NJS".

 Log File : C:\Windows\temp\2024-07-31 12-34-30 robocopy.log

BytesCopied : 3959034444
FilesCopied : 17477

Backup done.

Disable-M-Share     # disables the sharing of D:\Galaxis as M:\ - this will stop access from workstations that might cause issues when trying to overwrite certain binaries!
Disabling the sharing of D:\Galaxis!

Deploy-Galaxis Executables  # This will copy the prepared Executables folder to D:\Galaxis and overwrite everything!
Deploy-Galaxis Config       # This will copy the prepared Config folder to D:\Galaxis, no existing configuration files will be overwritten!
Deploy-Galaxis Other        # This will copy the prepared Other folder to D:\Galaxis and overwrite everything!
Deploy-Galaxis Install      # This will copy the prepared Install folder to D:\Galaxis and overwrite everything!
#Deploy-Galaxis ALL         # handles Executables, Config and Other!


Deploy-SYSTM Executables    # This will copy the prepared SYSTM Executables folder to D:\Galaxis and overwrite everything!
Deploy-SYSTM Config         # This will copy the prepared SYSTM Config folder to D:\Galaxis, no existing configuration files will be overwritten!

Show-CurrentGLXVersion  # show reflect the change made by the deployment!
 - Currently deployed vesion:
------------------------------
  -  10.97.00.2926
------------------------------

Install-MOD-Services    # checks the expected services and installs them as needed (using WinSW-folder scripts!)

Enable-M-Share  # enables the sharing of D:\Galaxis as M:\ again - workstations will again have access.
```

## Reinstalling RabbitMQ
```powershell
Uninstall-RabbitMQ  # will ninstall Erlang OTP and RabbitMQ Server
Stopping RabbitMQ service!
RabbitMQ service stopped!
Starting to uninstall RabbitMQ Server!
#known issue - might stop after deinstallation of Erlang OTP and get stuck
#in this case just press CTRL+C and repeat the step
Uninstall-RabbitMQ
Did not find RabbitMQ service!
RabbitMQ Server not installed!
Starting to uninstall Erlang OTP!
Erlang OTP was uninstalled!
Clearing out RabbitMQ directories!
Clearing Ericsson-registry entry!
VERBOSE: Performing the operation "Remove Key" on target "Item: HKEY_LOCAL_MACHINE\SOFTWARE\Ericsson".
Install-RabbitMQ    # will install and configure RabbitMQ by using the bat-files provided from RnD - using the updated binaries that were deployed!
```
<details>
<summary>expand for details!</summary>

```plaintext
Did not find RabbitMQ service!
RabbitMQ Server not installed!
Erlang OTP not installed!
Clearing out RabbitMQ directories!
Clearing Ericsson-registry entry!
Starting installation...
--------------------------

D:\Galaxis\Install\Batch>REM --- Set up RabbitMQ configuration

D:\Galaxis\Install\Batch>REM --- Set ERLANG_HOME

D:\Galaxis\Install\Batch>set ERLANG_HOME=D:\Galaxis\Program\bin\Erlang

D:\Galaxis\Install\Batch>REM --- Set Rabbit MQ variables

D:\Galaxis\Install\Batch>REM --- Change RabbitMQ Logs location

D:\Galaxis\Install\Batch>set RABBITMQ_BASE=D:\Galaxis\Data\RabbitMQ

D:\Galaxis\Install\Batch>set RABBITMQ_LOG_BASE=D:\Galaxis\Log\RabbitMQ

D:\Galaxis\Install\Batch>REM --- This is a script for the automatic installation for RabbitMQ application

D:\Galaxis\Install\Batch>REM --- For RabbitMQ to be installed, first we need to install Erlang/OTP

D:\Galaxis\Install\Batch>"D:\Galaxis\Install\Batch\lib\otp_win64_25.3.exe" /c /S /D=D:\Galaxis\Program\bin\Erlang

D:\Galaxis\Install\Batch>REM --- Now RabbitMQ is to be installed

D:\Galaxis\Install\Batch>"D:\Galaxis\Install\Batch\lib\rabbitmq-server-3.11.28.exe" /c /S /D=D:\Galaxis\Program\bin\RabbitMQ

D:\Galaxis\Install\Batch>REM --- Update Rabbit MQ service parameters

D:\Galaxis\Install\Batch>sc config RabbitMQ start= demand
[SC] ChangeServiceConfig SUCCESS

D:\Galaxis\Install\Batch>D:\Galaxis\Program\bin\RabbitMQ\rabbitmq_server-3.11.28\sbin\rabbitmq-service.bat install
RabbitMQ service is already present - only updating service parameters

D:\Galaxis\Install\Batch>REM --- THIS THE RABBITMQ MANAGEMENT CONFIGURATION

D:\Galaxis\Install\Batch>call "D:\Galaxis\Program\bin\RabbitMQ\rabbitmq_server-3.11.28\sbin\rabbitmq-plugins.bat" enable rabbitmq_management
Enabling plugins on node rabbit@ModulusAPP:
rabbitmq_management
The following plugins have been configured:
  rabbitmq_management
  rabbitmq_management_agent
  rabbitmq_web_dispatch
Applying plugin configuration to rabbit@ModulusAPP...
The following plugins have been enabled:
  rabbitmq_management
  rabbitmq_management_agent
  rabbitmq_web_dispatch

started 3 plugins.
Adding user "mis" ...
Done. Don't forget to grant the user permissions to some virtual hosts! See 'rabbitmqctl help set_permissions' to learn more.
Setting permissions for user "mis" in vhost "/" ...
Setting tags for user "mis" to [administrator] ...
Reinstallation finished!
```
</details>


## Upgrading DB and restarting services
```powershell
Execute-GalaxisOracle-jar   # Executes the ..\prep\HFandLib\galaxisoracle.jar with the needed parameters
                            # currently using hardcoded credentials, needs to be fixed! (mis!)
<#todo:
    - run HF scripts as needed manually!
    - run HF scripts via liquibase??
    - compile DB
#>

Start-MOD-Services

Show-MOD-Services
```

---

<a name="Jackpot"></a>

## Jackpot
```powershell
Backup-OnlineData
Set-DBX-Config
Set-SecurityServer-Config
Show-MOD-Components
Databases on this server:

name version
---- -------
GLX  19.0.0.0.0 Production
JKP  19.0.0.0.0 Production

Tools on this server:

name                 version
----                 -------
7-Zip                22.01
Notepad++            8.6.9
Oracle SQL Developer 22.2.1.234.1810
Oracle SQLcl         22.4.0.342.1212
NewDMM               1.0.0.0
FloorPlanDesigner    0.37.3
FloorPlanGenerator   10.93.00.1971
CleanRegistry        1.1.0.0
QueryBuilder         10.94.0.135

Modules on this server:

name                 version
----                 -------
OnlineData           -
DBX                  -
SecurityServer       -
JPChecksumCalculator 1.0.0.62
Floorserver          -
Reservation Agent    -
Qsched               -
Floor Messenger      -

Uninstall-JPApps    # uninstalls all 3 JP Applications (if found)
Install-JPApps      # installs all 3 JP Applications 
Set-JP-Config       # configures the respective .ini's
```

---

<a name="FS"></a>

# FS
```powershell
Stop-MOD-Services
Backup-OnlineData   # backups your D:\OnlineData directory

Install-Floorserver # installs the Floorserver.msi in your sources directory as a silent installation!
Set-FS-Config       # sets IPs and DHCP ranges from your mod-VM-config.json into the def.cfg of the FS!
Show-FS-Config      # opens the fscfg.tcl85 of your FS!
Start-MOD-Services

Prep-MBoxUI
Deploy-MBoxUI
```

---

<a name="CFCS"></a>

# CFCS
```powershell
Stop-MOD-Services
Uninstall-CFCS
Install-CFCS
Set-CFCS-Config
Start-MOD-Services
```

---

<a name="Control"></a>

# Control
```powershell
Stop-MOD-Services
Backup-OnlineData
Prep-CRYSTALControl
Deploy-CRYSTALControl
Set-CRYSTALControl-Config
Start-MOD-Services
```

---

<a name="PlayWatch"></a>

# PlayWatch
```powershell
Prep-PlayWatch
Deploy-PlayWatch
Set-PlayWatch-Config   

Set-AML-Config

```

---

<a name="Oracle"></a>

# Oracle

In order to execute scripts directly in our databases the scripts will ask you for the needed credentials and then store them in a Microsoft SecretStore vault.
Afterwards, whenever you execute a script that needs that same credential you will not be asked gain. If you mistakenly save a wrong credential it can be deleted from the vault. 
If you need help, let me know.

**Initial settings to the DB, exporting and importing,
spooling and executing privileges, compiling the DBs:**
```powershell
#GLX-related:
Set-GLX-default-profile #sets case sensitive settings/password life time settings, etc.
Show-GLX-mod-users  #shows the modulus specific users within GLX
Spool-GLX-sys-privileges  #Spools sys privileges to G:\Export
Spool-GLX-table-privileges  #Spools table privileges to G:\Export
Execute-GLX-sys-privileges #Executes the sys priviliges from G:\Export into the DB
Execute-GLX-table-privileges #Executes the table priviliges from G:\Export into the DB
Compile-GLX-Serial  #compiles GLX using recomp_serial.sql
Compile-GLX-Invalids #compiles GLX using compile_database.sql
Show-GLX-Invalids #shows the current invalid objects 
Prep-GLX-EXP_DIR  #prepares EXP_DIR->G:\Export in GLX
Spool-GLX-drop-users  #spools a drop statement for all modulus users within GLX
Execute-GLX-drop-users  #executes that spooled statement - confirmation is asked, currently buggy, care!
Export-GLX-Full #runs a full export on GLX to EXP_DIR, G:\Export
Import-GLX-Full #runs a full import from EXP_DIR, G:\Export to GLX!

#Other:
Show-GLX-betabli  #Shows the most relevant info from the table GALAXIS.BETABLI


#------------
#JKP-related:
Set-JKP-default-profile #sets case sensitive settings/password life time settings, etc.
Show-JKP-mod-users  #shows the modulus specific users within JKP
Spool-JKP-sys-privileges  #Spools sys privileges to F:\Export
Spool-JKP-table-privileges  #Spools table privileges to F:\Export
Execute-JKP-sys-privileges #Executes the sys priviliges from F:\Export into the DB
Execute-JKP-table-privileges #Executes the table priviliges from F:\Export into the DB
Compile-JKP-Serial  #compiles JKP using recomp_serial.sql
Compile-JKP-Invalids #compiles JKP using compile_database.sql
Show-JKP-Invalids #shows the current invalid objects 
Prep-JKP-EXP_DIR  #prepares EXP_DIR->F:\Export in GLX

Spool-JKP-drop-users  #spools a drop statement for all modulus users within GLX
Execute-JKP-drop-users  #executes that spooled statement - confirmation is asked, currently buggy, care!

Export-JKP-Full #runs a full export on JKP to EXP_DIR, F:\Export
Import-JKP-Full #runs a full import from EXP_DIR, F:\Export to JKP!

#Other:
Show-JKP-DB-version #shows the contents of the grips_patch_tables
```
More to come!

---

<a name="Helpers"></a>

# Helpers
```powershell
Install-QueryBuilder
Install-OEMJava
Uninstall-OEMJava

Map-I-Share
Map-M-Share



Open-Config SlotMachineServer # tab completion, a couple of config files available!
```

---

<a name="Sysprep/Setup"></a>

# Sysprep/Setup
```powershell
#make sure modulus-sysprep is loaded!
#the module is optional and is enabled by a specific key to avoid wrong usage!
<#
PowerShell 7.4.5
Loading modulus-base!
Initializing needed modules...
Initializing module vault...
Initializing needed tools...
Loading modulus-core!
Loading modulus-sysprep! (optional)
Loading modulus-toolkit!
Successfully loaded v1.4!
'Open-MOD-Help' to open README.md!
No changes detected.
Loading personal and system profiles took 2076ms.
#>
Set-Sysprep-Status RESET
Get-Sysprep-Status

status
------
@{legacy=False; registry=False; msdtc=False; restart=False; sysprep=False; disks=False; NICs=False; init=False}

#the following steps are best done via a vsphere connection or comparable, since connection through network adapters will be cut!
#1st execution
Modulus-Sysprep #will trigger a restart  

Get-Sysprep-Status  #every entry including restart will now be true, thus next step will be sysprep!

status
------
@{legacy=True; registry=True; msdtc=True; restart=True; sysprep=False; disks=False; NICs=False; init=False}

#2nd execution 
Modulus-Sysprep #will do the actual sysprep

#3rd execution
Modulus-Sysprep #will be run automaticaly after the sysprep

#After the sysprep script is finished you can continue via these 3 options, depending on the server you are on!
Initialize-DB
Initialize-APP
Initialize-FS
```

---


# this is not everything, I will try to document more as I go along!
# if something does not work as exepcted or is confusing, please let me know and i will try to improve it!
# feedback is very welcome!
