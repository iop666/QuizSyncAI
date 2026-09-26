# 数据模型与同步算法

两端使用**同一份** drift schema 定义（位于 `packages/quizsync_core/lib/db/`），两端表结构完全一致，差异只在数据量级（Windows 是全量主库，Android 是本地缓存但同样保留全部历史）。

---

## 1. 表结构

```sql
-- 已配对设备 / 已知节点
CREATE TABLE devices (
  device_id     TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  platform      TEXT NOT NULL,            -- 'windows' | 'android'
  token_hash    TEXT,                     -- 仅 Windows 存：token 的 sha256；Android 存 NULL
  paired_at     INTEGER NOT NULL,         -- UTC ms
  last_seen_at  INTEGER,
  revoked_at    INTEGER,                  -- 非空表示已吊销
  app_version   TEXT
);

-- 图片元数据（文件单独存放）
CREATE TABLE images (
  hash          TEXT PRIMARY KEY,         -- sha256(压缩后字节)
  size          INTEGER NOT NULL,
  mime          TEXT NOT NULL,
  width         INTEGER,
  height        INTEGER,
  local_path    TEXT,                     -- 本机文件路径；该端没有文件时为 NULL（可后台补传）
  created_at    INTEGER NOT NULL,
  uploaded_by   TEXT NOT NULL             -- device_id
);
CREATE INDEX idx_images_created ON images(created_at);

-- 任务合集（用户需求 8）：一次任务的全部识别记录归入一个合集
CREATE TABLE collections (
  collection_id TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  updated_by    TEXT NOT NULL,
  lamport       INTEGER NOT NULL,
  field_clocks_json TEXT NOT NULL DEFAULT '{}',
  deleted_at    INTEGER                 -- tombstone
);
CREATE INDEX idx_collections_created ON collections(created_at DESC);

-- 会话 = 一次识别 = 一条历史记录
CREATE TABLE sessions (
  session_id      TEXT PRIMARY KEY,
  task_id         TEXT,                   -- 发起端生成的幂等 id
  collection_id   TEXT,                   -- 所属合集；旧数据为 NULL = 未分类（用户需求 8）
  image_hash      TEXT NOT NULL,          -- 多页时 = 第一页
  source_device   TEXT NOT NULL,
  status          TEXT NOT NULL,          -- queued|analyzing|done|failed|cancelled
  error_code      TEXT,
  error_message   TEXT,
  ai_provider     TEXT,
  ai_model        TEXT,
  prompt_version  TEXT,
  raw_response    TEXT,                   -- 解析失败时保留原文
  cached          INTEGER NOT NULL DEFAULT 0,
  question_count  INTEGER NOT NULL DEFAULT 0,
  latency_ms      INTEGER,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  updated_by      TEXT NOT NULL,
  lamport         INTEGER NOT NULL,
  field_clocks_json TEXT NOT NULL DEFAULT '{}', -- 逐字段写入时钟，见 2.2
  deleted_at      INTEGER                 -- tombstone
);
CREATE INDEX idx_sessions_created ON sessions(created_at DESC);
CREATE INDEX idx_sessions_hash ON sessions(image_hash);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sessions_collection ON sessions(collection_id);

-- 会话的页图片（用户需求 4：多页题目一次识别）
CREATE TABLE session_images (
  session_image_id TEXT PRIMARY KEY,
  session_id       TEXT NOT NULL,
  ordinal          INTEGER NOT NULL,      -- 页序，0 起
  image_hash       TEXT NOT NULL,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  updated_by       TEXT NOT NULL,
  lamport          INTEGER NOT NULL,
  field_clocks_json TEXT NOT NULL DEFAULT '{}',
  deleted_at       INTEGER
);
CREATE INDEX idx_session_images_session ON session_images(session_id, ordinal);

-- 题目（会话内多题）
CREATE TABLE questions (
  question_id     TEXT PRIMARY KEY,
  session_id      TEXT NOT NULL,
  ordinal         INTEGER NOT NULL,       -- 会话内的顺序，0 起
  question_no     TEXT,                   -- 图中题号，可空
  stem            TEXT NOT NULL,
  material        TEXT NOT NULL DEFAULT '', -- 阅读材料/文章原文，端侧默认折叠（用户反馈 15）
  type            TEXT NOT NULL,          -- single|multi|judge|blank|subjective
  options_json    TEXT NOT NULL DEFAULT '[]',
  choice_json     TEXT NOT NULL DEFAULT '[]',  -- answer.choice
  answer_text     TEXT,                        -- answer.text
  analysis        TEXT NOT NULL DEFAULT '',
  confidence      REAL NOT NULL DEFAULT 0.5,
  need_review     INTEGER NOT NULL DEFAULT 0,
  answer_in_image INTEGER NOT NULL DEFAULT 0,
  incomplete      INTEGER NOT NULL DEFAULT 0,  -- 题目不全（用户需求 2）
  answer_guessed  INTEGER NOT NULL DEFAULT 0,  -- 答案是 AI 猜测（用户需求 2）
  warnings_json   TEXT NOT NULL DEFAULT '[]',
  analysis_edited INTEGER NOT NULL DEFAULT 0,  -- 字段级 user_edited 标记
  answer_edited   INTEGER NOT NULL DEFAULT 0,
  field_clocks_json TEXT NOT NULL DEFAULT '{}', -- 逐字段写入时钟，见 2.2
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  updated_by      TEXT NOT NULL,
  lamport         INTEGER NOT NULL,
  deleted_at      INTEGER
);
CREATE INDEX idx_questions_session ON questions(session_id, ordinal);
CREATE INDEX idx_questions_stem ON questions(stem);

-- 全文检索（Windows 用 FTS5；Android 若 FTS5 不可用可退化为 LIKE 查询）
CREATE VIRTUAL TABLE questions_fts USING fts5(
  stem, analysis, content='questions', content_rowid='rowid'
);

-- 操作日志：同步的唯一载体
CREATE TABLE sync_ops (
  op_id        TEXT PRIMARY KEY,          -- UUID v4
  device_id    TEXT NOT NULL,             -- 产生该 op 的设备
  lamport      INTEGER NOT NULL,
  entity       TEXT NOT NULL,             -- 'session' | 'question' | 'image' | 'device' | 'collection' | 'session_image' | 'snapshot'
  entity_id    TEXT NOT NULL,
  op_type      TEXT NOT NULL,             -- 'upsert' | 'delete'
  fields_json  TEXT NOT NULL,             -- 只含变更字段，字段级 LWW 的依据
  created_at   INTEGER NOT NULL
);
CREATE INDEX idx_ops_lamport ON sync_ops(device_id, lamport);
CREATE INDEX idx_ops_entity ON sync_ops(entity, entity_id);

-- 每个对端的同步水位线
CREATE TABLE peer_state (
  peer_device_id    TEXT PRIMARY KEY,
  sent_lamport      INTEGER NOT NULL DEFAULT 0,   -- 我已推送到该对端的最大 lamport
  acked_lamport     INTEGER NOT NULL DEFAULT 0,   -- 该对端已确认收到的最大 lamport
  last_sync_at      INTEGER
);

-- 分析任务（离线队列也在其中）
CREATE TABLE tasks (
  task_id       TEXT PRIMARY KEY,         -- 发起端生成的 UUID v4，保证幂等
  image_hash    TEXT NOT NULL,            -- 多页时 = 第一页
  source_device TEXT NOT NULL,
  status        TEXT NOT NULL,            -- queued|analyzing|done|failed|cancelled
  attempts      INTEGER NOT NULL DEFAULT 0,
  error_code    TEXT,
  session_id    TEXT,
  created_at    INTEGER NOT NULL,
  started_at    INTEGER,
  finished_at   INTEGER,
  payload_json  TEXT                      -- 本端协调用：{"image_hashes":[...],"collection_id":"..."}
);
CREATE INDEX idx_tasks_status ON tasks(status, created_at);

-- 本机设置（不含密钥）
CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- AI 用量与配额
CREATE TABLE ai_usage (
  id             TEXT PRIMARY KEY,
  called_at      INTEGER NOT NULL,
  model          TEXT NOT NULL,
  prompt_version TEXT NOT NULL,
  image_hash     TEXT NOT NULL,
  ok             INTEGER NOT NULL,
  error_code     TEXT,
  latency_ms     INTEGER
);
CREATE INDEX idx_usage_called ON ai_usage(called_at);
```

