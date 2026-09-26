import 'dart:io';

import 'package:drift/drift.dart'
    show
        OpeningDetails,
        QueryExecutor,
        QueryExecutorUser,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/db/offline_queue.dart';
import 'package:quizsync_core/db/open.dart';

import 'support.dart';

/// 只为把 v1 旧库「打开一次」用的最小 executor user。
class _V1User extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {}
}

/// v1 schema 的原始 DDL（`data-model.md` v1 快照）。
/// 手工建库 → 打开 v2 → 断言「升级后数据不丢 + 新列存在」。
const _v1Ddl = [
  "CREATE TABLE devices (device_id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, "
      "platform TEXT NOT NULL, token_hash TEXT NULL, paired_at INTEGER NOT NULL, "
      "last_seen_at INTEGER NULL, revoked_at INTEGER NULL, app_version TEXT NULL)",
  "CREATE TABLE images (hash TEXT NOT NULL PRIMARY KEY, size INTEGER NOT NULL, "
      "mime TEXT NOT NULL, width INTEGER NULL, height INTEGER NULL, local_path TEXT NULL, "
      "created_at INTEGER NOT NULL, uploaded_by TEXT NOT NULL)",
  "CREATE INDEX idx_images_created ON images (created_at)",
  "CREATE TABLE sessions (session_id TEXT NOT NULL PRIMARY KEY, task_id TEXT NULL, "
      "image_hash TEXT NOT NULL, source_device TEXT NOT NULL, status TEXT NOT NULL, "
      "error_code TEXT NULL, error_message TEXT NULL, ai_provider TEXT NULL, ai_model TEXT NULL, "
      "prompt_version TEXT NULL, raw_response TEXT NULL, cached INTEGER NOT NULL DEFAULT 0, "
      "question_count INTEGER NOT NULL DEFAULT 0, latency_ms INTEGER NULL, "
      "created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, updated_by TEXT NOT NULL, "
      "lamport INTEGER NOT NULL DEFAULT 0, field_clocks_json TEXT NOT NULL DEFAULT '{}', "
      "deleted_at INTEGER NULL)",
  "CREATE TABLE questions (question_id TEXT NOT NULL PRIMARY KEY, session_id TEXT NOT NULL, "
      "ordinal INTEGER NOT NULL, question_no TEXT NULL, stem TEXT NOT NULL, type TEXT NOT NULL, "
      "options_json TEXT NOT NULL DEFAULT '[]', choice_json TEXT NOT NULL DEFAULT '[]', "
      "answer_text TEXT NULL, analysis TEXT NOT NULL DEFAULT '', "
      "confidence REAL NOT NULL DEFAULT 0.5, need_review INTEGER NOT NULL DEFAULT 0, "
      "answer_in_image INTEGER NOT NULL DEFAULT 0, warnings_json TEXT NOT NULL DEFAULT '[]', "
      "analysis_edited INTEGER NOT NULL DEFAULT 0, answer_edited INTEGER NOT NULL DEFAULT 0, "
      "field_clocks_json TEXT NOT NULL DEFAULT '{}', created_at INTEGER NOT NULL, "
      "updated_at INTEGER NOT NULL, updated_by TEXT NOT NULL, "
      "lamport INTEGER NOT NULL DEFAULT 0, deleted_at INTEGER NULL)",
  "CREATE INDEX idx_questions_session ON questions (session_id, ordinal)",
  "CREATE TABLE sync_ops (op_id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL, "
      "lamport INTEGER NOT NULL, entity TEXT NOT NULL, entity_id TEXT NOT NULL, "
      "op_type TEXT NOT NULL, fields_json TEXT NOT NULL, created_at INTEGER NOT NULL)",
  "CREATE TABLE peer_state (peer_device_id TEXT NOT NULL PRIMARY KEY, "
      "sent_lamport INTEGER NOT NULL DEFAULT 0, acked_lamport INTEGER NOT NULL DEFAULT 0, "
      "last_sync_at INTEGER NULL)",
  "CREATE TABLE tasks (task_id TEXT NOT NULL PRIMARY KEY, image_hash TEXT NOT NULL, "
      "source_device TEXT NOT NULL, status TEXT NOT NULL, "
      "attempts INTEGER NOT NULL DEFAULT 0, error_code TEXT NULL, session_id TEXT NULL, "
      "created_at INTEGER NOT NULL, started_at INTEGER NULL, finished_at INTEGER NULL)",
  "CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)",
  "CREATE TABLE ai_usage (id TEXT NOT NULL PRIMARY KEY, called_at INTEGER NOT NULL, "
      "model TEXT NOT NULL, prompt_version TEXT NOT NULL, image_hash TEXT NOT NULL, "
      "ok INTEGER NOT NULL, error_code TEXT NULL, latency_ms INTEGER NULL)",
  "INSERT INTO sessions (session_id, image_hash, source_device, status, created_at, "
      "updated_at, updated_by, lamport) "
      "VALUES ('s-old', 'h-old', 'windows-local', 'done', 111, 111, 'windows-local', 3)",
  "INSERT INTO questions (question_id, session_id, ordinal, stem, type, created_at, "
      "updated_at, updated_by, lamport) "
      "VALUES ('q-old', 's-old', 0, '旧题干', 'single', 111, 111, 'windows-local', 4)",
];

