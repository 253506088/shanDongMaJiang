param([string]$Godot = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --editor --import --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/test_runner.gd
exit $LASTEXITCODE
