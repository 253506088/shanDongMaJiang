param([ValidateSet('windows','android','macos')][string]$Target='windows',[string]$Godot=$env:GODOT_BIN)
$ErrorActionPreference='Stop'
$projectDir=Split-Path $PSScriptRoot -Parent
$presets=@{windows='Windows Desktop';android='Android';macos='macOS'}
$files=@{windows='QingyuMahjong.exe';android='qingyu-mahjong-debug.apk';macos='QingyuMahjong.zip'}
$targetDir=Join-Path $projectDir "build/$Target"
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Set-Content -LiteralPath (Join-Path $projectDir 'build/.gdignore') -Value ''
$outputFile=Join-Path $targetDir $files[$Target]
if ($Target -eq 'macos') {
    # Godot's macOS exporter also validates the installed standard template.
    $macTemplate=Join-Path $projectDir 'tmp/export_templates/macos.zip'
    if (-not (Test-Path -LiteralPath $macTemplate)) { throw 'Run tools/fetch_templates.py first.' }
    $templateDir=Join-Path $env:APPDATA 'Godot/export_templates/4.5.1.stable'
    New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
    Copy-Item -LiteralPath $macTemplate -Destination (Join-Path $templateDir 'macos.zip')
}
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --editor --import --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Target -eq 'android') {
    & "$PSScriptRoot/run.ps1" -Godot $Godot --headless --export-debug $presets[$Target] $outputFile
} else {
    & "$PSScriptRoot/run.ps1" -Godot $Godot --headless --export-release $presets[$Target] $outputFile
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Get-FileHash -Algorithm SHA256 -LiteralPath $outputFile | Format-List
