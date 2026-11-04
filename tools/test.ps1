param([string]$Godot = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path $PSScriptRoot -Parent
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --editor --import --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/test_runner.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/ux_regressions.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/locked_turn_regressions.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/scene_surface.gd -- --qa
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/opponent_waits.gd -- --qa
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/lan_discovery_test.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/lan_session_test.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/lan_ui_test.gd -- --qa
exit $LASTEXITCODE
