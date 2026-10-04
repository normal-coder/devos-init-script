#!/usr/bin/env python3
"""全流程 PTY 测试：菜单 → 汇总 → 确认 → 试运行 → 暂停 → 退出"""
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

# 给伪终端设窗口尺寸（否则 gum 按 0x0 渲染，什么都画不出来）
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))

def drain(timeout):
    out = b""
    end = time.time() + timeout
    idle = 0.0
    while time.time() < end and idle < 0.8:
        try:
            os.set_blocking(fd, False)
            d = os.read(fd, 65536)
        except BlockingIOError:
            time.sleep(0.05)
            idle += 0.05
            continue
        except OSError:
            break
        if d:
            out += d
            idle = 0.0
        else:
            time.sleep(0.05)
            idle += 0.05
    return out.decode("utf-8", "replace")

log = ""
t0 = time.time()
log += drain(2.0)
print(f"[{time.time()-t0:.1f}s] stage1 菜单: {'选择交互方式' in log}", flush=True)

os.write(fd, b"\r")
log += drain(2.0)
print(f"[{time.time()-t0:.1f}s] stage2 汇总: {'执行清单' in log} | 确认框: {'确认执行这 26 件' in log}", flush=True)

os.write(fd, b"\r")
run = drain(5.0)
log += run
print(f"[{time.time()-t0:.1f}s] stage3 试运行: {'[试运行]' in run} | 完成: {'执行完成' in run}", flush=True)

os.write(fd, b"\r")
log += drain(2.0)
print(f"[{time.time()-t0:.1f}s] stage4 暂停返回菜单", flush=True)

os.write(fd, b"\x03")   # Ctrl-C：取消 gum choose → 脚本退出
log += drain(1.5)

checks = [
    ("菜单头",      "选择交互方式"),
    ("汇总表",      "执行清单"),
    ("汇总件数",    "共 26 件"),
    ("确认框",      "确认执行这 26 件"),
    ("试运行标记",  "[试运行]"),
    ("zshrc 步骤",  "更新 ~/.zshrc 受管块"),
    ("成功统计",    "共 26 件成功"),
    ("回车继续",    "回车继续"),
]
ok = True
for name, pat in checks:
    hit = pat in log
    print(("  ✔ " if hit else "  ✘ ") + name + ("" if hit else f"（缺: {pat!r}）"), flush=True)
    ok = ok and hit

time.sleep(0.5)
wpid, st = os.waitpid(pid, os.WNOHANG)
print("  " + ("✔ 进程已退出" if wpid else "✘ 进程还活着"), flush=True)
print("总体:", "PASS" if ok and wpid else "FAIL", flush=True)

# 留一份原始日志供排查
with open("/tmp/devos_pty.log", "w") as f:
    f.write(log)
sys.exit(0 if ok and wpid else 1)
