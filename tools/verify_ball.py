"""验证悬浮球：(1) 像素真的画出来了没（PrintWindow 回读，不用 GDI 截屏）(2) 点它能不能触发识别。"""

import ctypes
import ctypes.wintypes as wt
import os
import sqlite3
import subprocess
import time

import sys

# 路径走参数/环境变量 —— 不把开发机绝对路径写进仓库（卫生自检会红）。
EXE = sys.argv[1] if len(sys.argv) > 1 else "QuizSync.App.exe"
DB = os.environ.get("QS_APP_DB", os.path.join(os.environ["LOCALAPPDATA"], "QuizSyncAI", "app", "quizsync.db"))
TMP = os.environ.get("QS_TMP", os.path.dirname(os.path.abspath(__file__)))
# **先把自己变成 DPI-aware**：不这样做的话 GetWindowRect 返回的是虚拟化（逻辑）坐标，
# 本机 200% 缩放下会差 2 倍 —— 上一轮'球尺寸 28 而不是 56'很可能就是这么来的（AGENTS.md 记过这一条）。
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)  # PROCESS_PER_MONITOR_DPI_AWARE
    print('已设为 per-monitor DPI aware')
except Exception as error:
    print('设 DPI awareness 失败:', error)

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32


def sessions():
    con = sqlite3.connect("file:" + DB + "?mode=ro", uri=True)
    value = con.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    con.close()
    return value


def find_ball(pid):
    result = []

    def callback(hwnd, _):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            if cls.value == "QuizSyncFloatingBall":
                rect = wt.RECT()
                user32.GetWindowRect(hwnd, ctypes.byref(rect))
                result.append((hwnd, rect))
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(callback), 0)
    return result[0] if result else (None, None)


subprocess.run(["taskkill", "/IM", "QuizSync.App.exe", "/F"], capture_output=True)
time.sleep(1)
# 桩 AI + 服务端
subprocess.Popen(["python", os.path.join(TMP, "fake_ai.py"), "9099", os.path.join(TMP, "ai_req13.json")],
                 creationflags=0x08000000)
                  "run"], creationflags=0x08000000)
time.sleep(9)

before = sessions()
subprocess.Popen([EXE])
time.sleep(9)

out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq QuizSync.App.exe", "/FO", "CSV", "/NH"],
                     capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
pid = int(out.strip().split('","')[1])
hwnd, rect = find_ball(pid)
print("球窗口:", hwnd, "矩形:", (rect.left, rect.top, rect.right, rect.bottom))

# (1) 像素：PrintWindow 回读中心
dc = user32.GetDC(0)
mem = gdi32.CreateCompatibleDC(dc)
width, height = rect.right - rect.left, rect.bottom - rect.top
bitmap = gdi32.CreateCompatibleBitmap(dc, width, height)
gdi32.SelectObject(mem, bitmap)
user32.PrintWindow(hwnd, mem, 2)
center = gdi32.GetPixel(mem, width // 2, height // 2)
edge = gdi32.GetPixel(mem, 1, 1)
gdi32.DeleteObject(bitmap)
gdi32.DeleteDC(mem)
user32.ReleaseDC(0, dc)
print(f"球中心像素: 0x{center:06X}（要的是 brand green #35693E 的 BGR = 0x3E6935）")
print(f"球左上角像素: 0x{edge:06X}（圆外应接近透明/黑）")

# (2) 点击中心
cx, cy = (rect.left + rect.right) // 2, (rect.top + rect.bottom) // 2
user32.SetCursorPos(cx, cy)
time.sleep(0.3)
user32.mouse_event(0x0002, 0, 0, 0, 0)   # LEFTDOWN
time.sleep(0.08)
user32.mouse_event(0x0004, 0, 0, 0, 0)   # LEFTUP
print(f"已点击球中心 ({cx},{cy})，等待识别…")
time.sleep(16)
print("会话数:", before, "->", sessions())
