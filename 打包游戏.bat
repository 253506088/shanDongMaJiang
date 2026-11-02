@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
set "mahjong_target=%~1"
if defined mahjong_target goto dispatch

echo.
echo ===== 山东麻将 · 青玉台 =====
echo.
echo  1. Windows 可执行程序
echo  2. Android 调试 APK
echo  3. macOS 未签名 ZIP
echo  4. 打包以上全部平台
echo  0. 退出
echo.
echo  产物保存在本目录的 build 文件夹。
echo  iOS 需要在 Mac 上使用 Xcode 打包。
echo.
choice /C 12340 /N /M "请选择 [1/2/3/4/0]："
if errorlevel 5 exit /b 0
if errorlevel 4 goto all
if errorlevel 3 goto macos
if errorlevel 2 goto android
if errorlevel 1 goto windows
exit /b 1

:dispatch
if /I "%mahjong_target%"=="windows" goto windows
if /I "%mahjong_target%"=="android" goto android
if /I "%mahjong_target%"=="macos" goto macos
if /I "%mahjong_target%"=="all" goto all
echo 不支持的平台：%mahjong_target%
echo 用法：打包游戏.bat [windows^|android^|macos^|all]
set "mahjong_exit=2"
goto done

:windows
call :build windows
goto finish

:android
call :build android
goto finish

:macos
call :build macos
goto finish

:all
call :build windows
if errorlevel 1 goto finish
call :build android
if errorlevel 1 goto finish
call :build macos
goto finish

:finish
set "mahjong_exit=%errorlevel%"
echo.
if not "%mahjong_exit%"=="0" goto failed
echo 打包完成！产物目录：%~dp0build
goto done

:failed
echo 打包失败，退出码：%mahjong_exit%
echo 请查看上面的错误信息；环境准备方法见 README.md 的“打包”部分。

:done
if not defined MAHJONG_NO_PAUSE pause
exit /b %mahjong_exit%

:build
echo.
echo 正在打包 %~1 ……
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build.ps1" -Target "%~1"
exit /b %errorlevel%
