@echo off
chcp 65001 >nul
rem ============================================================
rem  唯一需要修改的配置文件。改动后无需改任何脚本。
rem ============================================================

rem --- 摄像头访问本机使用的局域网 IP ---
rem 建议: 在路由器中为本机做 DHCP 静态绑定，或给网卡配静态 IP。
rem 注意: 不要用 127.x 或本机回环，摄像头从局域网另一台设备连入。
set LAN_IP=192.168.1.100
set LAN_MASK=255.255.255.0
set LAN_GW=192.168.1.1
rem 网卡名称（ipconfig 里显示的名称，常见: WLAN / 太以太网 / Ethernet）
set LAN_IF=WLAN

rem --- 录像保存目录（Windows 路径，请提前创建）---
rem Samba 共享名将固定为 recordings，路径可自定义。
set RECORD_WIN=D:\Recordings

rem --- WSL 发行版名 ---
set WSL_DISTRO=Debian

rem --- APT 镜像: tuna=清华镜像(国内推荐) / default=官方源 ---
set APT_MIRROR=tuna
