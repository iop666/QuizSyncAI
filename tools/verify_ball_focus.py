"""点悬浮球时，主窗口会不会被抢到前台？

1.1.0 修过这个体验问题（用球识别后主窗口自己跳出来）。做法是让另一个窗口当前台，
然后点球，看前台窗口有没有变成我们。
"""

import ctypes
import ctypes.wintypes as wt
import subprocess
import time

import sys

# 路径走参数 —— 不把开发机绝对路径写进仓库(卫生自检会红)。
EXE = sys.argv[1] if len(sys.argv) > 1 else "QuizSync.App.exe"

ctypes.windll.shcore.SetProcessDpiAwareness(2)
user32 = ctypes.windll.user32


def pid_of(image):
    out = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {image}", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    return int(out.strip().split('","')[1]) if '","' in out else None


def foreground_pid():
    hwnd = user32.GetForegroundWindow()
    owner = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
    title = ctypes.create_unicode_buffer(256)
    user32.GetWindowTextW(hwnd, title, 256)
    return owner.value, title.value


def ball_rect(app_pid):
    found = []

    def callback(hwnd, _):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == app_pid:
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            if cls.value == "QuizSyncFloatingBall":
                rect = wt.RECT()
                user32.GetWindowRect(hwnd, ctypes.byref(rect))
                found.append(rect)
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(callback), 0)
    return found[0] if found else None


subprocess.run(["taskkill", "/IM", "QuizSync.App.exe", "/F"], capture_output=True)
subprocess.run(["taskkill", "/IM", "notepad.exe", "/F"], capture_output=True)
time.sleep(1.2)
subprocess.Popen([EXE])
time.sleep(9)

app_pid = pid_of("QuizSync.App.exe")
rect = ball_rect(app_pid)
if rect is None:
    print("没有球窗口，中止")
    raise SystemExit(1)

# 让记事本当前台（模拟「用户人在别的软件里」）
subprocess.Popen(["notepad.exe"])
time.sleep(3)
before_pid, before_title = foreground_pid()
print(f"点球前的前台窗口: pid={before_pid} title={before_title!r}")

# 点球
cx, cy = (rect.left + rect.right) // 2, (rect.top + rect.bottom) // 2
user32.SetCursorPos(cx, cy)
time.sleep(0.3)
user32.mouse_event(0x0002, 0, 0, 0, 0)
time.sleep(0.08)
user32.mouse_event(0x0004, 0, 0, 0, 0)
print("已点球，等待…")
time.sleep(6)

after_pid, after_title = foreground_pid()
print(f"点球后的前台窗口: pid={after_pid} title={after_title!r}")
print(f"应用 pid={app_pid}")
print("结论:", "主窗口被抢到前台（1.1.0 那个问题复现了）" if after_pid == app_pid
      else "主窗口没有被抢到前台 OK（用户仍在原来的软件里）")

subprocess.run(["taskkill", "/IM", "notepad.exe", "/F"], capture_output=True)
