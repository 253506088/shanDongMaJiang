@echo off
setlocal
cd /d "%~dp0"
rem Keep CMD input ASCII-only; PowerShell owns the UTF-8 menu and prompts.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\package_menu.ps1" %*
set "mahjong_exit=%errorlevel%"
if not defined MAHJONG_NO_PAUSE pause
exit /b %mahjong_exit%
