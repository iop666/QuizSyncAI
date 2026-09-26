-- ============================================================================
-- QuizSyncProtocol · 本地数据库 schema（SQLite）
-- 文件：schema-v1.sql          版本：schema_version = 3
-- ----------------------------------------------------------------------------
-- 用途：三端（主机 / 客户端 / 独立服务端）各自持有一个本地库，结构必须逐字一致。
--       本文件是**物理契约**：表名、列名、列序、类型、NOT NULL、默认值、主键、
--       CHECK、索引名与同步语义全部在这里；同步算法（Lamport / 逐字段 LWW /
--       墓碑 / 水位 / 快照）见 spec/06-sync.md。
-- 权威：DDL 与现有实现建库时执行的语句逐字一致（含标识符的双引号、可空列的
--       显式 NULL、布尔列的 CHECK ("c" IN (0, 1))）。结构化形态见 schema-v1.json。
-- 约定：
--   * 时间戳一律是 UTC 毫秒的 INTEGER，列名以 _at 结尾；
--   * id 一律是 TEXT（UUID v4 或 hash），不用自增整数；
--   * 布尔列落成 INTEGER 0/1，并带 CHECK 约束；
--   * *_json 列存 JSON 文本（形态见 README 与 schema-v1.json 的 json_shape）；
--   * 实现**没有**建任何 FOREIGN KEY 约束，*_id 列是逻辑引用（无级联、无校验）；
--   * 行内注释仅供阅读，不参与结构比对。
-- 版本：schema_version 记在 SQLite 的 PRAGMA user_version 上（见文件末尾）。
-- ============================================================================

-- ===================== 表 =====================

-- ------------------------------------------------------------------------
-- devices —— 已配对设备 / 已知节点（每个 device_id 一行）。
-- [同步] 参与：op.entity = 'device'。本表没有 lamport / field_clocks_json 列，
--         因此不做字段级 LWW —— 按主键合并、后到者写入；revoked_at 一旦非空，
--         不被不含 revoked_at 的远端写入复活。
-- [本地] token_hash 是本地专属列：不进 op，也不被远端 op 覆盖。
CREATE TABLE IF NOT EXISTS "devices" (
  "device_id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "platform" TEXT NOT NULL,
  "token_hash" TEXT NULL,
  "paired_at" INTEGER NOT NULL,
  "last_seen_at" INTEGER NULL,
  "revoked_at" INTEGER NULL,
  "app_version" TEXT NULL,
  PRIMARY KEY ("device_id")
);

-- ------------------------------------------------------------------------
-- images —— 图片元数据（文件字节单独存放，库里只有 hash 与元数据）。
-- [同步] 参与：op.entity = 'image'。本表没有 lamport / field_clocks_json 列，
--         因此不做字段级 LWW —— 按主键（hash）合并、后到者写入。
-- [本地] local_path 是本地专属列：不进 op，也不被远端 op 覆盖。
--         NULL = 本端没有这个文件（可后台补传后写回，补传本身不产生 op）。
CREATE TABLE IF NOT EXISTS "images" (
  "hash" TEXT NOT NULL,
  "size" INTEGER NOT NULL,
  "mime" TEXT NOT NULL,
  "width" INTEGER NULL,
  "height" INTEGER NULL,
  "local_path" TEXT NULL,
  "created_at" INTEGER NOT NULL,
  "uploaded_by" TEXT NOT NULL,
  PRIMARY KEY ("hash")
);

-- ------------------------------------------------------------------------
-- collections —— 任务合集：一次任务的全部识别记录归入一个合集。
-- [同步] 参与：op.entity = 'collection'；字段级 LWW（lamport + field_clocks_json + updated_by）；
--         deleted_at 是墓碑（软删除）。
CREATE TABLE IF NOT EXISTS "collections" (
  "collection_id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "updated_by" TEXT NOT NULL,
  "lamport" INTEGER NOT NULL DEFAULT 0,
  "field_clocks_json" TEXT NOT NULL DEFAULT '{}',
  "deleted_at" INTEGER NULL,
  PRIMARY KEY ("collection_id")
);

