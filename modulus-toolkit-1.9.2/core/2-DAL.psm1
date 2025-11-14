#tlukas, 21.10.2025

#write-host "Loading \core\2-DAL.psm1!" -ForegroundColor Green

#region --- scope.json
#region --- scope.json general
function Get-GeneralSystem {
    param([switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key 'general.system' -Prompt:$Prompt -Default:$Default
}
Set-Alias -Name PH_ENVIRONMENT      -Value Get-GeneralSystem
function Set-GeneralSystem {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('3VM','1VM')]$System)
    Set-ScopeValue -Key 'general.system' -Value $System -ValidateAs NonEmpty -CreateMissing
}

function Get-GeneralTimezone {
    param([switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key 'general.timezone' -Prompt:$Prompt -Default:$Default
}
Set-Alias -Name PH_TIMEZONE         -Value Get-GeneralTimezone
Set-Alias -Name Get-MOD-TimeZone    -Value Get-GeneralTimezone
function Set-GeneralTimezone {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Timezone)
    Set-ScopeValue -Key 'general.timezone' -Value $Timezone -ValidateAs NonEmpty -CreateMissing
}

function Get-GeneralLanguage {
    param([switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key 'general.language' -Prompt:$Prompt -Default:$Default
}
Set-Alias -Name PH_DEFAULT_LANGUAGE -Value Get-GeneralLanguage
function Set-GeneralLanguage {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Language)
    Set-ScopeValue -Key 'general.language' -Value $Language -ValidateAs NonEmpty -CreateMissing
}
#endregion

#region --- scope.json customer
function Get-CustomerCode {
    param([switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key 'customer.code' -Prompt:$Prompt -Default:$Default
}
Set-Alias -Name PH_SOCIETY          -Value Get-CustomerCode
Set-Alias -Name PH_CUSTOMER_CODE    -Value Get-CustomerCode
function Set-CustomerCode {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Code)
    Set-ScopeValue -Key 'customer.code' -Value $Code -ValidateAs NonEmpty -CreateMissing
}

function Get-CustomerName {
    param([switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key 'customer.name' -Prompt:$Prompt -Default:$Default
}
Set-Alias -Name PH_SOCIETY_NAME  -Value Get-CustomerName
Set-Alias -Name PH_CUSTOMER_NAME -Value Get-CustomerName
function Set-CustomerName {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)
    Set-ScopeValue -Key 'customer.name' -Value $Name -ValidateAs NonEmpty -CreateMissing
}
#endregion 

#region --- scope.json casino
function Get-CasinoID     { param([switch]$Prompt, [int]$Default) Get-ScopeValue -Key 'casino.ID'        -Prompt:$Prompt -Default:$Default }
Set-Alias -Name PH_CASINOID           -Value Get-CasinoID
Set-Alias -Name PH_CASINO_ID          -Value Get-CasinoID
function Get-CasinoCode   { param([switch]$Prompt, [string]$Default) Get-ScopeValue -Key 'casino.code'   -Prompt:$Prompt -Default:$Default }
Set-Alias -Name PH_ESTABLISHMENT      -Value Get-CasinoCode
Set-Alias -Name PH_CASINO_CODE        -Value Get-CasinoCode
function Get-CasinoName   { param([switch]$Prompt, [string]$Default) Get-ScopeValue -Key 'casino.name'   -Prompt:$Prompt -Default:$Default }
Set-Alias -Name PH_ESTABLISHMENT_NAME -Value Get-CasinoName
Set-Alias -Name PH_CASINO_NAME        -Value Get-CasinoName
function Get-CasinoLongName { param([switch]$Prompt, [string]$Default) Get-ScopeValue -Key 'casino.longname' -Prompt:$Prompt -Default:$Default }
Set-Alias -Name PH_ESTABLISHMENT_LONGNAME -Value Get-CasinoLongName
Set-Alias -Name PH_CASINO_LONGNAME        -Value Get-CasinoLongName

function Set-CasinoID       { [CmdletBinding(SupportsShouldProcess)] param([Parameter(Mandatory)][int]$Id)            Set-ScopeValue -Key 'casino.ID'       -Value $Id -CreateMissing }
function Set-CasinoCode     { [CmdletBinding(SupportsShouldProcess)] param([Parameter(Mandatory)][string]$Code)        Set-ScopeValue -Key 'casino.code'     -Value $Code -ValidateAs NonEmpty -CreateMissing }
function Set-CasinoName     { [CmdletBinding(SupportsShouldProcess)] param([Parameter(Mandatory)][string]$Name)        Set-ScopeValue -Key 'casino.name'     -Value $Name -ValidateAs NonEmpty -CreateMissing }
function Set-CasinoLongName { [CmdletBinding(SupportsShouldProcess)] param([Parameter(Mandatory)][string]$LongName)    Set-ScopeValue -Key 'casino.longname' -Value $LongName -ValidateAs NonEmpty -CreateMissing }

function Get-CasinoModuleState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('CAWA','Jackpot','Replication','R4R','MyBar')][string]$Module)
    Get-ScopeValue -Key "casino.modules.$Module"
}
function Set-CasinoModuleState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('CAWA','Jackpot','Replication','R4R','MyBar')][string]$Module,
        [Parameter(Mandatory)][bool]$Enabled
    )
    Set-ScopeValue -Key "casino.modules.$Module" -Value $Enabled -CreateMissing
}

function Get-CasinoRFIDKeys {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('BlowfishKey','ReadKey_MAD','WriteKey_MAD')][string]$Key)
    Get-ScopeValue -Key "casino.RFIDKeys.$Key"
}
function Set-CasinoRFIDKeys  {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('BlowfishKey','ReadKey_MAD','WriteKey_MAD')][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    Set-ScopeValue -Key "casino.RFIDKeys.$Key" -Value $Value -CreateMissing
}

function Get-IPSEC {
    $environment = Get-GeneralSystem
    if($environment -eq '3VM') {
        Return '15666'
    } else {
        Return '1666'
    }
}
Set-Alias -name PH_FSERVER_IPSEC -Value Get-IPSEC
#endregion

#region --- scope.json databases
function Get-DbTNS {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('GLX','JKP')] [string]$Database, [switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key "databases.$Database.TNS" -Prompt:$Prompt -Default:$Default
}
function Get-DBTns-GLX {
    Get-DbTns GLX
}
function Get-DBTns-JKP {
    Get-DbTns JKP
}
Set-Alias -Name PH_GALAXIS_DB_TNS -Value Get-DBTns-GLX
Set-Alias -Name PH_JACKPOT_DB_TNS -Value Get-DBTns-JKP
function Set-DbTNS {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('GLX','JKP')] [string]$Database,
          [Parameter(Mandatory)][string]$Tns)
    Set-ScopeValue -Key "databases.$Database.TNS" -Value $Tns -ValidateAs NonEmpty -CreateMissing
}

