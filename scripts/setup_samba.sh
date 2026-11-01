#!/bin/bash
# 在 WSL Debian 内安装并配置 Samba（幂等，可反复运行）
# 用法: setup_samba.sh <共享的WSL路径> <tuna|default>
# 由 2_install_samba.bat 调用，参数已自动换算，一般无需手动运行。
set -e
export DEBIAN_FRONTEND=noninteractive

RECORD_WSL="${1:?用法: setup_samba.sh <共享路径如/mnt/d/Recordings> <mirror>}"
MIRROR="${2:-default}"

echo "=== [1/5] 配置 APT 源 (mirror=$MIRROR) ==="
if [ "$MIRROR" = "tuna" ]; then
    cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian/
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian-security/
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    echo "" > /etc/apt/sources.list 2>/dev/null || true
    # 关键: 发行版自带的 0000debian.sources 排序优先级最高，会把自定义源压回去
    rm -f /etc/apt/sources.list.d/0000debian.sources
fi
ls -la /etc/apt/sources.list.d/

echo "=== [2/5] apt update + 安装 samba ==="
apt-get update
apt-get install -y samba

echo "=== [3/5] 写入 /etc/samba/smb.conf ==="
mkdir -p "$RECORD_WSL"
cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   server string = samba-for-camera
   # 允许最老的 SMB1 —— 部分摄像头固件只支持 NT1
   server min protocol = NT1
   server max protocol = SMB3
   # 未知用户名一律映射为 guest —— 兼容摄像头写入阶段发送的畸形令牌
   map to guest = Bad User
   log file = /var/log/samba/log.%m
   log level = 1
   max log size = 1000
   dns proxy = no

[recordings]
   path = $RECORD_WSL
   browseable = yes
   writable = yes
   guest ok = yes
   force user = root
   create mask = 0644
   directory mask = 0755
EOF

echo "=== [4/5] WSL 启动时自动拉起 smbd ==="
cat > /etc/wsl.conf <<'EOF'
[boot]
command = /usr/sbin/smbd -D
EOF

echo "=== [5/5] 重启 smbd 并校验 ==="
service smbd restart || service smbd start || /usr/sbin/smbd -D
sleep 1
smbd --version
testparm -s 2>&1 | head -30
echo ""
echo "### Samba 配置完成，共享: recordings -> $RECORD_WSL ###"