-- ------------------------------------------------------------------------
-- sessions —— 会话：一次识别 = 一条历史记录。
-- [同步] 参与：op.entity = 'session'；字段级 LWW；deleted_at 是墓碑。
--         多页识别时 image_hash = 第一页，页序见 session_images；
--         collection_id 可空 = 未分类（旧数据）。
-- [本地] 无：本表所有列都在 op 的字段域内。
CREATE TABLE IF NOT EXISTS "sessions" (
  "session_id" TEXT NOT NULL,
  "task_id" TEXT NULL,
  "collection_id" TEXT NULL,
  "image_hash" TEXT NOT NULL,
  "source_device" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "error_code" TEXT NULL,
  "error_message" TEXT NULL,
  "ai_provider" TEXT NULL,
  "ai_model" TEXT NULL,
  "prompt_version" TEXT NULL,
  "raw_response" TEXT NULL,
  "cached" INTEGER NOT NULL DEFAULT 0 CHECK ("cached" IN (0, 1)),
  "question_count" INTEGER NOT NULL DEFAULT 0,
  "latency_ms" INTEGER NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "updated_by" TEXT NOT NULL,
  "lamport" INTEGER NOT NULL DEFAULT 0,
  "field_clocks_json" TEXT NOT NULL DEFAULT '{}',
  "deleted_at" INTEGER NULL,
  PRIMARY KEY ("session_id")
);

-- ------------------------------------------------------------------------
-- session_images —— 会话的一页图片（多页题目一次识别）。
-- [同步] 参与：op.entity = 'session_image'；字段级 LWW；deleted_at 是墓碑。
--         ordinal 是会话内的页序，0 起。
CREATE TABLE IF NOT EXISTS "session_images" (
  "session_image_id" TEXT NOT NULL,
  "session_id" TEXT NOT NULL,
  "ordinal" INTEGER NOT NULL,
  "image_hash" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "updated_by" TEXT NOT NULL,
  "lamport" INTEGER NOT NULL DEFAULT 0,
  "field_clocks_json" TEXT NOT NULL DEFAULT '{}',
  "deleted_at" INTEGER NULL,
  PRIMARY KEY ("session_image_id")
);

-- ------------------------------------------------------------------------
-- questions —— 题目（会话内多题，ordinal 从 0 起）。
-- [同步] 参与：op.entity = 'question'；字段级 LWW；deleted_at 是墓碑。
--         analysis_edited / answer_edited 是「用户已手改」标记，保护对应字段
--         不被后到的 AI 结果覆盖。
-- [本地] 无。
CREATE TABLE IF NOT EXISTS "questions" (
  "question_id" TEXT NOT NULL,
  "session_id" TEXT NOT NULL,
  "ordinal" INTEGER NOT NULL,
  "question_no" TEXT NULL,
  "stem" TEXT NOT NULL,
  "material" TEXT NOT NULL DEFAULT '',
  "type" TEXT NOT NULL,
  "options_json" TEXT NOT NULL DEFAULT '[]',
  "choice_json" TEXT NOT NULL DEFAULT '[]',
  "answer_text" TEXT NULL,
  "analysis" TEXT NOT NULL DEFAULT '',
  "confidence" REAL NOT NULL DEFAULT 0.5,
  "need_review" INTEGER NOT NULL DEFAULT 0 CHECK ("need_review" IN (0, 1)),
  "answer_in_image" INTEGER NOT NULL DEFAULT 0 CHECK ("answer_in_image" IN (0, 1)),
  "incomplete" INTEGER NOT NULL DEFAULT 0 CHECK ("incomplete" IN (0, 1)),
  "answer_guessed" INTEGER NOT NULL DEFAULT 0 CHECK ("answer_guessed" IN (0, 1)),
  "warnings_json" TEXT NOT NULL DEFAULT '[]',
  "analysis_edited" INTEGER NOT NULL DEFAULT 0 CHECK ("analysis_edited" IN (0, 1)),
  "answer_edited" INTEGER NOT NULL DEFAULT 0 CHECK ("answer_edited" IN (0, 1)),
  "field_clocks_json" TEXT NOT NULL DEFAULT '{}',
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "updated_by" TEXT NOT NULL,
  "lamport" INTEGER NOT NULL DEFAULT 0,
  "deleted_at" INTEGER NULL,
  PRIMARY KEY ("question_id")
);

