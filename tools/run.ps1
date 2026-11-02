param([string]$Godot = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path $PSScriptRoot -Parent
if (-not $Godot) {
    $localEditor = Join-Path $projectDir 'tmp/godot/Godot_v4.5.1-stable_win64_console.exe'
    $candidate = 'D:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe'
    if (Test-Path -LiteralPath $localEditor) { $Godot = $localEditor }
    elseif (Test-Path -LiteralPath $candidate) { $Godot = $candidate }
    else { $Godot = (Get-Command godot -ErrorAction Stop).Source }
}
# Piping also waits for Windows GUI-subsystem Godot executables to finish.
& $Godot --path $projectDir @args | Out-Host
exit $LASTEXITCODE
