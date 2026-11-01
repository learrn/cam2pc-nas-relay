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
title Step3(optional) - static LAN IP
echo.
echo ============================================
echo   将把网卡 "%LAN_IF%" 设为静态 IP:
echo     IP : %LAN_IP%
echo     掩码: %LAN_MASK%
echo     网关: %LAN_GW%
echo   过程中 Wi-Fi 会短暂中断。
echo ============================================
choice /c YN /m "继续? "
if errorlevel 2 exit /b

netsh interface ip set address name="%LAN_IF%" static %LAN_IP% %LAN_MASK% %LAN_GW% 1
if errorlevel 1 (
    echo 设置失败，请确认网卡名称。当前地址列表:
    netsh interface ip show addresses
    pause
    exit /b 1
)
netsh interface ip set dns name="%LAN_IF%" static %LAN_GW% primary
netsh interface ip add dns name="%LAN_IF%" 223.5.5.5 index=2 >nul 2>&1

echo.
echo === Result ===
netsh interface ip show addresses name="%LAN_IF%"
echo.
echo 提示: 如路由器 DHCP 池覆盖 %LAN_IP%，建议同时在路由器上做静态绑定。
echo 撤销静态 IP: 手动把网卡改回自动获取(DHCP)。
echo.
pause
