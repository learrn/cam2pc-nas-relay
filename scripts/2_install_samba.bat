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
title Step2 - install Samba inside WSL
echo.
echo === [1/4] Check WSL distro ===
wsl -l -v
wsl -d %WSL_DISTRO% -u root -- true 2>nul
if errorlevel 1 (
    echo.
    echo 尚未安装 %WSL_DISTRO%，现在自动安装...
    wsl --install -d %WSL_DISTRO% --web-download
    echo.
    echo 安装完成后请重新运行本脚本。
    pause
    exit /b 1
)

echo.
echo === [2/4] Convert Windows record dir to WSL path ===
if not exist "%RECORD_WIN%" (
    echo 创建录像目录 %RECORD_WIN% ...
    mkdir "%RECORD_WIN%"
)
for /f "usebackq delims=" %%p in (`wsl -d %WSL_DISTRO% wslpath -a "%RECORD_WIN%"`) do set RECORD_WSL=%%p
echo Windows: %RECORD_WIN%
echo WSL    : %RECORD_WSL%
if "%RECORD_WSL%"=="" (
    echo ERROR: wslpath 转换失败。仓库需放在本机固定磁盘(NTFS)上。
    pause
    exit /b 1
)

echo.
echo === [3/4] Run setup_samba.sh inside WSL ===
pushd "%~dp0"
wsl -d %WSL_DISTRO% -u root -- bash -lc "./setup_samba.sh '%RECORD_WSL%' '%APT_MIRROR%'"
set RC=%errorlevel%
popd
if not "%RC%"=="0" (
    echo.
    echo ERROR: 脚本执行失败 (exit %RC%)。请把上方完整输出贴出来排查。
    pause
    exit /b %RC%
)

echo.
echo ============================================
echo Done. Samba 已就绪。下一步运行 4_start_relay.bat
echo ============================================
pause
