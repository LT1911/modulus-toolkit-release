# How to configure peripherals for Galaxis!

## Marketing Reception - Evolis 
```powershell
np D:\Galaxis\Application\Marketing\MarketingReception\Config\Common\Current\MarketingReception.ini

<#
[GESTION CARTE]
FORMATCARTE=DEFAULT
// card printer type 
// DATACARD EXPRESS, TOP-INO COLOR PRINTER, TOP COLOR PRINTER, DATACARD SELECT, 
// ELTRON P420, ELTRON P420 RECTO-VERSO, DATACARD SELECT RECTO-VERSO
TYPEIMPRIMANTECARTE=EVOLIS RECTO-VERSO
// card printer name for normal card 
NOMIMPRIMANTECARTE=Evolis 
// card printer name for chip card 
CHIPCARDPRINTER=Evolis 
// print version
VERSIONIMPRESSION=2
// encode version
VERSIONREENCODAGE=2
TYPECARTE=1
// print name on card [ON/OFF]
NOM=ON
// print first name on card [ON/OFF]
PRENOM=ON
// print alias on card [ON/OFF]
PSEUDONYME=OFF
// print card number on card [ON/OFF]
NUMEROCARTE=ON
// print expiry date on card [ON/OFF]
DATEEXPIRATION=ON
// print photo on card [ON/OFF]
PHOTOGRAPHIE=ON
DELAIIMPRESSIONCARTE=20
#>
```_