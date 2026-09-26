"""按 device_id 精确区分「App 推的 op」与「我探针推的 op」，检查中文是否完整。"""

import io
import json
import sqlite3

import os
import sys

# 路径走参数/环境变量 —— 不把开发机绝对路径写进仓库（卫生自检会红）。
DB = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get('QS_SERVER_DB', '')).strip()
if not DB:
    raise SystemExit('用法：python tools/check_utf8_push.py 服务端库文件（或设 QS_SERVER_DB）')
con = sqlite3.connect("file:" + DB + "?mode=ro", uri=True)

print("-- sync_ops 按 device_id 分组 --")
for row in con.execute("SELECT device_id, COUNT(*) FROM sync_ops GROUP BY device_id"):
    print(f"   {row[0]:<18} {row[1]} 条")

print("\n-- windows-desktop（App 自己推的）的 question op 里的 stem --")
bad = 0
for op_id, fields in con.execute(
    "SELECT op_id, fields_json FROM sync_ops WHERE device_id = 'windows-desktop' AND entity = 'question'"
):
    stem = json.loads(fields).get("stem", "")
    marker = "中文正常" if any("\u4e00" <= ch <= "\u9fff" for ch in stem) else "★没有中文或已损坏"
    if marker != "中文正常":
        bad += 1
    print(f"   {op_id[:26]:<28} {marker}  {stem[:40]!r}")

print("\n-- 服务端 questions 表里来自 App 的会话 --")
for row in con.execute(
    "SELECT q.question_id, q.stem FROM questions q JOIN sessions s ON s.session_id = q.session_id "
    "WHERE s.source_device = 'windows-desktop'"
):
    print("   ", repr(row[1])[:70])

con.close()
print("\n结论:", "App 推送的中文完整" if bad == 0 else f"有 {bad} 条 op 的中文有问题")
