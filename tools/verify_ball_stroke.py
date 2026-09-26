"""验证悬浮球描边：窗口尺寸 = 球 + 2×描边；环带颜色是加深后的主色。"""

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
gdi32 = ctypes.windll.gdi32


def probe(diameter, stroke, width):
    with open(BALL, "w", encoding="utf-8") as handle:
        json.dump({"enabled": True, "diameter": diameter, "opacity": 100,
                   "stroke": stroke, "stroke_width": width, "x": None, "y": None}, handle)

    subprocess.run(["taskkill", "/IM", "QuizSync.App.exe", "/F"], capture_output=True)
    time.sleep(1.2)
    subprocess.Popen([EXE])
    time.sleep(9)

    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq QuizSync.App.exe", "/FO", "CSV", "/NH"],
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    pid = int(out.strip().split('","')[1])
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
                found.append((hwnd, rect))
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(callback), 0)
    if not found:
        return None
    hwnd, rect = found[0]
    size = rect.right - rect.left

    dc = user32.GetDC(0)
    mem = gdi32.CreateCompatibleDC(dc)
    bitmap = gdi32.CreateCompatibleBitmap(dc, size, size)
    gdi32.SelectObject(mem, bitmap)
    user32.PrintWindow(hwnd, mem, 2)

    half = size // 2
    center = gdi32.GetPixel(mem, half, half)
    ring = gdi32.GetPixel(mem, width // 2 if stroke and width >= 2 else 0, half)
    corner = gdi32.GetPixel(mem, 0, 0)

    gdi32.DeleteObject(bitmap)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(0, dc)
    return size, center, ring, corner


for diameter, stroke, width, expect in ((40, True, 4, "窗口 48；中心=主色；x=2 处=加深主色"),
                                         (40, False, 4, "窗口 40；中心=主色"),
                                         (40, True, 8, "窗口 56；x=4 处=加深主色")):
    result = probe(diameter, stroke, width)
    print(f"球={diameter} 描边={stroke}/{width}  期望: {expect}")
    if result is None:
        print("  没有球窗口")
        continue
    size, center, ring, corner = result
    print(f"  实测窗口={size}x{size}  中心=0x{center:06X}  环带=0x{ring:06X}  角=0x{corner:06X}")
