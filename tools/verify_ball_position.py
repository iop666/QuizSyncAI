"""验证悬浮球位置持久化：拖动 -> 重启 -> 是否还在原处。"""

import ctypes
import ctypes.wintypes as wt
import json
import os
import subprocess
import time

import sys

# 路径走参数 —— 不把开发机绝对路径写进仓库(卫生自检会红)。
EXE = sys.argv[1] if len(sys.argv) > 1 else "QuizSync.App.exe"
BALL = os.path.join(os.environ["LOCALAPPDATA"], "QuizSyncAI", "app", "ball.json")

ctypes.windll.shcore.SetProcessDpiAwareness(2)
user32 = ctypes.windll.user32


def pid_of():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq QuizSync.App.exe", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    return int(out.strip().split('","')[1]) if '","' in out else None


def ball_rect():
    pid = pid_of()
    if pid is None:
        return None
    found = []

    def callback(hwnd, _):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            if cls.value == "QuizSyncFloatingBall":
                rect = wt.RECT()
                user32.GetWindowRect(hwnd, ctypes.byref(rect))
                found.append((rect.left, rect.top, rect.right - rect.left))
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(callback), 0)
    return found[0] if found else None


def launch():
    subprocess.run(["taskkill", "/IM", "QuizSync.App.exe", "/F"], capture_output=True)
    time.sleep(1.2)
    subprocess.Popen([EXE])
    time.sleep(9)


# 从「没有位置记录」开始
if os.path.exists(BALL):
    data = json.load(open(BALL, encoding="utf-8"))
    data.pop("x", None)
    data.pop("y", None)
    json.dump(data, open(BALL, "w", encoding="utf-8"), ensure_ascii=False)
launch()
first = ball_rect()
print("第一次启动（无位置记录）:", first)

# 拖到明显不同的地方：往左上拖
x, y, size = first
user32.SetCursorPos(x + size // 2, y + size // 2)
time.sleep(0.2)
user32.mouse_event(0x0002, 0, 0, 0, 0)
time.sleep(0.15)
for step in range(1, 13):
    user32.SetCursorPos(x + size // 2 - step * 40, y + size // 2 - step * 30)
    time.sleep(0.03)
user32.mouse_event(0x0004, 0, 0, 0, 0)
time.sleep(1.0)
dragged = ball_rect()
print("拖动后:", dragged)

print("ball.json 里记的位置:", {k: v for k, v in json.load(open(BALL, encoding="utf-8")).items()
                              if k in ("x", "y")})

# 重启 —— 关键一步
launch()
restarted = ball_rect()
print("重启后:", restarted)
print("结论:", "位置记住了 OK" if restarted and dragged and restarted[:2] == dragged[:2]
      else f"位置没记住 FAIL（拖动后 {dragged[:2] if dragged else None}，重启后 {restarted[:2] if restarted else None}）")
