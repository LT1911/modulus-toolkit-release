#tlukas, 22.10.2024

#write-host "Loading 4-server-admin.psm1!" -ForegroundColor Green

#region --- placeholder logic
function Invoke-PlaceholderReplacement {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()] 
        [string] $BasePath = "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates",

        # Or pass variables directly (Hashtable / PSCustomObject)
        [hashtable] $Variables,

        # File patterns to include (default: *.ini). You can pass many.
        [string[]] $Include = @('*.ini'),

        # Overwrite files in place
        [switch] $InPlace,

        # If NOT -InPlace: write processed files under this root, preserving subfolders
        [string] $OutputRoot,

        # If NOT -InPlace: suffix to append before extension (e.g. "file.out.ini")
        [string] $Suffix = '.out',

        # Create a .bak copy before overwriting (only when -InPlace)
        [switch] $Backup,

        # Log unresolved placeholders (default: on)
        [switch] $WarnOnUnresolved = $true,

        # Fail the write if any unresolved placeholders remain
        [switch] $FailOnUnresolved,

        # Emit DEBUG logs for each replacement (masked by default)
        [switch] $ShowReplacements,

        # Mask likely-secret values in DEBUG logs (recommended)
        [switch] $MaskSecrets = $true,

        # Substrings that mark a key as sensitive for masking (case-insensitive)
        [string[]] $MaskKeysLike = @('PASS','PASSWORD','SECRET','KEY','TOKEN'),

        # NEW: strip trailing template suffix from filenames (e.g., *.ini.template -> *.ini)
        [switch] $StripTemplateSuffix,

        # NEW: which suffix to strip when -StripTemplateSuffix is used
        [string] $TemplateSuffix = '.template',

        # NEW: when -InPlace and -StripTemplateSuffix, also rename the file in place after writing
        [switch] $RenameInPlace
    )

    begin {
        # Initialize $Variables if not provided by the user.
        # This will hold both user-provided and dynamically-resolved placeholders.
        if (-not $script:Variables) {
            $script:Variables = @{}
        } else {
            # Use the input $Variables as a starting point
            $script:Variables = $Variables.Clone()
        }

        if (-not $InPlace) {
            if (-not $OutputRoot) {
                throw "When not using -InPlace, you must provide -OutputRoot."
            }
            if (-not (Test-Path $OutputRoot)) {
                New-Item -ItemType Directory -Path $OutputRoot | Out-Null
            }
        }

        #write-log "debug 1" VERBOSE
        # Normalize base path for relative math
        $helper = Resolve-Path $BasePath
        $BasePath = $helper.Path
        #$BasePath = (Resolve-Path $BasePath).Path
        if ($BasePath[-1] -ne '\') { $BasePath += '\' }
        #write-log "debug 2" VERBOSE

        # Normalize base path for relative math
        # FIX START: Using a null check and TrimEnd() is much safer than $BasePath[-1]
#        try {
#            $ResolvedPath = (Resolve-Path $BasePath -ErrorAction Stop | Select-Object -ExpandProperty Path -First 1)
#
#            if (-not [string]::IsNullOrEmpty($ResolvedPath)) {
#                # Trim any existing separator and append a single one.
#                # This ensures $BasePath is always a string and correctly terminated.
#                $BasePath = $ResolvedPath.TrimEnd('\', '/') + '\'
#            } else {
#                # This ensures we don't proceed if Resolve-Path failed unexpectedly
#                throw "Resolved BasePath is empty or null."
#            }
#        } catch {
#            throw "Failed to resolve BasePath '$BasePath'. Error: $($_.Exception.Message)"
#        }
        # FIX END

        # Regex to find any placeholder: {{ NAME }} - Group 1 is the key name
        $script:PlaceholderRx = [regex]'{{\s*([A-Za-z0-9_:\.-]+)\s*}}'

        # Stats
        $script:stats = [ordered]@{
            Processed              = 0
            Written                = 0
            Backups                = 0
            ReadErrors             = 0
            TemplateErrors         = 0
            PatternsFailed         = 0
            UnresolvedTokensTotal  = 0
            UnresolvedFiles        = 0
            SkippedDueToUnresolved = 0
            SkippedNoKnown         = 0
            DynamicResolved        = 0 # NEW Stat
        }
    }

    process {
        # Collect files robustly (no empty-pipe issue)
        $files = @()
        foreach ($pattern in $Include) {
            try {
                $files += Get-ChildItem -Path $BasePath -Recurse -File -Filter $pattern -ErrorAction Stop
            } catch {
                $script:stats.PatternsFailed++
                Write-Log "Include pattern failed: $pattern — $_" -Level WARNING
            }
        }
        $files = $files | Sort-Object -Property FullName -Unique

        foreach ($file in $files) {
            $script:stats.Processed++

            try {
                $content = Get-Content $file.FullName -Raw -ErrorAction Stop
            } catch {
                $script:stats.ReadErrors++
                Write-Log "Skipping (read error): $($file.FullName) — $_" -Level ERROR
                continue
            }

            # ----------------------------------------------------
            # 1. IDENTIFY REQUIRED PLACEHOLDERS IN THIS FILE
            # ----------------------------------------------------
            $requiredKeys = @{}
            $script:PlaceholderRx.Matches($content) | ForEach-Object {
                $key = $_.Groups[1].Value
                $requiredKeys[$key] = $true
            }

            # Skip files if no placeholders were found
            if ($requiredKeys.Count -eq 0) {
                $script:stats.SkippedNoKnown++
                continue
            }

            write-log "Processing file: $($file.FullName)" -Level VERBOSE

            # ----------------------------------------------------
            # 2. LAZY RESOLUTION: Resolve only the necessary PH_*
            # ----------------------------------------------------
            foreach ($key in $requiredKeys.Keys) {
                # Only attempt to resolve if:
                # 1. The key starts with 'PH_' (our naming convention for dynamic keys)
                # 2. The key is NOT already present in our working $script:Variables collection
                if ($key -like 'PH_*' -and -not $script:Variables.ContainsKey($key)) {

                    # Check if a function/alias exists for the placeholder name
                    if (Get-Command -Name $key -ErrorAction SilentlyContinue) {
                        
                        Write-Log "Dynamically resolving required placeholder: $key" -Level DEBUG
                        # Direct invocation of the PH_* alias/function to get the clean value
                        $Value = & $key
                        
                        # Add the resolved value to the session-level variables hashtable
                        $script:Variables[$key] = $Value
                        $script:stats.DynamicResolved++
                    }
                }
            }


            # Optional: per-placeholder DEBUG preview of replacements
            if ($ShowReplacements) {
                foreach ($key in $script:Variables.Keys) {
                    # Only show replacements for keys required by THIS file
                    if ($requiredKeys.ContainsKey($key)) {
                        $value = $script:Variables[$key]
                        $rx = [regex]("\{\{\s*" + [regex]::Escape($key) + "\s*\}\}")
                        if ($rx.IsMatch($content)) {
                            $display = $value
                            if ($MaskSecrets) {
                                foreach ($needle in $MaskKeysLike) {
                                    if ($key -imatch [regex]::Escape($needle)) {
                                        $display = if ($null -ne $value) { '***' } else { '<null>' }
                                        break
                                    }
                                }
                            }
                            Write-Log ("Replacing {{${key}}} → '{0}' in {1}" -f $display, $file.Name) -Level DEBUG
                        }
                    }
                }
            }

            # ----------------------------------------------------
            # 3. RENDER CONTENT
            # ----------------------------------------------------
            # Use the now-updated $script:Variables for rendering
            try {
                $rendered = $content | Fill-Template -Variables $script:Variables
            } catch {
                $script:stats.TemplateErrors++
                Write-Log "Skipping (template error): $($file.FullName) — $_" -Level ERROR
                continue
            }

            # ----------------------------------------------------
            # 4. WRITE FILE
            # ----------------------------------------------------
            # Detect unresolved placeholders AFTER rendering (using the same PlaceholderRx as before)
            $unresolvedMatches = $script:PlaceholderRx.Matches($rendered)
            $unresolvedNames = @()
            foreach ($m in $unresolvedMatches) { $unresolvedNames += $m.Groups[1].Value }
            $unresolvedNames = $unresolvedNames | Sort-Object -Unique
            $unresolvedCount = $unresolvedMatches.Count

            if ($unresolvedCount -gt 0) {
                $script:stats.UnresolvedTokensTotal += $unresolvedCount
                $script:stats.UnresolvedFiles++
                if ($WarnOnUnresolved) {
                    Write-Log ("Unresolved placeholders in {0}: {1}" -f $file.FullName, ($unresolvedNames -join ', ')) -Level WARNING
                }
                if ($FailOnUnresolved) {
                    $script:stats.SkippedDueToUnresolved++
                    Write-Log "Failing write due to unresolved placeholders: $($file.FullName)" -Level ERROR
                    continue
                }
            } else {
                Write-Log "All placeholders resolved for: $($file.FullName)" -Level INFO
            }

            # Writing logic remains the same (InPlace or OutputRoot)
            if ($InPlace) {
                if ($PSCmdlet.ShouldProcess($file.FullName, "Overwrite with rendered content")) {
                    # ... [Backup, Set-Content, and RenameInPlace logic here] ...
                    try {
                        if ($Backup) {
                            $bak = "$($file.FullName).bak"
                            Copy-Item $file.FullName $bak -Force
                            $script:stats.Backups++
                            Write-Log "Backup created: $bak" -Level INFO
                        }
                        Set-Content -Path $file.FullName -Value $rendered -Encoding UTF8
                        $script:stats.Written++

                        # Optional in-place rename after writing (strip .template)
                        if ($StripTemplateSuffix -and $RenameInPlace -and ($file.Extension -ieq $TemplateSuffix)) {
                            $dir = Split-Path $file.FullName -Parent
                            $stem = $file.BaseName
                            $innerExt = [System.IO.Path]::GetExtension($file.BaseName)
                            if (-not [string]::IsNullOrEmpty($innerExt)) {
                                $stem = [System.IO.Path]::GetFileNameWithoutExtension($file.BaseName)
                                $targetName = '{0}{1}' -f $stem, $innerExt # e.g., 'app.ini'
                            } else {
                                $targetName = $stem # e.g., 'app'
                            }
                            $targetPath = Join-Path $dir $targetName

                            try {
                                Move-Item -LiteralPath $file.FullName -Destination $targetPath -Force
                                Write-Log "Renamed to: $targetPath" -Level INFO
                            } catch {
                                Write-Log "Failed to rename to: $targetPath — $_" -Level ERROR
                            }
                        }
                    } catch {
                        Write-Log "Failed to write: $($file.FullName) — $_" -Level ERROR
                    }
                }
            } else {
                # Preserve relative path under OutputRoot
                $relative = $file.FullName.Substring($BasePath.Length)
                $outDir = Split-Path (Join-Path $OutputRoot $relative) -Parent

                # Compute output name with optional .template stripping
                $stem = $file.BaseName
                $finalExt = $file.Extension
                if ($StripTemplateSuffix -and ($file.Extension -ieq $TemplateSuffix)) {
                    $innerExt = [System.IO.Path]::GetExtension($file.BaseName)
                    if ([string]::IsNullOrEmpty($innerExt)) {
                        $finalExt = ''
                    } else {
                        $finalExt = $innerExt
                        $stem = [System.IO.Path]::GetFileNameWithoutExtension($file.BaseName)
                    }
                }

                $outName = '{0}{1}{2}' -f $stem, $Suffix, $finalExt
                $outPath = Join-Path $outDir $outName

                if (-not (Test-Path $outDir)) {
                    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
                }

                if ($PSCmdlet.ShouldProcess($outPath, "Write rendered file")) {
                    try {
                        Set-Content -Path $outPath -Value $rendered -Encoding UTF8
                        $script:stats.Written++
                        Write-Log "Wrote file: $outPath" -Level VERBOSE
                    } catch {
                        Write-Log "Failed to write: $outPath — $_" -Level ERROR
                    }
                }
            }
        }
    }

    end {
        Write-Host " " # empty line for readability
        Write-Log "Summary" -Level DEBUG
        Write-Log ("Processed:{0}  Written:{1}  Backups:{2}  ReadErrors:{3}  TemplateErrors:{4}  UnresolvedTokens:{5}  UnresolvedFiles:{6}  SkippedDueToUnresolved:{7}  PatternsFailed:{8}  SkippedNoKnown:{9}  DynamicResolved:{10}" -f `
            $script:stats.Processed, `
            $script:stats.Written, `
            $script:stats.Backups, `
            $script:stats.ReadErrors, `
            $script:stats.TemplateErrors, `
            $script:stats.UnresolvedTokensTotal, `
            $script:stats.UnresolvedFiles, `
            $script:stats.SkippedDueToUnresolved, `
            $script:stats.PatternsFailed, `
            $script:stats.SkippedNoKnown, `
            $script:stats.DynamicResolved) -Level SUCCESS
    }
}

function Set-hosts {
    Write-Log "Set-hosts" -Header
    
    Invoke-PlaceholderReplacement `
        -BasePath "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates" `
        -Include 'hosts.template' `
        -OutputRoot "C:\Windows\System32\drivers\etc" `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets    
}

function Set-QB-Config {
    write-log "Set-QB-Config" -Header
    Invoke-PlaceholderReplacement `
        -BasePath "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates" `
        -Include 'qb.cfg.template' `
        -OutputRoot "D:\OnlineData\cfg" `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets    
}

function Set-Client-tnsnames {
    Write-Log "Set-Client-tnsnames" -Header
    Invoke-PlaceholderReplacement `
        -BasePath "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates" `
        -Include 'tnsnames.ora.template' `
        -OutputRoot "C:\Oracle\client32\network\admin\" `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets    
}

function Set-GalaxisIntall-tnsnames {
    Write-Log "Set-GalaxisIntall-tnsnames" -Header
    if ($env:MODULUS_SERVER -notin ("APP","1VM")) {
        Write-Log "Wrong server!" WARNING
        Return
    }
    Invoke-PlaceholderReplacement `
        -BasePath "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates" `
        -Include 'tnsnames.ora.template' `
        -OutputRoot "D:\Galaxis\Install\Batch\" `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets    
}

function Set-Binaries-tnsnames {
    Write-Log "Set-Binaries-tnsnames" -Header

    $candidates = @(
        'D:\Oracle\Ora23c\network\admin',
        'D:\Oracle\Ora19c\network\admin',
        'D:\Oracle\Ora12c\network\admin'
    )

    foreach ($path in $candidates) {
        if (Test-Path -Path $path -PathType Container) {
            $OutputRoot = $path
        }
    }
    
    Invoke-PlaceholderReplacement `
        -BasePath "C:\Program Files\PowerShell\Modules\modulus-toolkit\templates" `
        -Include 'tnsnames.ora.template' `
        -OutputRoot $OutputRoot `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets    
}

function Test-ConfigOnly-PH {
    Write-Log "Test-ConfigOnly-PH" -Header
    
    Invoke-PlaceholderReplacement `
        -BasePath "I:\modulus-toolkit\prep\GALAXIS Config only" `
        -Include '*' `
        -OutputRoot "I:\modulus-toolkit\prep\GALAXIS Config only replaced" `
        -StripTemplateSuffix `
        -Suffix '' `
        -ShowReplacements `
        -MaskSecrets    
}
#endregion

#region --- initialization scripts
function Initialize-VM {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Optional override. If not provided, we read $env:MODULUS_SERVER
        [ValidateSet('DB','APP','FS','1VM','WS')]
        [string] $VM
    )

    #Write-Log "Initialize-VM" -Header

    $envRole = ($env:MODULUS_SERVER ?? '').Trim()
    if (-not $VM) {
        if ([string]::IsNullOrWhiteSpace($envRole)) {
            $msg = "MODULUS_SERVER environment variable is not set. Expected one of: DB, APP, FS, 1VM, WS."
            Write-Log $msg -Level ERROR
            throw $msg
        }
        $VM = $envRole.ToUpperInvariant()
        Write-Log "Using role from MODULUS_SERVER: '$VM'." -Level INFO
    }
    else {
        # If both provided and disagree, prefer parameter but warn.
        if ($envRole -and ($VM.ToUpperInvariant() -ne $envRole.ToUpperInvariant())) {
            Write-Log "Parameter -VM '$VM' overrides MODULUS_SERVER='$envRole'." -Level WARNING
        }
        $VM = $VM.ToUpperInvariant()
    }

    # Bubble -WhatIf/-Confirm to inner functions
    $invokeCommon = @{}
    if ($PSBoundParameters.ContainsKey('WhatIf'))  { $invokeCommon['WhatIf']  = $PSBoundParameters['WhatIf'] }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $invokeCommon['Confirm'] = $PSBoundParameters['Confirm'] }

    switch ($VM) {
        'DB'  { Initialize-DB  @invokeCommon }
        'APP' { Initialize-APP @invokeCommon }
        'FS'  { Initialize-FS  @invokeCommon }
        '1VM' { Initialize-1VM @invokeCommon }
        'WS'  { Initialize-WS  @invokeCommon }
        default {
            $msg = "Unsupported role '$VM'. Allowed: DB, APP, FS, 1VM, WS."
            Write-Log $msg -Level ERROR
            throw $msg
        }
    }
}

function Initialize-DB {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $server = $env:MODULUS_SERVER
    if ($server -ine 'DB') {
        Write-Log "Skipping Initialize-DB because MODULUS_SERVER='$server'." -Level WARNING
        return
    }

    Write-Log "Initialize-DB" -Header

    $desired = Get-MOD-DB-hostname
    $current = $env:COMPUTERNAME  # fast & reliable for local box
    $renamed = $false

    # 1) Computer name
    if ($current -ieq $desired) {
        Write-Log "Hostname already set to '$current'. Skipping rename." INFO
    } else {
        Write-Log "Preparing to rename computer: '$current' -> '$desired'" INFO
        if ($PSCmdlet.ShouldProcess($desired, "Rename computer from '$current'")) {
            try {
                Rename-Computer -NewName $desired -Force -ErrorAction Stop
                Write-Log "Computer rename scheduled: '$current' -> '$desired' (reboot required)." WARNING
                $renamed = $true
            } catch {
                Write-Log "Rename-Computer failed: $_" ERROR
                return
            }
        }
    }

    try {
        Initialize-Disks -AsResult | Out-Null
        #Mount-I-Share  # relies on I: share already existing on APP-server - leaving this one out for now
    } catch {
        Write-Log "Disk initialization failed: $_" -Level ERROR
        return
    }

    try {
        Rename-MOD-NetAdapters
        Set-MOD-Network
        #Compare-MOD-Network
    }
    catch {
        Write-Log "Network initialization failed: $_" -Level ERROR
        return
    }

    #try {
        Set-MOD-ENVVARs
    
        Set-hosts
        Set-QB-Config
        Set-Client-tnsnames
        Set-Binaries-tnsnames

        Set-DBX-Config
        Set-SecurityServer-Config
        Set-TriggerMDS-Properties

    #} catch {
    #    Write-Log "Initial configuration failed: $_" -Level ERROR
    #    return
    #}

    if ($renamed) {
         # 3) Reboot note / action
        Write-Log "The changes made need a reboot to be effective!" WARNING
        Restart-HostWithPrompt
    }
}

function Initialize-APP {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $server = $env:MODULUS_SERVER
    if ($server -ine 'APP') {
        Write-Log "Skipping Initialize-APP because MODULUS_SERVER='$server'." -Level WARNING
        return
    }

    Write-Log "Initialize-APP" -Header

    $desired = Get-MOD-APP-hostname
    $current = $env:COMPUTERNAME
    $renamed = $false

    # 1) Computer name
    if ($current -ieq $desired) {
        Write-Log "Hostname already set to '$current'. Skipping rename." -Level INFO
    } else {
        Write-Log "Preparing to rename computer: '$current' -> '$desired'" -Level INFO
        if ($PSCmdlet.ShouldProcess($desired, "Rename computer from '$current'")) {
            try {
                Rename-Computer -NewName $desired -Force -ErrorAction Stop
                Write-Log "Computer rename scheduled: '$current' -> '$desired' (reboot required)." -Level WARNING
                $renamed = $true
            } catch {
                Write-Log "Rename-Computer failed: $_" -Level ERROR
                return
            }
        }
    }

    try {
        Initialize-Disks -AsResult | Out-Null
        Mount-M-Share
        Set-SubstO-autostart
    } catch {
        Write-Log "Disk initialization failed: $_" -Level ERROR
        return
    }

    try {
        Rename-MOD-NetAdapters
        Set-MOD-Network
        #Compare-MOD-Network
    }
    catch {
        Write-Log "Network initialization failed: $_" -Level ERROR
        return
    }

    #try {
        Set-MOD-ENVVARs
        
        Set-hosts
        Set-QB-Config
        Set-Client-tnsnames

        Set-JPApps-Config
        Set-Web-Config
        Set-Reverse-Proxy-Config

    #} catch {
    #    Write-Log "Initial configuration failed: $_" -Level ERROR
    #    return
    #}

    # 3) Reboot note / action
    if ($renamed) {
        Write-Log "The changes made need a reboot to be effective!" -Level WARNING
        Write-Log "After the hostname change, run: D:\GALAXIS\Install\Batch\SERVER.bat" -Level WARNING
        Restart-HostWithPrompt
    }
}

function Initialize-FS {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $server = $env:MODULUS_SERVER
    if ($server -ine 'FS') {
        Write-Log "Skipping Initialize-FS because MODULUS_SERVER='$server'." -Level WARNING
        return
    }

    Write-Log "Initialize-FS" -Header

    $desired = Get-MOD-FS-hostname
    $current = $env:COMPUTERNAME
    $renamed = $false

    # 1) Computer name
    if ($current -ieq $desired) {
        Write-Log "Hostname already set to '$current'. Skipping rename." -Level INFO
    } else {
        Write-Log "Preparing to rename computer: '$current' -> '$desired'" -Level INFO
        if ($PSCmdlet.ShouldProcess($desired, "Rename computer from '$current'")) {
            try {
                Rename-Computer -NewName $desired -Force -ErrorAction Stop
                Write-Log "Computer rename scheduled: '$current' -> '$desired' (reboot required)." -Level WARNING
                $renamed = $true
            } catch {
                Write-Log "Rename-Computer failed: $_" -Level ERROR
                return
            }
        }
    }

    try {
        Initialize-Disks -AsResult | Out-Null
        #Mount-I-Share  # relies on I: share already existing on APP-server - leaving this one out for now
    } catch {
        Write-Log "Disk initialization failed: $_" -Level ERROR
        return
    }

    try {
        Rename-MOD-NetAdapters
        Set-MOD-Network
        #Compare-MOD-Network
    }
    catch {
        Write-Log "Network initialization failed: $_" -Level ERROR
        return
    }

    #try {
        Set-MOD-ENVVARs
        
        Set-hosts
        Set-QB-Config
        Set-Client-tnsnames

        Set-CFCS-Config
        Set-CRYSTALControl-Config
        Set-FS-Config
        #Set-Reverse-Proxy-Config #TODO - differentiate between APP nginx and FS nginx

    #} catch {
    #    Write-Log "Initial configuration failed: $_" -Level ERROR
    #    return
    #}

    if ($renamed) {
        Write-Log "The changes made need a reboot to be effective!" -Level WARNING
        Restart-HostWithPrompt
    }
}

function Initialize-1VM {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $server = $env:MODULUS_SERVER
    if ($server -ine '1VM') {
        Write-Log "Skipping Initialize-1VM because MODULUS_SERVER='$server'." -Level WARNING
        return
    }

    Write-Log "Initialize-1VM" -Header

    $desired = Get-MOD-APP-hostname
    $current = $env:COMPUTERNAME
    $renamed = $false

    # 1) Computer name
    if ($current -ieq $desired) {
        Write-Log "Hostname already set to '$current'. Skipping rename." -Level INFO
    } else {
        Write-Log "Preparing to rename computer: '$current' -> '$desired'" -Level INFO
        if ($PSCmdlet.ShouldProcess($desired, "Rename computer from '$current'")) {
            try {
                Rename-Computer -NewName $desired -Force -ErrorAction Stop
                Write-Log "Computer rename scheduled: '$current' -> '$desired' (reboot required)." -Level WARNING
                $renamed = $true
            } catch {
                Write-Log "Rename-Computer failed: $_" -Level ERROR
                return
            }
        }
    }

    try {
        Initialize-Disks -AsResult | Out-Null
        #Mount-I-Share  # relies on I: share already existing on APP-server - leaving this one out for now
        Mount-M-Share
        Set-SubstO-autostart
    } catch {
        Write-Log "Disk initialization failed: $_" -Level ERROR
        return
    }

    try {
        Rename-MOD-NetAdapters
        Set-MOD-Network
        Compare-MOD-Network
    }
    catch {
        Write-Log "Network initialization failed: $_" -Level ERROR
        return
    }

    #try {
        Set-MOD-ENVVARs
    
        Set-hosts
        Set-QB-Config
        Set-Client-tnsnames
        Set-Binaries-tnsnames

        Set-DBX-Config
        Set-SecurityServer-Config
        Set-TriggerMDS-Properties
		
		Set-JPApps-Config
        Set-Web-Config
        Set-Reverse-Proxy-Config
		
		Set-CFCS-Config
        Set-CRYSTALControl-Config
        Set-FS-Config

    #} catch {
    #    Write-Log "Initial configuration failed: $_" -Level ERROR
    #    return
    #}

    # 3) Reboot note / action
    if ($renamed) {
        Write-Log "The changes made need a reboot to be effective!" -Level WARNING
        Write-Log "After the hostname change, run: D:\GALAXIS\Install\Batch\SERVER.bat" -Level WARNING
        Restart-HostWithPrompt
    }
}

function Initialize-WS {
    Write-Host "Not implemented yet!" -ForegroundColor Red
}
#endregion

#region --- restart VM after initializing
function Restart-HostWithPrompt {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    do {
        $response = Read-Host "Do you want to reboot the host now? (Yes/No)"
    } while ($response -notmatch '^(?i:yes|no)$')  # loop until valid

    if ($response -ieq "yes") {
        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Restart-Computer -Force")) {
            write-log "Restarting computer now..." WARNING
            Restart-Computer -Force
            return $true
        }
    } else {
        write-log "Reboot cancelled by user. Please remember to reboot later to apply changes." WARNING
        return $false
    }
}
#endregion

#region --- one time things after sysprep?!
function Set-SubstO-Autostart {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Where the subst script lives
        [string] $ScriptPath = 'I:\Other\substO.bat',

        # Also run the script immediately after ensuring autostart
        [switch] $RunAfter,

        # Overwrite existing Startup copy even if hashes match
        [switch] $Force
    )

    Write-Log "Set-SubstO-Autostart" -Header

    # 1) Validate source script
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        Write-Log "Source script not found: $ScriptPath" ERROR
        return
    }

    # 2) Resolve Startup folder generically (no hard-coded user path)
    try {
        $startupDir = [Environment]::GetFolderPath('Startup')
    } catch {
        Write-Log "Could not resolve Startup folder: $_" ERROR
        return
    }
    if (-not $startupDir) {
        Write-Log "Startup folder path is empty or null." ERROR
        return
    }

    if (-not (Test-Path -LiteralPath $startupDir -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($startupDir, "Create Startup folder")) {
            New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
            Write-Log "Created Startup folder: $startupDir" DEBUG
        }
    }

    $destPath = Join-Path $startupDir 'substO.bat'

    # 3) Decide whether to copy (compare hashes if destination exists)
    $shouldCopy = $true
    if (Test-Path -LiteralPath $destPath -PathType Leaf) {
        try {
            $srcHash  = (Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256).Hash
            $dstHash  = (Get-FileHash -LiteralPath $destPath  -Algorithm SHA256).Hash
            if (-not $Force -and $srcHash -eq $dstHash) {
                $shouldCopy = $false
                Write-Log "Autostart already set and up-to-date: $destPath" INFO
            } else {
                Write-Log "Existing Startup copy differs (or -Force used); will update." DEBUG
            }
        } catch {
            Write-Log "Hash comparison failed; will overwrite destination. $_" WARNING
        }
    }

    # 4) Copy into Startup if needed
    if ($shouldCopy) {
        if ($PSCmdlet.ShouldProcess($destPath, "Copy $ScriptPath -> Startup")) {
            try {
                Copy-Item -LiteralPath $ScriptPath -Destination $destPath -Force -ErrorAction Stop
                Write-Log "Placed subst script in Startup: $destPath" INFO
            } catch {
                Write-Log "Failed to copy to Startup: $_" ERROR
                return
            }
        }
    }

    # 5) Optionally run the script now
    if ($RunAfter) {
        if ($PSCmdlet.ShouldProcess($ScriptPath, "Run subst script now")) {
            try {
                # Run via cmd.exe to execute .bat reliably without popping an editor
                Start-Process -FilePath $env:ComSpec -ArgumentList "/c `"$ScriptPath`"" -WindowStyle Hidden
                Write-Log "Executed: $ScriptPath" INFO
            } catch {
                Write-Log "Failed to execute $ScriptPath : $_" ERROR
            }
        }
    }
}
#endregion

