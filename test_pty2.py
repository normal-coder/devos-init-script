#!/usr/bin/env python3
"""PTY 测试：菜单 → 自己挑（选配屏）→ 汇总 → 确认 → 试运行 → 退出"""
import pty, os, time, sys, fcntl, termios, struct

script = r'''
set -euo pipefail
cd /Users/normal/temp/daily/devos-init-script
exec ./install.sh
'''
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp("bash", ["bash", "-c", script])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 120, 0, 0))

def drain(timeout):
    out = b""; end = time.time() + timeout; idle = 0.0
    while time.time() < end and idle < 0.8:
        try:
            os.set_blocking(fd, False)
            d = os.read(fd, 65536)
        except BlockingIOError:
            time.sleep(0.05); idle += 0.05; continue
        except OSError:
            break
        if d: out += d; idle = 0.0
        else: time.sleep(0.05); idle += 0.05
    return out.decode("utf-8", "replace")

log = drain(2.0)
assert "选择交互方式" in log, "菜单未渲染"

os.write(fd, b"\x1b[B")      # ↓ 到「自己挑」
time.sleep(0.4)
os.write(fd, b"\r")          # 进入选配屏
sel = drain(2.0); log += sel

os.write(fd, b"\r")          # 直接回车 = 保持默认 26 件
summ = drain(2.0); log += summ

os.write(fd, b"\r")          # 确认执行
run = drain(5.0); log += run

os.write(fd, b"\r")          # ui_pause
log += drain(1.5)
os.write(fd, b"\x03")        # 菜单 Ctrl-C 退出
log += drain(1.5)

checks = [
    ("选配屏头部",   "x 勾选"),
    ("全选行",       "全选本组"),
    ("分组标题行",   "── 基础软件 ──"),
    ("汇总表",       "执行清单"),
    ("试运行",       "[试运行]"),
    ("成功统计",     "共 26 件成功"),
]
ok = True
for name, pat in checks:
    hit = pat in log
    print(("  ✔ " if hit else "  ✘ ") + name + ("" if hit else f"（缺: {pat!r}）"), flush=True)
    ok = ok and hit

time.sleep(0.5)
wpid, _ = os.waitpid(pid, os.WNOHANG)
print("  " + ("✔ 进程已退出" if wpid else "✘ 进程还活着"), flush=True)
print("总体:", "PASS" if ok and wpid else "FAIL", flush=True)
with open("/tmp/devos_pty2.log", "w") as f:
    f.write(log)
sys.exit(0 if ok and wpid else 1)