function Get-DbUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('as_dbx','as_jackpot','as_security','as_jp_report','specific')] [string]$UserKey,
          [switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key "databases.users.$UserKey" -Prompt:$Prompt -Default:$Default
}
function Set-DbUser {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('as_dbx','as_jackpot','as_security','as_jp_report','specific')] [string]$UserKey,
          [Parameter(Mandatory)][string]$Username)
    Set-ScopeValue -Key "databases.users.$UserKey" -Value $Username -ValidateAs NonEmpty -CreateMissing
}
#endregion

#region --- scope.json servers.hostnames
function Get-ServerHostname {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')][string]$Server,
          [switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key "servers.$Server.hostname" -Prompt:$Prompt -Default:$Default
}
function Set-ServerHostname {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')][string]$Server,
          [Parameter(Mandatory)][string]$Hostname)
    Set-ScopeValue -Key "servers.$Server.hostname" -Value $Hostname -ValidateAs Hostname -CreateMissing
}
#endregion

#region --- scope.json servers.networkAdapters (NIC IP)
function Get-NicIP {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
          [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
          [switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.IP" -Prompt:$Prompt -Default:$Default -ValidateAs IpAddress
}
function Set-NicIP {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
          [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
          [Parameter(Mandatory)][string]$IP)
    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.IP" -Value $IP -ValidateAs IpAddress -CreateMissing
}
#endregion

#region --- scope.json servers.networkAdapters (NIC SNM)
function Get-NicSNM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [switch]$Prompt, [string]$Default
    )
    Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.SNM" -Prompt:$Prompt -Default:$Default -ValidateAs IpAddress
}
function Set-NicSNM {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [Parameter(Mandatory)][string]$SubnetMask
    )
    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.SNM" -Value $SubnetMask -ValidateAs IpAddress -CreateMissing
}
#endregion

#region --- scope.json servers.networkAdapters (NIC DG)
function Get-NicDG {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [switch]$Prompt, [string]$Default
    )
    Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DG" -Prompt:$Prompt -Default:$Default -ValidateAs IpAddress
}
function Set-NicDG {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [Parameter(Mandatory)][string]$Gateway
    )
    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DG" -Value $Gateway -ValidateAs IpAddress -CreateMissing
}
#endregion

#region --- scope.json servers.networkAdapters (NIC DNS - array)
function Get-NicDns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter
    )
    $v = Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS"
    if ($null -eq $v) { return @() }
    $out = @()
    foreach ($x in @($v)) {
        $t = "$x".Trim()
        if ($t) { $out += $t }
    }
    return ,$out
}

function Set-NicDns {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [Parameter(Mandatory)][string[]]$Servers
    )
    $clean = @()
    foreach ($s in $Servers) {
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $ip = $s.Trim()
        if (-not (Test-ConfigValue -Validator IpAddress -Value $ip)) { throw "Invalid DNS IP: $s" }
        $clean += $ip
    }
    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS" -Value $clean -CreateMissing
}

function Add-NicDns {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [Parameter(Mandatory)][string]$ServerIp
    )
    $ip = $ServerIp.Trim()
    if (-not (Test-ConfigValue -Validator IpAddress -Value $ip)) { throw "Invalid DNS IP: $ServerIp" }
    $current = Get-NicDns -Server $Server -Adapter $Adapter
    if ($current -notcontains $ip) { $current += $ip }
    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS" -Value $current -CreateMissing
}

function Remove-NicDns {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [Parameter(Mandatory)][string]$ServerIp
    )
    $ip = $ServerIp.Trim()
    $current = Get-NicDns -Server $Server -Adapter $Adapter
    $before  = $current.Count
    $filtered = @($current | Where-Object { $_ -ne $ip })
    if ($filtered.Count -eq $before) {
        Write-Log "Remove-NicDns: '$ip' not present; no change." VERBOSE
        return $filtered
    }
    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS" -Value $filtered -CreateMissing
}
#endregion

#region --- scope.json servers.networkAdapters (NIC VLAN)
function Get-NicVlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter
    )
    Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.VLAN"
}
function Set-NicVlan {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [int]$Vlan,
        [switch]$Clear
    )

    if ($Clear -and $PSBoundParameters.ContainsKey('Vlan')) {
        throw "Specify either -Vlan or -Clear, not both."
    }
    if (-not $Clear -and -not $PSBoundParameters.ContainsKey('Vlan')) {
        throw "Specify -Vlan (number) or -Clear to set null."
    }

    if ($Clear) {
        $value = $null
    } else {
        #vlan range check (1-4094)?
        $value = $Vlan
    }

    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.VLAN" -Value $value -CreateMissing
}
#endregion

#region --- scope.json servers.networkAdapters (NIC DHCP enabled)
function Get-NicDhcpEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter
    )
    Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DHCP"
}
function Set-NicDhcpEnabled {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,
        [Parameter(Mandatory)][bool]$Enabled
    )
    Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DHCP" -Value $Enabled -CreateMissing
}
#endregion

#region --- scope.json servers.DHCP.ranges
function Get-DhcpRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('FS','1VM')][string]$Server,
        [Parameter(Mandatory)][ValidateSet('range1','range2')][string]$Range
    )
    [pscustomobject]@{
        Range = $Range
        From  = Get-ScopeValue -Key "servers.$Server.DHCP[name=$Range].from"
        To    = Get-ScopeValue -Key "servers.$Server.DHCP[name=$Range].to"
    }
}

function Set-DhcpRange {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('FS','1VM')][string]$Server,
        [Parameter(Mandatory)][ValidateSet('range1','range2')][string]$Range,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To
    )
    Set-ScopeValue -Key "servers.$Server.DHCP[name=$Range].from" -Value $From -ValidateAs IpAddress -CreateMissing
    Set-ScopeValue -Key "servers.$Server.DHCP[name=$Range].to"   -Value $To   -ValidateAs IpAddress -CreateMissing
}
#endregion

#region --- scope.json directories
function Get-ToolkitPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('workspace','galaxis','onlinedata','backup')] [string]$Name,
          [switch]$Prompt, [string]$Default)
    Get-ScopeValue -Key "directories.$Name" -Prompt:$Prompt -Default:$Default -ValidateAs NonEmpty
}
function Set-ToolkitPath {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateSet('workspace','galaxis','onlinedata','backup')] [string]$Name,
          [Parameter(Mandatory)][string]$Path)
    Set-ScopeValue -Key "directories.$Name" -Value $Path -ValidateAs NonEmpty -CreateMissing
}
#endregion

