# Manual steps for Galaxis 10.99 update!

## Checking for installed ASP.NET & .NET Runtime versions!
```powershell
#Run this powershell script as administrator!
#Galaxis 10.99 now needs ASP.NET and .NET runtime versions 8.0!
#If the script does not return a version like this, you need to install those before starting the services!
#This functionality will be introduced into the normal toolkit-scope, then its just a normal function call!

# Define the base Program Files directory
$programFiles = ${env:ProgramFiles}

# Build the paths to the shared runtime directories
$aspnetCoreSharedPath = Join-Path $programFiles "dotnet\shared\Microsoft.AspNetCore.App"
$dotnetSharedPath = Join-Path $programFiles "dotnet\shared\Microsoft.NETCore.App"

# Function to check if any version is installed
function Check-InstalledRuntime {
    param(
        [string]$path,
        [string]$runtimeName
    )
    
    if (Test-Path $path -PathType Container) {
        $versions = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        if ($versions.Count -gt 0) {
            Write-Output "$runtimeName is installed. Versions found: $($versions -join ', ')"
        }
        else {
            Write-Output "$runtimeName folder exists but no versions were detected."
        }
    }
    else {
        Write-Output "$runtimeName is NOT installed."
    }
}

# Check for ASP.NET Core runtime
Check-InstalledRuntime -path $aspnetCoreSharedPath -runtimeName "ASP.NET Core Runtime"

# Check for .NET Runtime
Check-InstalledRuntime -path $dotnetSharedPath -runtimeName ".NET Runtime"

```

## Manual step after Prep-Galaxis ALL, before deploying!
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
@'Scripts 10.99 [1] Common.sql'
--mis
--G:\Oracle
--GLX
spool end

spool specific.sql
show user
@'Scripts 10.99 [2] Specific.sql'
--site
spool end

spool specific.sql
show user
@'Scripts 10.99 [3] Import_en.sql'
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



**let me know if I forgot something!**