import 'package:drift/drift.dart';

import '../model/option.dart';
import '../sync/field_clocks.dart';
import 'converters.dart';
import 'tables.dart';

part 'database.g.dart';

/// 两端共用的 drift 数据库。schema 定义见 `data-model.md` 第 1 节。
@DriftDatabase(tables: [
  Devices,
  Images,
  Collections,
  Sessions,
  SessionImages,
  Questions,
  SyncOps,
  PeerStates,
  Tasks,
  Settings,
  AiUsage,
])
class QuizSyncDb extends _$QuizSyncDb {
  QuizSyncDb(super.e);

  /// FTS5 不可用（创建失败）时置 false，检索退化 LIKE。
  bool ftsAvailable = true;

  /// v2：+ collections / session_images，sessions.collection_id，
  /// questions.incomplete / answer_guessed（用户需求 2/4/8）。
  /// v3：questions.material（用户反馈 15：阅读类题目的材料，端侧默认折叠）。
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // FTS5 外部内容表 + 触发器：与 questions 表保持同步。
          // 老系统 sqlite 可能不支持 trigram：失败则退化 LIKE 检索。
          try {
            for (final sql in fts5Statements) {
              await customStatement(sql);
            }
          } catch (e) {
            ftsAvailable = false;
            // ignore: avoid_print
            print('FTS5 unavailable, fallback to LIKE: $e');
          }
        },
        onUpgrade: (m, from, to) async {
          // v1 → v2（用户需求 2/4/8）：新增合集表与多页图片表，
          // sessions 加 collection_id，questions 加不全/AI 猜测标记，
          // tasks 加离线队列的 payload_json（多页页序 + 合集归属）。
          // 全部为新增列（可空或带默认值），旧数据不丢。
          if (from < 2) {
            await m.createTable(collections);
            await m.createTable(sessionImages);
            await m.addColumn(sessions, sessions.collectionId);
            await m.addColumn(questions, questions.incomplete);
            await m.addColumn(questions, questions.answerGuessed);
            await m.addColumn(tasks, tasks.payloadJson);
          }
          // v2 → v3（用户反馈 15）：阅读类题目的材料列，带默认值，旧数据不丢。
          if (from < 3) {
            await m.addColumn(questions, questions.material);
          }
        },
        beforeOpen: (details) async {
          await _repairMissingColumns();
        },
      );

  /// 历次升级新增过的列（表名 / 列名 / 列定义）。
  ///
  /// 用途见 [QuizSyncDb._repairMissingColumns]。
  static const List<(String, String, String)> _upgradedColumns = [
    ('collections', 'deleted_at', 'INTEGER'),
    ('sessions', 'collection_id', 'TEXT'),
    ('questions', 'incomplete', 'INTEGER NOT NULL DEFAULT 0'),
    ('questions', 'answer_guessed', 'INTEGER NOT NULL DEFAULT 0'),
    ('questions', 'material', "TEXT NOT NULL DEFAULT ''"),
    ('tasks', 'payload_json', 'TEXT'),
  ];

  /// 打开时幂等补齐「升级路径漏加过的列」。
  ///
  /// 起因：1.1.0 及更早版本的 v1→v2 迁移漏了 `tasks.payload_json`，而从 v1 库
  /// 升上来的库已经被标成 `user_version = 3` —— `onUpgrade` 再也不会跑，
  /// 于是 `tasks` 表永久缺这一列（离线队列一读就 `no such column`
  /// `payload_json`）。这类库只能在打开时补一次。
  Future<void> _repairMissingColumns() async {
    for (final (table, column, ddl) in _upgradedColumns) {
      final info = await customSelect('PRAGMA table_info($table)').get();
      if (info.isEmpty) continue; // 表不存在：由 onUpgrade 负责
      final exists = info.any((r) => r.read<String>('name') == column);
      if (exists) continue;
      await customStatement('ALTER TABLE $table ADD COLUMN $column $ddl');
    }
  }

  /// FTS5 全文检索在 CoreRepository 里实现（返回模型类）。

  static const fts5Statements = [
    // trigram 分词器：默认 unicode61 无法切分中文（整段 CJK 成一个 token），
    // 检索会失效；trigram 支持子串匹配，中文可用（见 DECISIONS.md 实施期决策）。
    "CREATE VIRTUAL TABLE IF NOT EXISTS questions_fts USING fts5("
        "stem, analysis, content='questions', content_rowid='rowid', "
        "tokenize='trigram')",
    "CREATE TRIGGER IF NOT EXISTS questions_fts_ai AFTER INSERT ON questions BEGIN "
        "INSERT INTO questions_fts(rowid, stem, analysis) VALUES (new.rowid, new.stem, new.analysis); END",
    "CREATE TRIGGER IF NOT EXISTS questions_fts_ad AFTER DELETE ON questions BEGIN "
        "INSERT INTO questions_fts(questions_fts, rowid, stem, analysis) "
        "VALUES ('delete', old.rowid, old.stem, old.analysis); END",
    "CREATE TRIGGER IF NOT EXISTS questions_fts_au AFTER UPDATE ON questions BEGIN "
        "INSERT INTO questions_fts(questions_fts, rowid, stem, analysis) "
        "VALUES ('delete', old.rowid, old.stem, old.analysis); "
        "INSERT INTO questions_fts(rowid, stem, analysis) VALUES (new.rowid, new.stem, new.analysis); END",
  ];

  /// 本地已见最大 lamport（启动时恢复 Lamport 时钟用）。
  Future<int> maxLamport() async {
    final rows =
        await customSelect('SELECT MAX(lamport) AS m FROM sync_ops').get();
    return rows.first.readNullable<int>('m') ?? 0;
  }

  /// 同步 ops 总行数（快照折叠的触发条件用，M6）。
  Future<int> syncOpsCount() async {
    final rows = await customSelect('SELECT COUNT(*) AS c FROM sync_ops').get();
    return rows.first.read<int>('c');
  }
}

/// FTS MATCH 语法的最小转义：按空白切词，每词加引号避免被当作操作符。
String ftsEscape(String raw) {
  final tokens = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .map((t) => '"${t.replaceAll('"', ' ')}"')
      .toList();
  return tokens.join(' ');
}
