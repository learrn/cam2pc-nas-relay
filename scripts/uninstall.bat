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
title Uninstall - restore Windows defaults
echo.
echo === [1/5] Remove scheduled tasks ===
schtasks /delete /tn "XiaomiCam-SMB-Relay" /f >nul 2>&1
schtasks /delete /tn "XiaomiCam-WSL-KeepAlive" /f >nul 2>&1
schtasks /delete /tn "XiaomiCam-WSL-IPRefresh" /f >nul 2>&1
echo done.

echo.
echo === [2/5] Stop relay process ===
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name like 'python%%'\" | Where-Object { $_.CommandLine -match 'smb_relay\.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo done.

echo.
echo === [3/5] Re-enable Windows file sharing (LanmanServer) ===
sc config LanmanServer start= auto
net start LanmanServer >nul 2>&1
echo done.

echo.
echo === [4/5] Remove firewall rules ===
netsh advfirewall firewall delete rule name="WSL-Samba-Relay-445" >nul 2>&1
netsh advfirewall firewall delete rule name="WSL-Samba-Relay-139" >nul 2>&1
echo done.

echo.
echo === [5/5] Remove portproxy leftovers ===
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=445 >nul 2>&1
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=139 >nul 2>&1
echo done.

echo.
echo ============================================
echo Windows 文件共享与端口已恢复。
echo 如需彻底清理，可手动删除 WSL 发行版:
echo   wsl --unregister %WSL_DISTRO%
echo (会删除该发行版内全部数据，慎重)
echo ============================================
pause
