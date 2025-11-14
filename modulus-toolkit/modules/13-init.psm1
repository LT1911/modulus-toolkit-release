#tlukas, 23.10.2025

#write-host "Loading 13-init.psm1!" -ForegroundColor Green

#region --- parameters
$dependencies = @(
    "PSIni",
    "Microsoft.PowerShell.SecretManagement",
    "Microsoft.PowerShell.SecretStore",
    "pstemplate")
  
$legacyPath = 'C:\Program Files\PowerShell\Modules\modulus-toolkit\config\mod-VM-config.json'
$scopePath  = 'C:\Program Files\PowerShell\Modules\modulus-toolkit\config\scope.json'
$pfxPath    = 'C:\Program Files\PowerShell\Modules\modulus-toolkit\config\crypto.pfx'
#endregion
 
#region --- module initialization
Initialize-Modules -Modules $dependencies
Initialize-Config -Force
#Convert-LegacyConfig -LegacyPath $legacyPath -ScopePath $scopePath #-RemoveLegacy
Initialize-Vault
#Enable-VaultWithoutPassword
Initialize-Tools
Initialize-Environment
Initialize-CryptoModule -PfxPath $pfxPath -DeletePfxAfterImport 
#endregion

#region --- check for updates/components
Find-Toolkit-Updates
Assert-MOD-Components -Silent
#endregion