#region --- scope.json summary
function Show-ScopeSummary {
    [CmdletBinding()]
    param()

    $general  = [pscustomobject]@{
        System   = Get-ScopeValue -Key 'general.system'
        Timezone = Get-ScopeValue -Key 'general.timezone'
        Language = Get-ScopeValue -Key 'general.language'
    }

    $customer = [pscustomobject]@{
        Code = Get-ScopeValue -Key 'customer.code'
        Name = Get-ScopeValue -Key 'customer.name'
    }

    $casino = [pscustomobject]@{
        ID       = Get-ScopeValue -Key 'casino.ID'
        Code     = Get-ScopeValue -Key 'casino.code'
        Name     = Get-ScopeValue -Key 'casino.name'
        LongName = Get-ScopeValue -Key 'casino.longname'
        Modules  = (Get-ScopeValue -Key 'casino.modules')
    }

    $servers = foreach ($srv in 'DB','APP','FS','1VM') {
        $hn   = Get-ScopeValue -Key "servers.$srv.hostname"
        $mods = @('OFFICE','MODULUS','FLOOR' | Where-Object { $_ -ne 'FLOOR' -or $srv -in 'FS','1VM' })
        foreach ($ad in $mods) {
            $exists = $null -ne (Get-ScopeValue -Key "servers.$srv.networkAdapters.$ad")
            if ($exists) {
                [pscustomobject]@{
                    Server  = $srv
                    Adapter = $ad
                    Host    = $hn
                    IP      = Get-ScopeValue -Key "servers.$srv.networkAdapters.$ad.IP"
                    SNM     = Get-ScopeValue -Key "servers.$srv.networkAdapters.$ad.SNM"
                    DG      = Get-ScopeValue -Key "servers.$srv.networkAdapters.$ad.DG"
                    DNS     = -join @(Get-ScopeValue -Key "servers.$srv.networkAdapters.$ad.DNS")
                    VLAN    = Get-ScopeValue -Key "servers.$srv.networkAdapters.$ad.VLAN"
                    DHCP    = Get-ScopeValue -Key "servers.$srv.networkAdapters.$ad.DHCP"
                }
            }
        }
    }

    Write-Host "=== GENERAL ==="
    $general | Format-List | Out-String | Write-Host

    Write-Host "`n=== CUSTOMER ==="
    $customer | Format-List | Out-String | Write-Host

    Write-Host "`n=== CASINO ==="
    $casino | Format-List | Out-String | Write-Host

    Write-Host "`n=== SERVERS / ADAPTERS ==="
    $servers | Sort-Object Server,Adapter | Format-Table -AutoSize
}
#endregion

#region --- scope.json pre-update check
function Confirm-ScopeFields {
    [CmdletBinding()]
    param(
        # Each item: @{ Key='servers.APP.hostname'; Label='APP Hostname'; ValidateAs='Hostname'; Default='ModulusAPP'; Prompt=$true }
        [Parameter(Mandatory)][object[]]$Fields,
        [switch]$NonInteractive
    )

    $results = @()
    foreach ($f in $Fields) {
        $key        = $f.Key
        $label      = $f.Label
        $validator  = $f.ValidateAs
        $default    = $f.Default
        $doPrompt   = [bool]$f.Prompt -and -not $NonInteractive

        $val = Get-ScopeValue -Key $key `
                              -Prompt:$doPrompt `
                              -PromptLabel $label `
                              -ValidateAs $validator `
                              -Ensure:([bool]$f.ContainsKey('Default')) `
                              -Default $default `
                              -NonInteractive:$NonInteractive

        $results += [pscustomobject]@{
            Key       = $key
            Value     = $val
            WasEmpty  = ($null -eq $val -or ($val -is [string] -and $val -eq ""))
            Validator = $validator
            Prompted  = $doPrompt
        }
    }
    $results
}
#endregion
#endregion

#region --- convenience functions
#region --- convenience functions for full NIC config object
function Get-NicConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter
    )

    [pscustomobject]@{
        Server     = $Server
        Adapter    = $Adapter
        IP         = Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.IP"
        SNM        = Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.SNM"
        DG         = Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DG"
        DNS        = @(Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS")
        VLAN       = Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.VLAN"
        DHCP       = Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DHCP"
    }
}

function Set-NicConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][ValidateSet('OFFICE','MODULUS','FLOOR')] [string]$Adapter,

        [string]$IP,
        [string]$SNM,
        [string]$DG,
        [string[]]$DNS,              # full replace list
        [string[]]$AddDns,           # additive
        [string[]]$RemoveDns,        # subtractive

        [int]$Vlan,
        [switch]$ClearVlan,

        [bool]$DhcpEnabled
    )

    # IP/SNM/DG
    if ($PSBoundParameters.ContainsKey('IP'))  { Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.IP"  -Value $IP  -ValidateAs IpAddress -CreateMissing }
    if ($PSBoundParameters.ContainsKey('SNM')) { Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.SNM" -Value $SNM -ValidateAs IpAddress -CreateMissing }
    if ($PSBoundParameters.ContainsKey('DG'))  { Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DG"  -Value $DG  -ValidateAs IpAddress -CreateMissing }

    # DNS (replace)
    if ($PSBoundParameters.ContainsKey('DNS')) {
        $clean = @()
        foreach ($s in $DNS) {
            if ([string]::IsNullOrWhiteSpace($s)) { continue }
            $ip = $s.Trim()
            if (-not (Test-ConfigValue -Validator IpAddress -Value $ip)) { throw "Invalid DNS IP: $ip" }
            $clean += $ip
        }
        Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS" -Value $clean -CreateMissing
    }

    # DNS (add/remove)
    if ($PSBoundParameters.ContainsKey('AddDns') -or $PSBoundParameters.ContainsKey('RemoveDns')) {
        $current = @(Get-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS")
        if ($PSBoundParameters.ContainsKey('AddDns')) {
            foreach ($s in $AddDns) {
                $ip = $s.Trim()
                if (-not (Test-ConfigValue -Validator IpAddress -Value $ip)) { throw "Invalid DNS IP: $ip" }
                if ($current -notcontains $ip) { $current += $ip }
            }
        }
        if ($PSBoundParameters.ContainsKey('RemoveDns')) {
            $removeSet = @($RemoveDns | ForEach-Object { $_.Trim() })
            $current = @($current | Where-Object { $removeSet -notcontains $_ })
        }
        Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DNS" -Value $current -CreateMissing
    }

    # VLAN (mutually exclusive)
    if ($ClearVlan -and $PSBoundParameters.ContainsKey('Vlan')) {
        throw "Specify either -Vlan or -ClearVlan, not both."
    }
    if ($ClearVlan) {
        Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.VLAN" -Value $null -CreateMissing
    } elseif ($PSBoundParameters.ContainsKey('Vlan')) {
        # (optional) add a VlanId validator later
        Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.VLAN" -Value $Vlan -CreateMissing
    }

    # DHCP
    if ($PSBoundParameters.ContainsKey('DhcpEnabled')) {
        Set-ScopeValue -Key "servers.$Server.networkAdapters.$Adapter.DHCP" -Value ([bool]$DhcpEnabled) -CreateMissing
    }
}
#endregion

#region --- convenience functions for full DHCP range object
function Get-DhcpRanges {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('FS','1VM')] [string]$Server)

    $arr = Get-ScopeValue -Key "servers.$Server.DHCP"
    if ($null -eq $arr) { return @() }
    $out = @()
    foreach ($r in $arr) {
        $out += [pscustomobject]@{
            Server = $Server
            Name   = $r.name
            From   = $r.from
            To     = $r.to
        }
    }
    $out
}

function New-DhcpRange {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To
    )
    if (-not (Test-ConfigValue -Validator IpAddress -Value $From)) { throw "Invalid IP: $From" }
    if (-not (Test-ConfigValue -Validator IpAddress -Value $To))   { throw "Invalid IP: $To" }

    # if exists, just set fields; else create element
    Set-ScopeValue -Key "servers.$Server.DHCP[name=$Name].name" -Value $Name -CreateMissing
    Set-ScopeValue -Key "servers.$Server.DHCP[name=$Name].from" -Value $From -ValidateAs IpAddress -CreateMissing
    Set-ScopeValue -Key "servers.$Server.DHCP[name=$Name].to"   -Value $To   -ValidateAs IpAddress -CreateMissing
}

