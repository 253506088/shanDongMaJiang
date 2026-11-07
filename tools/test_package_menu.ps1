$ErrorActionPreference = 'Stop'
$projectDir = Split-Path $PSScriptRoot -Parent
$scratchRoot = [IO.Path]::GetFullPath((Join-Path $projectDir 'tmp'))
$scratch = Join-Path $scratchRoot ('package-menu-test-' + [Guid]::NewGuid().ToString('N'))
$checks = 0
function Check([bool]$Passed, [string]$Message) {
    if (-not $Passed) { throw $Message }
    $script:checks++
}
function Run-Menu([string]$Arguments, [string]$InputText, [string]$FailTarget = '') {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.WorkingDirectory = $scratch
    $info.Arguments = '/d /c package.bat ' + $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['MAHJONG_NO_PAUSE'] = '1'
    $info.EnvironmentVariables['MAHJONG_TEST_FAIL'] = $FailTarget
    $process = [Diagnostics.Process]::Start($info)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($InputText)
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(15000)) {
            # CMD owns a PowerShell child. Retire only this probe's process
            # tree, otherwise the child can keep the scratch directory open.
            & "$env:SystemRoot/System32/taskkill.exe" /PID $process.Id /T /F | Out-Null
            $process.WaitForExit(3000) | Out-Null
            throw 'Menu test timed out.'
        }
        return @{ code=$process.ExitCode; text=$output.Result; errors=$errors.Result }
    } finally { $process.Dispose() }
}
try {
    New-Item -ItemType Directory -Path (Join-Path $scratch 'tools') | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectDir '打包游戏.bat') -Destination (Join-Path $scratch 'package.bat')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'package_menu.ps1') -Destination (Join-Path $scratch 'tools/package_menu.ps1')
    $stub = @'
param([string]$Target, [switch]$EnableLan)
Write-Output "BUILD:${Target}:$([bool]$EnableLan)"
if ($env:MAHJONG_TEST_FAIL -eq $Target) { exit 7 }
exit 0
'@
    [IO.File]::WriteAllText((Join-Path $scratch 'tools/build.ps1'), $stub, [Text.Encoding]::ASCII)
    Check (-not ([IO.File]::ReadAllBytes((Join-Path $scratch 'package.bat')) | Where-Object { $_ -gt 127 })) 'BAT must remain ASCII-only.'
    $menuBytes = [IO.File]::ReadAllBytes((Join-Path $scratch 'tools/package_menu.ps1'))
    Check ([BitConverter]::ToString($menuBytes[0..2]) -eq 'EF-BB-BF') 'Windows PowerShell needs a UTF-8 BOM for this menu.'
    $result = Run-Menu '' "0`r`n"
    Check ($result.code -eq 0 -and $result.text.Contains('2. Android') -and -not $result.text.Contains('BUILD:') -and $result.errors -eq '') 'Menu displays Android and exits without CMD errors.'
    $result = Run-Menu '' ''
    Check ($result.code -ne 0 -and -not $result.text.Contains('BUILD:')) 'Closed redirected input cancels instead of looping forever.'
    $result = Run-Menu '' "2`r`n`r`n"
    Check ($result.code -eq 0 -and $result.text.Contains('BUILD:android:False') -and $result.errors -eq '') 'Interactive Android defaults to offline.'
    $result = Run-Menu '' "1`r`ny`r`n"
    Check ($result.code -eq 0 -and $result.text.Contains('BUILD:windows:True')) 'Interactive LAN selection reaches builder.'
    $result = Run-Menu '' "invalid`r`n4`r`ninvalid`r`nn`r`n"
    Check ($result.code -eq 0 -and ([regex]::Matches($result.text,'BUILD:\w+:False')).Count -eq 3) 'Invalid choices retry; all platforms use chosen capability.'
    $result = Run-Menu 'windows' ''
    Check ($result.code -eq 0 -and $result.text.Contains('BUILD:windows:False')) 'CLI defaults to offline without prompting.'
    $result = Run-Menu 'all -EnableLan' ''
    Check ($result.code -eq 0 -and ([regex]::Matches($result.text,'BUILD:\w+:True')).Count -eq 3) 'CLI LAN option applies to all platforms.'
    $result = Run-Menu 'all' '' 'android'
    Check ($result.code -eq 7 -and $result.text.Contains('BUILD:android:False') -and -not $result.text.Contains('BUILD:macos')) 'Failure exit code propagates and stops remaining builds.'
    $result = Run-Menu 'unsupported' ''
    Check ($result.code -ne 0 -and -not $result.text.Contains('BUILD:')) 'Invalid CLI target cannot build.'
    Write-Output "PACKAGE_MENU_RESULT: $checks checks, 0 failures"
} finally {
    if (Test-Path -LiteralPath $scratch) {
        $resolved = (Resolve-Path -LiteralPath $scratch).Path
        if (-not $resolved.StartsWith($scratchRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing cleanup outside scratch root: $resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
