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
title Step5 - WSL keepalive (VM anti-GC + IP refresh)
echo.
echo === [1/3] Register logon task: VM persistent session daemon ===
rem 必须以登录用户身份运行，SYSTEM 看不到用户级发行版
schtasks /create /f /sc onlogon /tn "XiaomiCam-WSL-KeepAlive" /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File '%~dp0vm_keepalive_daemon.ps1'"

echo.
echo === [2/3] Register minute task: refresh WSL IP ===
schtasks /create /f /sc minute /mo 1 /tn "XiaomiCam-WSL-IPRefresh" /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File '%~dp0refresh_wsl_ip.ps1'"

echo.
echo === [3/3] Start daemon now (hidden) ===
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0vm_keepalive_daemon.ps1"
schtasks /run /tn "XiaomiCam-WSL-IPRefresh" >nul 2>&1
timeout /t 15 /nobreak >nul

echo.
echo === Verify ===
powershell -NoProfile -Command "$p=Get-Process wslhost -ErrorAction SilentlyContinue; if($p){'wslhost alive (pid ' + ($p.Id -join ',') + ') - VM is pinned awake'}else{'wslhost not found'}"
type "%~dp0logs\vm_keepalive.log" 2>nul | more +0
echo.
echo ============================================
echo All set. 去米家 App 添加 NAS:
echo   服务器地址: %LAN_IP%  (或列表中选择本机)
echo   共享名    : recordings
echo   账号/密码 : 随意填写
echo ============================================
pause
