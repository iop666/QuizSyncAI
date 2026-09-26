#!/usr/bin/env python3
"""仓库自检：不许出现「开发机专有」的内容。

红线（全部是实测踩过的）：
1. Windows 绝对路径（`D:\\...` / `C:/Users/...`）—— 泄漏开发机的目录结构；
2. 用户名 / 机型 / 真机序列号 / 局域网 IP —— 个人与设备信息；
3. 常见密钥形态（`sk-...`、`ghp_...`、`AKIA...`）—— 绝不能进仓库。

用法：
    python tools/check_no_machine_paths.py [仓库根目录]
默认仓库根 = 本脚本的上两级目录。命中即失败（退出码 1）。
跳过：二进制文件、`.git/`、构建产物目录。
"""
import os
import re
import subprocess
import sys
from pathlib import Path

# Windows 控制台默认是 GBK：带 emoji/特殊字符的行会让 print 抛 UnicodeEncodeError，
# 把「检查失败」变成「脚本崩了」。统一改成 UTF-8 + 替换不会写的字符。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PATTERNS = [
    # 匹配**整条**盘符路径（含 `\\` 转义写法），后面交给 is_synthetic_path 判定是不是单测里的假路径。
    (r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/][^\s\"'`)\],;]*", "Windows 绝对路径"),
    (r"/Users/[A-Za-z0-9._-]+", "macOS 用户目录"),
    (r"/home/[A-Za-z0-9._-]+", "Linux 用户目录"),
    # 只拦**非教科书**的私网地址：`192.168.0.x` / `192.168.1.x` 是文档里的常见示例，
    # 而真实网段（例如某台机器的 `192.168.101.x`）不该出现在仓库里。
    (r"\b192\.168\.(?!0\.|1\.)\d{1,3}\.\d{1,3}\b", "真实局域网 IP"),
    (r"\b10\.(?!0\.0\.)\d{1,3}\.\d{1,3}\.\d{1,3}\b", "内网 IP"),
    (r"\b172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b", "内网 IP"),
    (r"\bsk-[A-Za-z0-9]{16,}", "疑似 API Key"),
    (r"\bgh[pousr]_[A-Za-z0-9]{20,}", "疑似 GitHub Token"),
    (r"\bAKIA[0-9A-Z]{16}\b", "疑似 AWS Key"),
]

# 合成路径的判据：某个盘符路径的**每一段**都是通用词（没有项目名 / 工具名 / 用户名），
# 就算是单测里的假路径。像 `D:\ZCode\...`、`D:\Windows\Apps\...` 这类真实路径一定会因为
# `ZCode` / `Windows` 不在表里而被拦下。
GENERIC_COMPONENTS = {
    "app", "apps", "proj", "project", "rel", "me", "user", "users", "tmp", "temp", "test",
    "tests", "data", "logs", "log", "exports", "userdata", "share", "server", "srv", "config",
    "config.json", "cfg", "appdata", "roaming", "local", "quizsync", "x", "a", "b", "c", "d",
    "one", "two", "foo", "bar", "baz", "backup", "cache", "media", "images", "file.txt",
}


# 开发机的**特征标记**：任何文件里出现这些，一律报（这是真正的泄漏面）。
# 注意：**不要把任何真实用户名写进这里** —— 这个脚本本身也是公开的，写进去等于把
# 要藏的东西印在封面上（实测踩过）。用户名靠下面的「家目录路径」规则通用识别。
MACHINE_MARKERS = (
    "zcode", "windows\\apps", "windows/apps", "deepseekharness", "dsh_tools", "dshtools",
    "quizsync_ai-issue",
)

# 家目录路径：`C:\Users\<谁>` / `/Users/<谁>` / `/home/<谁>` —— 不写死具体是谁。
HOME_DIR = re.compile(r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/]Users[\\/][^\\/\s\"']+|/Users/[^/\s\"']+|/home/[^/\s\"']+")

# 通用占位用户名：文档与单测里常写 `C:\Users\me\...` 这类假路径，不算泄漏。
GENERIC_USERS = {"me", "user", "username", "yourname", "test", "tester", "runner", "someone", "<用户>", "<username>"}


def is_generic_home(line: str) -> bool:
    match = HOME_DIR.search(line)
    if not match:
        return False
    parts = [p for p in re.split(r"[\\/]+", match.group(0)) if p]
    return bool(parts) and parts[-1].lower() in GENERIC_USERS


def is_test_file(rel_posix: str) -> bool:
    lowered = rel_posix.lower()
    return ("/test/" in lowered or "/tests/" in lowered or lowered.startswith("test/")
            or lowered.endswith("_test.dart") or lowered.endswith("test.dart")
            or lowered.endswith("tests.cs") or "/src/test/" in lowered)


