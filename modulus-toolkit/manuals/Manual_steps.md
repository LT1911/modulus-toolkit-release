# Manual installation steps for Galaxis/SYSTM

**Version:** 1.0.0
**Author:** Thomas Lukas  
**Last Updated:** 25.08.2025

All the manual steps necessary when updating to  different Galaxis/SYSTM versions!

---

## Table of Contents

1. [Galaxis/SYSTM 10.97](#1)
2. [Galaxis/SYSTM 10.99](#2)
3. [Galaxis/SYSTM 10.101](#3)
4. [Mandatory final steps](#4)


---

<a name="1"></a>

## 1. Galaxis/SYSTM 10.97


## Edit your AuthenticationService.ini:
```powershell
open-config AuthenticationService
<#
...
DBTnsAlias=//PH_DBSERVER_IP:1521/GLX
...
[General]
PinRequired=false
EnableSSL=false
AllowedInactivityPeriod=120
#>
```

##  Edit your ServicesToStart.xml:
```powershell
np D:\Galaxis\Program\bin\ServicesToStart.xml
<#
#compare to ModulusAPP template, add new services, add rabbitMQ/nginx if it isn't already, etc.
#>
```

## Edit your Auth.Service.Start.exe.config:
```powershell
np D:\Galaxis\Program\bin\AuthenticationService\Auth.Service.Start.exe.config
#check Auth.Service.Start.exe.config 
#add this line if it does not exist yet:
#    <add key="AllowedInactivityPeriod" value="60"/> 
```

## Edit your AddressBook.xml:
```powershell
#check addressbook.xml and add 2 new lines and put the correct IP in
#replace existing hostnames by the correct IP  (PH_APPSERVER_HOSTNAME -> PH_APPSERVER_IP)
open-config AddressBook
<# add these 2 lines:
    <service name="PlayerService" address="http://PH_APPSERVER_IP:5010"/>
    <service name="LoyaltyService" address="http://PH_APPSERVER_IP:5011"/>
#>
```

## Edit Report.ini:
```powershell
#manual config changes for https://modulusgroup.atlassian.net/browse/GLXHOST-3678

#open the files:
np D:\Galaxis\Program\Common\Report.ini

#add this line for Star Table reports
#   2040=\Program\StarTable\Report\TableAccountingCountSummaryReport.rtm

```

## Edit the following files:
```powershell
#manual config changes for https://modulusgroup.atlassian.net/browse/GLXHOST-2940

#open the files:
np D:\Galaxis\Program\bin\AuthenticationService\Auth.Service.Start.exe.config
np D:\Galaxis\Program\bin\Config\QPonCash\QPonCashService-Settings.config
np D:\Galaxis\Program\bin\Config\StarCage\CageIntelligence\CageIntelligence-Settings.config
np D:\Galaxis\Program\bin\Config\StarControl\StatutoryService\StatutoryService-Settings.config
np D:\Galaxis\Program\bin\Config\StarMarketing\MarketingIntelligence\MarketingIntelligence-Settings.config
np D:\Galaxis\Program\bin\Config\StarSlots\FloorAlarmService\FloorAlarmService-Settings.config
np D:\Galaxis\Program\bin\Config\StarSlots\SlotDataExporterService\SlotDataExporterService-Settings.config
np D:\Galaxis\Program\bin\Config\StarSlots\SlotIntelligence\SlotIntelligence-Settings.config

#add this line for each file if it does not exist yet:
#   <add key="FloorServer_NoExcTimeout" value="300" /> <!-- 0 = disabled -->

```

## Reinstall RabbitMQ:
```powershell
Install-RabbitMQ
<#
Installation got stuck the first time
Press strg+c
Start the installation again it will run through
#>
<#
localhost:15672
#>
```

---


<a name="2"></a>

## 2. Galaxis/SYSTM 10.99


## Checking for installed ASP.NET & .NET Runtime versions!
```powershell
#Run this powershell script as administrator!
#Galaxis 10.99 now needs ASP.NET and .NET runtime versions 8.0!
#If the script does not return a version like this, you need to install those before starting the services!

Show-InstalledRuntime .NET
#   ASP.NET Core Runtime is installed. Versions found: 6.0.7, 8.0.14
Show-InstalledRuntime ASP.NET
#   ASP.NET Core Runtime is installed. Versions found: 6.0.7, 8.0.14
```

## Manual step after Prep-Galaxis ALL, before deploying! Not needed with 10.100 and higher!
```powershell
<#
Go to folder I:\modulus-toolkit\sources
Using 7z:

1.) Extract 
    Galaxis v10.99.00.3274(Config only).7z\Galaxis Classic\Executable\Server\Galaxis\Program\Bin\* 
to  I:\modulus-toolkit\prep\Executable only\Program\bin\*

2.) Extract 
    Galaxis v10.99.00.3274(Config only).7z\Galaxis Classic\Configuration\Server\Galaxis\Program\Common\ePayGate.ini 
to  I:\modulus-toolkit\prep\Config only\Program\Common\*

3.) Extract
    Galaxis v10.99.00.3274(Other only).7z\Galaxis Classic\Executable\Server\Galaxis\Program\Bin\* 
to  I:\modulus-toolkit\prep\Executable only\Program\bin\*

4.) Go to I:\modulus-toolkit\prep\Web only\Web\SYSTM\browser\ and move everything in it one folder up, then remove the folder browser!

#>
```

##  Edit your ServicesToStart.xml:
```powershell
np D:\Galaxis\Program\bin\ServicesToStart.xml
<#
#add these 2 new <SERVICE>-entries at the end of the file within the <SERVICES>-block:
<SERVICE name="data-setup-service">
    <DEPENDENCIES>
        <DEPENDENCY type="DB">GALAXIS</DEPENDENCY>
    </DEPENDENCIES>
</SERVICE>
<SERVICE name="assets-service">
    <DEPENDENCIES>
        <DEPENDENCY type="NONE">NONE</DEPENDENCY>
    </DEPENDENCIES>
</SERVICE>
#>
```

## Edit your AddressBook.xml:
```powershell
#check addressbook.xml and add 2 new lines and put the correct IP in
#replace existing hostnames by the correct IP  (APP_SERVER_HOSTNAME -> APP_SERVER_IP)
open-config AddressBook
<# add these 2 lines:
    <server name="AssetFTPServer" address="PH_FSERVER_IP" port="21" />
    <server name="AssetHTTPServer" address="PH_FSERVER_FLOOR_IP" port="80" />

 and those 3 lines under APIs:
    <service name="DataSetupService" address="http://PH_APPSERVER_IP:5013"/>
    <service name="JunketService" address="http://PH_APPSERVER_IP:5012"/>
    <service name="AssetsService" address="http://PH_APPSERVER_IP:5014"/>
#>
```

## Copy updated *.rtm files to your installation
```powershell
<#
Replace the following reports from Other Only package in M:\Program\StarCage\Report
- AccountBalance.rtm
- CageSummary.rtm
- CageSummaryDetailed.rtm
- Receipt.rtm
Replace the following reports from Other Only package in M:/Program/StarTable/Report
- Permanences.rtm
#>
```

## Add a picture for deposit tender
```powershell
<#
Data Setup
in General / Tender Type (Moyen de Paiement)
load image for Tender Type deposit 
image path = "M:\Program\StarCage\Images\Transactions\deposit.gif"
if Deposit is written with strange characters, rename it in GTENDERTYP!
#>
```

## Edit the systm-db-configuration.json:
```powershell
#open the files:
np D:\Galaxis\Program\Common\systm-db-configuration.json
<#
#overwrite the content like this:
#PASSWORD-fields need to be encoded using EncryptionOnlyTool!

{
	"DB": {
		"JUNKET": {
			"DATASOURCE": "//PH_DBSERVER_IP:1521/GLX",
			"SCHEMA": "JUNKET",
			"USERNAME": "JUNKET",
			"PASSWORD": "WM/d3mHEnwuZ8WV2a27PTQ=="
		},
		"ASSET": {
			"DATASOURCE": "//PH_DBSERVER_IP:1521/GLX",
			"SCHEMA": "ASSET",
			"USERNAME": "ASSET",
			"PASSWORD": "buZxWySl2SxSrsVnDR9rsw=="
		}
	}
}

#>
```

## Edit the reverse-proxy.conf of nginx:
```powershell
#open the files:
np D:\Galaxis\Program\bin\nginx\modulus\reverse-proxy.conf
<#
    #add the entry for the Assets Service at the end of the file like this:

    location ~* /api/asset {
            rewrite ^/api/asset/(.*)$ $1 break; 
            proxy_pass http://PH_APPSERVER_IP:5014/api/core/$1$is_args$args;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

#>
```

## Edit the config.json of SYSTM:
```powershell
#open the files:
np D:\Galaxis\Web\SYSTM\assets\config.json
<#
#configure the file like this:

{
  "apiUrl": "http://PH_APPSERVER_IP:4445/api/",
  "apiUrlMedia": "http://PH_APPSERVER_IP:4445/api/asset/v1/assets",
  "httpFileServerUrl": "http://PH_FSERVER_IP/"
}

#>
```

## Edit the OutboxService\appsettings.json
```powershell
#open the files:
np D:\Galaxis\Program\bin\OutboxService\appsettings.json
<#
#PollingRate is now using miliseconds, so at the very beginning of the file set:

      "PollingRate": "1000",
#>
```

## Cleanup
```powershell
<#
#Remove the following folders from your D:\Galaxis-directory since they are no longer needed!
D:\Galaxis\Program\bin\GlxApi\*
D:\Galaxis\Program\bin\GlxPartnerApi\*
D:\Galaxis\Program\bin\GlxPublicApi\*
D:\Galaxis\Program\bin\LicenseServer\* 

D:\Galaxis\Program\bin\Config\GlxApi\*
D:\Galaxis\Program\bin\Config\GlxPartnerApi\*
D:\Galaxis\Program\bin\Config\GlxPublicApi\*
D:\Galaxis\Program\bin\Config\LicenseServer\* 

#>
```

---


<a name="3"></a>

## 3. Galaxis/SYSTM 10.101


## Copy updated *.rtm files to your installation
```powershell
<#
Replace the following reports from Other Only package in M:/Program/StarTable/Report
- Permanences.rtm
#>
```

## For existing environments, update the Application Server inittab to add -Duser.name=… for RTDS
```powershell
<#
# R.T.D.S programs
id="1.SLOT MACHINE SERVER" cmd="d:\Galaxis\Install\JRE\bin\java.exe -classpath smserv3.jar;%GALAXIS_ORACLE_HOME%\jdbc\lib\ojdbc8.jar;%GALAXIS_ORACLE_HOME%\jdbc\lib\ojdbc6.jar;../../Common/Current/*;../../../Common/Current/*;../../../Common/Current/axis/*;../../../Vision/Current/starvision.jar -Xmx1024m -Djni.libraries.path=d:\Galaxis\Application\OnLine\Common\Current -DARIMETERDLL=d:\Galaxis\Application\Online\Common\Current\JNIImplementation.dll -Duser.name=SMSERV mc.mis.server.smserv3.onlineorchestra.Conductor /SYS_ERR" home="d:\Galaxis\Application\Online\SlotMachineServer\Current" stoptime="2" flags="console"
id="2.ALARM SERVER" cmd="d:\Galaxis\Install\JRE\bin\java -classpath alarmserver.jar;../../SlotMachineServer/Current/smserv3.jar;%GALAXIS_ORACLE_HOME%\jdbc\lib\ojdbc8.jar;%GALAXIS_ORACLE_HOME%\jdbc\lib\ojdbc6.jar;../../Common/Current/*;../../../Common/Current/*;../../../Common/Current/axis/*;../../../Vision/Current/starvision.jar -Xmx1024m -Djni.libraries.path=d:\Galaxis\Application\Online\Common\Current -Duser.name=ALARMSERVER mc.mis.server.alarmserver.AlarmServer /SYS_ERR" home="d:\Galaxis\Application\Online\AlarmServer\Current" stoptime="5" flags="console"
id="3.TRANSACTION SERVER" cmd="d:\Galaxis\Install\JRE\bin\java -classpath transactionserver.jar;../../SlotMachineServer/Current/smserv3.jar;../../../Vision/Current/starvision.jar;%GALAXIS_ORACLE_HOME%\jdbc\lib\ojdbc8.jar;%GALAXIS_ORACLE_HOME%\jdbc\lib\ojdbc6.jar;../../Common/Current/*;../../../Common/Current/*;../../../Common/Current/axis/*;../../../../Program/bin/MessengerService/lib/* -Xmx128m -Djni.libraries.path=d:\Galaxis\Application\Online\Common\Current -Duser.name=TRNSERVER mc.mis.server.transactionserver.TransactionServer /SYS_ERR" home="d:\Galaxis\Application\Online\TransactionServer\Current" stoptime="5" flags="console"
#>
```

---


<a name="4"></a>

## 4. Mandatory final steps


## Clear your browsers cache!
```powershell
#Press F12 (in Chrome) to enable developer mode, then go to the refresh button (left of the URL) and right-click it, then choose "Empty Cache and Hard Realod"!
#This will ensure that newly deployed SYSTM Web components are correctly used!
```
![Chrome](screenshots\Chrome_cache.png)


## Install required DB scripts:
```powershell
prep-HFandLib
cd I:\modulus-toolkit\prep\HFandLib
dir
<#
sqlplus sys/asdba@glx as sysdba

spool common.sql
show user
@'Scripts 10.<version-number> [1] Common.sql'
--mis
--G:\Oracle
--GLX
spool end

spool specific.sql
show user
@'Scripts 10.<version-number>  [2] Specific.sql'
--site
spool end

spool specific.sql
show user
@'Scripts 10.<version-number>  [3] Import_en.sql'
spool end

#>
```

## Execute new galaxisoracle.jar:
```powershell
Execute-GalaxisOracle-jar
<#
in the same powershell run the execute-galaxisOracle-jar 
#>
```

## Check your database for invalid objects:
```powershell
Show-GLX-Invalids
Compile-GLX-Serial
Show-GLX-Invalids
<#
This will show you the invalid objects within your GLX instance, then compile it, and then again show you how the status has improved.
#>
```

*This list of manual steps should give an overview over all installation instructions within the release notes that are not automated or are too specific to automate.
The goal is to have very few manual steps and to automate everything that can reliably be automated.*

---

