@echo off
setlocal
call "%~dp0..\config.bat"
chcp 65001 >nul
title Test - full chain check
echo.
echo === [1/4] wsl_ip.txt ===
type "%~dp0wsl_ip.txt" 2>nul || echo MISSING - run refresh_wsl_ip.ps1
echo.
echo === [2/4] smbd inside WSL ===
wsl -d %WSL_DISTRO% -u root -- bash -c "pgrep -a smbd || echo smbd NOT RUNNING"
echo.
echo === [3/4] Relay listening on host ===
netstat -ano | findstr "LISTENING" | findstr ":445 :139 "
echo.
echo === [4/4] Chain test from LAN address ===
powershell -NoProfile -Command "$r=Test-NetConnection -ComputerName %LAN_IP% -Port 445 -WarningAction SilentlyContinue; '%LAN_IP%:445 -> ' + $(if($r.TcpTestSucceeded){'OPEN (OK)'}else{'CLOSED (FAIL)'})"
echo.
echo === 最近中继日志 ===
powershell -NoProfile -Command "Get-Content '%~dp0logs\smb_relay.log' -Tail 10 -ErrorAction SilentlyContinue"
echo.
pause
