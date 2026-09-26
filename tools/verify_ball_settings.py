"""按 ball.json 的配置启动，量球的尺寸/可见性 —— 验「设置真的生效」。"""

import ctypes
import ctypes.wintypes as wt
import json
import os
import subprocess
import time

import sys

# 路径走参数 —— 不把开发机绝对路径写进仓库（卫生自检会红）。
EXE = sys.argv[1] if len(sys.argv) > 1 else "QuizSync.App.exe"
BALL = os.environ.get("QS_BALL_JSON", os.path.join(os.environ["LOCALAPPDATA"], "QuizSyncAI", "app", "ball.json"))

ctypes.windll.shcore.SetProcessDpiAwareness(2)  # 不这样做量到的是虚拟化坐标（差 2 倍）
user32 = ctypes.windll.user32


def write(enabled, diameter, opacity):
    with open(BALL, "w", encoding="utf-8") as handle:
        json.dump({"enabled": enabled, "diameter": diameter, "opacity": opacity}, handle)


def measure():
    subprocess.run(["taskkill", "/IM", "QuizSync.App.exe", "/F"], capture_output=True)
    time.sleep(1)
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
                found.append((rect.right - rect.left, rect.bottom - rect.top,
                              (rect.left, rect.top), bool(user32.IsWindowVisible(hwnd))))
        return True

    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(callback), 0)
    return found


for enabled, diameter, opacity, expect in ((True, 72, 100, "直径应为 72"),
                                           (True, 96, 60, "直径应为 96"),
                                           (False, 72, 100, "不该有球窗口")):
    write(enabled, diameter, opacity)
    time.sleep(0.3)
    result = measure()
    print(f"配置 enabled={enabled} diameter={diameter} opacity={opacity}  ({expect})")
    print(f"  实测球窗口: {result if result else '没有'}")
