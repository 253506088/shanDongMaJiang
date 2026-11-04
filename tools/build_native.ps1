param(
    [switch]$Force,
    [string]$VisualStudio = 'C:\Program Files\Microsoft Visual Studio\18\Community',
    [string]$SdkVersion = '10.0.26100.0'
)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path $PSScriptRoot -Parent
$nativeDir = Join-Path $projectDir 'native/windows'
$binaryDir = Join-Path $nativeDir 'bin'
$intermediateDir = Join-Path $nativeDir 'build'
$outputFile = Join-Path $binaryDir 'motion_gate.windows.x86_64.dll'
$sourceFile = Join-Path $nativeDir 'motion_gate.cpp'
$headerFile = Join-Path $nativeDir 'vendor/gdextension_interface.h'
$inputs = @($sourceFile, $headerFile, $PSCommandPath)
foreach ($inputFile in $inputs) {
    if (-not (Test-Path -LiteralPath $inputFile)) { throw "Missing native build input: $inputFile" }
}
if (-not $Force -and (Test-Path -LiteralPath $outputFile)) {
    $outputTime = (Get-Item -LiteralPath $outputFile).LastWriteTimeUtc
    $newerInputs = @($inputs | Where-Object { (Get-Item -LiteralPath $_).LastWriteTimeUtc -gt $outputTime })
    if ($newerInputs.Count -eq 0) {
        Write-Output "Native motion gate is up to date: $outputFile"
        $global:LASTEXITCODE = 0
        return
    }
}
$vcvars = Join-Path $VisualStudio 'VC/Auxiliary/Build/vcvars64.bat'
if (-not (Test-Path -LiteralPath $vcvars)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installation) { $vcvars = Join-Path $installation 'VC/Auxiliary/Build/vcvars64.bat' }
    }
}
if (-not (Test-Path -LiteralPath $vcvars)) {
    throw 'MSVC x64 tools were not found. Install Visual Studio Desktop development with C++ or pass -VisualStudio.'
}
if ($SdkVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'SdkVersion must be a numeric Windows SDK version.' }
New-Item -ItemType Directory -Force -Path $binaryDir, $intermediateDir | Out-Null
Set-Content -LiteralPath (Join-Path $intermediateDir '.gdignore') -Value ''
# Read the official developer environment in a child shell. No filesystem
# operation or user data is passed between shells; only compiler environment.
$environmentCommand = 'call "{0}" {1} >nul && set' -f $vcvars, $SdkVersion
$developerEnvironment = & $env:ComSpec /d /s /c $environmentCommand
if ($LASTEXITCODE -ne 0) { throw "MSVC environment setup failed: $vcvars" }
$savedEnvironment = @{}
foreach ($name in @('PATH', 'INCLUDE', 'LIB', 'LIBPATH')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    $line = $developerEnvironment | Where-Object { $_.StartsWith($name + '=', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($line) { [Environment]::SetEnvironmentVariable($name, $line.Substring($name.Length + 1), 'Process') }
}
try {
    $compiler = (Get-Command cl.exe -ErrorAction Stop).Source
    $compilerArgs = @('/nologo', '/std:c++17', '/EHsc', '/O2', '/W4', '/MT', '/LD', '/utf-8',
        '/DUNICODE', '/D_UNICODE', $sourceFile,
        ('/Fo' + (Join-Path $intermediateDir 'motion_gate.obj')),
        ('/Fe:' + $outputFile), '/link', '/INCREMENTAL:NO',
        ('/IMPLIB:' + (Join-Path $intermediateDir 'motion_gate.lib')),
        ('/PDB:' + (Join-Path $intermediateDir 'motion_gate.pdb')),
        'user32.lib', 'comctl32.lib', 'shell32.lib')
    & $compiler @compilerArgs
    if ($LASTEXITCODE -ne 0) { throw "Native motion gate compilation failed (exit $LASTEXITCODE)." }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
Write-Output "Native motion gate: $outputFile"
$global:LASTEXITCODE = 0
