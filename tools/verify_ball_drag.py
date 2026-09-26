"""验证悬浮球的拖动与右键隐藏（这两项一直「已写、未验」）。"""

import ctypes
import ctypes.wintypes as wt
import subprocess
import time

import sys

# 路径走参数 —— 不把开发机绝对路径写进仓库(卫生自检会红)。
EXE = sys.argv[1] if len(sys.argv) > 1 else "QuizSync.App.exe"

ctypes.windll.shcore.SetProcessDpiAwareness(2)  # 不这样做量到的是虚拟化坐标（差 2 倍）
user32 = ctypes.windll.user32


def ball(pid):
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
                found.append((hwnd, rect, bool(user32.IsWindowVisible(hwnd))))
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(callback), 0)
    return found[0] if found else None


subprocess.run(["taskkill", "/IM", "QuizSync.App.exe", "/F"], capture_output=True)
time.sleep(1)
subprocess.Popen([EXE])
time.sleep(9)

out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq QuizSync.App.exe", "/FO", "CSV", "/NH"],
                     capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
pid = int(out.strip().split('","')[1])

hwnd, rect, visible = ball(pid)
print(f"起始: 位置=({rect.left},{rect.top}) 可见={visible}")

# ---- 拖动：按住球心往左上拖 200 像素 ----
cx, cy = (rect.left + rect.right) // 2, (rect.top + rect.bottom) // 2
user32.SetCursorPos(cx, cy)
time.sleep(0.2)
user32.mouse_event(0x0002, 0, 0, 0, 0)      # LEFTDOWN
time.sleep(0.15)
for step in range(1, 11):                    # 分步移动，模拟真实拖动
    user32.SetCursorPos(cx - step * 20, cy - step * 20)
    time.sleep(0.03)
user32.mouse_event(0x0004, 0, 0, 0, 0)      # LEFTUP
time.sleep(0.6)

_, moved, visible_after = ball(pid)
print(f"拖动后: 位置=({moved.left},{moved.top}) 可见={visible_after}")
print(f"  位移 = ({moved.left - rect.left}, {moved.top - rect.top})   期望约 (-200, -200)")

# ---- 右键：应隐藏 ----
user32.SetCursorPos((moved.left + moved.right) // 2, (moved.top + moved.bottom) // 2)
time.sleep(0.2)
user32.mouse_event(0x0008, 0, 0, 0, 0)      # RIGHTDOWN
time.sleep(0.08)
user32.mouse_event(0x0010, 0, 0, 0, 0)      # RIGHTUP
time.sleep(0.8)

after = ball(pid)
print(f"右键后: {'窗口已隐藏 OK' if after and not after[2] else ('窗口仍可见 FAIL' if after else '窗口已销毁')}")
