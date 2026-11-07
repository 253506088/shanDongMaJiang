param(
    [ValidateSet('windows','android','macos','all')][string]$Target,
    [switch]$EnableLan
)
$ErrorActionPreference = 'Stop'
function Read-MenuLine([string]$Prompt) {
    if ([Console]::IsInputRedirected) {
        Write-Host $Prompt
        return [Console]::ReadLine()
    }
    return Read-Host $Prompt
}
try {
    if (-not $Target) {
        Write-Host ''
        Write-Host '===== 山东麻将 · 青玉台 ====='
        Write-Host ''
        Write-Host '  1. Windows 可执行程序'
        Write-Host '  2. Android 调试 APK'
        Write-Host '  3. macOS 未签名 ZIP'
        Write-Host '  4. 打包以上全部平台'
        Write-Host '  0. 退出'
        Write-Host ''
        Write-Host '产物保存在本目录的 build 文件夹。'
        Write-Host 'iOS 需要在 Mac 上使用 Xcode 打包。'
        do {
            $choice = Read-MenuLine '请选择 [1/2/3/4/0]'
            if ($null -eq $choice) { throw '未收到平台选择，已取消打包。' }
        } while ($choice -notin @('1','2','3','4','0'))
        if ($choice -eq '0') { exit 0 }
        $Target = @{ '1'='windows'; '2'='android'; '3'='macos'; '4'='all' }[$choice]
        if (-not $EnableLan) {
            do {
                $answer = Read-MenuLine '是否支持局域网联机？[y/N，直接回车为否]'
                if ($null -eq $answer) { throw '未收到联机选项，已取消打包。' }
            } while ($answer -notin @('','y','n','yes','no'))
            $EnableLan = $answer -in @('y','yes')
        }
    }
    Write-Host ('局域网联机：' + $(if ($EnableLan) { '支持' } else { '不支持（单机包）' }))
    $targets = if ($Target -eq 'all') { @('windows','android','macos') } else { @($Target) }
    foreach ($platform in $targets) {
        Write-Host "正在打包 $platform ……"
        & "$PSScriptRoot/build.ps1" -Target $platform -EnableLan:$EnableLan
        if ($LASTEXITCODE -ne 0) {
            Write-Host "打包失败，退出码：$LASTEXITCODE"
            Write-Host '请查看上面的错误信息；环境准备方法见 README.md 的“打包”部分。'
            exit $LASTEXITCODE
        }
    }
    Write-Host '打包完成！单机包在 build/<平台>/，联机包在 build/<平台>-lan/。'
    exit 0
} catch {
    Write-Host "打包失败：$($_.Exception.Message)"
    exit 1
}
