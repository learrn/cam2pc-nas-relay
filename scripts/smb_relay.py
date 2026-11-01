# 用户态 TCP 中继：把本机 445/139 端口的连接转发到 WSL 虚拟机里的 Samba。
#
# 为什么不用 netsh portproxy？
#   portproxy 遇到 SMB 流量存在数据黑洞（连接建立后数据不转发），实测失败，
#   因此改用 Python 用户态中继。
#
# WSL 虚拟机 IP 由 refresh_wsl_ip.ps1 周期刷新写入同目录 wsl_ip.txt，
# 本脚本每次接受连接时重新读取，IP 变化无需重启。

import os
import socket
import sys
import threading
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
IP_FILE = os.path.join(BASE_DIR, "wsl_ip.txt")
LOG_FILE = os.path.join(BASE_DIR, "logs", "smb_relay.log")
PORTS = (445, 139)

os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)


def log(msg):
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass
    print(line, flush=True)


def get_target():
    """读取并校验当前 WSL 虚拟机 IP。"""
    try:
        with open(IP_FILE) as f:
            ip = f.read().strip()
        socket.inet_aton(ip)
        return ip
    except (OSError, socket.error):
        return None


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle(client, port):
    addr = client.getpeername()[0]
    target_ip = get_target()
    if not target_ip:
        log(f"DROP {addr}:{port} - wsl_ip.txt 无有效 IP，先运行 refresh_wsl_ip.ps1")
        client.close()
        return
    try:
        backend = socket.create_connection((target_ip, port), timeout=5)
    except OSError as e:
        log(f"FAIL {addr} -> {target_ip}:{port} : {e}")
        client.close()
        return
    log(f"CONN {addr} -> {target_ip}:{port} (relay established)")
    # 注意: 两个方向的 pump 线程都必须 start()，漏掉会导致连接挂起无数据
    t = threading.Thread(target=pump, args=(client, backend), daemon=True)
    t.start()
    pump(backend, client)
    t.join(timeout=5)
    client.close()
    backend.close()
    log(f"DISC {addr} port {port}")


def listen(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("0.0.0.0", port))
    except OSError as e:
        log(f"LISTEN {port} FAILED: {e}")
        log("提示: 445 被占用时先运行 4_start_relay.bat 的释放流程")
        return
    srv.listen(8)
    log(f"LISTEN 0.0.0.0:{port}")
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c, port), daemon=True).start()


if __name__ == "__main__":
    log(f"=== relay starting (python {sys.version.split()[0]}) ===")
    for p in PORTS:
        threading.Thread(target=listen, args=(p,), daemon=True).start()
    while True:
        time.sleep(3600)
