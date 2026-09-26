"""量当前悬浮球窗口的尺寸与可见性（DPI-aware，避免又量到虚拟化坐标）。"""

import ctypes
import ctypes.wintypes as wt
import subprocess

ctypes.windll.shcore.SetProcessDpiAwareness(2)
user32 = ctypes.windll.user32

out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq QuizSync.App.exe", "/FO", "CSV", "/NH"],
                     capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
if '","' not in out:
    print("应用没在跑")
    raise SystemExit(1)

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
            found.append(((rect.right - rect.left, rect.bottom - rect.top),
                          (rect.left, rect.top), bool(user32.IsWindowVisible(hwnd))))
    return True


user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)(callback), 0)
print("实测球窗口:", found if found else "没有")
