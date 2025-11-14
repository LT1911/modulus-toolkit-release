#tlukas, 07.10.2024

#write-host "Loading 5-devops-info.psm1!" -ForegroundColor Green

#region --- toolkit-related cleanup functions
function Clear-PrepDir {
	Write-Log "Clear-PrepDir" -Header
	$prepDir    = Get-PrepPath
    Get-ChildItem $prepDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
	Write-Log "Cleared the toolkits staging area, the prep directory: $prepDir" DEBUG
	Write-Log "Clear-PrepDir completed!" -Level INFO
}

function Clear-ToolkitLogs {
	Write-Log "Clear-ToolkitLogs" -Header
	$logs    = Get-LogsPath
    Get-ChildItem $logs | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
	Write-Log "Cleared the toolkits logs directory: $logs" DEBUG
	Write-Log "Clear-ToolkitLogs completed!" -Level INFO
}
#endregion

#region --- check for locked files in D:\Galaxis and in sourcesDir
function Test-UnblockMoTW {
    <#
    .SYNOPSIS
      Scan folders for Mark-of-the-Web (Zone.Identifier) and (optionally) unblock interactively.

    .DESCRIPTION
      Looks for DLL/EXE/CONFIG (customizable via -Include) that have a Zone.Identifier ADS.
      If none are blocked, exits quietly (returns $null).
      If blocked files are found, it lists them and prompts to unblock (Y/N/Yes to All/No to All).
      Supports -WhatIf / -Confirm and returns details for any blocked files it found.

    .PARAMETER Path
      One or more folders to scan.

    .PARAMETER Include
      File patterns to check. Default: *.dll, *.exe, *.config

    .PARAMETER Recurse
      Recurse into subdirectories.

    .EXAMPLE
      Test-UnblockMoTW -Path 'D:\Galaxis\Program\bin\AuthenticationService','D:\Galaxis\Program\bin\SlotMachineServer\Current' -Recurse

    .EXAMPLE
      Test-UnblockMoTW -Path 'D:\Galaxis\Program\bin\AuthenticationService' -Include *.dll,*.exe -Recurse -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [string[]] $Include = @('*.dll','*.exe','*.config'),

        [switch] $Recurse
    )

    begin {
        $blockedFound = @()
    }

    process {
        foreach ($p in $Path) {
            if (-not (Test-Path -LiteralPath $p -PathType Container)) {
                Write-Warning "Path not found or not a directory: $p"
                continue
            }

            # Gather candidate files
            $files = Get-ChildItem -LiteralPath $p -File -Include $Include -Recurse:$Recurse -ErrorAction SilentlyContinue

            foreach ($f in $files) {
                # If a Zone.Identifier ADS exists, this file is "blocked"
                $ads = Get-Item -LiteralPath $f.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
                if ($ads) {
                    $blockedFound += [pscustomobject]@{
                        Path   = $f.FullName
                        Length = $f.Length
                        LastWriteTime = $f.LastWriteTime
                    }
                }
            }
        }
    }

    end {
        if (-not $blockedFound -or $blockedFound.Count -eq 0) {
            # Nothing blocked → quiet success
            return
        }

        Write-Host "Blocked files detected (Mark-of-the-Web):" -ForegroundColor Yellow
        $blockedFound | Sort-Object Path | Format-Table -AutoSize

        $yesToAll = $false
        $noToAll  = $false

        foreach ($item in ($blockedFound | Sort-Object Path)) {
            if ($noToAll) { break }

            $target = $item.Path
            $action = "Unblock"
            $caption = "Remove Mark-of-the-Web (Zone.Identifier)"

            $proceed = $yesToAll -or $PSCmdlet.ShouldContinue(
                "Unblock:`n$target",
                $caption,
                $true,
                [ref]$yesToAll,
                [ref]$noToAll
            )

            if ($proceed) {
                if ($PSCmdlet.ShouldProcess($target, $action)) {
                    try {
                        Unblock-File -LiteralPath $target -ErrorAction Stop
                    } catch {
                        Write-Warning "Failed to unblock: $target - $($_.Exception.Message)"
                    }
                }
            }
        }

        # Return the set that was originally blocked (useful for logging/pipelines)
        $blockedFound
    }
}
#endregion

#Export-ModuleMember -Function * -Alias * -Variable *