-- ------------------------------------------------------------------------
-- sync_ops —— 操作日志：同步的唯一载体。
-- [同步] 本表自身不同步，它就是同步的载荷：本机产生的 op 与从对端拉回并转存的
--         op 都存这里，后者保留原 device_id（推送时只推 device_id = 本机的 op）。
-- [索引] idx_ops_lamport(device_id, lamport) 是同步游标索引：
--         推送与拉取都是 WHERE device_id = ? AND lamport > ? ORDER BY lamport ASC LIMIT ?。
--         idx_ops_entity(entity, entity_id) 用于取某实体的最大 lamport（墓碑 GC 的确认判据）。
CREATE TABLE IF NOT EXISTS "sync_ops" (
  "op_id" TEXT NOT NULL,
  "device_id" TEXT NOT NULL,
  "lamport" INTEGER NOT NULL,
  "entity" TEXT NOT NULL,
  "entity_id" TEXT NOT NULL,
  "op_type" TEXT NOT NULL,
  "fields_json" TEXT NOT NULL,
  "created_at" INTEGER NOT NULL,
  PRIMARY KEY ("op_id")
);

-- ------------------------------------------------------------------------
-- peer_state —— 每个对端的同步水位线（本机协调状态，表名单数）。
-- [本地] 不同步：它描述的正是「本机与某个对端之间同步到哪了」。
--         注意：拉取游标不在本表，而在 settings 的 pull_cursor:<peer_device_id>。
CREATE TABLE IF NOT EXISTS "peer_state" (
  "peer_device_id" TEXT NOT NULL,
  "sent_lamport" INTEGER NOT NULL DEFAULT 0,
  "acked_lamport" INTEGER NOT NULL DEFAULT 0,
  "last_sync_at" INTEGER NULL,
  PRIMARY KEY ("peer_device_id")
);

-- ------------------------------------------------------------------------
-- tasks —— 分析任务（离线队列也在其中）。
-- [本地] 不同步：任务由发起端与主机各自管理，不产生 op。
--         payload_json 是入队时记下的额外参数，断网重连后原样补跑
--         （多页与合集归属没有独立列）。
CREATE TABLE IF NOT EXISTS "tasks" (
  "task_id" TEXT NOT NULL,
  "image_hash" TEXT NOT NULL,
  "source_device" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "error_code" TEXT NULL,
  "session_id" TEXT NULL,
  "created_at" INTEGER NOT NULL,
  "started_at" INTEGER NULL,
  "finished_at" INTEGER NULL,
  "payload_json" TEXT NULL,
  PRIMARY KEY ("task_id")
);

-- ------------------------------------------------------------------------
-- settings —— 本机设置与本地协调状态（不含密钥）。
-- [本地] 不同步：键值由各端自定。已知键见 README「本地专属列与本地专属表」一节。
CREATE TABLE IF NOT EXISTS "settings" (
  "key" TEXT NOT NULL,
  "value" TEXT NOT NULL,
  PRIMARY KEY ("key")
);