#region --- environment variables
function Set-MOD-ENVVARs {    
    $PH_TIMEZONE     = Get-GeneralTimezone
    $PH_APPSERVER_HN = Get-MOD-APP-hostname
    $PH_DBSERVER_HN  = Get-MOD-DB-hostname
    
    $desiredENVVARs  = Get-MOD-DesiredENVVARs
    
    Write-Log "Set-MOD-ENVVARs" -Header

    # Iterate over the environment variables and set them
    foreach ($envVar in $desiredENVVARs.EnvironmentVariables.PSObject.Properties) {
        # Replace placeholders in the variable value
        $variableValue = $envVar.Value `
            -replace '{{PH_APPSERVER_HN}}', $PH_APPSERVER_HN `
            -replace '{{PH_DBSERVER_HN}}',  $PH_DBSERVER_HN `
            -replace '{{PH_TIMEZONE}}',     $PH_TIMEZONE

        # Set the environment variable
        [System.Environment]::SetEnvironmentVariable($envVar.Name, $variableValue, [System.EnvironmentVariableTarget]::Machine)
        Write-Log "Set environment variable $($envVar.Name) to $variableValue." INFO    
    }
}
#endregion

#region --- network adapters
function Rename-MOD-NetAdapters {
    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact='High'
    )]
    param()

    begin {
        $script:OverallSuccess = $true
        # Array to store all required rename actions
        $script:RenameActions = @()
        Write-Log "Rename-MOD-NetAdapters" -Header 
    }

    process {
        $serverRole = $env:MODULUS_SERVER
        if ([string]::IsNullOrWhiteSpace($serverRole)) {
            Write-Log "MODULUS_SERVER environment variable is NOT set. Cannot determine server role for renaming." -Level ERROR
            $script:OverallSuccess = $false
            return
        }

        # 1. Get all physical adapters, sorted by InterfaceDescription (ASC) for reliable positional consistency.
        $adapters = Get-NetAdapter -Physical | Sort-Object { $_.InterfaceDescription }
        $totalNics = $adapters.Count
        $roleMap = @{} # Dictionary to hold {Position Index: DesiredName}

        # 2. Define Naming Logic based on your role rules
        $normalizedRole = $serverRole.ToUpper()

        switch ($normalizedRole) {
            'DB' {
                # ENFORCED ORDER: Position 0 MUST be OFFICE, Position 1 MUST be MODULUS
                $roleMap.Add(0, 'OFFICE'); if ($totalNics -ge 2) { $roleMap.Add(1, 'MODULUS') }
            }
            'APP' {
                # ENFORCED ORDER: Position 0 MUST be OFFICE, Position 1 MUST be MODULUS
                $roleMap.Add(0, 'OFFICE'); if ($totalNics -ge 2) { $roleMap.Add(1, 'MODULUS') }
            }
            'FS' {
                # ENFORCED ORDER: Position 0=OFFICE, Position 1=FLOOR, Position 2=MODULUS
                $roleMap.Add(0, 'OFFICE'); if ($totalNics -ge 2) { $roleMap.Add(1, 'FLOOR') }; if ($totalNics -ge 3) { $roleMap.Add(2, 'MODULUS') }
            }
            '1VM' {
                # ENFORCED ORDER: Position 0=OFFICE, Position 1=FLOOR, Position 2=MODULUS
                $roleMap.Add(0, 'OFFICE'); if ($totalNics -ge 2) { $roleMap.Add(1, 'FLOOR') }; if ($totalNics -ge 3) { $roleMap.Add(2, 'MODULUS') }
            }
            default {
                Write-Log "Server role '$serverRole' is not recognized. Cannot proceed with renaming." -Level ERROR
                $script:OverallSuccess = $false
                return
            }
        }
        
        Write-Log "Role '$serverRole' detected. Will scan $($totalNics) adapter(s)." -Level INFO

        # 3. Collect ALL required rename actions into $script:RenameActions
        for ($i = 0; $i -lt $adapters.Count; $i++) {
            $liveAdapter = $adapters[$i]
            $currentAlias = $liveAdapter.InterfaceAlias
            
            if ($roleMap.ContainsKey($i)) {
                $desiredAlias = $roleMap[$i]
                
                if ($currentAlias -ne $desiredAlias) {
                    Write-Log "DISCREPANCY: Position $i currently '$currentAlias', desired '$desiredAlias'." -Level WARNING
                    
                    # Store the action needed for two-pass processing
                    $script:RenameActions += [PSCustomObject]@{
                        CurrentAlias = $currentAlias
                        DesiredAlias = $desiredAlias
                        TempAlias    = "_TEMP_$i" # Unique temporary name
                    }
                } else {
                    Write-Log "Adapter '$desiredAlias' is already correctly named (Position $i). Skipping." -Level INFO
                }
            } else {
                # Adapter exists but is not mapped in this server role
                Write-Log "NIC at Position $i ('$currentAlias') is unmapped for role '$serverRole'. Skipping rename." -Level VERBOSE
            }
        }
    }

    end {
        # Check if any renames are necessary
        if ($script:RenameActions.Count -eq 0) {
            Write-Log "No renaming actions required." SUCCESS
            return $true
        }

        # --- PASS 1: STAGING (Rename CurrentAlias to TempAlias) ---
        Write-Log "PASS 1: Staging $($script:RenameActions.Count) adapter(s) to temporary names." -Header
        foreach ($action in $script:RenameActions) {
            if ($PSCmdlet.ShouldProcess($action.CurrentAlias, "Stage rename to temporary alias $($action.TempAlias)")) {
                try {
                    Rename-NetAdapter -Name $action.CurrentAlias -NewName $action.TempAlias -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Log "STAGED: '$($action.CurrentAlias)' -> '$($action.TempAlias)'." -Level SUCCESS
                }
                catch {
                    Write-Log "CRITICAL FAILURE (Pass 1 - Staging): Failed to rename '$($action.CurrentAlias)': $($_.Exception.Message)" -Level ERROR
                    $script:OverallSuccess = $false
                    # If staging fails, we must stop the whole process for safety
                    break
                }
            }
        }

        # If staging failed for any reason, stop here.
        if (-not $script:OverallSuccess) {
             Write-Log "Renaming aborted due to critical failure during Staging Pass." ERROR
             return $false
        }
        
        # --- PASS 2: FINALIZING (Rename TempAlias to DesiredAlias) ---
        Write-Log "PASS 2: Finalizing names from temporary aliases." DEBUG
        foreach ($action in $script:RenameActions) {
            # Since the TempAlias is unique, we don't need ShouldProcess again for safety,
            # but we use try/catch to ensure the name stuck.
            try {
                Rename-NetAdapter -Name $action.TempAlias -NewName $action.DesiredAlias -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Log "FINALIZED: '$($action.TempAlias)' -> '$($action.DesiredAlias)'." -Level SUCCESS
            }
            catch {
                Write-Log "CRITICAL FAILURE (Pass 2 - Finalizing): Failed to rename '$($action.TempAlias)': $($_.Exception.Message)" -Level ERROR
                $script:OverallSuccess = $false
            }
        }

        # Final Result
        if ($script:OverallSuccess) {
            Write-Log "Positional NIC renaming routine finished successfully." SUCCESS
        } else {
            Write-Log "Positional NIC renaming routine finished with ERRORS. Check log file for details." ERROR
        }

        return $script:OverallSuccess
    }
}

function Clear-NetAdapterConfig {
    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact='High' # This modifies live network settings
    )]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string[]]$InterfaceAlias,

        [switch]$Force,
        
        # New switch to explicitly target all adapters
        [switch]$FullScope 
    )

    begin {
        $script:AliasesToProcess = @()
        $script:OverallSuccess = $true
        # Define the set of target adapters for the default scope
        $defaultInternalAliases = @('OFFICE', 'FLOOR')
        Write-Log "Clear-NetAdapterConfig" -Header
    }

    process {
        # Collect aliases coming from pipeline or direct parameter call
        if ($InterfaceAlias) {
            $script:AliasesToProcess += $InterfaceAlias
        }
    }

    end {
        # --- Determine the final list of adapters to process ---
        $finalAliases = @()

        if ($script:AliasesToProcess.Count -gt 0) {
            # Scenario 1: User explicitly provided aliases (highest priority)
            $finalAliases = $script:AliasesToProcess
            Write-Log "Targeting $($finalAliases.Count) adapter(s) from explicit input: $($finalAliases -join ', ')" -Level INFO
        } elseif ($FullScope) {
            # Scenario 2: User specified -FullScope (target ALL physical adapters)
            Write-Log "FullScope requested. Targeting ALL physical adapters system-wide." -Level WARNING
            $finalAliases = Get-NetAdapter -Physical | Select-Object -ExpandProperty InterfaceAlias
            
            if (-not $finalAliases) {
                Write-Log "No physical network adapters were found on the system to clean." -Level WARNING
                return $true 
            }
            Write-Log "Found $($finalAliases.Count) physical adapters to process: $($finalAliases -join ', ')" -Level VERBOSE

        } else {
            # Scenario 3: Default scope (target only OFFICE and FLOOR)
            Write-Log "No specific adapter input. Defaulting to internal adapters: $($defaultInternalAliases -join ', ')" -Level INFO
            Write-Log "NOTE: External adapter(s) will be intentionally skipped for system stability. Use -InterfaceAlias or -FullScope to override." -Level VERBOSE
            
            # Filter the system's physical adapters to only include the defaults
            $SystemPhysicalAliases = Get-NetAdapter -Physical | Select-Object -ExpandProperty InterfaceAlias
            $finalAliases = $SystemPhysicalAliases | Where-Object { $_ -in $defaultInternalAliases }
            
            if (-not $finalAliases) {
                Write-Log "No internal adapters ('OFFICE', 'FLOOR') were found on the system to clean." -Level WARNING
                return $true
            }
            Write-Log "Processing $($finalAliases.Count) adapter(s): $($finalAliases -join ', ')" -Level VERBOSE
        }

        # --- Process each adapter ---
        foreach ($alias in $finalAliases) {
            Write-Log "Checking and cleaning configuration for adapter: $alias" -Level INFO
            $currentAdapterSuccess = $false
            
            # 1. Safety Check: ShouldProcess will only run if -Force is NOT used.
            # We use an OR condition: (Force is present) OR (ShouldProcess returns true)
            if ($Force -or $PSCmdlet.ShouldProcess($alias, "Reset IP, Gateway, and DNS to DHCP and cycle adapter link state")) {
                
                try {
                    # --- Remove Existing Static IP Addresses ---
                    $staticIPs = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 | 
                                 Where-Object { $_.PrefixOrigin -eq 'Manual' -and $_.IPAddress -ne '127.0.0.1' }

                    if ($staticIPs) {
                        Write-Log "Removing $($staticIPs.Count) static IP address(es)." -Level VERBOSE
                        # Pipe existing static IPs to removal function
                        $staticIPs | Remove-NetIPAddress -Confirm:$false -ErrorAction Stop | Out-Null
                        Write-Log "Static IP addresses successfully removed." -Level SUCCESS
                    } else {
                        Write-Log "No static IP addresses found to remove." -Level VERBOSE
                    }

                    # --- Set IP and DNS to DHCP ---
                    # Removed '-AutoconfigurationEnabled $true' for backward compatibility.
                    Set-NetIPInterface -InterfaceAlias $alias -DHCP Enabled -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Log "IP configuration successfully set to DHCP." -Level SUCCESS
                    
                    # Set DNS assignment method to Automatic (clears existing static DNS)
                    Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Log "DNS configuration successfully set to Automatic." -Level SUCCESS

                    # --- Cycle Adapter Link State to force configuration to apply ---
                    Write-Log "Cycling adapter link state to enforce configuration (Disable/Enable)." -Level VERBOSE
                    Disable-NetAdapter -InterfaceAlias $alias -Confirm:$false -ErrorAction Stop | Out-Null
                    Start-Sleep -Seconds 1 # Wait for disable to fully register
                    Enable-NetAdapter -InterfaceAlias $alias -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-Log "Adapter link state successfully cycled." -Level SUCCESS
                    
                    $currentAdapterSuccess = $true
                }
                catch {
                    Write-Log "CRITICAL FAILURE on $alias. Could not reset configuration or cycle link: $($_.Exception.Message)" -Level ERROR
                    $script:OverallSuccess = $false
                }
            }
            
            # If the adapter failed to clean, update the overall success flag
            if (-not $currentAdapterSuccess) {
                $script:OverallSuccess = $false
            }
        }
        
        # Final Result
        if ($script:OverallSuccess) {
            Write-Log "Network cleanup routine finished successfully for all targets." -Level SUCCESS
        } else {
            Write-Log "Network cleanup routine finished with ERRORS. Check log file." -Level ERROR
        }

        # Return the boolean result
        return $script:OverallSuccess
    }
}

function Set-MOD-Network {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$FullScope,

        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    Write-Log "Set-MOD-Network" -Header

    # -- Scoped confirm suppression when -Force is used
    $prevConfirmPref = $ConfirmPreference
    if ($Force) { $ConfirmPreference = 'None' }
    try {
        # 1. Determine scope
        $CompareParams = @{ Silent = $true }
        if ($FullScope) {
            $scope = "Full Scope (All Adapters)"
            $CompareParams.InterfaceAlias = [string[]]@('OFFICE','FLOOR','MODULUS')
        } else {
            $scope = "Server-based Scope."
        }
        Write-Log "Configuration Scope: $scope" INFO

        # Compare live state against desired state to determine necessary changes
        $changesRequired = Compare-MOD-Network @CompareParams
        if (-not $changesRequired -or $changesRequired.Count -eq 0) {
            Write-Log "Network configuration already matches desired state. No changes required." SUCCESS
            return $true
        }

        Write-Log "$($changesRequired.Count) adapter(s) require configuration changes. Proceeding..." INFO

        # Retrieve the full desired configuration once for reference
        $desiredAdapters = Get-MOD-NetworkAdaptersConfig

        $overallSuccess = $true

        foreach ($change in $changesRequired) {
            $alias   = $change.InterfaceAlias
            $reasons = $change.Reasons

            # Look up the full desired config for this adapter
            $desiredConfig = $desiredAdapters | Where-Object { $_.InterfaceAlias -ceq $alias } | Select-Object -First 1
            if (-not $desiredConfig) {
                Write-Log "Error: Could not find desired configuration for alias '$alias'. Skipping." ERROR
                $overallSuccess = $false
                continue
            }

            Write-Log "Applying changes to adapter: $alias. Reasons: $($reasons -join ', ')" INFO
            $currentAdapterSuccess = $true

            # --- A. DHCP Configuration (If needed) ---
            if ($reasons -contains 'DHCP') {
                if ($desiredConfig.DhcpEnabled) {
                    Write-Log "  Configuring for DHCP (Enable IP and Reset DNS)..." INFO

                    if ($PSCmdlet.ShouldProcess("Adapter '$alias'", "Set IPv4 to DHCP and Reset DNS")) {
                        try {
                            $ipParams = @{
                                InterfaceAlias = $alias
                                Dhcp           = 'Enabled'
                                ErrorAction    = 'Stop'
                            }
                            Set-NetIPInterface @ipParams

                            $dnsResetParams = @{
                                InterfaceAlias        = $alias
                                ResetServerAddresses  = $true
                                ErrorAction           = 'Stop'
                            }
                            Set-DnsClientServerAddress @dnsResetParams

                            Write-Log "  DHCP enabled and DNS servers reset." SUCCESS
                        } catch {
                            Write-Log "  Failed to set DHCP: $($_.Exception.Message)" ERROR
                            $currentAdapterSuccess = $false
                        }
                    }
                } else {
                    Write-Log "  DHCP mismatch. Preparing for Static IP Configuration..." VERBOSE
                }
            }

            # --- B. Static IP/Gateway Configuration (If needed and DHCP is not desired) ---
            if (-not $desiredConfig.DhcpEnabled -and ($reasons -contains 'IP' -or $reasons -contains 'Gateway')) {
                Write-Log "  Configuring Static IP and Gateway..." INFO

                if ($PSCmdlet.ShouldProcess("Adapter '$alias'", "Set static IP/Gateway")) {
                    try {
                        # 1. Clean up existing IPs before adding the new one
                        $liveIPs = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
                        foreach ($liveIP in $liveIPs) {
                            if ($liveIP.IPAddress -ne '127.0.0.1') {
                                Write-Log "    Removing old IP: $($liveIP.IPAddress)." VERBOSE
                                $rmParams = @{
                                    InputObject = $liveIP
                                    ErrorAction = 'SilentlyContinue'
                                }
                                if ($Force) { $rmParams.Confirm = $false }  # <--- ✅ Added here
                                Remove-NetIPAddress @rmParams
                            }
                        }

                        # 2. Use Splatting for Conditional Gateway
                        $NewIPParams = @{
                            InterfaceAlias = $alias
                            IPAddress      = $desiredConfig.IPAddress
                            PrefixLength   = $desiredConfig.PrefixLength
                            ErrorAction    = 'Stop'
                        }

                        if ($desiredConfig.NextHop) {
                            $NewIPParams.DefaultGateway = $desiredConfig.NextHop
                            Write-Log "    ...including Default Gateway: $($desiredConfig.NextHop)" VERBOSE
                        }

                        New-NetIPAddress @NewIPParams | Out-Null
                        Write-Log "  Static IP/Gateway set successfully." SUCCESS
                    } catch {
                        Write-Log "  Failed to set Static IP/Gateway: $($_.Exception.Message)" ERROR
                        $currentAdapterSuccess = $false
                    }
                }
            }

            # --- C. DNS Server Configuration (If needed) ---
            if ($reasons -contains 'DNS') {
                $desiredDNSServers = $desiredConfig.DNSServer

                if ($desiredDNSServers -and $desiredDNSServers.Count -gt 0) {
                    Write-Log "  Setting static DNS servers: $($desiredDNSServers -join ', ')" INFO

                    if ($PSCmdlet.ShouldProcess("Adapter '$alias'", "Set static DNS servers")) {
                        try {
                            $dnsParams = @{
                                InterfaceAlias  = $alias
                                ServerAddresses = $desiredDNSServers
                                ErrorAction     = 'Stop'
                            }
                            Set-DnsClientServerAddress @dnsParams
                            Write-Log "  DNS servers set successfully." SUCCESS
                        } catch {
                            Write-Log "  Failed to set DNS servers: $($_.Exception.Message)" ERROR
                            $currentAdapterSuccess = $false
                        }
                    }
                } else {
                    Write-Log "  Resetting DNS servers to automatic (clearing static list)." VERBOSE

                    if ($PSCmdlet.ShouldProcess("Adapter '$alias'", "Reset DNS servers")) {
                        try {
                            $dnsParams = @{
                                InterfaceAlias       = $alias
                                ResetServerAddresses = $true
                                ErrorAction          = 'Stop'
                            }
                            Set-DnsClientServerAddress @dnsParams
                            Write-Log "  DNS servers reset successfully (cleared static list)." SUCCESS
                        } catch {
                            Write-Log "  Failed to reset DNS servers: $($_.Exception.Message)" ERROR
                            $currentAdapterSuccess = $false
                        }
                    }
                }
            }

            if (-not $currentAdapterSuccess) {
                $overallSuccess = $false
            }
        }

        # 3. Final Summary
        if ($overallSuccess) {
            Write-Log "Network configuration successfully applied to all required adapters." SUCCESS
        } else {
            Write-Log "Network configuration completed, but errors occurred during setup." ERROR
        }

        return $overallSuccess
    }
    finally {
        if ($Force) { $ConfirmPreference = $prevConfirmPref }
    }
}
#endregion

#region --- disk partitions
function Initialize-Disks {
    [CmdletBinding()]
    param(
        [switch]$AsResult,
        # Best practice: keep this OFF. If you must bounce, opt-in and we guard hard.
        [switch]$AllowBounceNonCritical
    )

    $allOk   = $true
    $changed = $false

    Write-Log "Initialize-Disks" -Header

    # Normalize any drive-letter-ish input to a single uppercase string or $null
    function _Norm-Letter([object]$x) {
        if ($null -eq $x) { return $null }
        $s = [string]$x
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        return $s.Substring(0,1).ToUpperInvariant()
    }

    # Validate that we have exactly one A–Z letter
    function _Is-ValidLetter([object]$x) {
        $L = _Norm-Letter $x
        return ($null -ne $L -and $L -cmatch '^[A-Z]$')
    }

    # Free a drive letter if it's in use (DVD or regular partition)
    function _Free-DriveLetter([string]$Letter) {
        $L = _Norm-Letter $Letter
        if (-not $L) { return $true } # nothing to do
        try {
            $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { (_Norm-Letter $_.DriveLetter) -eq $L }
            if (-not $vol) { return $true }

            if ($vol.DriveType -eq 'CD-ROM' -or $vol.DriveType -match 'CD') {
                # Use DiskPart to remove letter from optical drive
                $dp = @"
select volume $L
remove letter=$L
exit
"@
                $tmp = Join-Path $env:TEMP "dp_remove_$L.txt"
                $dp | Out-File -FilePath $tmp -Encoding ASCII
                Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$tmp`"" -Wait
                Remove-Item $tmp -ErrorAction SilentlyContinue
                return $true
            } else {
                try {
                    $part = Get-Partition -DriveLetter $L -ErrorAction Stop
                    if (_Is-ValidLetter $L) {
                        Remove-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath "$($L):" -ErrorAction Stop
                    }
                    return $true
                } catch {
                    $msg = $_.Exception.Message
                    if ($msg -match 'access path is not valid') {
                        Write-Host ("Access path {0}: not present; already unlettered." -f $L) -ForegroundColor DarkGray
                        return $true
                    }
                    Write-Host "Could not remove access path for $($L): $_" -ForegroundColor Red
                    return $false
                }
            }
        } catch {
            Write-Host "Failed freeing letter $($L): $_" -ForegroundColor Red
            return $false
        }
    }

    # -------------------------------
    # Mapping builder (same rules you had)
    # -------------------------------
    function _Build-Mapping {
        param([string]$ServerType)

        $mapping = @(
            @{ DiskNumber = 0; PartitionNumber = 1; DesiredLetter = $null }   # System Reserved
            @{ DiskNumber = 0; PartitionNumber = 3; DesiredLetter = $null }   # Recovery/Hidden
            @{ DiskNumber = 1; PartitionNumber = 1; DesiredLetter = "D" }     # Data partition
        )

        switch ($ServerType.ToUpper()) {
            "DB"  { $mapping += @(
                       @{ DiskNumber = 2; PartitionNumber = 1; DesiredLetter = "F" }
                       @{ DiskNumber = 3; PartitionNumber = 1; DesiredLetter = "G" }
                       @{ DiskNumber = 4; PartitionNumber = 1; DesiredLetter = "H" }
                       @{ DiskNumber = 5; PartitionNumber = 1; DesiredLetter = "S" }
                   ) }
            "1VM" { $mapping += @(
                       @{ DiskNumber = 2; PartitionNumber = 1; DesiredLetter = "F" }
                       @{ DiskNumber = 3; PartitionNumber = 1; DesiredLetter = "G" }
                       @{ DiskNumber = 4; PartitionNumber = 1; DesiredLetter = "H" }
                       @{ DiskNumber = 5; PartitionNumber = 1; DesiredLetter = "I" }
                   ) }
            "APP" { $mapping += @{ DiskNumber = 2; PartitionNumber = 1; DesiredLetter = "I" } }
            "FS"  { } # base mapping only
            default { throw ("Unknown server type: {0}" -f $ServerType) }
        }
        return ,$mapping
    }

    # -------------------------------
    # Preflight: compute a "plan" and early-exit if nothing to do
    # -------------------------------
    function _Compute-Plan {
        param([object[]]$Mapping)

        $reasons = New-Object System.Collections.Generic.List[string]

        # 1) Any disk offline or read-only?
        foreach ($d in (Get-Disk)) {
            if ($d.IsOffline)  { $reasons.Add(("Disk {0} is offline" -f $d.Number)) }
            if ($d.IsReadOnly) { $reasons.Add(("Disk {0} is read-only" -f $d.Number)) }
        }

        # 2) DVD letter not E (if any DVD)
        $dvd = Get-Volume -ErrorAction SilentlyContinue |
               Where-Object { $_.DriveType -eq 'CD-ROM' -or $_.DriveType -match 'CD' } |
               Select-Object -First 1
        if ($dvd) {
            $dvdLetter = _Norm-Letter $dvd.DriveLetter
            if ($dvdLetter -ne 'E') {
                $reasons.Add(("DVD is at {0}, expected E" -f ($dvdLetter ? $dvdLetter : '(none)')))
            }
        }

        # 3) Mapping mismatches
        foreach ($m in $Mapping) {
            try {
                $part = Get-Partition -DiskNumber $m.DiskNumber -PartitionNumber $m.PartitionNumber -ErrorAction Stop
            } catch {
                $reasons.Add(("Partition not found Disk {0} Part {1}" -f $m.DiskNumber, $m.PartitionNumber))
                continue
            }
            $desired = _Norm-Letter $m.DesiredLetter
            $current = _Norm-Letter $part.DriveLetter

            if ($null -eq $desired) {
                if (_Is-ValidLetter $current) {
                    $reasons.Add(("Disk {0} Part {1} should be unlettered (has {2})" -f $m.DiskNumber, $m.PartitionNumber, $current))
                }
            } else {
                if ($current -ne $desired) {
                    $reasons.Add(("Disk {0} Part {1} should be {2} (has {3})" -f $m.DiskNumber, $m.PartitionNumber, $desired, ($current ? $current : '(none)')))
                }
            }
        }

        [pscustomobject]@{
            Compliant = ($reasons.Count -eq 0)
            Reasons   = $reasons
        }
    }

    # Server type
    $serverType = $env:MODULUS_SERVER
    if (-not $serverType) {
        Write-Host "MODULUS_SERVER is not set. Exiting." -ForegroundColor Red
        if ($AsResult) { return [pscustomobject]@{ Success = $false; Changed = $false } }
        return $false
    }
    Write-Host ("Detected server type: {0}" -f $serverType) -ForegroundColor Cyan

    # Build mapping and preflight plan
    try {
        $mapping = _Build-Mapping -ServerType $serverType
    } catch {
        Write-Host $_ -ForegroundColor Red
        if ($AsResult) { return [pscustomobject]@{ Success = $false; Changed = $false } }
        return $false
    }

    $plan = _Compute-Plan -Mapping $mapping
    if ($plan.Compliant) {
        Write-Host "Already compliant — no changes needed. Skipping initialization." -ForegroundColor Green
        if ($AsResult) { return [pscustomobject]@{ Success = $true; Changed = $false } }
        return $true
    } else {

        Write-Host "====================================================================" -ForegroundColor Yellow
        Write-Host " Managing Disks Post-Sysprep – Assigning Letters by Disk & Partition" -ForegroundColor Yellow
        Write-Host "====================================================================" -ForegroundColor Yellow

        Write-Host "Changes required:" -ForegroundColor Yellow
        $plan.Reasons | ForEach-Object { Write-Host (" - {0}" -f $_) -ForegroundColor Yellow }
        write-host " "
    }

    # -------------------------------
    # Step 1: Bring disks online and clear read-only flags.
    # -------------------------------
    Write-Host "`n[Step 1] Bringing disks online and clearing read-only flags..."
    Get-Disk | ForEach-Object {
        try {
            if ($_.IsOffline) {
                Set-Disk -Number $_.Number -IsOffline $false -ErrorAction Stop
                Write-Host ("Disk {0} brought online." -f $_.Number) -ForegroundColor Cyan
                $changed = $true
            }
            if ($_.IsReadOnly) {
                Set-Disk -Number $_.Number -IsReadOnly $false -ErrorAction Stop
                Write-Host ("Cleared read-only on disk {0}." -f $_.Number) -ForegroundColor Cyan
                $changed = $true
            }
        } catch {
            Write-Host ("Error touching Disk {0}: {1}" -f $_.Number, $_) -ForegroundColor Red
            $allOk = $false
        }
    }

    # -------------------------------
    # Step 2: If DVD has D:, remove D: (using DiskPart by letter).
    # -------------------------------
    Write-Host "`n[Step 2] Releasing D: if it's on a DVD-ROM..."
    try {
        $dvdOnD = Get-Volume -ErrorAction SilentlyContinue |
                  Where-Object { (_Norm-Letter $_.DriveLetter) -eq 'D' -and ($_.DriveType -eq 'CD-ROM' -or $_.DriveType -match 'CD') }
        if ($dvdOnD) {
            Write-Host "DVD currently on D:. Removing letter D: from DVD..." -ForegroundColor Cyan
            if (-not (_Free-DriveLetter 'D')) { $allOk = $false } else { $changed = $true }
        } else {
            Write-Host "No DVD on D:. Nothing to release." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "DVD check failed: $_" -ForegroundColor Red
        $allOk = $false
    }

    # -------------------------------
    # Step 3: Disable automount via DiskPart (prevents churn while we assign).
    # -------------------------------
    Write-Host "`n[Step 3] Disabling automount to prevent auto-assignment..."
    try {
        $autoDisable = @"
automount disable
exit
"@
        $tempAutoDisable = "$env:TEMP\disable_automount.txt"
        $autoDisable | Out-File -FilePath $tempAutoDisable -Encoding ASCII
        Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$tempAutoDisable`"" -Wait
        Remove-Item $tempAutoDisable -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to disable automount: $_" -ForegroundColor Red
        $allOk = $false
    }

    # -------------------------------
    # Step 4: Force DVD to letter E (select by current letter if present).
    # -------------------------------
    Write-Host "`n[Step 4] Ensuring DVD is at E: ..."
    try {
        $dvd = Get-Volume -ErrorAction SilentlyContinue |
               Where-Object { $_.DriveType -eq 'CD-ROM' -or $_.DriveType -match 'CD' } |
               Select-Object -First 1
        if ($dvd) {
            $dvdLetter = _Norm-Letter $dvd.DriveLetter
            if ($dvdLetter -eq 'E') {
                Write-Host "DVD already at E:. Skipping." -ForegroundColor DarkGray
            } else {
                if (-not (_Free-DriveLetter 'E')) { $allOk = $false }
                $selectToken = ($dvdLetter) ? $dvdLetter : 0
                $dpAssignE = @"
select volume $selectToken
assign letter=E
exit
"@
                $tempE = "$env:TEMP\assign_E.txt"
                $dpAssignE | Out-File -FilePath $tempE -Encoding ASCII
                Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$tempE`"" -Wait
                Remove-Item $tempE -ErrorAction SilentlyContinue
                Write-Host "DVD set to E:." -ForegroundColor Green
                $changed = $true
            }
        } else {
            Write-Host "No DVD volume detected; skipping E: assignment." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to set DVD to E:: $_" -ForegroundColor Red
        $allOk = $false
    }

    # -------------------------------
    # Step 5: Show mapping (for visibility)
    # -------------------------------
    Write-Host "`nMapping by DiskNumber & PartitionNumber:" -ForegroundColor Magenta
    foreach ($m in $mapping) {
        $target = if ($m.DesiredLetter) { (_Norm-Letter $m.DesiredLetter) } else { "(no letter)" }
        Write-Host ("Disk {0}, Partition {1} → {2}" -f $m.DiskNumber, $m.PartitionNumber, $target)
    }

    # -------------------------------
    # Step 6: Assign letters (idempotent, with collision handling).
    # -------------------------------
    Write-Host "`nAssigning drive letters based on partition mapping..." -ForegroundColor Cyan
    foreach ($m in $mapping) {
        try {
            $part = Get-Partition -DiskNumber $m.DiskNumber -PartitionNumber $m.PartitionNumber -ErrorAction Stop

            $desired = _Norm-Letter $m.DesiredLetter
            $current = _Norm-Letter $part.DriveLetter

            if ($null -eq $desired) {
                # We want this partition unlettered
                if (_Is-ValidLetter $current) {
                    $ap = "$($current):"
                    Write-Host ("Removing letter {0} from Disk {1}, Partition {2}..." -f $current, $m.DiskNumber, $m.PartitionNumber) -ForegroundColor Cyan
                    try {
                        Remove-PartitionAccessPath -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $ap -ErrorAction Stop
                        $changed = $true
                    } catch {
                        $msg = $_.Exception.Message
                        if ($msg -match 'access path is not valid') {
                            Write-Host "Access path $ap not present; already unlettered." -ForegroundColor DarkGray
                        } else {
                            Write-Host ("Error removing {0} on Disk {1}, Part {2}: {3}" -f $ap, $m.DiskNumber, $m.PartitionNumber, $_) -ForegroundColor Red
                            $allOk = $false
                        }
                    }
                } else {
                    Write-Host "Partition already unlettered." -ForegroundColor DarkGray
                }
                continue
            }

            if ($current -and ($current -ieq $desired)) {
                Write-Host ("Disk {0}, Part {1} already has {2}. Skipping." -f $m.DiskNumber, $m.PartitionNumber, $desired) -ForegroundColor DarkGray
                continue
            }

            # Free the desired letter if someone else holds it (DVD or another partition)
            if (-not (_Free-DriveLetter $desired)) {
                $allOk = $false
                continue
            }

            Write-Host ("Assigning letter {0} to Disk {1}, Partition {2}..." -f $desired, $m.DiskNumber, $m.PartitionNumber) -ForegroundColor Cyan
            Set-Partition -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -NewDriveLetter $desired -ErrorAction Stop
            Write-Host ("Successfully assigned letter {0}." -f $desired) -ForegroundColor Green
            $changed = $true
        }
        catch {
            Write-Host ("Error processing Disk {0}, Partition {1}: {2}" -f $m.DiskNumber, $m.PartitionNumber, $_) -ForegroundColor Red
            $allOk = $false
        }
    }

    # -------------------------------
    # Step 7: Re-enable automount via DiskPart.
    # -------------------------------
    Write-Host "`nRe-enabling automount..." -ForegroundColor Cyan
    try {
        $autoEnable = @"
automount enable
exit
"@
        $tempAutoEnable = "$env:TEMP\enable_automount.txt"
        $autoEnable | Out-File -FilePath $tempAutoEnable -Encoding ASCII
        Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$tempAutoEnable`"" -Wait
        Remove-Item $tempAutoEnable -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Failed to enable automount: $_" -ForegroundColor Red
        $allOk = $false
    }

    # -------------------------------
    # Step 8: BEST PRACTICE REFRESH (no bouncing by default)
    # -------------------------------
    Write-Host "`nRefreshing storage view (no bounce)..." -ForegroundColor Cyan
    try { Update-HostStorageCache -ErrorAction SilentlyContinue } catch {
        Write-Host "Update-HostStorageCache failed (non-fatal): $_" -ForegroundColor Yellow
    }
    try {
        $dpRescan = @"
rescan
exit
"@
        $tmpRescan = Join-Path $env:TEMP "dp_rescan.txt"
        $dpRescan | Out-File -FilePath $tmpRescan -Encoding ASCII
        Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$tmpRescan`"" -Wait
        Remove-Item $tmpRescan -ErrorAction SilentlyContinue
    } catch {
        Write-Host "DiskPart rescan failed (non-fatal): $_" -ForegroundColor Yellow
    }

    # Optional: guarded bounce only on non-critical data disks
    if ($AllowBounceNonCritical) {
        Write-Host "`n[Optional] Guarded bounce of non-critical data disks..." -ForegroundColor DarkCyan

        $unsafeDiskNumbers = @()
        try {
            $unsafeDiskNumbers = (Get-Partition | Where-Object { $_.IsBoot -or $_.IsSystem } |
                                 Select-Object -ExpandProperty DiskNumber -Unique)
        } catch {}

        $unsafeLetters = @()
        try {
            $unsafeLetters = (Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue).Name |
                             ForEach-Object { ($_ -split ':')[0].Trim().ToUpperInvariant() }
        } catch {}

        Get-Disk | ForEach-Object {
            try {
                if ($unsafeDiskNumbers -contains $_.Number) { return }
                if ($_.PartitionStyle -eq 'RAW')             { return }
                if ($_.Number -eq 0)                         { return }

                $letters = (Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue |
                            Where-Object DriveLetter |
                            Select-Object -ExpandProperty DriveLetter -Unique |
                            ForEach-Object { _Norm-Letter $_ })
                if ($letters | Where-Object { $unsafeLetters -contains $_ }) { return }

                Write-Host ("Lightly bouncing Disk {0}..." -f $_.Number) -ForegroundColor DarkCyan
                Set-Disk -Number $_.Number -IsOffline $true  -ErrorAction Stop
                Start-Sleep -Seconds 2
                Set-Disk -Number $_.Number -IsOffline $false -ErrorAction Stop
                $changed = $true
            } catch {
                Write-Host ("Skipping bounce on Disk {0}: {1}" -f $_.Number, $_) -ForegroundColor Yellow
            }
        }
    }

    Write-Host "`nFinal drive-letter assignments:" -ForegroundColor Magenta
    Get-Volume | Format-Table DriveLetter, FileSystemLabel, SizeRemaining, DriveType -AutoSize

    if ($AsResult) { return [pscustomobject]@{ Success = $allOk; Changed = $changed } }
    return $allOk
}
#endregion

#region --- crypto handlers
function Protect-Password {
    <#
      Legacy-compatible encryption.
      Input:  (positional string) OR (-Credential object)
      Output: Base64(ciphertext) — NO IV prefix
    #>
    [CmdletBinding(DefaultParameterSetName='PlainTextSet')]
    param(
        # SET 1: Accepts positional string input (default)
        [Parameter(Mandatory=$true, Position=0, ParameterSetName='PlainTextSet')]
        [string]$PlainText,

        # SET 2: Requires the named parameter for credential object
        [Parameter(Mandatory=$true, ParameterSetName='CredentialSet')]
        [System.Management.Automation.PSCredential]$Credential
    )

    try {
        # 1. Determine the actual string input based on the parameter set
        $inputString = switch ($PSCmdlet.ParameterSetName) {
            'PlainTextSet'  { $PlainText }
            'CredentialSet' { $Credential.GetNetworkCredential().Password }
        }
        
        # 2. Proceed with the encryption using the determined string
        $ctx = Get-LegacyCryptoContext
        # Note: We use the determined $inputString here
        $inputBytes = [Text.Encoding]::ASCII.GetBytes($inputString) 
        
        # ... (rest of your encryption logic remains the same) ...
        $algo = New-Object System.Security.Cryptography.RijndaelManaged
        try {
            $algo.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $algo.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $algo.KeySize = 128; $algo.BlockSize = 128
            $algo.Key = $ctx.Key; $algo.IV = $ctx.IV

            $encryptor = $algo.CreateEncryptor()
            $ms = New-Object IO.MemoryStream
            try {
                $cs = New-Object System.Security.Cryptography.CryptoStream($ms, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
                try { $cs.Write($inputBytes, 0, $inputBytes.Length); $cs.FlushFinalBlock() } finally { $cs.Dispose() }
                $cipher = $ms.ToArray()
            } finally { $ms.Dispose() }
        } finally { $algo.Dispose() }

        [Convert]::ToBase64String($cipher)
    }
    catch {
        Write-Error "Protect-Password failed: $($_.Exception.Message)"
        throw
    }
}

<#hide
function Unprotect-Password {
    # Legacy-compatible decryption (for local validation/testing).
    # Input:  Base64(ciphertext), NO IV prefix expected.
    # Output: ASCII string
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CipherBase64)

    try {
        $ctx = Get-LegacyCryptoContext
        $cipher = [Convert]::FromBase64String($CipherBase64)

        $algo = New-Object System.Security.Cryptography.RijndaelManaged
        try {
            $algo.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $algo.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $algo.KeySize = 128; $algo.BlockSize = 128
            $algo.Key = $ctx.Key; $algo.IV = $ctx.IV

            $decryptor = $algo.CreateDecryptor()
            $ms = New-Object IO.MemoryStream($cipher, $false)
            try {
                $cs = New-Object System.Security.Cryptography.CryptoStream($ms, $decryptor, [System.Security.Cryptography.CryptoStreamMode]::Read)
                try {
                    $buf = New-Object byte[] 4096
                    $out = New-Object IO.MemoryStream
                    while (($read = $cs.Read($buf,0,$buf.Length)) -gt 0) { $out.Write($buf,0,$read) }
                    $pt = [Text.Encoding]::ASCII.GetString($out.ToArray())
                } finally { $cs.Dispose() }
            } finally { $ms.Dispose() }
        } finally { $algo.Dispose() }

        Write-Log "Password unprotected (legacy AES-128-CBC)" DEBUG
        $pt
    }
    catch {
        Write-Log "Unprotect-Password failed: $($_.Exception.Message)" ERROR
        throw
    }
}
#>

function Reset-CryptoModuleFunctionality {
    <#
      Removes CN=modulus-toolkit certificates from LocalMachine\My and CurrentUser\My,
      clears in-session caches, and (optionally) deletes a given PFX file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Subject = 'CN=modulus-toolkit',
        [string]$PfxPath,
        [switch]$DeletePfx
    )

    Write-Log "Resetting crypto materials…" INFO

    foreach ($store in 'Cert:\LocalMachine\My','Cert:\CurrentUser\My') {
        try {
            $certs = Get-ChildItem $store -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $Subject }
            if ($certs) {
                Write-Log "Removing $($certs.Count) certificate(s) from $store" INFO
                foreach ($c in $certs) { Remove-Item -LiteralPath "$store\$($c.Thumbprint)" -Force }
            } else {
                Write-Log "No matching certificates in $store" DEBUG
            }
        } catch {
            Write-Log "Could not enumerate/remove from $($store): $($_.Exception.Message)" WARNING
        }
    }

    if (Get-Variable -Name ModuleCryptoCache -Scope Script -ErrorAction SilentlyContinue) {
        Remove-Variable -Name ModuleCryptoCache -Scope Script -Force -ErrorAction SilentlyContinue
        Write-Log "Cleared script:ModuleCryptoCache" DEBUG
    }
    if (Get-Variable -Name LegacyCryptoCache -Scope Script -ErrorAction SilentlyContinue) {
        Remove-Variable -Name LegacyCryptoCache -Scope Script -Force -ErrorAction SilentlyContinue
        Write-Log "Cleared script:LegacyCryptoCache" DEBUG
    }

    if ($DeletePfx -and $PfxPath -and (Test-Path -LiteralPath $PfxPath -PathType Leaf)) {
        Remove-Item -LiteralPath $PfxPath -Force
        Write-Log "Deleted PFX: $PfxPath" INFO
    }

    Write-Log "Reset complete" INFO
}
#endregion

#region --- toolkit cleanup according to manifest.json mapping
function Invoke-ToolkitCleanup {
    <#
    .SYNOPSIS
        Enforce the declared state from manifest.json by removing undeclared files and (optionally) undeclared directories.
    .DESCRIPTION
        - Removes only what is NOT listed or pattern-allowed.
        - Honors exclude/protect/patterns/case.
        - Safe: supports -WhatIf, -Confirm, and optional recycle-bin deletion.
        - Logs via Write-Log (INFO, DEBUG, WARNING, ERROR).
        - Optional: -RemoveEmptyDirs (prune empty, undeclared dirs), -RemoveUndeclaredDirs (recursively remove undeclared dirs containing no allowed files).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Root,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ManifestPath,

        [switch]$IncludeHiddenSystem,
        [switch]$RemoveEmptyDirs,
        [switch]$RemoveUndeclaredDirs,
        [switch]$Recycle
    )

    # ----------------------------------------------------------------------
    # Helpers
    # ----------------------------------------------------------------------
    function Normalize-RelPath([string]$base, [string]$full) {
        try {
            $b = (Resolve-Path -LiteralPath $base -ErrorAction Stop).Path
            $f = (Resolve-Path -LiteralPath $full -ErrorAction Stop).Path
            if (-not $b.EndsWith('\')) { $b += '\' }  # ensure directory semantics
            $uriBase = [System.Uri]$b
            $uriFull = [System.Uri]$f
            $rel = $uriBase.MakeRelativeUri($uriFull).ToString() -replace '/','\'
            return $rel.TrimStart('\')
        } catch {
            Write-Log "Failed to normalize path '$full': $($_.Exception.Message)" DEBUG
            return $null
        }
    }

    function New-Set([string[]]$items,[bool]$insensitive) {
        $cmp = if ($insensitive) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
        $set = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
        foreach ($i in $items) { if ($i -and ($i.Trim() -ne '')) { [void]$set.Add($i) } }
        return $set
    }

    # ----------------------------------------------------------------------
    # Manifest loading
    # ----------------------------------------------------------------------
    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        Write-Log "Loaded manifest from $ManifestPath" INFO
    } catch {
        Write-Log "Failed to read manifest: $($_.Exception.Message)" ERROR
        return
    }

    $insensitive = ($manifest.case -eq 'insensitive')

    $allowFiles  = New-Set ($manifest.files) $insensitive
    $allowDirs   = New-Set ($manifest.dirs)  $insensitive
    $protectList = @($manifest.protect  | Where-Object { $_ -and $_.Trim() -ne '' })
    $patterns    = @($manifest.patterns | Where-Object { $_ -and $_.Trim() -ne '' })
    $excludes    = @($manifest.exclude  | Where-Object { $_ -and $_.Trim() -ne '' })

    $rootReal = (Resolve-Path -LiteralPath $Root).Path
    Write-Log "Scanning root: $rootReal" INFO

    # Predicates -----------------------------------------------------------
    function IsExcluded([string]$rel) {
        if (-not $rel) { return $false }
        foreach ($x in $excludes) { if ($rel -like $x) { return $true } }
        return $false
    }
    function IsAllowedByPattern([string]$rel) {
        if (-not $rel) { return $false }
        foreach ($p in $patterns) { if ($rel -like $p) { return $true } }
        return $false
    }
    function IsProtected([string]$rel) {
        if (-not $rel) { return $false }
        foreach ($p in $protectList) { if ($rel -like $p) { return $true } }
        return $false
    }

    # ----------------------------------------------------------------------
    # Scan files
    # ----------------------------------------------------------------------
    $scanParams = @{
        LiteralPath = $rootReal
        Recurse     = $true
        Force       = $IncludeHiddenSystem
        ErrorAction = 'Stop'
    }

    Write-Log "Enumerating files..." DEBUG
    $currentFiles = Get-ChildItem @scanParams -File |
        ForEach-Object { Normalize-RelPath $rootReal $_.FullName } |
        Where-Object { $_ -and -not (IsExcluded $_) }

    $cmp = if ($insensitive) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $currentSet = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
    foreach ($rel in $currentFiles) { [void]$currentSet.Add($rel) }

    Write-Log "Scanned $($currentSet.Count) files under $Root" INFO

    # ----------------------------------------------------------------------
    # Compute extras (only deletions matter)
    # ----------------------------------------------------------------------
    $extras = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $currentSet) {
        if (-not $allowFiles.Contains($rel) -and -not (IsAllowedByPattern $rel)) {
            if (-not (IsProtected $rel)) { $extras.Add($rel) | Out-Null }
        }
    }

    if ($extras.Count -eq 0) {
        Write-Log "No undeclared files detected." INFO
    } else {
        Write-Log "Found $($extras.Count) undeclared file(s) for removal." WARNING
        foreach ($rel in ($extras | Sort-Object)) {
            $full = Join-Path -Path $rootReal -ChildPath $rel
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                if ($PSCmdlet.ShouldProcess($full, "Remove undeclared file")) {
                    try {
                        Write-Log "Removing undeclared file: $rel" WARNING
                        if ($Recycle) {
                            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
                            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($full,'OnlyErrorDialogs','SendToRecycleBin')
                        } else {
                            Remove-Item -LiteralPath $full -Force
                        }
                    } catch {
                        Write-Log "Failed to delete '$rel': $($_.Exception.Message)" ERROR
                    }
                }
            }
        }
    }

    # ----------------------------------------------------------------------
    # Optionally remove empty dirs (simple prune)
    # ----------------------------------------------------------------------
    if ($RemoveEmptyDirs) {
        Write-Log "Checking for empty undeclared directories..." DEBUG
        $dirs = Get-ChildItem -LiteralPath $rootReal -Recurse -Directory -Force:$IncludeHiddenSystem |
                Sort-Object FullName -Descending
        foreach ($d in $dirs) {
            $rel = Normalize-RelPath $rootReal $d.FullName
            if (-not $rel) { continue }
            if (IsExcluded $rel) { continue }
            if ($allowDirs.Contains($rel)) { continue }
            if (IsProtected $rel) { continue }
            $hasContent = Get-ChildItem -LiteralPath $d.FullName -Force | Select-Object -First 1
            if (-not $hasContent) {
                if ($PSCmdlet.ShouldProcess($d.FullName, "Remove empty directory")) {
                    try {
                        Write-Log "Removing empty directory: $rel" INFO
                        Remove-Item -LiteralPath $d.FullName -Force -Recurse
                    } catch {
                        Write-Log "Failed to remove directory '$rel': $($_.Exception.Message)" ERROR
                    }
                }
            }
        }
    }

    # ----------------------------------------------------------------------
    # Optionally remove undeclared directories (recursive, safe)
    # ----------------------------------------------------------------------
    if ($RemoveUndeclaredDirs) {
        Write-Log "Evaluating undeclared directories for recursive removal..." INFO

        $allDirs = Get-ChildItem -LiteralPath $rootReal -Recurse -Directory -Force:$IncludeHiddenSystem |
                   Sort-Object FullName -Descending  # deepest first

        foreach ($d in $allDirs) {
            $rel = Normalize-RelPath $rootReal $d.FullName
            if (-not $rel) { continue }
            if (IsExcluded $rel) { continue }
            if ($allowDirs.Contains($rel)) { continue }
            if (IsProtected $rel) { continue }

            # Does this directory (recursively) contain any declared or pattern-allowed file?
            $hasAllowedContent = $false
            Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force:$IncludeHiddenSystem | ForEach-Object {
                $childRel = Normalize-RelPath $rootReal $_.FullName
                if ($childRel) {
                    if ($allowFiles.Contains($childRel) -or (IsAllowedByPattern $childRel)) {
                        $hasAllowedContent = $true
                        break
                    }
                }
            }

            if (-not $hasAllowedContent) {
                if ($PSCmdlet.ShouldProcess($d.FullName, "Remove undeclared directory (recursive)")) {
                    try {
                        Write-Log "Removing undeclared directory: $rel" WARNING
                        Remove-Item -LiteralPath $d.FullName -Force -Recurse
                    } catch {
                        Write-Log "Failed to remove directory '$rel': $($_.Exception.Message)" ERROR
                    }
                }
            } else {
                Write-Log "Keeping directory (contains allowed content): $rel" DEBUG
            }
        }
    }

    # ----------------------------------------------------------------------
    # Summary
    # ----------------------------------------------------------------------
    Write-Log "Cleanup completed. Deleted $($extras.Count) files." INFO
    [pscustomobject]@{
        Root                  = $rootReal
        Manifest              = (Resolve-Path -LiteralPath $ManifestPath).Path
        CaseInsensitive       = $insensitive
        FilesScanned          = $currentSet.Count
        ExtrasDeleted         = $extras.Count
        RemoveEmptyDirs       = [bool]$RemoveEmptyDirs
        RemoveUndeclaredDirs  = [bool]$RemoveUndeclaredDirs
        Recycle               = [bool]$Recycle
    }
}

function Test-ToolkitCleanupPlan {
    <#
    .SYNOPSIS
        Dry-run analyzer that lists undeclared files and undeclared dirs (recursive) plus empty dir prune candidates.
    .DESCRIPTION
        - Read-only preview of what Invoke-ToolkitCleanup would act on.
        - Computes:
          * ExtrasToDelete (files)
          * CandidatesForUndeclaredDirRemoval (recursive, safe: no allowed files inside)
          * CandidatesForEmptyDirPrune (strictly empty, undeclared)
        - Logs via Write-Log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Root,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ManifestPath,

        [switch]$IncludeHiddenSystem
    )

    Write-Log "Testing cleanup plan for $Root" INFO
    try {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "Failed to parse manifest: $($_.Exception.Message)" ERROR
        return
    }

    $insensitive = ($manifest.case -eq 'insensitive')
    $cmp = if ($insensitive) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    $allowFiles  = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
    foreach ($f in $manifest.files) { if ($f) { [void]$allowFiles.Add($f) } }
    $allowDirs   = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
    foreach ($d in $manifest.dirs)  { if ($d) { [void]$allowDirs.Add($d) } }

    $protectList = @($manifest.protect  | Where-Object { $_ -and $_.Trim() -ne '' })
    $patterns    = @($manifest.patterns | Where-Object { $_ -and $_.Trim() -ne '' })
    $excludes    = @($manifest.exclude  | Where-Object { $_ -and $_.Trim() -ne '' })

    function Normalize-RelPath([string]$base, [string]$full) {
        try {
            $b = (Resolve-Path -LiteralPath $base -ErrorAction Stop).Path
            $f = (Resolve-Path -LiteralPath $full -ErrorAction Stop).Path
            if (-not $b.EndsWith('\')) { $b += '\' }
            $uriBase = [System.Uri]$b
            $uriFull = [System.Uri]$f
            $rel = $uriBase.MakeRelativeUri($uriFull).ToString() -replace '/','\'
            return $rel.TrimStart('\')
        } catch { return $null }
    }
    function IsExcluded([string]$rel) { if (-not $rel) { return $false }; foreach ($x in $excludes) { if ($rel -like $x) { return $true } }; $false }
    function IsAllowedByPattern([string]$rel) { if (-not $rel) { return $false }; foreach ($p in $patterns) { if ($rel -like $p) { return $true } }; $false }
    function IsProtected([string]$rel) { if (-not $rel) { return $false }; foreach ($p in $protectList) { if ($rel -like $p) { return $true } }; $false }

    $rootReal = (Resolve-Path -LiteralPath $Root).Path

    # Files — extras
    $files = Get-ChildItem -LiteralPath $rootReal -Recurse -File -Force:$IncludeHiddenSystem |
             ForEach-Object { Normalize-RelPath $rootReal $_.FullName } |
             Where-Object { $_ -and -not (IsExcluded $_) }

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ($cmp)
    foreach ($rel in $files) { [void]$set.Add($rel) }

    $extras = @()
    foreach ($rel in $set) {
        if (-not $allowFiles.Contains($rel) -and -not (IsAllowedByPattern $rel) -and -not (IsProtected $rel)) {
            $extras += $rel
        }
    }

    # Dirs — empty prune and undeclared recursive removal candidates
    $pruneEmpty = @()
    $undeclaredDirs = @()
    $dirs = Get-ChildItem -LiteralPath $rootReal -Recurse -Directory -Force:$IncludeHiddenSystem |
            Sort-Object FullName -Descending

    foreach ($d in $dirs) {
        $rel = Normalize-RelPath $rootReal $d.FullName
        if (-not $rel) { continue }
        if (IsExcluded $rel) { continue }
        if ($allowDirs.Contains($rel)) { continue }
        if (IsProtected $rel) { continue }

        # empty prune candidate?
        $hasContent = Get-ChildItem -LiteralPath $d.FullName -Force | Select-Object -First 1
        if (-not $hasContent) { $pruneEmpty += $rel }

        # undeclared dir removal candidate? (no declared or pattern-allowed files anywhere inside)
        $hasAllowedContent = $false
        Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force:$IncludeHiddenSystem | ForEach-Object {
            $childRel = Normalize-RelPath $rootReal $_.FullName
            if ($childRel) {
                if ($allowFiles.Contains($childRel) -or (IsAllowedByPattern $childRel)) {
                    $hasAllowedContent = $true
                    break
                }
            }
        }
        if (-not $hasAllowedContent) { $undeclaredDirs += $rel }
    }

    Write-Log "Plan analysis complete. $($extras.Count) undeclared files, $($undeclaredDirs.Count) undeclared dirs (recursive), $($pruneEmpty.Count) empty dirs." INFO
    [pscustomobject]@{
        Root                              = $rootReal
        Manifest                          = (Resolve-Path -LiteralPath $ManifestPath).Path
        CaseInsensitive                   = $insensitive
        ExtrasToDelete                    = ($extras | Sort-Object)
        CandidatesForUndeclaredDirRemoval = ($undeclaredDirs | Sort-Object)
        CandidatesForEmptyDirPrune        = ($pruneEmpty | Sort-Object)
        ExtrasCount                       = $extras.Count
        UndeclaredDirCount                = $undeclaredDirs.Count
        EmptyDirPruneCount                = $pruneEmpty.Count
    }
}

function Reset-ToolkitState {
    $ModuleRoot = Get-ModuleRoot "modulus-toolkit"
    $ManifestPath   = Join-Path -Path $ModuleRoot -ChildPath 'config\manifest.json'
    Invoke-ToolkitCleanup -Root $moduleRoot `
        -ManifestPath $ManifestPath `
        -RemoveUndeclaredDirs
}
#endregion

#region --- log-level admin
function Set-MOD-ServiceLogLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$NewLevel
    )

    $servicesMapping = Get-ServiceMapping
    $targetService = $servicesMapping | Where-Object { $_.serviceName -eq $ServiceName }
    
    if (-not $targetService) {
        Write-Error "Service '$ServiceName' not found in mapping."
        return
    }

    if (-not $targetService.configFiles -or $targetService.configFiles.Count -eq 0) {
        Write-Error "No config files defined for service '$ServiceName'."
        return
    }

    foreach ($cfg in $targetService.configFiles) {
        $type = $cfg.type
        if ($cfg.logAppenders -and $cfg.logAppenders.Count -gt 0) {
            foreach ($appender in $cfg.logAppenders) {
                if ($type -eq "json") {
                    $loggingKey = $appender.jsonKeyPath
                }
                else {
                    $loggingKey = $appender.loggingXPath
                }
                try {
                    Set-LoggingLevelInConfig -ConfigFilePath $cfg.path -LoggingKey $loggingKey -NewLevel $NewLevel -Type $type
                    Write-Verbose "Updated service '$ServiceName' config '$($cfg.path)' (Appender: $($appender.name)) to level '$NewLevel'."
                }
                catch {
                    Write-Warning "Failed to update service '$ServiceName' config '$($cfg.path)' (Appender: $($appender.name)): $_"
                }
            }
        }
        else {
            Write-Verbose "No log appenders defined for service '$ServiceName' in config '$($cfg.path)'."
        }
    }
}

function Set-MOD-AppenderLogLevel {
    <#
    .SYNOPSIS
      Sets the logging level for a specific appender of a given service.
    
    .DESCRIPTION
      This function loads the JSON mapping, locates the specified service,
      and then searches through all of its config files for the given appender name.
      When a match is found, it updates that appender’s logging level (using the
      appropriate XML or JSON helper function) to the supplied value.
    
    .PARAMETER ServiceName
      The service name (as defined in the JSON mapping) to update.
    
    .PARAMETER AppenderName
      The name of the log appender to target.
    
    .PARAMETER NewLevel
      The new logging level to set (e.g. "ERROR", "DEBUG", etc.).
    
    .EXAMPLE
      Set-SpecificAppenderLogLevel -ServiceName "GalaxisAuthenticationService" -AppenderName "DefaultAppender" -NewLevel "ERROR"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [Parameter(Mandatory)]
        [string]$AppenderName,
        [Parameter(Mandatory)]
        [string]$NewLevel
    )

    $servicesMapping = Get-ServiceMapping
    $targetService = $servicesMapping | Where-Object { $_.serviceName -eq $ServiceName }
    
    if (-not $targetService) {
        Write-Error "Service '$ServiceName' not found in mapping."
        return
    }
    if (-not $targetService.configFiles -or $targetService.configFiles.Count -eq 0) {
        Write-Error "No config files defined for service '$ServiceName'."
        return
    }

    $found = $false
    foreach ($cfg in $targetService.configFiles) {
        $type = $cfg.type
        if ($cfg.logAppenders -and $cfg.logAppenders.Count -gt 0) {
            foreach ($appender in $cfg.logAppenders) {
                if ($appender.name -eq $AppenderName) {
                    $found = $true
                    if ($type -eq "json") {
                        $loggingKey = $appender.jsonKeyPath
                    }
                    else {
                        $loggingKey = $appender.loggingXPath
                    }
                    try {
                        Set-LoggingLevelInConfig -ConfigFilePath $cfg.path -LoggingKey $loggingKey -NewLevel $NewLevel -Type $type
                        Write-Verbose "Updated service '$ServiceName' config '$($cfg.path)' (Appender: $AppenderName) to level '$NewLevel'."
                    }
                    catch {
                        Write-Warning "Failed to update service '$ServiceName' config '$($cfg.path)' (Appender: $AppenderName): $_"
                    }
                }
            }
        }
    }
    if (-not $found) {
        Write-Error "Appender '$AppenderName' not found for service '$ServiceName'."
    }
}

function Set-MOD-AllDefaultLogLevels {
    <#
    .SYNOPSIS
      Sets each service's log level to its default value as defined in the JSON mapping.
    
    .DESCRIPTION
      This function loads the JSON mapping file (via Load-ServiceMapping) and iterates over every service,
      then for each configuration file and each log appender defined in the mapping, it reads the defaultLevel
      property and updates the configuration file accordingly using the appropriate XML or JSON helper function.
    
    .EXAMPLE
      Set-AllDefaultLogLevels
    #>
    [CmdletBinding()]
    param()

    $servicesMapping = Get-ServiceMapping

    foreach ($svc in $servicesMapping) {
        if (-not $svc.configFiles -or $svc.configFiles.Count -eq 0) {
            Write-Verbose "No config files defined for service '$($svc.serviceName)'."
            continue
        }
        foreach ($cfg in $svc.configFiles) {
            $type = $cfg.type
            if ($cfg.logAppenders -and $cfg.logAppenders.Count -gt 0) {
                foreach ($appender in $cfg.logAppenders) {
                    $defaultLevel = $appender.defaultLevel
                    if (-not $defaultLevel) {
                        Write-Verbose "No default level defined for service '$($svc.serviceName)' appender '$($appender.name)'."
                        continue
                    }
                    
                    if ($type -eq "json") {
                        $loggingKey = $appender.jsonKeyPath
                    }
                    else {
                        $loggingKey = $appender.loggingXPath
                    }
                    
                    try {
                        Set-LoggingLevelInConfig -ConfigFilePath $cfg.path -LoggingKey $loggingKey -NewLevel $defaultLevel -Type $type
                        Write-Verbose "Set default level for service '$($svc.serviceName)' config '$($cfg.path)' (Appender: $($appender.name)) to '$defaultLevel'."
                    }
                    catch {
                        Write-Warning "Failed to set default level for service '$($svc.serviceName)' config '$($cfg.path)' (Appender: $($appender.name)): $_"
                    }
                }
            }
            else {
                Write-Verbose "No log appenders defined for service '$($svc.serviceName)' in config '$($cfg.path)'."
            }
        }
    }
}
#endregion

#Export-ModuleMember -Function * -Alias * -Variable *