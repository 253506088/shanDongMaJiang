@echo off
cd /d "%~dp0"
if exist "build\windows\QingyuMahjong.exe" (
    start "" "build\windows\QingyuMahjong.exe"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1"
)
