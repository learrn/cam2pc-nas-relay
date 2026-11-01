# 小米摄像头 NAS 直存 · Windows + WSL2 Samba 中继方案

让小米智能摄像头（4K 变焦版等）把录像直接存到 Windows 电脑的共享文件夹。
针对摄像头固件 SMB 客户端畸形导致的"添加失败"问题，提供一套在 Windows 上可落地的替代方案。

## 这解决什么问题

在米家 App 给摄像头添加 NAS(SMB) 存储时，反复提示：

> 添加失败 / 请确保所选文件夹权限为可读写并重试

无论共享权限、NTFS 权限、账号密码怎么改都无效。抓包与事件日志分析定位到根因：

- 摄像头的 SMB 客户端固件行为畸形：**浏览/认证阶段**使用你输入的账号密码（正常 NTLM）；**实际写入阶段**却发送**空用户名的畸形 NTLM 令牌**
- Windows LSA 直接拒绝该令牌（安全日志 4625，子状态 `0x80090308 SEC_E_INVALID_TOKEN`）
- 该行为在 Windows 侧**无任何策略/注册表可绕过**（试过 NtlmMinServerSec=0、Guest 启用、启用 SMB1 均无效）
- 部分群晖 DSM 版本能容忍这种令牌，所以"群晖可以用"是侥幸兼容，不是 Windows 配错了

## 方案原理

不在 Windows 上伺服 SMB，改由 **WSL2 里的 Debian + Samba** 提供一个"宽容"的 SMB 服务：

- `server min protocol = NT1` —— 兼容只支持老协议的固件
- `map to guest = Bad User` —— 未知/畸形用户名一律映射为 guest，这正是群晖能收下摄像头的原因
- Windows 侧停用 `LanmanServer` 释放 445 端口
- 用 **Python 用户态 TCP 中继**把 445/139 转发进 WSL 虚拟机

```
小米摄像头 (SMB1/畸形令牌)
      │  局域网
      ▼
Windows 主机  LAN_IP:445 / :139
      │  Python 用户态中继 (smb_relay.py)
      ▼  读取 wsl_ip.txt 获知当前虚拟机 IP
WSL2 Debian 虚拟机 (Samba, NT1 + map to guest)
      │  drvfs 挂载
      ▼
D:\Recordings\  ←  你的看板/分析管线从这里读录像
```

> **为什么不用 netsh portproxy？** 实测 portproxy 对 SMB 流量存在数据黑洞：
> TCP 连接能建立，但数据不转发（客户端报错误 64），只能换用户态中继。

## 目录结构

```
├── config.bat                  ← 唯一需要修改的配置文件
└── scripts/
    ├── 1_install_wsl.bat           启用 WSL2 功能 + 安装内核（需重启）
    ├── 2_install_samba.bat         在 Debian 内安装配置 Samba
    ├── setup_samba.sh              Samba 配置脚本（WSL 内执行，自动调用）
    ├── 3_set_static_ip.bat         （可选）给网卡设静态 IP
    ├── 4_start_relay.bat           停 Windows SMB、释放 445、启动中继+自启
    ├── 5_install_keepalive.bat     VM 防回收守护 + IP 刷新计划任务
    ├── smb_relay.py                用户态 TCP 中继（445/139 → WSL）
    ├── refresh_wsl_ip.ps1          多通道获取并校验 WSL IP
    ├── vm_keepalive_daemon.ps1     WSL 持久会话守护
    ├── test_chain.bat              全链路自检
    └── uninstall.bat               恢复 Windows 默认配置
```

## 快速开始

**前置要求**：Windows 10 21H2+ / Windows 11，管理员权限，已安装 Python 3（加入 PATH），仓库放在本机固定磁盘（NTFS）上。

1. **改配置**：编辑 `config.bat`，至少确认 `LAN_IP`（本机局域网 IP）和 `RECORD_WIN`（录像保存目录）
2. **安装 WSL**：右键管理员运行 `scripts\1_install_wsl.bat`，完成后**重启电脑**
3. **安装 Samba**：管理员运行 `scripts\2_install_samba.bat`
4. **（可选）固定 IP**：管理员运行 `scripts\3_set_static_ip.bat`；或在路由器上对 `LAN_IP` 做 DHCP 静态绑定（二选一）
5. **启动中继**：管理员运行 `scripts\4_start_relay.bat`
   - 注意：从此 Windows 自身的文件共享(LanmanServer)会被停用
   - 脚本末尾的 `Chain test ... -> OPEN` 即链路通畅