void main() {
  test('schemaVersion == 3（data-model.md 第 3 节）', () async {
    final db = createTestDb();
    expect(db.schemaVersion, 3);
    await db.close();
  });

  test('v1 → v2 迁移：旧数据保留 + 新表新列就位', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await Directory.systemTemp.createTemp('quizsync-migrate-');
    final path = '${dir.path}/v1.db';
    // setup 回调在「打开时」执行：借此把 v1 结构写进文件，再关掉，
    // 得到一个真正处于 schemaVersion=1 的旧库。
    final raw = NativeDatabase(File(path), setup: (db) {
      for (final sql in _v1Ddl) {
        db.execute(sql);
      }
      db.execute('PRAGMA user_version = 1');
    });
    await raw.ensureOpen(_V1User());
    await raw.close();

    final db = openQuizSyncDb(path);
    // 触发迁移。
    final sessions = await db.select(db.sessions).get();
    expect(sessions.length, 1, reason: '迁移不得丢数据');
    expect(sessions.single.sessionId, 's-old');
    expect(sessions.single.collectionId, isNull, reason: '旧记录归为未分类');
    final questions = await db.select(db.questions).get();
    expect(questions.single.stem, '旧题干');
    expect(questions.single.incomplete, isFalse);
    expect(questions.single.answerGuessed, isFalse);
    // 用户反馈 15：v1 库升上来也要有 material 列，旧题目为空材料。
    expect(questions.single.material, '');

    // 新表可用。
    final collections =
        await db.customSelect('SELECT COUNT(*) AS c FROM collections').get();
    expect(collections.first.read<int>('c'), 0);
    final pages = await db.customSelect(
        'SELECT COUNT(*) AS c FROM session_images').get();
    expect(pages.first.read<int>('c'), 0);

    // M47 第 1 条：v1 库升上来也必须带 `tasks.payload_json`。
    // 原来 v1→v2 的迁移漏了这一列（`data-model.md` 的迁移表里有），
    // 从 v1 库升上来的机器一入离线队列就 `no such column: payload_json`。
    final taskCols = (await db.customSelect('PRAGMA table_info(tasks)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(taskCols, contains('payload_json'), reason: '缺 tasks.payload_json');
    final queued = await OfflineQueue(db).enqueue(
      imageHash: 'h-old',
      sourceDevice: 'android-test',
      imageHashes: const ['h-old', 'h-2'],
      collectionId: 'c-1',
    );
    expect(OfflineQueue.parsePayload(queued).imageHashes, ['h-old', 'h-2']);
    expect(OfflineQueue.parsePayload(queued).collectionId, 'c-1');

    await db.close();
    await dir.delete(recursive: true);
  });

  test('已标成 v3 但缺列的老库在打开时自愈（1.1.0 的历史遗留）', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final dir = await Directory.systemTemp.createTemp('quizsync-repair-');
    final path = '${dir.path}/v3-missing-column.db';
    // 复现历史缺陷：结构是 v1 的（tasks 没有 payload_json），
    // 但 user_version 已经被那一版写成了 3 —— onUpgrade 再也不会跑。
    final raw = NativeDatabase(File(path), setup: (db) {
      for (final sql in _v1Ddl) {
        db.execute(sql);
      }
      db.execute('PRAGMA user_version = 3');
    });
    await raw.ensureOpen(_V1User());
    await raw.close();

    final db = openQuizSyncDb(path);
    final cols = (await db.customSelect('PRAGMA table_info(tasks)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(cols, contains('payload_json'), reason: '打开时应补齐缺失的列');
    final queued = await OfflineQueue(db).enqueue(
      imageHash: 'h-1',
      sourceDevice: 'android-test',
      collectionId: 'c-9',
    );
    expect(OfflineQueue.parsePayload(queued).collectionId, 'c-9');
    await db.close();
    await dir.delete(recursive: true);
  });

  test('全部表 + FTS5 虚拟表 + 触发器都存在', () async {
    final db = createTestDb();
    final names = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get())
        .map((r) => r.read<String>('name'))
        .toSet();
    for (final t in [
      'devices',
      'images',
      'collections',
      'sessions',
      'session_images',
      'questions',
      'sync_ops',
      'peer_state', // 单数表名，契约要求
      'tasks',
      'settings',
      'ai_usage', // 单数表名，契约要求
      'questions_fts',
    ]) {
      expect(names, contains(t), reason: '缺表 $t');
    }

    final triggers = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='trigger'")
            .get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(triggers, containsAll(['questions_fts_ai', 'questions_fts_ad', 'questions_fts_au']));
    await db.close();
  });

  test('索引存在（契约第 1 节列出的全部索引）', () async {
    final db = createTestDb();
    final indexes = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'")
            .get())
        .map((r) => r.read<String>('name'))
        .toSet();
    for (final idx in [
      'idx_images_created',
      'idx_sessions_created',
      'idx_sessions_hash',
      'idx_sessions_status',
      'idx_questions_session',
      'idx_questions_stem',
      'idx_ops_lamport',
      'idx_ops_entity',
      'idx_tasks_status',
      'idx_usage_called',
    ]) {
      expect(indexes, contains(idx), reason: '缺索引 $idx');
    }
    await db.close();
  });

  test('sessions 列名与契约一致（snake_case）', () async {
    final db = createTestDb();
    final cols = (await db.customSelect('PRAGMA table_info(sessions)').get())
        .map((r) => r.read<String>('name'))
        .toSet();
    for (final c in [
      'session_id',
      'task_id',
      'image_hash',
      'source_device',
      'status',
      'error_code',
      'error_message',
      'ai_provider',
      'ai_model',
      'prompt_version',
      'raw_response',
      'cached',
      'question_count',
      'latency_ms',
      'created_at',
      'updated_at',
      'updated_by',
      'lamport',
      'field_clocks_json',
      'deleted_at',
    ]) {
      expect(cols, contains(c), reason: 'sessions 缺列 $c');
    }
    await db.close();
  });
}
