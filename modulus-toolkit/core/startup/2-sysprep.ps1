if ($PSVersionTable.PSVersion.Major -lt 7) {
    & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoExit -Command {
        Write-Host "Started PowerShell 7 session" -ForegroundColor Green
        Start-MOD-Sysprep
    }
} else {
	Start-MOD-Sysprep
}