function Remove-DhcpRange {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][string]$Name
    )

    $list = @(Get-ScopeValue -Key "servers.$Server.DHCP")
    if ($list.Count -eq 0) {
        Write-Log "Remove-DhcpRange: no DHCP ranges on $Server." VERBOSE
        return
    }

    $filtered = @($list | Where-Object { $_.name -ne $Name })
    if ($filtered.Count -eq $list.Count) {
        Write-Log "Remove-DhcpRange: '$Name' not found on $Server; no change." VERBOSE
        return
    }

    Set-ScopeValue -Key "servers.$Server.DHCP" -Value $filtered -CreateMissing
}

function Rename-DhcpRange {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('FS','1VM')] [string]$Server,
        [Parameter(Mandatory)][string]$OldName,
        [Parameter(Mandatory)][string]$NewName
    )

    $keyBase = "servers.$Server.DHCP"
    $exists = Get-ScopeValue -Key "$keyBase[name=$OldName].name"
    if ($null -eq $exists) {
        throw "DHCP range '$OldName' not found on $Server."
    }
    Set-ScopeValue -Key "$keyBase[name=$OldName].name" -Value $NewName
}
#endregion

#region --- convenience functions for directories incl. validation
function Get-ToolkitPaths {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        workspace = Get-ScopeValue -Key 'directories.workspace'
        galaxis   = Get-ScopeValue -Key 'directories.galaxis'
        onlinedata= Get-ScopeValue -Key 'directories.onlinedata'
        backup    = Get-ScopeValue -Key 'directories.backup'
    }
}

function Test-ToolkitPaths {
    [CmdletBinding()]
    param()
    $paths = Get-ToolkitPaths
    $rows = @()
    foreach ($name in 'workspace','galaxis','onlinedata','backup') {
        $p = $paths.$name
        $exists = if ([string]::IsNullOrWhiteSpace($p)) { $false } else { Test-Path -LiteralPath $p }
        $rows += [pscustomobject]@{ Name = $name; Path = $p; Exists = $exists }
    }
    $rows
}

function Get-WorkspacePath     { Get-ToolkitPath -Name 'workspace' }

function Get-SourcesPath       { 
    $ws = Get-WorkspacePath
    if ([string]::IsNullOrWhiteSpace($ws)) {
        throw "Workspace path is not set."
    }
    Join-Path -Path $ws -ChildPath 'sources'
}

function Get-PrepPath          { 
    $ws = Get-WorkspacePath
    if ([string]::IsNullOrWhiteSpace($ws)) {
        throw "Workspace path is not set."
    }
    Join-Path -Path $ws -ChildPath 'prep'
}

function Get-LogsPath          { 
    $ws = Get-WorkspacePath
    if ([string]::IsNullOrWhiteSpace($ws)) {
        throw "Workspace path is not set."
    }
    Join-Path -Path $ws -ChildPath 'logs'
}

function Get-HealthcheckPath   { 
    $ws = Get-WorkspacePath
    if ([string]::IsNullOrWhiteSpace($ws)) {
        throw "Workspace path is not set."
    }
    Join-Path -Path $ws -ChildPath 'healthcheck'
}

function Get-GalaxisPath       { Get-ToolkitPath -Name 'galaxis' }
function Get-OnlinedataPath    { Get-ToolkitPath -Name 'onlinedata' }
function Get-BackupPath        { Get-ToolkitPath -Name 'backup' }

function Initialize-ToolkitPaths {
    [CmdletBinding(SupportsShouldProcess)]
    param()  

    $checks = Test-ToolkitPaths
    foreach ($row in $checks) {
        if (-not $row.Exists -and -not [string]::IsNullOrWhiteSpace($row.Path)) {
            if ($PSCmdlet.ShouldProcess($row.Path, 'Create directory')) {
                New-Item -ItemType Directory -Force -Path $row.Path | Out-Null
                Write-Log "Ensure-ToolkitPaths: created '$($row.Path)'" VERBOSE
            }
        }
    }
    Test-ToolkitPaths
}
#endregion
#endregion


#---


#region --- OLD SCOPE
function Get-MOD-DesiredENVVARs {
    $desired = (Get-EnvironmentVariables).environments.$ENV:MODULUS_SERVER
    Return $desired
}
#endregion


#---


#region --- DataAccess Helpers
function Resolve-LogicalServerKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('DB','APP','FS','1VM')] [string]$Role)

    $system = Get-ScopeValue -Key 'general.system'
    if ($system -eq '1VM') { return '1VM' }
    return $Role
}

