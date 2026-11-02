@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
if not exist "build\windows\QingyuMahjong.exe" goto source
start "" "%~dp0build\windows\QingyuMahjong.exe" %*
if errorlevel 1 goto failed
exit /b 0

:source
echo 首次源码启动：正在导入 Godot 资源……
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1" --headless --editor --import --quit
if errorlevel 1 goto failed
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1" %*
if errorlevel 1 goto failed
exit /b 0

:failed
set "mahjong_exit=%errorlevel%"
echo.
echo 启动失败，请查看上面的错误信息。可在 README.md 中查看运行环境说明。
if not defined MAHJONG_NO_PAUSE pause
exit /b %mahjong_exit%
