param([string]$Package = '', [string]$OutputDir = 'artifacts/lan-process')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path $PSScriptRoot -Parent
if (-not $Package) { $Package = Join-Path $projectDir 'build/windows-lan/QingyuMahjong.exe' }
if (-not (Test-Path -LiteralPath $Package)) { throw 'Build the Windows LAN package first: tools/build.ps1 -Target windows -EnableLan' }
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $projectDir $OutputDir }
# A fresh directory avoids treating previous completion files as new evidence.
$runDirectory = Join-Path $OutputDir ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
$peerScript = Join-Path $projectDir 'tests/lan_process_peer.gd'
$port = 44000 + ($PID % 10000)
$processes = @()
function Start-HeadlessPeer([string]$Role, [int]$Index) {
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Package
    $info.WorkingDirectory = Split-Path $Package -Parent
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $log = Join-Path $runDirectory "$Role$Index.log"
    # Quoted paths contain no shell evaluation; no visible desktop window is created.
    $info.Arguments = "--headless --log-file `"$log`" --script `"$peerScript`" -- $Role $port `"$runDirectory`" $Index"
    return [System.Diagnostics.Process]::Start($info)
}
try {
    $processes += Start-HeadlessPeer 'host' 0
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath (Join-Path $runDirectory 'listening.json'))) {
        if ($processes[0].HasExited -or $timer.Elapsed.TotalSeconds -gt 10) { throw 'Headless package host did not start.' }
        Start-Sleep -Milliseconds 50
    }
    foreach ($index in 1..3) { $processes += Start-HeadlessPeer 'client' $index }
    foreach ($process in $processes) {
        if (-not $process.WaitForExit(50000)) { throw 'Headless package network test timed out.' }
        if ($process.ExitCode -ne 0) { throw "Headless package peer failed: $($process.ExitCode)" }
    }
    $completed = Get-Content -LiteralPath (Join-Path $runDirectory 'complete.json') -Raw | ConvertFrom-Json
    $seats = @()
    foreach ($name in @('host0','client1','client2','client3')) {
        $result = Get-Content -LiteralPath (Join-Path $runDirectory "$name.json") -Raw | ConvertFrom-Json
        if ($result.round -ne 2 -or ($result.scores -join ',') -ne ($completed.scores -join ',')) { throw 'Peers disagree on round or cumulative scores.' }
        $seats += $result.seat
        $logText = Get-Content -LiteralPath (Join-Path $runDirectory "$name.log") -Raw
        if ($logText -match '(?m)^(SCRIPT ERROR|ERROR|LAN_PROCESS_FAIL):') { throw "Package peer emitted errors: $name" }
    }
    if (($seats | Sort-Object -Unique).Count -ne 4) { throw 'Peers do not occupy four distinct seats.' }
    Write-Output "LAN_PACKAGE_RESULT: 4 headless package processes passed. Evidence: $runDirectory"
} finally {
    # Only terminate processes created by this test, never other Godot/game windows.
    foreach ($process in $processes) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(3000) | Out-Null }
        $process.Dispose()
    }
}
