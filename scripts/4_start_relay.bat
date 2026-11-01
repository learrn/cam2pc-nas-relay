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
title Step4 - SMB relay (start + autostart)
echo.
echo === [1/7] Stop Windows SMB service to free port 445 ===
echo (此后本机的 Windows 文件共享不可用，由 WSL Samba 接管)
net stop LanmanServer /y >nul 2>&1
sc config LanmanServer start= disabled

echo.
echo === [2/7] Remove portproxy rules (they black-hole SMB data) ===
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=445 >nul 2>&1
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=139 >nul 2>&1
echo done.

echo.
echo === [3/7] Release stale 445 listener if kernel still holds it ===
netstat -ano | findstr ":445 " | findstr "LISTENING" | findstr " 4 " >nul 2>&1
if not errorlevel 1 (
    echo 检测到残留监听(System pid 4^)，重启 iphlpsvc / srvnet 释放...
    net stop iphlpsvc /y >nul 2>&1
    timeout /t 2 /nobreak >nul
    net start iphlpsvc >nul 2>&1
    timeout /t 2 /nobreak >nul
    netstat -ano | findstr ":445 " | findstr "LISTENING" | findstr " 4 " >nul 2>&1
    if not errorlevel 1 (
        net stop srvnet /y
        timeout /t 2 /nobreak >nul
    )
)
netstat -ano | findstr ":445 " | findstr "LISTENING" || echo OK - port 445 is free

echo.
echo === [4/7] Firewall: allow inbound TCP 445 + 139 ===
netsh advfirewall firewall delete rule name="WSL-Samba-Relay-445" >nul 2>&1
netsh advfirewall firewall delete rule name="WSL-Samba-Relay-139" >nul 2>&1
netsh advfirewall firewall add rule name="WSL-Samba-Relay-445" dir=in action=allow protocol=TCP localport=445 >nul
netsh advfirewall firewall add rule name="WSL-Samba-Relay-139" dir=in action=allow protocol=TCP localport=139 >nul
echo done.

echo.
echo === [5/7] Wake WSL and record VM IP ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0refresh_wsl_ip.ps1"
type "%~dp0wsl_ip.txt" 2>nul

echo.
echo === [6/7] Start relay + register autostart ===
rem 只杀 smb_relay.py 实例，不动机器上其它 python 进程
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name like 'python%%'\" | Where-Object { $_.CommandLine -match 'smb_relay\.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
start "" /b powershell -NoProfile -WindowStyle Hidden -Command "Start-Process python -ArgumentList '\"%~dp0smb_relay.py\"' -WindowStyle Hidden"
timeout /t 4 /nobreak >nul
schtasks /create /f /sc onlogon /rl highest /tn "XiaomiCam-SMB-Relay" /tr "powershell -NoProfile -WindowStyle Hidden -Command \"Start-Process python -ArgumentList '%~dp0smb_relay.py' -WindowStyle Hidden\""

echo.
echo === [7/7] Verify: relay must own BOTH ports ===
netstat -ano | findstr "LISTENING" | findstr ":445 :139 "
echo (上方 0.0.0.0:445 与 0.0.0.0:139 应各有一行，且属于同一 python pid)
powershell -NoProfile -Command "Start-Sleep 2; $r=Test-NetConnection -ComputerName %LAN_IP% -Port 445 -WarningAction SilentlyContinue; 'Chain test %LAN_IP%:445 -> ' + $(if($r.TcpTestSucceeded){'OPEN'}else{'CLOSED'})"
echo.
echo 日志: %~dp0logs\smb_relay.log
echo 下一步: 运行 5_install_keepalive.bat
echo.
pause