def is_synthetic_path(text: str) -> bool:
    """路径形如 `D:\\a\\b` 且每段都是通用词（或含插值占位）→ 单测里的合成路径。"""
    body = re.sub(r"^[A-Za-z]:", "", text)
    parts = [p for p in re.split(r"[\\/]+", body) if p]
    if not parts:
        return True  # 光秃秃的盘符根，例如 `C:\`
    for part in parts:
        if "$" in part or "{" in part or "%" in part:
            continue  # 模板/插值路径，例如 `C:/$hash.jpg`
        lowered = part.lower()
        if lowered in GENERIC_COMPONENTS:
            continue
        # 通用文件名（短名 + 常见扩展名），例如 `x.jpg` / `0.jpg` / `new.jpg`；
        # 项目名/工具名（`ZCode`、`QuizSyncAI_Server`）不会长这样，照样会被拦。
        if re.fullmatch(r"[a-z0-9_-]{1,4}\.[a-z0-9]{2,5}", lowered):
            continue
        return False
    return True


# 标准安装位置与占位符：任何 Windows 机器都一样，不算「开发机专有信息」。
ALLOW_PATH_PREFIXES = (
    "C:\\Program Files",
    "C:\\Program Files (x86)",
    "C:\\Windows",
    "%ProgramFiles%",
    "<盘符>",
)

SKIP_DIRS = {".git", "build", "dist", "node_modules", ".dart_tool", ".gradle", "bin", "obj", ".idea", "__pycache__"}

# **只在内部仓存在**的工作记录：它们本来就不导出（见发布流程），里面记着开发机路径与实测
# 环境，属于「内部资料」而不是「仓库卫生问题」。公开仓里没有这些文件，跳过不影响红线。
INTERNAL_ONLY = {
    "AGENTS.md",
    "docs/DECISIONS.md",
    "docs/progress.md",
    "docs/milestones.md",
    "docs/NATIVE-2.0-PLAN.md",
    "docs/DEV.md",
    "docs/optimization-plan.md",
    "docs/manual-test-android.md",
    "docs/agent-kickoff-prompt.md",
}
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".ico", ".ttf", ".otf", ".zip", ".apk", ".exe", ".dll", ".so", ".jar", ".keystore", ".jks", ".sqlite"}

# 允许出现的「示例」字样：行内含这些标记就不算命中（示例 IP / 占位路径）。
ALLOW_HINTS = (
    "示例", "例如", "example", "placeholder", "<用户", "<username>", "0.0.0.0",
    "sk-abcdef",  # 导出/脱敏测试里的假 Key
    "127.0.0.1",
)


def tracked_files(root: Path):
    """优先只查 git 跟踪的文件 —— 未跟踪的生成物（.dart_tool / local.properties）不该算命中。"""
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", check=True,
        ).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    names = [n for n in out.split("\0") if n.strip()]
    return [root / n for n in names] if names else None


def scan(root: Path):
    hits = []
    tracked = tracked_files(root)
    if tracked is None:
        candidates = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            candidates.extend(Path(dirpath) / name for name in filenames)
    else:
        candidates = tracked

    for path in candidates:
        if path.suffix.lower() in SKIP_SUFFIX or not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        rel_posix = path.relative_to(root).as_posix()
        # 本脚本自己要写着示例路径（允许列表），跳过它自身。
        if rel_posix == "tools/check_no_machine_paths.py":
            continue
        if rel_posix in INTERNAL_ONLY or rel_posix.startswith("docs/adr/"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if any(hint in line for hint in ALLOW_HINTS):
                continue
            if any(prefix in line for prefix in ALLOW_PATH_PREFIXES):
                continue
            for pattern, label in PATTERNS:
                match = re.search(pattern, line)
                if not match:
                    continue
                matched = match.group(0)
                lowered = matched.lower()
                # ① 命中开发机特征标记或**真实**家目录 → 一律报（不分文件类型）。
                if any(marker in lowered for marker in MACHINE_MARKERS) or (
                    HOME_DIR.search(line) and not is_generic_home(line)
                ):
                    hits.append((path.relative_to(root), lineno, label, line.strip()[:110]))
                    continue
                if label.startswith("Windows 绝对路径"):
                    # ② 单测里大量使用合成路径（`C:/img/h1.jpg` 这类），逐个认词表只会没完没了；
                    #    测试文件里只看特征标记，形状检查留给非测试文件。
                    if is_test_file(rel_posix):
                        continue
                    # ③ 非测试文件（源码 / 脚本 / 文档 / 工作流）里出现盘符路径就报。
                    if any(prefix in line for prefix in ALLOW_PATH_PREFIXES):
                        continue
                hits.append((path.relative_to(root), lineno, label, line.strip()[:110]))
    return hits


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    hits = scan(root)
    print(f"[机器信息自检] 扫描 {root}")
    if not hits:
        print("[机器信息自检] OK：没有开发机路径 / 个人设备信息 / 密钥形态")
        return 0
    print(f"[机器信息自检] FAIL：{len(hits)} 处")
    for rel, lineno, label, sample in hits[:40]:
        print(f"  - {rel}:{lineno} [{label}] {sample}")
    if len(hits) > 40:
        print(f"  ...（另有 {len(hits) - 40} 处）")
    return 1


if __name__ == "__main__":
    sys.exit(main())