**明文密钥绝不入库。** AI API Key 用 `flutter_secure_storage`；Android 的 token 同样走安全存储，Windows 端只存 `devices.token_hash`。

---

## 2. 同步算法

### 2.1 Lamport 时钟

- 每个节点维护一个本地计数器 `clock`。
- 本地写入：`clock = clock + 1`，新记录的 `lamport = clock`。
- 收到对端 op：`clock = max(clock, max(收到的 lamport)) + 1`。
- 排序规则：先比 `lamport`，相同则比 `device_id` 的字典序。**绝不用设备墙钟排序**，墙钟只用于展示。

### 2.2 字段级 LWW

- 每条 op 的 `fields_json` **只含本次真正改动的字段**。
- 每行额外保存 `field_clocks_json`，形如 `{"stem": {"l": 12, "d": "dev-a"}, "answer_text": {"l": 15, "d": "dev-b"}}`，只记录被显式写过的字段。
- 应用 op 时逐字段比较：

```
对 op.fields_json 里的每个字段 f：
    cur = field_clocks_json[f]
    if (cur 存在 && (op.lamport, op.device_id) <= (cur.l, cur.d)):
        跳过该字段                            # 已有更新的写入
    else:
        写入 f 的值
        field_clocks_json[f] = { l: op.lamport, d: op.device_id }

行级 lamport / updated_by 更新为所有字段时钟中的最大值（用于列表排序与 tombstone 比较）
```

