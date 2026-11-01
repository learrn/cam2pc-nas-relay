# 开机/每分钟由计划任务调用：唤醒 WSL、确保 smbd 存活、
# 把当前虚拟机 IP 写入同目录 wsl_ip.txt（供 smb_relay.py 读取）。
#
# 已知坑: wsl.exe 输出是 UTF-16，直接按默认编码解析会得到乱码
# （曾导致 portproxy 写入 "N/ec/" 这类垃圾地址），因此这里
# 先切换控制台解码再读取，并对结果做严格 IPv4 校验，多通道兜底。
param()
$Distro = 'Debian'   # 与 config.bat 中 WSL_DISTRO 保持一致
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$IpFile = Join-Path $ScriptDir 'wsl_ip.txt'
$Log = Join-Path $ScriptDir 'logs\refresh_wsl_ip.log'

function L([string]$m) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -LiteralPath $Log -Encoding UTF8
}
New-Item -ItemType Directory -Force -Path (Join-Path $ScriptDir 'logs') | Out-Null
L "=== refresh start ==="

# 拉起 WSL（幂等）并确保 smbd 活着
wsl -d $Distro -u root -- true 2>$null
Start-Sleep -Seconds 2
wsl -d $Distro -u root -- service smbd start 2>$null

# ---- 多通道获取当前 WSL IP，严格校验，绝不写入非法值 ----
$ip = $null

# 通道1: wsl.exe 输出为 UTF-16，先切控制台解码
try { [Console]::OutputEncoding = [Text.Encoding]::Unicode } catch {}
$raw = wsl -d $Distro hostname -I 2>$null
$cand = (($raw -join ' ').Trim() -split '\s+')[0]
L "ch1 raw: [$cand]"
if ($cand -match '^\d{1,3}(\.\d{1,3}){3}$') { $ip = $cand }

# 通道2: 虚拟机内部读 eth0 地址
if (-not $ip) {
    $raw2 = wsl -d $Distro -u root -- bash -c "ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet )[\d.]+'" 2>$null
    $cand2 = (($raw2 -join ' ').Trim() -split '\s+')[0]
    L "ch2 raw: [$cand2]"
    if ($cand2 -match '^\d{1,3}(\.\d{1,3}){3}$') { $ip = $cand2 }
}

# 通道3: ARP 邻居表 (vEthernet (WSL) 接口上的 172.x 地址)
if (-not $ip) {
    $n = Get-NetNeighbor -InterfaceAlias 'vEthernet (WSL)' -ErrorAction SilentlyContinue |
         Where-Object { $_.IPAddress -match '^172\.' -and $_.State -in 'Reachable','Stale','Probe','Delay' } |
         Select-Object -First 1
    if ($n -and $n.IPAddress -match '^\d{1,3}(\.\d{1,3}){3}$') { $ip = $n.IPAddress; L "ch3 arp: [$ip]" }
}

if (-not $ip) {
    L "ERROR: 无法确定 WSL IP，保留现有 wsl_ip.txt 不动"
    exit 1
}
L "WSL IP validated: $ip"
Set-Content -LiteralPath $IpFile -Value $ip -Encoding ASCII
L "=== refresh done ==="