6. **安装保活**：管理员运行 `scripts\5_install_keepalive.bat`
7. **米家添加**：摄像头设置 → NAS 存储 → 选择列表中的本机（或填 `LAN_IP`），**账号密码随意填写**，共享选择 `recordings`

**验证**：运行 `scripts\test_chain.bat` 全链路自检；添加成功后 `RECORD_WIN` 目录会出现 `XiaomiCamera_00_<序列号>/00_日期_时间.mp4`。

## 已知坑（全部实战踩过）

| 坑 | 现象 | 处理 |
|---|---|---|
| portproxy 数据黑洞 | TCP 连上但 SMB 协商无响应 | 放弃 portproxy，用用户态中继 |
| `wsl hostname -I` 乱码 | UTF-16 输出被按其他编码解析，得到 `N/ec/` 类垃圾 IP | `refresh_wsl_ip.ps1` 先切 Unicode 解码 + 严格 IPv4 校验 + ARP 兜底 |
| WSL VM 被自动回收 | 空闲 25~60 秒后虚拟机消失，中继后端失联 | `vmIdleTimeout=-1` 在 WSL 3.0.3 无效；用持久会话守护（`sleep infinity`）钉住 VM |
| 445 被占用 (pid 4) | 中继绑定 445 报 WinError 10013 | 删除 portproxy 规则后内核监听残留；重启 `iphlpsvc`，必要时 `srvnet` |
| 计划任务 SYSTEM 跑不了 WSL | SYSTEM 任务下 `wsl` 命令找不到发行版 | 发行版按用户隔离，守护任务必须以**登录用户**身份运行 |
| 自提权检测失效 | `net session` 在 LanmanServer 停止后永远失败 | 改用 `fltmc` 检测管理员权限 |
| 转发线程漏 start() | 连接建立但无数据 | 中继代码两个方向都要 `start()`（本仓库已修复） |
| APT 官方源极慢 | Debian in WSL 下载卡住 | `setup_samba.sh` 内置清华 TUNA 镜像（`config.bat` 里 `APT_MIRROR=tuna`） |

## 安全影响与恢复

运行本方案后 Windows 侧的改动：

- `LanmanServer`（Windows 文件共享服务）被停用 —— 本机不再向局域网提供 Windows 共享
- 防火墙新增 445/139 入站放行规则
- WSL 发行版内启用 SMB1 与 guest 映射 —— **风险限制在 WSL 虚拟机内部**，不波及宿主机

不需要时运行 `scripts\uninstall.bat` 一键恢复：删除计划任务与防火墙规则、重启 LanmanServer、清理端口残留。WSL 发行版本身保留（`wsl --unregister Debian` 可彻底删除，慎用）。

## 常见问题

**Q: 添加成功后录像存在哪？**
`config.bat` 里 `RECORD_WIN` 指定的目录，摄像头会自建 `XiaomiCamera_00_<序列号>` 子目录。

**Q: 电脑重启后需要手动启动什么？**
不用。计划任务随登录自动拉起中继、VM 守护和 IP 刷新；`wsl.conf` 的 boot command 会拉起 smbd。

**Q: 换了网络 / IP 变了怎么办？**
更新 `config.bat` 的 `LAN_IP`，重跑 `4_start_relay.bat`（或手动改防火墙无关，只需米家里重填地址）；WSL 虚拟机内部 IP 变化无需干预，IP 刷新任务每分钟自动更新。

**Q: 其他品牌的摄像头能用吗？**
凡是"SMB 实现兼容性差、只支持老协议或 guest 写入"的设备（部分老款摄像头/打印机扫描仪）都可能受益，原理相同。

## 免责声明

本方案仅用于解决自有设备在自有局域网内的存储兼容问题。请在可信网络环境中使用，勿将相关端口暴露到公网。
