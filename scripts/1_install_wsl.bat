@echo off
setlocal
call "%~dp0..\config.bat"
chcp 65001 >nul
if "%~1"=="-elevated" goto :elevated
fltmc >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '-elevated' -Verb RunAs"
    exit /b
)
:elevated
title Step1 - install WSL2
echo.
echo === [1/2] Enable WSL + Virtual Machine Platform ===
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /noreturn
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /noreturn

echo.
echo === [2/2] Install / update WSL kernel ===
wsl --update --web-download 2>nul || wsl --update
wsl --set-default-version 2

echo.
echo ============================================
echo Done. 如果上方没有红色报错:
echo   1. 重启电脑
echo   2. 运行 2_install_samba.bat
echo ============================================
pause