function Get-MOD-DB  { [CmdletBinding()] param(); $k = Resolve-LogicalServerKey -Role 'DB';  Get-ScopeValue -Key "servers.$k" }
function Get-MOD-APP { [CmdletBinding()] param(); $k = Resolve-LogicalServerKey -Role 'APP'; Get-ScopeValue -Key "servers.$k" }
function Get-MOD-FS  { [CmdletBinding()] param(); $k = Resolve-LogicalServerKey -Role 'FS';  Get-ScopeValue -Key "servers.$k" }
function Get-MOD-1VM { [CmdletBinding()] param();                                        Get-ScopeValue -Key "servers.1VM" }

#helper to get current scope to work on network for example
function Get-MOD-Server {
    [CmdletBinding()] param()
    switch ($ENV:MODULUS_SERVER) {
        'DB'  { return (Get-MOD-DB)  }
        'APP' { return (Get-MOD-APP) }
        'FS'  { return (Get-MOD-FS)  }
        '1VM' { return (Get-MOD-1VM) }
        default { throw "MODULUS_SERVER is not set to one of: DB, APP, FS, 1VM." }
    }
}

function Get-MOD-DB-hostname  { [CmdletBinding()] param(); (Get-MOD-DB).hostname }
Set-Alias -Name PH_DBSERVER_HOSTNAME -Value Get-MOD-DB-hostname 
function Get-MOD-APP-hostname { [CmdletBinding()] param(); (Get-MOD-APP).hostname }
Set-Alias -Name PH_APPSERVER_HOSTNAME -Value Get-MOD-APP-hostname 
function Get-MOD-FS-hostname  { [CmdletBinding()] param(); (Get-MOD-FS).hostname }
Set-Alias -Name PH_FSERVER_HOSTNAME -Value Get-MOD-FS-hostname 
#function Get-MOD-1VM-hostname { [CmdletBinding()] param(); (Get-MOD-1VM).hostname }

# NIC helpers (now direct hashtable properties, no Where-Object)
function Get-MOD-DB-OFFICE-NIC     { [CmdletBinding()] param(); (Get-MOD-DB).networkAdapters.OFFICE }
function Get-MOD-DB-OFFICE-IP      { [CmdletBinding()] param(); (Get-MOD-DB).networkAdapters.OFFICE.IP }
Set-Alias -Name PH_DBSERVER_IP -Value Get-MOD-DB-OFFICE-IP
function Get-MOD-APP-OFFICE-NIC    { [CmdletBinding()] param(); (Get-MOD-APP).networkAdapters.OFFICE }
function Get-MOD-APP-OFFICE-IP     { [CmdletBinding()] param(); (Get-MOD-APP).networkAdapters.OFFICE.IP }
Set-Alias -Name PH_APPSERVER_IP -Value Get-MOD-APP-OFFICE-IP
function Get-MOD-FS-OFFICE-NIC     { [CmdletBinding()] param(); (Get-MOD-FS).networkAdapters.OFFICE }
function Get-MOD-FS-OFFICE-IP      { [CmdletBinding()] param(); (Get-MOD-FS).networkAdapters.OFFICE.IP }
Set-Alias -Name PH_FSERVER_IP -Value Get-MOD-FS-OFFICE-IP

function Get-MOD-DB-MODULUS-NIC    { [CmdletBinding()] param(); (Get-MOD-DB).networkAdapters.MODULUS }
function Get-MOD-APP-MODULUS-NIC   { [CmdletBinding()] param(); (Get-MOD-APP).networkAdapters.MODULUS }
function Get-MOD-FS-MODULUS-NIC    { [CmdletBinding()] param(); (Get-MOD-FS).networkAdapters.MODULUS }

function Get-MOD-FS-FLOOR-NIC      { [CmdletBinding()] param(); (Get-MOD-FS).networkAdapters.FLOOR }
function Get-MOD-FS-FLOOR-IP      { [CmdletBinding()] param(); (Get-MOD-FS).networkAdapters.FLOOR.IP }
Set-Alias -Name PH_FSERVER_FLOOR_IP -Value Get-MOD-FS-FLOOR-IP

# DHCP ranges: array-of-objects at servers.<FS or 1VM>.DHCP
function Get-MOD-FS-DHCP-Ranges {
    [CmdletBinding()] param()
    $k = Resolve-LogicalServerKey -Role 'FS'
    $arr = Get-ScopeValue -Key "servers.$k.DHCP"
    if ($null -eq $arr) { return @() }
    return $arr
}
#endregion


#---


#region --- database credential handling and placeholders
#region --- ADMINISTRATIVE users (DBA)
#region --- DB user sys
function Get-DbUser-sys {
    Return "sys"
}

