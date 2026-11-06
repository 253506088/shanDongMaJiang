param([string]$Godot = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path $PSScriptRoot -Parent
# Let the importer complete its asynchronous editor work before shutdown.
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --import --frame-delay 800
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
foreach ($suite in @('bluff_core_test', 'bluff_session_test', 'bluff_ui_test', 'bluff_audio_test')) {
    & "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script "res://tests/$suite.gd" -- --qa
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/test_runner.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
foreach ($suite in @('doudizhu_core_test', 'doudizhu_recorder_test', 'doudizhu_session_test', 'doudizhu_ui_test', 'doudizhu_audio_test')) {
    & "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script "res://tests/$suite.gd" -- --qa
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
foreach ($suite in @('field_rules_test', 'field_flow_test', 'field_engine_test', 'field_session_test', 'field_ui_test', 'field_review_test')) {
    & "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script "res://tests/$suite.gd" -- --qa
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/ux_regressions.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/locked_turn_regressions.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --script res://tests/touch_smoke.gd '--' --qa
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
