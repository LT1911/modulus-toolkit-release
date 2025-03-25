# Manual steps for Galaxis 10.97 update!

## Edit your AuthenticationService.ini:
```powershell
open-config AuthenticationService
<#
...
DBTnsAlias=//IP of DB Server:1521/GLX
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
#replace existing hostnames by the correct IP  (APP_SERVER_HOSTNAME -> APP_SERVER_IP)
open-config AddressBook
<# add these 2 lines:
    <service name="PlayerService" address="http://APP_SERVER_IP:5010"/>
    <service name="LoyaltyService" address="http://APP_SERVER_IP:5011"/>
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
#   <add key="FloorServer_NoExcTimeout" value="0" /> <!-- 0 = disabled -->

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

## Install required DB scripts:
```powershell
prep-HFandLib
<#
open new powershell and connect as sys to run the scripts from I:\modulus-toolkit\prep\HFandLib
#>
```

## execute new galaxisoracle.jar:
```powershell
execute-galaxisOracle-jar
<#
in the same powershell run the execute-galaxisOracle-jar 
#>
```

**let me know if I forgot something!**