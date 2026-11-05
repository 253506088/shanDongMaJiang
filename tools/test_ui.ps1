param(
    [string]$Godot = $env:GODOT_BIN,
    [string[]]$Resolutions = @('1440x810', '960x540'),
    [ValidateSet('ui_smoke', 'ux_smoke', 'touch_smoke', 'waits_smoke', 'table_art_smoke', 'window_smoke', 'render_performance', 'opponent_waits', 'doudizhu_ui_test')]
    [string[]]$Suites = @('ui_smoke', 'ux_smoke', 'touch_smoke', 'waits_smoke', 'table_art_smoke'),
    [switch]$AllowDesktopChanges,
    [string]$OutputDir = 'artifacts/ui-verification'
)
$ErrorActionPreference = 'Stop'
# Fullscreen/resize tests take over the desktop. Keep them explicit, especially
# while the user is working in other projects. Performance sampling is opt-in.
if ('window_smoke' -in $Suites -and -not $AllowDesktopChanges) {
    throw 'window_smoke changes desktop windows. Run it separately with -AllowDesktopChanges when the desktop is available.'
}
$projectDir = Split-Path $PSScriptRoot -Parent
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $projectDir $OutputDir
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
Set-Content -LiteralPath (Join-Path $OutputDir '.gdignore') -Value ''
$results = @()
foreach ($resolution in $Resolutions) {
    if ($resolution -notmatch '^\d{3,5}x\d{3,5}$') { throw "Invalid resolution: $resolution" }
    foreach ($suite in $Suites) {
        $directory = Join-Path $OutputDir "$resolution/$suite"
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        $log = Join-Path $directory 'godot.log'
        $engineArgs = @('--resolution', $resolution, '--log-file', $log,
            '--script', "res://tests/$suite.gd", '--', '--qa', '--capture-dir', $directory)
        # Exercise the supported lower-cost rendering at the minimum window size.
        if ($resolution -eq '960x540' -and $suite -eq 'table_art_smoke') {
            $engineArgs += '--low-quality'
        }
        Write-Output "Running $suite at $resolution"
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        & "$PSScriptRoot/run.ps1" -Godot $Godot @engineArgs
        $code = $LASTEXITCODE
        $timer.Stop()
        $text = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
        $passed = $code -eq 0 -and $text -match '(?m)^\w*UI_RESULT: 0 failures' -and $text -notmatch '(?m)^(SCRIPT ERROR|ERROR):'
        $results += [pscustomobject]@{
            suite = $suite; resolution = $resolution; passed = $passed
            exit_code = $code; seconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
            log = $log; screenshots = $directory
        }
        $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDir 'results.json') -Encoding UTF8
        if (-not $passed) { throw "UI verification failed: $suite at $resolution. See $log" }
    }
}
Write-Output "Passed $($results.Count) rendered suites. Review screenshots in $OutputDir"
