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
# --import owns the editor's completion and shutdown. Leave time for its
# asynchronous work before exit instead of combining it with an early --quit.
& "$PSScriptRoot/run.ps1" -Godot $Godot --headless --import --frame-delay 800
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Target -eq 'android') {
    # apksigner writes a second APK in the Java temporary directory. Keep that
    # rebuildable scratch data on the project drive instead of filling C:.
    $androidTempRoot = Join-Path $projectDir 'tmp/android-export'
    $androidTempDirectory = Join-Path $androidTempRoot ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $androidTempDirectory | Out-Null
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    try {
        $env:TEMP = $androidTempDirectory
        $env:TMP = $androidTempDirectory
        & "$PSScriptRoot/run.ps1" -Godot $Godot --headless --export-debug $presets[$Target] $outputFile
    } finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        # Delete only this invocation's private scratch folder, including when
        # signing fails. Never remove another build's files or delivered art.
        if (Test-Path -LiteralPath $androidTempDirectory) {
            $cleanupRoot = [System.IO.Path]::GetFullPath($androidTempRoot)
            $cleanupTarget = (Resolve-Path -LiteralPath $androidTempDirectory).Path
            if (-not $cleanupTarget.StartsWith($cleanupRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to clean outside Android export scratch directory: $cleanupTarget"
            }
            Remove-Item -LiteralPath $cleanupTarget -Recurse -Force
            if (-not (Get-ChildItem -LiteralPath $cleanupRoot -Force | Select-Object -First 1)) {
                Remove-Item -LiteralPath $cleanupRoot -Force
            }
        }
    }
} else {
    & "$PSScriptRoot/run.ps1" -Godot $Godot --headless --export-release $presets[$Target] $outputFile
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Use .NET directly: a BAT starts Windows PowerShell, whose module path can
# differ from the PowerShell 7 terminal that launched it.
$hashAlgorithm=[System.Security.Cryptography.SHA256]::Create()
$stream=[System.IO.File]::OpenRead($outputFile)
try {
    $checksum=[System.BitConverter]::ToString($hashAlgorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant()
} finally {
    $stream.Dispose()
    $hashAlgorithm.Dispose()
}
Write-Output "Output: $outputFile"
Write-Output "SHA256: $checksum"