function Get-DbCred-sysGLX {
    $user = Get-DbUser-sys
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbCred-sysJKP {
    $user = Get-DbUser-sys
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}
#endregion

#region --- DB user system
function Get-DbUser-system {
    Return "system"
}

function Get-DbCred-systemGLX {
    $user = Get-DbUser-system
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbCred-systemJKP {
    $user = Get-DbUser-system
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}
#endregion

#region --- DB user grafanau
function Get-DbUser-grafanau {
    Return "grafanau"
}
Set-Alias -Name PH_GRAFANAU_DB_USER -Value Get-DbUser-grafanau

function Get-DbCred-grafanauGLX{
    $user = Get-DbUser-grafanau
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbCred-grafanauJKP{
    $user = Get-DbUser-grafanau
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbPass-grafanau {
    $cred = Get-DbCred-grafanauGLX
    $pass = $cred.GetNetworkCredential().Password
    Return $pass
}
Set-Alias -Name PH_GRAFANAU_DB_PASSWORD  -Value Get-DbPass-grafanau
#endregion
#endregion

#region --- GALAXIS related users
#region --- DB user specific (mostly site)
function Get-DbUser-specific {
    $user = Get-DbUser specific
    Return $user
}
Set-Alias -Name PH_SPECIFIC_DB_USER  -Value Get-DbUser-specific

function Get-DbCred-specific {
    $user = Get-DbUser-specific
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-specific {
    $cred = Get-DbCred-specific
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_SPECIFIC_DB_PASSWORD  -Value Get-DbEnCred-specific
#endregion

#region --- DB user galaxis
function Get-DbUser-galaxis {
    Return "GALAXIS"
}
Set-Alias -Name PH_GALAXIS_DB_USER  -Value Get-DbUser-galaxis

function Get-DbCred-galaxis {
    $user = Get-DbUser-galaxis
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-galaxis {
    $cred = Get-DbCred-galaxis
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_GALAXIS_DB_PASSWORD  -Value Get-DbEnCred-galaxis
#endregion

#region --- DB user mis
function Get-DbUser-mis {
    Return "MIS"
}
Set-Alias -Name PH_MIS_DB_USER  -Value Get-DbUser-mis

function Get-DbCred-mis {
    $user = Get-DbUser-mis
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-mis {
    $cred = Get-DbCred-mis
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_MIS_DB_PASSWORD  -Value Get-DbEnCred-mis
#endregion

#region --- DB user spa
function Get-DbUser-spa {
    Return "SPA"
}
Set-Alias -Name PH_SPA_DB_USER  -Value Get-DbUser-spa

function Get-DbCred-spa {
    $user = Get-DbUser-spa
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-spa {
    $cred = Get-DbCred-spa
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_SPA_DB_PASSWORD  -Value Get-DbEnCred-spa
#endregion

#region --- DB user mktdtm
function Get-DbUser-mktdtm {
    Return "MKTDTM"
}
Set-Alias -Name PH_MKTDTM_DB_USER  -Value Get-DbUser-mktdtm

function Get-DbCred-mktdtm {
    $user = Get-DbUser-mktdtm
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-mktdtm {
    $cred = Get-DbCred-mktdtm
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_MKTDTM_DB_PASSWORD  -Value Get-DbEnCred-mktdtm
#endregion

#region --- DB user messenger
function Get-DbUser-messenger {
    Return "messenger"
}
Set-Alias -Name PH_MESSENGER_DB_USER  -Value Get-DbUser-messenger

function Get-DbCred-messenger {
    $user = Get-DbUser-messenger
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-messenger {
    $cred = Get-DbCred-messenger
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_MESSENGER_DB_PASSWORD  -Value Get-DbEnCred-messenger
#endregion

#region --- DB user qpcash
function Get-DbUser-qpcash {
    Return "QPCASH"
}
Set-Alias -Name PH_QPCASH_DB_USER  -Value Get-DbUser-qpcash

function Get-DbCred-qpcash {
    $user = Get-DbUser-qpcash
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-qpcash {
    $cred = Get-DbCred-qpcash
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_QPCASH_DB_PASSWORD  -Value Get-DbEnCred-qpcash
#endregion

#region --- DB user tbl 
function Get-DbUser-tbl {
    Return "tbl"
}
Set-Alias -Name PH_TBL_DB_USER  -Value Get-DbUser-tbl

function Get-DbCred-tbl {
    $user = Get-DbUser-tbl
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-tbl {
    $cred = Get-DbCred-tbl
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_TBL_DB_PASSWORD  -Value Get-DbEnCred-tbl
#endregion

#region --- DB user alrmsrv
function Get-DbUser-alrmsrv {
    Return "alrmsrv"
}
Set-Alias -Name PH_ALRMSRV_DB_USER  -Value Get-DbUser-alrmsrv

function Get-DbCred-alrmsrv {
    $user = Get-DbUser-alrmsrv
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-alrmsrv {
    $cred = Get-DbCred-alrmsrv
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_ALRMSRV_DB_PASSWORD  -Value Get-DbEnCred-alrmsrv
#endregion

#region --- DB user trnssrv
function Get-DbUser-trnssrv {
    Return "trnssrv"
}
Set-Alias -Name PH_TRNSSRV_DB_USER  -Value Get-DbUser-trnssrv

function Get-DbCred-trnssrv {
    $user = Get-DbUser-trnssrv
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-trnssrv {
    $cred = Get-DbCred-trnssrv
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_TRNSSRV_DB_PASSWORD  -Value Get-DbEnCred-trnssrv
#endregion

#region --- DB user aml
function Get-DbUser-aml {
    Return "aml"
}
Set-Alias -Name PH_AML_DB_USER  -Value Get-DbUser-aml

function Get-DbCred-aml {
    $user = Get-DbUser-aml
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-aml {
    $cred = Get-DbCred-aml
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_AML_DB_PASSWORD  -Value Get-DbEnCred-aml
#endregion

#region --- DB user junket
function Get-DbUser-junket {
    Return "junket"
}
Set-Alias -Name PH_JUNKET_DB_USER  -Value Get-DbUser-junket

function Get-DbCred-junket {
    $user = Get-DbUser-junket
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-junket {
    $cred = Get-DbCred-junket
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_JUNKET_DB_PASSWORD  -Value Get-DbEnCred-junket
#endregion

#region --- DB user asset
function Get-DbUser-asset {
    Return "asset"
}
Set-Alias -Name PH_ASSET_DB_USER  -Value Get-DbUser-asset

function Get-DbCred-asset {
    $user = Get-DbUser-asset
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-asset {
    $cred = Get-DbCred-asset
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_ASSET_DB_PASSWORD  -Value Get-DbEnCred-asset
#endregion

#region --- DB user slotexp
function Get-DbUser-slotexp {
    Return "slotexp"
}
Set-Alias -Name PH_SLOTEXP_DB_USER  -Value Get-DbUser-slotexp
Set-Alias -Name PH_SLOTEXP_DB_SCHEMA  -Value Get-DbUser-slotexp

function Get-DbCred-slotexp {
    $user = Get-DbUser-slotexp
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-slotexp {
    $cred = Get-DbCred-slotexp
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_SLOTEXP_DB_PASSWORD  -Value Get-DbEnCred-slotexp
#endregion

#region --- DB user rg
function Get-DbUser-rg {
    Return "rg"
}
Set-Alias -Name PH_RG_DB_USER  -Value Get-DbUser-rg

function Get-DbCred-rg {
    $user = Get-DbUser-rg
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-rg {
    $cred = Get-DbCred-rg
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_RG_DB_PASSWORD  -Value Get-DbEnCred-rg
#endregion

#region --- DB user auth (as_auth)
function Get-DbUser-auth {
    Return "as_auth"
}
Set-Alias -Name PH_AUTH_DB_USER  -Value Get-DbUser-auth

function Get-DbCred-auth {
    $user = Get-DbUser-auth
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-auth {
    $cred = Get-DbCred-auth
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_AUTH_DB_PASSWORD  -Value Get-DbEnCred-auth
#endregion

#region --- DB user sbc (as_sbc)
function Get-DbUser-sbc {
    Return "as_sbc"
}
Set-Alias -Name PH_SBC_DB_USER  -Value Get-DbUser-sbc

function Get-DbCred-sbc {
    $user = Get-DbUser-sbc
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-sbc {
    $cred = Get-DbCred-sbc
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_SBC_DB_PASSWORD  -Value Get-DbEnCred-sbc
#endregion

#region --- DB user cldb (as_cldb)
function Get-DbUser-cldb {
    Return "as_cldb"
}
Set-Alias -Name PH_CL_DB_USER  -Value Get-DbUser-cldb

function Get-DbCred-cldb {
    $user = Get-DbUser-cldb
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-cldb {
    $cred = Get-DbCred-cldb
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_CL_DB_PASSWORD  -Value Get-DbEnCred-cldb
#endregion

#region --- DB user fx 
function Get-DbUser-fx {
    Return "fx" 
}
Set-Alias -Name PH_FX_DB_USER  -Value Get-DbUser-fx

function Get-DbCred-fx {
    $user = Get-DbUser-fx
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-fx {
    $cred = Get-DbCred-fx
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_FX_DB_PASSWORD  -Value Get-DbEnCred-fx
#endregion
#endregion

#region --- SRADDINDB related users
#region --- DB user headoffice (rep_admin_*)
function Get-DbUser-headoffice {
    #$user = Get-DbUser specific
    #Return $user
    Return "rep_admin_ho"
}
Set-Alias -Name PH_REP_ADMIN_HO_USER  -Value Get-DbUser-headoffice

function Get-DbCred-headoffice {
    $user = Get-DbUser-headoffice
    $DB   = Get-DBTns-GLX
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-headoffice {
    $cred = Get-DbCred-headoffice
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_REP_ADMIN_HO_PASSWORD  -Value Get-DbEnCred-headoffice
#endregion
#endregion

#region --- JACKPOT related users
#region --- DB user jackpot (as_jackpot/grips_jackpot)
function Get-DbUser-jackpot {
    $user = Get-DbUser as_jackpot
    Return $user
}
Set-Alias -Name PH_JACKPOT_DB_USER  -Value Get-DbUser-jackpot

function Get-DbCred-jackpot {
    $user = Get-DbUser-jackpot
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-jackpot {
    $cred = Get-DbCred-jackpot
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_JACKPOT_DB_PASSWORD  -Value Get-DbEnCred-jackpot
#endregion

#region --- DB user jackpot (as_base/grips_base)
function Get-DbUser-base {
    $user = Get-DbUser-jackpot
    if ($user -like 'as*') {
        Return "as_base"
    } else {
        Return "grips_base"
    }
}
Set-Alias -Name PH_BASE_DB_USER  -Value Get-DbUser-base

function Get-DbCred-base {
    $user = Get-DbUser-base
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-base {
    $cred = Get-DbCred-base
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_BASE_DB_PASSWORD  -Value Get-DbEnCred-base
#endregion

#region --- DB user security (as_security/grips_security)
function Get-DbUser-security {
    $user = Get-DbUser as_security
    Return $user
}
Set-Alias -Name PH_SECURITY_DB_USER  -Value Get-DbUser-security

function Get-DbCred-security {
    $user = Get-DbUser-security
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-security {
    $cred = Get-DbCred-security
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_SECURITY_DB_PASSWORD  -Value Get-DbEnCred-security
#endregion

#region --- DB user dbx (as_dbx/grips_dbx)
function Get-DbUser-dbx {
     $user = Get-DbUser-jackpot
    if ($user -like 'as*') {
        Return "as_dbx"
    } else {
        Return "grips_dbx"
    }
}
Set-Alias -Name PH_DBX_DB_USER  -Value Get-DbUser-dbx

function Get-DbCred-dbx {
    $user = Get-DbUser-dbx
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-dbx {
    $cred = Get-DbCred-dbx
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_DBX_DB_PASSWORD  -Value Get-DbEnCred-dbx
#endregion

#region --- DB user report (as_jp_report/grips_jp_report)
function Get-DbUser-report {
    $user = Get-DbUser as_jp_report
    Return $user
}
Set-Alias -Name PH_REPORT_DB_USER  -Value Get-DbUser-report

function Get-DbCred-report {
    $user = Get-DbUser-report
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-report {
    $cred = Get-DbCred-report
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_REPORT_DB_PASSWORD  -Value Get-DbEnCred-report
#endregion

#region --- DB user config_interface_user (as_config_interface/grips_config_interface)
function Get-DbUser-config_interface {
    $user = Get-DbUser-jackpot
    if ($user -like 'as*') {
        Return "as_config_interface"
    } else {
        Return "grips_config_interface"
    }
}
Set-Alias -Name PH_CONFIG_INTERFACE_USER  -Value Get-DbUser-specific

function Get-DbCred-config_interface {
    $user = Get-DbUser-config_interface
    $DB   = Get-DBTns-JKP
    $cred = Get-DatabaseCredentials -User $user -DB $DB
    Return $cred
}

function Get-DbEnCred-config_interface {
    $cred = Get-DbCred-config_interface
    $enc = Protect-Password -Credential $cred
    Return $enc
}
Set-Alias -Name PH_CONFIG_INTERFACE_PASSWORD  -Value Get-DbEnCred-config_interface
#endregion
#endregion

#region --- Different Casino settings
#region --- setting CASHLESSLEVEL
function Get-CasinoSetting-CashlessLevel {
    Return "2"
}
Set-Alias -Name PH_CASHLESSLEVEL -Value Get-CasinoSetting-CashlessLevel
#endregion

#region --- setting AUTH_PIN_REQUIRED
function Get-CasinoSetting-AuthPinRequired {
    Return $false
}
Set-Alias -name PH_AUTH_PIN_REQ -Value Get-CasinoSetting-AuthPinRequired
#endregion

#region --- setting AUTH_INACTIVITY
function Get-CasinoSetting-AuthInactivity {
    Return "60"
}
Set-Alias -Name PH_AUTH_INACTIVITY -Value Get-CasinoSetting-AuthInactivity
#endregion

#region --- setting CAWA_PURSELIMIT
function Get-CasinoSetting-CaWaPurseLimit {
    Return "10000"
}
Set-Alias -Name PH_CAWA_PURSELIMIT -Value Get-CasinoSetting-CaWaPurseLimit
#endregion

#region --- setting RFID_BLOWFISH
function Get-CasinoSetting-RFIDBlowfish {
    #Return "1MNZ1obhhiDhP4zc1rIv2Qa+4ESGyJO94bTt7txlhZU="
    Return (Get-CasinoRFIDKeys BlowfishKey)
}
Set-Alias -Name PH_RFID_BLOWFISH -Value Get-CasinoSetting-RFIDBlowfish
#endregion

#region --- setting RFID_READKEY_MAD 
function Get-CasinoSetting-RFIDReadKeyMAD {
    #Return "uAUc8/dyBJ4mtfcG9aV1zQ=="
    Return (Get-CasinoRFIDKeys ReadKey_MAD)
}
Set-Alias -Name PH_RFID_READKEY_MAD -Value Get-CasinoSetting-RFIDReadKeyMAD
#endregion

#region --- setting RFID_WRITEKEY_MAD 
function Get-CasinoSetting-RFIDWriteKeyMAD {
    #Return "tMvBcO9a0wy3tomAVgnkPw=="
    Return (Get-CasinoRFIDKeys WriteKey_MAD)
}
Set-Alias -Name PH_RFID_WRITEKEY_MAD -Value Get-CasinoSetting-RFIDWriteKeyMAD
#endregion

#region --- setting SAM_CRD
function Get-CasinoSetting-SAMCRD {
    Return "to be defined :)"
}
Set-Alias -Name PH_SAM_CRD -Value Get-CasinoSetting-SAMCRD
#endregion

#region --- setting SAM_CRD
function Get-CasinoSetting-PlayerCRD {
    Return "to be defined :)"
}
Set-Alias -Name PH_PLAYER_CRD -Value Get-CasinoSetting-PlayerCRD
#endregion

#region --- setting WRITEKEY_READONLY
function Get-CasinoSetting-WriteKeyReadOnly {
    Return "NBAepXV27woiGDb8j2eJkw=="
}
Set-Alias -Name PH_WRITEKEY_READONLY -Value Get-CasinoSetting-WriteKeyReadOnly
#endregion

#region --- setting READKEY_READONLY
function Get-CasinoSetting-ReadKeyReadOnly {
    Return "NBAepXV27woiGDb8j2eJkw=="
}
Set-Alias -Name PH_READKEY_READONLY -Value Get-CasinoSetting-ReadKeyReadOnly
#endregion

#region --- setting WRITEKEY_READWRITE
function Get-CasinoSetting-WriteKeyReadWrite {
    Return "NBAepXV27woiGDb8j2eJkw=="
}
Set-Alias -Name PH_WRITEKEY_READWRITE -Value Get-CasinoSetting-WriteKeyReadWrite
#endregion

#region --- setting READKEY_READWRITE
function Get-CasinoSetting-ReadKeyReadWrite {
    Return "NBAepXV27woiGDb8j2eJkw=="
}
Set-Alias -Name PH_READKEY_READWRITE -Value Get-CasinoSetting-ReadKeyReadWrite
#endregion 
#endregion

#region --- all PlaceholderKeys as an array for later use
function Get-PlaceholderKeys {
    [CmdletBinding()]
    param()

    $placeholderKeys = @()
    $placeholderKeys = (Get-Command -CommandType Alias, Function -Name 'PH_*' -ErrorAction SilentlyContinue).Name

    if ($placeholderKeys) {
        Return $placeholderKeys
    } else {
        $fallback = @(
            "PH_ENVIRONMENT",
            "PH_TIMEZONE",
            "PH_DEFAULT_LANGUAGE",
            "PH_SOCIETY",
            "PH_CUSTOMER_CODE",
            "PH_SOCIETY_NAME",
            "PH_CUSTOMER_NAME",
            "PH_CASINOID",
            "PH_CASINO_ID",
            "PH_ESTABLISHMENT",
            "PH_CASINO_CODE",
            "PH_ESTABLISHMENT_NAME",
            "PH_CASINO_NAME",
            "PH_ESTABLISHMENT_LONGNAME",
            "PH_CASINO_LONGNAME",
            "PH_FSERVER_IPSEC",
            "PH_GALAXIS_DB_TNS",
            "PH_JACKPOT_DB_TNS",
            "PH_DBSERVER_HOSTNAME",
            "PH_APPSERVER_HOSTNAME",
            "PH_FSERVER_HOSTNAME",
            "PH_DBSERVER_IP",
            "PH_APPSERVER_IP",
            "PH_FSERVER_IP",
            "PH_FSERVER_FLOOR_IP",
            "PH_SPECIFIC_DB_USER",
            "PH_SPECIFIC_DB_PASSWORD",
            "PH_GALAXIS_DB_USER",
            "PH_GALAXIS_DB_PASSWORD",
            "PH_MIS_DB_USER",
            "PH_MIS_DB_PASSWORD",
            "PH_SPA_DB_USER",
            "PH_SPA_DB_PASSWORD",
            "PH_MKTDTM_DB_USER",
            "PH_MKTDTM_DB_PASSWORD",
            "PH_MESSENGER_DB_USER",
            "PH_MESSENGER_DB_PASSWORD",
            "PH_QPCASH_DB_USER",
            "PH_QPCASH_DB_PASSWORD",
            "PH_TBL_DB_USER",
            "PH_TBL_DB_PASSWORD",
            "PH_ALRMSRV_DB_USER",
            "PH_ALRMSRV_DB_PASSWORD",
            "PH_TRNSSRV_DB_USER",
            "PH_TRNSSRV_DB_PASSWORD",
            "PH_AML_DB_USER",
            "PH_AML_DB_PASSWORD",
            "PH_JUNKET_DB_USER",
            "PH_JUNKET_DB_PASSWORD",
            "PH_ASSET_DB_USER",
            "PH_ASSET_DB_PASSWORD",
            "PH_SLOTEXP_DB_USER",
            "PH_SLOTEXP_DB_SCHEMA",
            "PH_SLOTEXP_DB_PASSWORD",
            "PH_RG_DB_USER",
            "PH_RG_DB_PASSWORD",
            "PH_AUTH_DB_USER",
            "PH_AUTH_DB_PASSWORD",
            "PH_SBC_DB_USER",
            "PH_SBC_DB_PASSWORD",
            "PH_REP_ADMIN_HO_USER",
            "PH_REP_ADMIN_HO_PASSWORD",
            "PH_JACKPOT_DB_USER",
            "PH_JACKPOT_DB_PASSWORD",
            "PH_BASE_DB_USER",
            "PH_BASE_DB_PASSWORD",
            "PH_SECURITY_DB_USER",
            "PH_SECURITY_DB_PASSWORD",
            "PH_DBX_DB_USER",
            "PH_DBX_DB_PASSWORD",
            "PH_FX_DB_USER",
            "PH_FX_DB_PASSWORD",
            "PH_REPORT_DB_USER",
            "PH_REPORT_DB_PASSWORD",
            "PH_CONFIG_INTERFACE_USER",
            "PH_CONFIG_INTERFACE_PASSWORD",
            "PH_CASHLESSLEVEL",
            "PH_AUTH_PIN_REQ",
            "PH_AUTH_INACTIVITY",
            "PH_CAWA_PURSELIMIT",
            "PH_RFID_BLOWFISH",
            "PH_RFID_READKEY_MAD",
            "PH_RFID_WRITEKEY_MAD",
            "PH_SAM_CRD",
            "PH_PLAYER_CRD",
            "PH_WRITEKEY_READONLY",
            "PH_READKEY_READONLY",
            "PH_WRITEKEY_READWRITE",
            "PH_READKEY_READWRITE"
        )
        Return $fallback
    }    
}
#endregion
#endregion

#Export-ModuleMember -Function * -Alias * -Variable *