-- ------------------------------------------------------------------------
-- ai_usage —— AI 用量与配额（表名单数）。
-- [本地] 不同步：用量是每台机器自己的记账。
CREATE TABLE IF NOT EXISTS "ai_usage" (
  "id" TEXT NOT NULL,
  "called_at" INTEGER NOT NULL,
  "model" TEXT NOT NULL,
  "prompt_version" TEXT NOT NULL,
  "image_hash" TEXT NOT NULL,
  "ok" INTEGER NOT NULL CHECK ("ok" IN (0, 1)),
  "error_code" TEXT NULL,
  "latency_ms" INTEGER NULL,
  PRIMARY KEY ("id")
);

-- ===================== 索引 =====================

-- 缺文件的图片补传：按 created_at 倒序取最近 200 张。
CREATE INDEX idx_images_created ON images (created_at);

-- 合集列表按创建时间排序。
CREATE INDEX idx_collections_created ON collections (created_at);

-- 按合集分组（合集导出 / 合集内历史）。
CREATE INDEX idx_sessions_collection ON sessions (collection_id);

-- 历史列表按时间倒序。
CREATE INDEX idx_sessions_created ON sessions (created_at);

-- 按图片 hash 找会话（同图复用 / 缩略图反查）。
CREATE INDEX idx_sessions_hash ON sessions (image_hash);

-- 按状态过滤（queued / analyzing 的会话）。
CREATE INDEX idx_sessions_status ON sessions (status);

-- 取某会话的页序（session_id, ordinal）。
CREATE INDEX idx_session_images_session ON session_images (session_id, ordinal);

-- 取某会话的题目（session_id, ordinal）。
CREATE INDEX idx_questions_session ON questions (session_id, ordinal);

-- 题干前缀检索 / 退化 LIKE 检索。
CREATE INDEX idx_questions_stem ON questions (stem);

-- 取某实体的最大 lamport（墓碑 GC 的确认判据）。
CREATE INDEX idx_ops_entity ON sync_ops (entity, entity_id);

-- 同步游标索引：推送与拉取都按 (device_id, lamport) 递增翻页。
CREATE INDEX idx_ops_lamport ON sync_ops (device_id, lamport);

-- 按状态取任务（队列处理按 created_at 顺序）。
CREATE INDEX idx_tasks_status ON tasks (status, created_at);

-- 用量按时间统计。
CREATE INDEX idx_usage_called ON ai_usage (called_at);

-- ================= 全文检索（可选能力）=================

-- 外部内容虚表 + 三个触发器，与 questions 表保持同步。
-- 分词器是 trigram（子串匹配，中文可用）。引擎不支持 FTS5 / trigram 时，
-- 整段可以跳过：检索退化为 LIKE，其余功能不受影响。
-- questions_fts_* 影子表由引擎自动创建，不需要手写。
CREATE VIRTUAL TABLE IF NOT EXISTS questions_fts USING fts5(stem, analysis, content='questions', content_rowid='rowid', tokenize='trigram');
CREATE TRIGGER IF NOT EXISTS questions_fts_ad AFTER DELETE ON questions BEGIN INSERT INTO questions_fts(questions_fts, rowid, stem, analysis) VALUES ('delete', old.rowid, old.stem, old.analysis); END;
CREATE TRIGGER IF NOT EXISTS questions_fts_ai AFTER INSERT ON questions BEGIN INSERT INTO questions_fts(rowid, stem, analysis) VALUES (new.rowid, new.stem, new.analysis); END;
CREATE TRIGGER IF NOT EXISTS questions_fts_au AFTER UPDATE ON questions BEGIN INSERT INTO questions_fts(questions_fts, rowid, stem, analysis) VALUES ('delete', old.rowid, old.stem, old.analysis); INSERT INTO questions_fts(rowid, stem, analysis) VALUES (new.rowid, new.stem, new.analysis); END;

-- ===================== 版本标记 =====================

-- 建库或升级完成后写一次；应用启动时读它决定升级路径：
-- 比期望值小 → 走升级迁移；比期望值大 → 提示「主机数据库版本较新」，不要直接崩。
PRAGMA user_version = 3;

