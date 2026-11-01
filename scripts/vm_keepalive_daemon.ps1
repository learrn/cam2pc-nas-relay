# WSL 持久会话守护：保持一个长会话，防止 utility VM 被回收。
# 已知坑: WSL 3.0.3 的 vmIdleTimeout=-1 无效，空闲 25~60 秒后 VM 仍会被
# 自动回收；且发行版按用户隔离，SYSTEM 账户看不到用户安装的发行版，
# 因此本守护必须以登录用户身份运行（计划任务不要用 SYSTEM）。
param()
$Distro = 'Debian'   # 与 config.bat 中 WSL_DISTRO 保持一致
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log = Join-Path $ScriptDir 'logs\vm_keepalive.log'

function L([string]$m) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Add-Content -LiteralPath $Log -Encoding UTF8
}
New-Item -ItemType Directory -Force -Path (Join-Path $ScriptDir 'logs') | Out-Null
L "=== daemon started (pid $PID, user $env:USERNAME) ==="

$failCount = 0
while ($true) {
    # 这个调用在会话存续期间一直阻塞，VM 因此不会被回收
    $err = & wsl.exe -d $Distro -u root -- sh -c "exec sleep infinity" 2>&1
    $code = $LASTEXITCODE
    if ($err) {
        $failCount++
        L ("session ended (exit=$code, fail#$failCount): " + (($err | Out-String).Trim() -replace "`r`n", ' | '))
    } else {
        $failCount = 0
        L "session ended normally (exit=$code) - relaunching in 5s"
    }
    if ($failCount -ge 5) {
        L "ERROR: wsl 连续失败 - 检查发行版名/用户上下文；60s 后重试"
        Start-Sleep -Seconds 60
    } else {
        Start-Sleep -Seconds 5
    }
}
