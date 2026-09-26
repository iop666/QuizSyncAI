"""协议 schema 与实际库的**列级 diff**（重写版，第三十轮）。

用法：python tools/schema_diff.py <协议仓目录> <库文件> [--verbose]
     也可用环境变量 QS_PROTOCOL_DIR / QS_SERVER_DB

## 为什么重写（重要）

旧版报「`session_images` 缺 `updated_at`/`updated_by`」，而**两种独立方式都证明那两列在**：
① 读写方式直接 `PRAGMA table_info` 查得到；② 服务端 56/56（INSERT 显式引用这两列，列不存在必报错）。
我在预算内**没能隔离出旧版的 bug**，于是按「宁可没有工具，也不要一个带假阳性的工具」把它换掉 ——
它上一轮差点让我回滚一个**已经修对**的改动。

新版刻意只做最简单的事：
* 协议侧：先定位每个 `CREATE TABLE` 的起点，再取到**下一个起点之前**（不跨块匹配）；
* 库侧：`PRAGMA table_info` 逐表读；
* 两边都**能打印出来**（`--verbose`），让结论可人工核对，而不是只给一句「缺 N 列」。

## 另一条实测前提

打开库**必须用读写方式**（不要 `mode=ro`）：服务端跑在 WAL 模式下，schema 可能还全在
`quizsync.db-wal` 里没 checkpoint（实测主文件 4096 字节 / WAL 210152 字节），
只读打开会看到残缺视图。下面只跑 SELECT / PRAGMA，不写库。
"""

import io
import os
import re
import sqlite3
import sys

protocol_dir = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("QS_PROTOCOL_DIR", "")
db_path = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("QS_SERVER_DB", "")
if not protocol_dir or not db_path:
    raise SystemExit("用法：python tools/schema_diff.py <协议仓目录> <库文件> [--verbose]"
                     "（或设 QS_PROTOCOL_DIR / QS_SERVER_DB）")

verbose = "--verbose" in sys.argv
schema_sql = os.path.join(protocol_dir, "schema", "schema-v1.sql")


def parse_protocol(path: str) -> dict:
    """{表: {列: {"notnull": bool}}}。按块切：下一个 CREATE TABLE 之前都属于当前表。"""
    text = io.open(path, encoding="utf-8").read()
    starts = list(re.finditer(r'CREATE TABLE IF NOT EXISTS "(\w+)"\s*\(', text))
    tables = {}
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        columns = {}
        for line in text[match.end():end].splitlines():
            column = re.match(r'"(\w+)"\s+([A-Z]+)(.*)$', line.strip().rstrip(","))
            if column:
                columns[column.group(1)] = {"notnull": "NOT NULL" in column.group(3)}
        tables[match.group(1)] = columns
    return tables


def read_database(path: str) -> dict:
    con = sqlite3.connect(path)  # 读写打开才能看到 WAL（见文件头）
    tables = {}
    names = [row[0] for row in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]
    for name in names:
        tables[name] = {row[1]: {"notnull": bool(row[3])}
                        for row in con.execute(f'PRAGMA table_info("{name}")')}
    con.close()
    return tables


protocol = parse_protocol(schema_sql)
database = read_database(db_path)

print(f"协议: {len(protocol)} 表 / {sum(len(c) for c in protocol.values())} 列")
print(f"实际: {len(database)} 表 / {sum(len(c) for c in database.values())} 列")

problem = 0
for name in sorted(set(protocol) | set(database)):
    if name not in protocol:
        print(f"\n-- {name} -- 只在库里（协议没定义）")
        problem += 1
        continue
    if name not in database:
        print(f"\n-- {name} -- 只在协议里（库里缺整张表）")
        problem += 1
        continue

    missing = sorted(set(protocol[name]) - set(database[name]))
    extra = sorted(set(database[name]) - set(protocol[name]))
    tightened = sorted(c for c in set(protocol[name]) & set(database[name])
                       if database[name][c]["notnull"] and not protocol[name][c]["notnull"])
    if not (missing or extra or tightened):
        if verbose:
            print(f"\n-- {name} -- 一致（{len(protocol[name])} 列）")
        continue

    problem += 1
    print(f"\n-- {name} --")
    if missing:
        print(f"   库里缺列: {missing}")
    if extra:
        print(f"   库里多列: {extra}")
    if tightened:
        print(f"   库里额外收紧 NOT NULL: {tightened}")

print("\n结论:" + ("没有差异" if problem == 0 else f"{problem} 张表存在差异"))