- 字段从未被单独记录过时（`cur` 不存在），以该行的 `lamport` / `updated_by` 作为基准比较，即「整体写入」与「字段写入」可以正确比较先后。

这样「两端分别修改同一题的不同字段」两个改动都能保留，而「同时改同一字段」由时间戳决胜。

### 2.3 `user_edited` 保护

- 用户在 UI 上修改答案或解析 → 置对应 `*_edited = 1`。
- 收到 AI 重新分析的结果时：`answer_edited == 1` 则不覆盖答案字段，`analysis_edited == 1` 则不覆盖解析字段；并在 UI 上给出「AI 已给出新结果，是否覆盖？」的入口，用户点击才覆盖并清除标记。

### 2.4 图片策略

- `images` 的元数据随 op 同步（不含文件本身）。
- `local_path` 为 NULL 表示本端没有文件 → 后台按 `created_at` 倒序补传，一次最多 5 张，最近约 200 张为止。
- 补传成功后写入 `local_path`，本身**不产生 op**（避免无谓同步）。
- 本地文件清理：超过上限时删除最旧的本地文件并把 `local_path` 置 NULL（文本结果与元数据永久保留）。

### 2.5 水位线与增量拉取

- 每个对端一条 `peer_state`。
- 推送：客户端把 `lamport > peer_state.sent_lamport` 且属于本机的 op 推给对端，成功后更新 `sent_lamport`。
- 确认：对端在 WS 上发 `ack` 或在 HTTP 推送响应里回水位线，更新 `acked_lamport`。
- 拉取：`GET /api/v1/sync/ops?since_lamport=<本地已见最大>&from_device=<peer>` 分页拉取，每页最多 500 条，返回 `next_cursor`，直到 `has_more == false`。
- 断线重连：先拉后推，避免缺口。

### 2.6 快照折叠（防止 ops 无限增长）

- 触发条件：单个 `device_id` 的 `sync_ops` 行数 > 5000，**且**该设备的所有对端 `acked_lamport` 都已越过其中最早的一批。
- 动作：把所有对端都已确认的 op 折叠为一条 `snapshot` 记录（`sync_ops.entity = 'snapshot'`，payload 为被折叠到的 `lamport` 水位），并删除这些 op 行。快照本身保留最近一次即可。
- 新设备 bootstrap：`GET /api/v1/sync/snapshot` 返回全量实体（分页），新设备导入后把 `peer_state` 的水位线设为快照水位，之后只走增量。**不通过重放全部历史 op 来 bootstrap。**

### 2.7 Tombstone 与 GC

