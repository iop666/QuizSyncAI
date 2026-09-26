"""协议 schema 与服务端实际表结构的**列级 diff**。

背景（第十二轮）：服务端 `sessions` 没有 `ai_model`、`questions.answer_text` 却是 NOT NULL ——
协议 schema 里后者是 NULL 可空。也就是说服务端跑的是**另一套投影**，与「三端照同一份纸实现」冲突。
在决定改哪边之前，先把差异量化出来。
"""

import io
import os
import re
import sqlite3
import sys

# 路径一律从参数或环境变量来 —— **不要把开发机的绝对路径写进仓库**
# （这条被仓库卫生自检抓到过一次）。用法：
#   python tools/schema_diff.py <协议仓目录> <服务端库文件>
_protocol = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("QS_PROTOCOL_DIR", "")).strip()
_server_db = (sys.argv[2] if len(sys.argv) > 2 else os.environ.get("QS_SERVER_DB", "")).strip()
if not _protocol or not _server_db:
    raise SystemExit(
        "用法：python tools/schema_diff.py <协议仓目录> <服务端库文件>\n"
        "（也可用环境变量 QS_PROTOCOL_DIR / QS_SERVER_DB）"
    )

PROTOCOL = os.path.join(_protocol, "schema", "schema-v1.sql")
SERVER_DB = _server_db


def parse_protocol(path: str) -> dict[str, dict[str, dict]]:
    """{表: {列: {"notnull": bool, "default": str|None}}}"""
    text = io.open(path, encoding="utf-8").read()
    tables: dict[str, dict[str, dict]] = {}
    for match in re.finditer(r'CREATE TABLE IF NOT EXISTS "(\w+)"\s*\((.*?)\n\);', text, re.S):
        name, body = match.group(1), match.group(2)
        columns: dict[str, dict] = {}
        for line in body.splitlines():
            line = line.strip().rstrip(",")
            col = re.match(r'"(\w+)"\s+([A-Z]+)(.*)$', line)
            if not col:
                continue
            rest = col.group(3)
            columns[col.group(1)] = {
                "notnull": "NOT NULL" in rest,
                "default": (re.search(r"DEFAULT\s+('[^']*'|\S+)", rest) or [None, None])[1],
            }
        tables[name] = columns
    return tables


def read_sqlite(path: str) -> dict[str, dict[str, dict]]:
    con = sqlite3.connect("file:" + path + "?mode=ro", uri=True)
    tables: dict[str, dict[str, dict]] = {}
    names = [r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    for name in names:
        columns: dict[str, dict] = {}
        for row in con.execute(f'PRAGMA table_info("{name}")'):
            # row = (cid, name, type, notnull, dflt_value, pk)
            columns[row[1]] = {"notnull": bool(row[3]), "default": row[4]}
        tables[name] = columns
    con.close()
    return tables


protocol = parse_protocol(PROTOCOL)
server = read_sqlite(SERVER_DB)

print(f"协议 schema: {len(protocol)} 张表，共 {sum(len(c) for c in protocol.values())} 列")
print(f"服务端实际: {len(server)} 张表，共 {sum(len(c) for c in server.values())} 列")

only_protocol = sorted(set(protocol) - set(server))
only_server = sorted(set(server) - set(protocol))
print(f"\n只在协议里（服务端缺整张表） {len(only_protocol)}: {only_protocol}")
print(f"只在服务端里（协议没定义） {len(only_server)}: {only_server}")

print("\n########## 共有的表：列级差异 ##########")
total_missing = total_extra = total_tightened = 0
for name in sorted(set(protocol) & set(server)):
    p, s = protocol[name], server[name]
    missing = sorted(set(p) - set(s))
    extra = sorted(set(s) - set(p))
    tightened = []
    for col in sorted(set(p) & set(s)):
        if s[col]["notnull"] and not p[col]["notnull"]:
            tightened.append(col)
    if not (missing or extra or tightened):
        continue
    total_missing += len(missing)
    total_extra += len(extra)
    total_tightened += len(tightened)
    print(f"\n-- {name} --")
    if missing:
        print(f"   服务端缺列 {len(missing)}: {missing}")
    if extra:
        print(f"   服务端多列 {len(extra)}: {extra}")
    if tightened:
        print(f"   [!!] 服务端要求 NOT NULL 而协议可空 {len(tightened)}: {tightened}")

print(f"\n合计：协议有而服务端缺 {total_missing} 列；服务端多出 {total_extra} 列；"
      f"服务端额外收紧 NOT NULL {total_tightened} 列")
