<#
.SYNOPSIS
    Start / stop the local harness server.

.DESCRIPTION
    Serves the repo root over HTTP so the page runs from a real origin.
    Opening index.html via file:// restricts sessionStorage and changes how
    injected scripts behave, which defeats the point of the harness.

    The server is started detached so the terminal stays usable and `stop`
    has something to act on.

    Stop resolves the target by PORT rather than by the recorded PID. A pid
    file goes stale (crash, reboot, manual kill, a server started some other
    way) and acting on a stale PID either misses the real process or kills an
    unrelated one. Whatever is holding the port is by definition the thing in
    the way.
#>

[CmdletBinding()]
param(
    [ValidateSet('start', 'stop', 'restart', 'status')]
    [string] $Action = 'status',

    [int] $Port = 8765
)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $root '.server.pid'
$logFile = Join-Path $root '.server.log'
$url     = "http://localhost:$Port/"

function Get-Listener {
    param([int] $Port)

    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1

    if (-not $conn) { return $null }

    return Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
}

function Invoke-Start {

    $existing = Get-Listener -Port $Port

    if ($existing) {
        Write-Host "Already serving on $url (PID $($existing.Id), $($existing.ProcessName))"
        return
    }

    # -u unbuffers, so the log is readable while the server is running.
    $proc = Start-Process -FilePath 'python' `
                          -ArgumentList '-u', '-m', 'http.server', $Port `
                          -WorkingDirectory $root `
                          -WindowStyle Hidden `
                          -RedirectStandardOutput $logFile `
                          -RedirectStandardError "$logFile.err" `
                          -PassThru

    # Binding can fail after the process starts (port taken, python missing a
    # module), so confirm it is actually listening instead of trusting the spawn.
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        if (Get-Listener -Port $Port) {
            Set-Content -Path $pidFile -Value $proc.Id -Encoding utf8
            Write-Host "Serving $root"
            Write-Host "  $url            (PID $($proc.Id))"
            Write-Host "  log: $logFile"
            return
        }
        if ($proc.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }

    Write-Host "Failed to start on port $Port." -ForegroundColor Red
    if (Test-Path "$logFile.err") {
        Get-Content "$logFile.err" -Tail 10 | ForEach-Object { Write-Host "  $_" }
    }
    exit 1
}

function Invoke-Stop {

    $proc = Get-Listener -Port $Port

    if (-not $proc) {
        Write-Host "Nothing listening on port $Port."
        if (Test-Path $pidFile) { Remove-Item $pidFile -Force }
        return
    }

    Stop-Process -Id $proc.Id -Force
    Write-Host "Stopped PID $($proc.Id) ($($proc.ProcessName)) on port $Port."

    if (Test-Path $pidFile) { Remove-Item $pidFile -Force }
}

function Invoke-Status {

    $proc = Get-Listener -Port $Port

    if ($proc) {
        Write-Host "Running - $url (PID $($proc.Id), $($proc.ProcessName))"
    } else {
        Write-Host "Stopped - nothing listening on port $Port."
    }
}

switch ($Action) {
    'start'   { Invoke-Start }
    'stop'    { Invoke-Stop }
    'status'  { Invoke-Status }
    'restart' {
        Invoke-Stop
        # Give the socket a moment to clear before rebinding.
        Start-Sleep -Milliseconds 500
        Invoke-Start
    }
}