- 删除即写 `deleted_at`，并产生 `op_type = 'delete'` 的 op。
- 物理清理条件：`deleted_at` 距今超过 **30 天**，且所有对端的 `acked_lamport` 已越过该删除 op。不满足就继续保留。
- 查询一律带 `WHERE deleted_at IS NULL`（FTS 查询同样要 join 排除，避免搜到已删除内容）。

### 2.8 离线队列

- Android 在 Windows 不在线时：图片与文本入库，`tasks.status = 'queued'`，`sessions.status = 'queued'`。
- 多页与合集归属必须一起入队：`tasks.payload_json` 记 `{"image_hashes":[...],"collection_id":"..."}`，补跑时原样还原（用户需求 4/8）。
- Windows 上线（WS 连接建立）后：Android 按 `created_at` 顺序上传图片与创建任务，每个任务单独幂等（`task_id` 已定）。
- 队列上限：默认 20 条，超出时提示用户并拒绝新任务入队（避免无限堆积）。
- 任务成功后更新本地会话状态并通知用户。

### 2.9 冲突场景与预期结果（测试必须覆盖）

| 场景 | 预期 |
|---|---|
| 两端同时改同一题的同一字段 | 时间戳大者胜，两端最终一致 |
| 两端分别改同一题的不同字段 | 两个改动都保留（字段级 LWW 的目的） |
| 用户手改答案，另一端 AI 重新分析 | 手改保留，另一端收到覆盖提示而非静默覆盖 |
| Android 离线删除了某会话，Windows 同时修改了它 | 删除胜出（墓碑时间戳更大）或修改胜出，取决于时间戳；两端最终一致，不得出现一端删一端在的永久分叉 |
| 同一图片被两端各上传一次 | 按 hash 合并为一条 image 记录 |
| 收到重复 op | 按 `op_id` 忽略，不产生副作用 |

---

## 3. 迁移

- 用 drift 的 `MigrationStrategy`，`schemaVersion` 从 1 开始。
- 每次改表必须写 `onUpgrade` 迁移，并在 `packages/quizsync_core/test/db/migration_test.dart` 里覆盖「从上一版升级后数据不丢」。
- 两端共用同一 schema 定义，因此 `schemaVersion` 必须同步递增；Windows 与 Android 的版本不一致时，手机端应在 UI 上提示「主机数据库版本较新/较旧」，而不是直接崩。

### 当前版本：**3**（用户需求 2/4/8 + 用户反馈 15）

v1 → v2 的 `onUpgrade`：

| 变更 | 说明 |
|---|---|
| `CREATE TABLE collections` | 任务合集 |
| `CREATE TABLE session_images` | 多页页序 |
| `ALTER TABLE sessions ADD collection_id` | 可空；旧记录 = 未分类 |
| `ALTER TABLE questions ADD incomplete` | 默认 0 |
| `ALTER TABLE questions ADD answer_guessed` | 默认 0 |
| `ALTER TABLE tasks ADD payload_json` | 可空；离线队列的多页/合集参数 |

v2 → v3 的 `onUpgrade`：

| 变更 | 说明 |
|---|---|
| `ALTER TABLE questions ADD material` | 默认 `''`；阅读类题目的材料（用户反馈 15），旧题目 = 无材料 |

全部为**新增表 / 可空列 / 带默认值列**，旧数据不丢（`migration_test.dart` 用真实 v1 文件库断言往返，并断言升级后 `material` 为空）。

---

## 4. 测试要求（M1 起）

1. `sync_ops` 的生成：每次 upsert / delete 都必须恰好产生 1 条 op，字段只含变更项。
2. Lamport 单调递增；收到较大 lamport 后本地时钟被推高。
3. 字段级 LWW：覆盖 2.9 表格里的前两行场景。
4. `user_edited` 保护：AI 覆盖请求不改变已手改字段。
5. Tombstone：`deleted_at` 后查询不可见，FTS 也搜不到。
6. 快照折叠：构造 5001 条 op + 对端已确认，断言折叠后行数下降且增量拉取仍能拿到最新状态。
7. 离线队列：模拟对端离线 → 入队 → 上线 → 按序处理 → 断言最终状态一致。
