import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/answer_value.dart';
import '../model/collection.dart';
import '../model/device_info.dart';
import '../model/image_meta.dart';
import '../model/option.dart';
import '../model/question.dart';
import '../model/question_type.dart';
import '../model/session.dart';
import '../model/session_image.dart';
import '../model/sync_op.dart';
import '../model/task_state.dart';
import '../sync/field_clocks.dart';
import '../sync/lamport_clock.dart';
import '../sync/lww_applier.dart';
import '../sync/sync_op_writer.dart';
import '../util/ids.dart';
import 'database.dart';
import 'mappers.dart';

/// 远端 op 应用结果。
class ApplyRemoteResult {
  final bool duplicate;
  final Set<String> appliedFields;

  /// 因 user_edited 保护而跳过、等待用户决定的字段（`data-model.md` 2.3）。
  final Set<String> protectedFields;

  const ApplyRemoteResult({
    required this.duplicate,
    required this.appliedFields,
    required this.protectedFields,
  });
}

/// 一次 AI 分析结果的落库参数。
class AnalysisResultInput {
  final String? aiProvider;
  final String? aiModel;
  final String? promptVersion;
  final String? rawResponse;
  final int? latencyMs;
  final bool cached;

  /// 已按 ordinal 排好的题目。
  final List<Question> questions;

  const AnalysisResultInput({
    this.aiProvider,
    this.aiModel,
    this.promptVersion,
    this.rawResponse,
    this.latencyMs,
    this.cached = false,
    required this.questions,
  });
}

/// images / devices 表按 `data-model.md` 没有 lamport / field_clocks 列，
/// 这些实体不做字段级 LWW：按主键合并、后到写入，
/// 但本地专属列（local_path / token_hash）绝不进 op、也不被远端 op 覆盖。
const _imageLocalOnlyColumns = {'local_path'};
const _deviceLocalOnlyColumns = {'token_hash'};

/// 核心仓库：所有本地写入都经此类（保证 op 生成），远端 op 也经此类应用。
/// 平台通道 / UI 不直接碰表。
class CoreRepository {
  final QuizSyncDb db;
  final String deviceId;
  final LamportClock clock = LamportClock();
  late final SyncOpWriter writer;

  /// 远端 op 里的「删除合集」是否落地成 tombstone（M18 第 4 条）。
  ///
  /// 默认 `true`（两端口径一致：对端删了本地也删）。
  ///
  /// 安卓端传 `false`：用户明确要求**修改 M17 的第 5 条** ——
  /// 「windows 端删除后安卓端不再同步跟着删除」。主机删掉一个合集时，手机本地
  /// 那一行原样保留（历史里那个分组不消失、下面的识别记录也不会被打散成
  /// 「未分类」）。
  ///
  /// 只影响**远端** op：本机 `deleteCollection` 照常软删除并生成 op —— 用户在
  /// 手机上主动删合集是明确动作，仍然会同步给主机。op 本身照常入库（拉取游标
  /// 正常推进），只是不回写 `deleted_at`。
  final bool applyRemoteCollectionDeletes;

  CoreRepository({
    required this.db,
    required this.deviceId,
    this.applyRemoteCollectionDeletes = true,
  }) {
    writer = SyncOpWriter(
      deviceId: deviceId,
      clock: clock,
      persist: (op) => db.into(db.syncOps).insert(opToCompanion(op)),
    );
  }

  /// 启动时调用：从库中恢复 Lamport 时钟。
  Future<void> init() async {
    clock.restore(await db.maxLamport());
  }

  // ============================================================
  // sessions
  // ============================================================

  Future<Session> upsertSession(Session s) async {
    return db.transaction(() async {
      final existingRow = await _sessionRow(s.sessionId);
      final existing = existingRow == null ? null : sessionFromRow(existingRow);
      final now = nowMs();
      final stamped = s.copyWith(updatedAt: now, updatedBy: deviceId);
      final map = sessionFieldMap(stamped);
      if (existing != null) {
        // 身份字段以既有行为准，避免误清空。
        map['created_at'] = existing.createdAt;
        map['image_hash'] = existing.imageHash;
        map['source_device'] = existing.sourceDevice;
      }
      final changed =
          diffFields(existing == null ? null : sessionFieldMap(existing), map);
      if (existing != null && changed.isEmpty) return existing;

      final op = await writer.upsert(
        entity: SyncEntity.session,
        entityId: s.sessionId,
        changedFields: changed,
        now: now,
      );
      final clocks =
          Map<String, FieldClock>.from(existingRow?.fieldClocksJson ?? {});
      for (final k in changed.keys) {
        clocks[k] = FieldClock(op.lamport, deviceId);
      }
      await db.into(db.sessions).insertOnConflictUpdate(
          sessionCompanionFromFields(map).copyWith(
            sessionId: Value(s.sessionId),
            lamport: Value(op.lamport),
            fieldClocksJson: Value(clocks),
          ));
      return stamped.copyWith(
        lamport: op.lamport,
        fieldClocks: {for (final e in clocks.entries) e.key: e.value.toJson()},
      );
    });
  }

  /// 软删除会话及其题目；每条被删实体恰好 1 条 delete op。
  /// 幂等：已删除的会话再次调用不会产生第二条 delete op（否则会把
  /// tombstone 的时间往后推，永久阻塞 30 天 GC）。
  Future<void> deleteSession(String sessionId) async {
    await db.transaction(() async {
      final row = await _sessionRow(sessionId);
      if (row == null || row.deletedAt != null) return;
      final now = nowMs();
      final qs = await questionsOfSession(sessionId);
      for (final q in qs) {
        final op = await writer.delete(
            entity: SyncEntity.question, entityId: q.questionId, now: now);
        await _tombstoneQuestion(q.questionId, now, op.lamport);
      }
      final op = await writer.delete(
          entity: SyncEntity.session, entityId: sessionId, now: now);
      await _tombstoneSession(sessionId, now, op.lamport);
    });
  }

  Future<Session?> getSession(String sessionId,
      {bool includeDeleted = false}) async {
    final row = await _sessionRow(sessionId);
    if (row == null) return null;
    if (!includeDeleted && row.deletedAt != null) return null;
    return sessionFromRow(row);
  }

  /// 时间倒序、排除 tombstone（列表唯一入口）。
  /// [collectionId] 非空时只返回该合集的会话（用户需求 8/9）。
  Future<List<Session>> listSessions({int limit = 500, String? collectionId}) async {
    final rows = await (db.select(db.sessions)
          ..where((t) => collectionId == null
              ? t.deletedAt.isNull()
              : t.deletedAt.isNull() & t.collectionId.equals(collectionId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
    return rows.map(sessionFromRow).toList();
  }

  Stream<List<Session>> watchSessions({int limit = 500, String? collectionId}) {
    final query = db.select(db.sessions)
      ..where((t) => collectionId == null
          ? t.deletedAt.isNull()
          : t.deletedAt.isNull() & t.collectionId.equals(collectionId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(sessionFromRow).toList());
  }

  /// 识别顺序升序（合集导出用，用户需求 9）。
  Future<List<Session>> listSessionsAscending({String? collectionId}) async {
    final rows = await (db.select(db.sessions)
          ..where((t) => collectionId == null
              ? t.deletedAt.isNull()
              : t.deletedAt.isNull() & t.collectionId.equals(collectionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(sessionFromRow).toList();
  }

  Future<SessionRow?> _sessionRow(String sessionId) =>
      (db.select(db.sessions)..where((t) => t.sessionId.equals(sessionId)))
          .getSingleOrNull();

  Future<void> _tombstoneSession(String sessionId, int now, int lamport) async {
    final row = await _sessionRow(sessionId);
    if (row == null) return;
    final clocks = Map<String, FieldClock>.from(row.fieldClocksJson);
    clocks['deleted_at'] = FieldClock(lamport, deviceId);
    await (db.update(db.sessions)..where((t) => t.sessionId.equals(sessionId)))
        .write(SessionsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      updatedBy: Value(deviceId),
      lamport: Value(lamport),
      fieldClocksJson: Value(clocks),
    ));
  }

  // ============================================================
  // questions
  // ============================================================

  Future<Question> upsertQuestion(Question q, {Set<String> forceOpFields = const {}}) async {
    return db.transaction(() async {
      final existingRow = await _questionRow(q.questionId);
      final existing =
          existingRow == null ? null : questionFromRow(existingRow);
      final now = nowMs();
      final stamped = q.copyWith(updatedAt: now, updatedBy: deviceId);
      final map = questionFieldMap(stamped);
      if (existing != null) {
        map['session_id'] = existing.sessionId;
        map['created_at'] = existing.createdAt;
      }
      final changed =
          diffFields(existing == null ? null : questionFieldMap(existing), map);
      // 用户手改必须让 op 带上 *_edited 标记：对端靠它区分「AI 结果」与
      // 「用户手改」，从而只对 AI 结果做 user_edited 保护（否则两端永久分歧）。
      if (changed.isNotEmpty) {
        for (final f in forceOpFields) {
          changed[f] = map[f];
        }
      }
      if (existing != null && changed.isEmpty) return existing;

      final op = await writer.upsert(
        entity: SyncEntity.question,
        entityId: q.questionId,
        changedFields: changed,
        now: now,
      );
      final clocks =
          Map<String, FieldClock>.from(existingRow?.fieldClocksJson ?? {});
      for (final k in changed.keys) {
        clocks[k] = FieldClock(op.lamport, deviceId);
      }
      await db.into(db.questions).insertOnConflictUpdate(
          questionCompanionFromFields(map).copyWith(
            questionId: Value(q.questionId),
            lamport: Value(op.lamport),
            fieldClocksJson: Value(clocks),
          ));
      return stamped.copyWith(
        lamport: op.lamport,
        fieldClocks: {for (final e in clocks.entries) e.key: e.value.toJson()},
      );
    });
  }

  Future<List<Question>> questionsOfSession(String sessionId) async {
    final rows = await (db.select(db.questions)
          ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.ordinal)]))
        .get();
    return rows.map(questionFromRow).toList();
  }

  Future<Question?> getQuestion(String questionId,
      {bool includeDeleted = false}) async {
    final row = await _questionRow(questionId);
    if (row == null) return null;
    if (!includeDeleted && row.deletedAt != null) return null;
    return questionFromRow(row);
  }

  Future<QuestionRow?> _questionRow(String questionId) =>
      (db.select(db.questions)..where((t) => t.questionId.equals(questionId)))
          .getSingleOrNull();

  Future<void> _tombstoneQuestion(
      String questionId, int now, int lamport) async {
    final row = await _questionRow(questionId);
    if (row == null) return;
    final clocks = Map<String, FieldClock>.from(row.fieldClocksJson);
    clocks['deleted_at'] = FieldClock(lamport, deviceId);
    await (db.update(db.questions)
          ..where((t) => t.questionId.equals(questionId)))
        .write(QuestionsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      updatedBy: Value(deviceId),
      lamport: Value(lamport),
      fieldClocksJson: Value(clocks),
    ));
  }

  /// FTS5 全文检索（题干 + 解析），排除软删除（`data-model.md` 2.7）。
  /// trigram 分词器要求 >= 3 字符；更短的查询退化为 LIKE（对中文同样有效）。
  /// FTS5 不可用时（部分安卓 sqlite）同样退化 LIKE，绝不抛异常。
  Future<List<Question>> searchQuestions(String rawQuery,
      {int limit = 200}) async {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.length < 3 || !db.ftsAvailable) {
      return _searchLike(trimmed, limit);
    }
    final q = ftsEscape(trimmed);
    try {
      final rows = await db.customSelect(
        'SELECT q.* FROM questions q JOIN questions_fts f ON q.rowid = f.rowid '
        'WHERE questions_fts MATCH ? AND q.deleted_at IS NULL '
        'ORDER BY q.updated_at DESC LIMIT ?',
        variables: [Variable.withString(q), Variable.withInt(limit)],
        readsFrom: {db.questions},
      ).get();
      return rows.map(_questionFromQueryRow).toList();
    } catch (_) {
      // 虚拟表/触发器缺失或 MATCH 语法被拒：退回 LIKE，别让搜索整个失败。
      db.ftsAvailable = false;
      return _searchLike(trimmed, limit);
    }
  }

  /// LIKE 兜底：`\` `%` `_` 都是 LIKE 的特殊字符，全部转义（否则 'a_' 会匹配
  /// 'abc'、'_' 会匹配全部记录）。
  Future<List<Question>> _searchLike(String trimmed, int limit) async {
    final like = '%${trimmed
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_')}%';
    final rows = await db.customSelect(
      'SELECT q.* FROM questions q '
      'WHERE (q.stem LIKE ? ESCAPE \'\\\' OR q.analysis LIKE ? ESCAPE \'\\\') '
      'AND q.deleted_at IS NULL '
      'ORDER BY q.updated_at DESC LIMIT ?',
      variables: [
        Variable.withString(like),
        Variable.withString(like),
        Variable.withInt(limit)
      ],
      readsFrom: {db.questions},
    ).get();
    return rows.map(_questionFromQueryRow).toList();
  }

  Question _questionFromQueryRow(QueryRow r) {
    List<Map<String, dynamic>> decodeList(String key) {
      final raw = r.readNullable<String>(key);
      if (raw == null || raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      } catch (_) {}
      return const [];
    }

    List<String> decodeStrings(String key) {
      final raw = r.readNullable<String>(key);
      if (raw == null || raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
      return const [];
    }

    return Question(
      questionId: r.read<String>('question_id'),
      sessionId: r.read<String>('session_id'),
      ordinal: r.read<int>('ordinal'),
      questionNo: r.readNullable<String>('question_no'),
      stem: r.read<String>('stem'),
      material: r.readNullable<String>('material') ?? '',
      type: QuestionType.parse(r.read<String>('type')),
      options:
          decodeList('options_json').map((m) => Option.fromJson(m)).toList(),
      choice: decodeStrings('choice_json'),
      answerText: r.readNullable<String>('answer_text'),
      analysis: r.readNullable<String>('analysis') ?? '',
      confidence: r.readNullable<double>('confidence') ?? 0.5,
      needReview: (r.readNullable<int>('need_review') ?? 0) == 1,
      answerInImage: (r.readNullable<int>('answer_in_image') ?? 0) == 1,
      incomplete: (r.readNullable<int>('incomplete') ?? 0) == 1,
      answerGuessed: (r.readNullable<int>('answer_guessed') ?? 0) == 1,
      warnings: decodeStrings('warnings_json'),
      analysisEdited: (r.readNullable<int>('analysis_edited') ?? 0) == 1,
      answerEdited: (r.readNullable<int>('answer_edited') ?? 0) == 1,
      createdAt: r.read<int>('created_at'),
      updatedAt: r.read<int>('updated_at'),
      updatedBy: r.read<String>('updated_by'),
      lamport: r.read<int>('lamport'),
      deletedAt: r.readNullable<int>('deleted_at'),
    );
  }

  // ============================================================
  // AI 结果落库（user_edited 保护，data-model.md 2.3）
  // ============================================================

  /// 应用一次 AI 分析结果。重分析的题目按 ordinal 与既有题目对应：
  /// 已有 `answer_edited=1` 则答案字段保留用户值；`analysis_edited=1` 同理。
  /// 既有题目多于新结果时，多出的软删除。
  Future<void> applyAnalysisResult({
    required String sessionId,
    required AnalysisResultInput input,
  }) async {
    await db.transaction(() async {
      final now = nowMs();
      final existing = await questionsOfSession(sessionId);

      for (final fresh in input.questions) {
        Question? old;
        for (final e in existing) {
          if (e.ordinal == fresh.ordinal) {
            old = e;
            break;
          }
        }
        if (old == null) {
          await upsertQuestion(fresh);
          continue;
        }
        var merged = fresh.copyWith(
          questionId: old.questionId,
          sessionId: old.sessionId,
          createdAt: old.createdAt,
        );
        if (old.answerEdited) {
          merged =
              merged.copyWith(choice: old.choice, answerText: old.answerText);
        }
        if (old.analysisEdited) {
          merged = merged.copyWith(analysis: old.analysis);
        }
        merged = merged.copyWith(
          answerEdited: old.answerEdited,
          analysisEdited: old.analysisEdited,
        );
        await upsertQuestion(merged);
      }

      final freshOrdinals = input.questions.map((q) => q.ordinal).toSet();
      for (final old in existing) {
        if (!freshOrdinals.contains(old.ordinal)) {
          final op = await writer.delete(
              entity: SyncEntity.question, entityId: old.questionId, now: now);
          await _tombstoneQuestion(old.questionId, now, op.lamport);
        }
      }

      final sess = await getSession(sessionId, includeDeleted: true);
      if (sess != null) {
        final empty = input.questions.isEmpty;
        await upsertSession(sess.copyWith(
          status: empty ? TaskState.failed : TaskState.done,
          errorCode: empty ? 'no_question_found' : null,
          errorMessage: empty ? '未识别到题目' : null,
          aiProvider: input.aiProvider ?? sess.aiProvider,
          aiModel: input.aiModel ?? sess.aiModel,
          promptVersion: input.promptVersion ?? sess.promptVersion,
          rawResponse: input.rawResponse ?? sess.rawResponse,
          cached: input.cached,
          questionCount: input.questions.length,
          latencyMs: input.latencyMs ?? sess.latencyMs,
        ));
      }
    });
  }

  /// 用户手改答案：置 `answer_edited = 1`，生成 op。
  Future<Question> updateUserAnswer(
      String questionId, AnswerValue answer) async {
    final q = await getQuestion(questionId, includeDeleted: true);
    if (q == null) throw StateError('question not found: $questionId');
    return upsertQuestion(
      q.copyWith(
        choice: answer.choice ?? const [],
        answerText: answer.text,
        answerEdited: true,
      ),
      forceOpFields: const {'answer_edited'},
    );
  }

  /// 用户手改解析：置 `analysis_edited = 1`，生成 op。
  Future<Question> updateUserAnalysis(String questionId, String analysis) async {
    final q = await getQuestion(questionId, includeDeleted: true);
    if (q == null) throw StateError('question not found: $questionId');
    return upsertQuestion(
      q.copyWith(analysis: analysis, analysisEdited: true),
      forceOpFields: const {'analysis_edited'},
    );
  }

  // ============================================================
  // collections（用户需求 8/9）
  // ============================================================

  Future<Collection> upsertCollection(Collection c) async {
    return db.transaction(() async {
      final existingRow = await _collectionRow(c.collectionId);
      final existing =
          existingRow == null ? null : collectionFromRow(existingRow);
      final now = nowMs();
      final stamped = c.copyWith(updatedAt: now, updatedBy: deviceId);
      final map = collectionFieldMap(stamped);
      if (existing != null) map['created_at'] = existing.createdAt;
      final changed = diffFields(
          existing == null ? null : collectionFieldMap(existing), map);
      if (existing != null && changed.isEmpty) return existing;

      final op = await writer.upsert(
        entity: SyncEntity.collection,
        entityId: c.collectionId,
        changedFields: changed,
        now: now,
      );
      final clocks =
          Map<String, FieldClock>.from(existingRow?.fieldClocksJson ?? {});
      for (final k in changed.keys) {
        clocks[k] = FieldClock(op.lamport, deviceId);
      }
      await db.into(db.collections).insertOnConflictUpdate(
          collectionCompanionFromFields(map).copyWith(
        collectionId: Value(c.collectionId),
        lamport: Value(op.lamport),
        fieldClocksJson: Value(clocks),
      ));
      return stamped.copyWith(
        lamport: op.lamport,
        fieldClocks: {for (final e in clocks.entries) e.key: e.value.toJson()},
      );
    });
  }

  /// 主机**活跃合集列表**的镜像导入（M18 第 4 条）。
  ///
  /// 用户原话：「安卓端现在识别不到无法同步 windows 端的分类，想办法完成同步」。
  /// 症状是主机新建的合集在手机本地根本没有那一行，于是主机识别的记录在手机
  /// 「历史」里全被算进「未分类」。原来的落地通道只有 ops 拉取，而拉取靠
  /// `ops_lamport` 水位这种**间接信号**触发：水位基线/断线/WS 不可用任一环节
  /// 出问题就漏，且漏了不会自愈。现在主机把「当前的活跃合集列表」直接放进每秒
  /// 一次的状态探测里，客户端按这份**想要的结果**对齐本地库 —— 差什么补什么。
  ///
  /// 语义（用户反馈 M18 第 4 条明确要求，与 M17 相反）：
  /// - **只增改，不删**：主机列表里没有的合集在本地原样保留，绝不变 tombstone。
  ///   于是「Windows 端删除后安卓端不再同步跟着删除」。
  /// - 本机已删除的合集（本地 tombstone）**绝不复活**：删除是用户的明确动作
  ///   （历史页长按批量删），本机删除优先，否则会出现「删了又自己回来」。
  /// - 不产生 sync op：合集的主写入方是 Windows，安卓端只做镜像。因此本地
  ///   行的 `lamport` / `field_clocks` 保持原样（合集 op 在安卓端不落地，
  ///   见 `AndroidSync` 的拉取过滤）。
  ///
  /// 返回真正写进去的行数（0 = 本地已经一致，界面不必重建）。
  Future<int> mirrorCollections(Iterable<Collection> host) async {
    var changed = 0;
    await db.transaction(() async {
      for (final c in host) {
        final row = await _collectionRow(c.collectionId);
        if (row == null) {
          await db.into(db.collections).insert(CollectionsCompanion.insert(
                collectionId: c.collectionId,
                name: c.name,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
                updatedBy: c.updatedBy,
              ));
          changed++;
          continue;
        }
        if (row.deletedAt != null) continue;
        if (row.name == c.name && row.updatedAt == c.updatedAt) continue;
        await (db.update(db.collections)
              ..where((t) => t.collectionId.equals(c.collectionId)))
            .write(CollectionsCompanion(
          name: Value(c.name),
          updatedAt: Value(c.updatedAt),
          updatedBy: Value(c.updatedBy),
        ));
        changed++;
      }
    });
    return changed;
  }

  /// 时间倒序、排除 tombstone。
  Future<List<Collection>> listCollections({int limit = 500}) async {
    final rows = await (db.select(db.collections)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
    return rows.map(collectionFromRow).toList();
  }

  Stream<List<Collection>> watchCollections({int limit = 500}) {
    final query = db.select(db.collections)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(collectionFromRow).toList());
  }

  Future<Collection?> getCollection(String collectionId,
      {bool includeDeleted = false}) async {
    final row = await _collectionRow(collectionId);
    if (row == null) return null;
    if (!includeDeleted && row.deletedAt != null) return null;
    return collectionFromRow(row);
  }

  Future<CollectionRow?> _collectionRow(String collectionId) =>
      (db.select(db.collections)
            ..where((t) => t.collectionId.equals(collectionId)))
          .getSingleOrNull();

  /// 合集内会话数（删除确认提示用）。
  Future<int> sessionCountOfCollection(String collectionId) async {
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.deletedAt.isNull() & t.collectionId.equals(collectionId)))
        .get();
    return rows.length;
  }

  /// 软删除合集本身（**不**级联删除其下的会话：用户只是不想再看到这个分组）。
  Future<void> deleteCollection(String collectionId) async {
    await db.transaction(() async {
      final row = await _collectionRow(collectionId);
      if (row == null || row.deletedAt != null) return;
      final now = nowMs();
      final op = await writer.delete(
          entity: SyncEntity.collection, entityId: collectionId, now: now);
      final clocks = Map<String, FieldClock>.from(row.fieldClocksJson);
      clocks['deleted_at'] = FieldClock(op.lamport, deviceId);
      await (db.update(db.collections)
            ..where((t) => t.collectionId.equals(collectionId)))
          .write(CollectionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        updatedBy: Value(deviceId),
        lamport: Value(op.lamport),
        fieldClocksJson: Value(clocks),
      ));
    });
  }

  // ============================================================
  // session_images（用户需求 4：多页题目一次识别）
  // ============================================================

  Future<SessionImage> upsertSessionImage(SessionImage s) async {
    return db.transaction(() async {
      final existingRow = await _sessionImageRow(s.sessionImageId);
      final existing =
          existingRow == null ? null : sessionImageFromRow(existingRow);
      final now = nowMs();
      final stamped = s.copyWith(updatedAt: now, updatedBy: deviceId);
      final map = sessionImageFieldMap(stamped);
      if (existing != null) {
        map['created_at'] = existing.createdAt;
        map['session_id'] = existing.sessionId;
      }
      final changed = diffFields(
          existing == null ? null : sessionImageFieldMap(existing), map);
      if (existing != null && changed.isEmpty) return existing;

      final op = await writer.upsert(
        entity: SyncEntity.sessionImage,
        entityId: s.sessionImageId,
        changedFields: changed,
        now: now,
      );
      final clocks =
          Map<String, FieldClock>.from(existingRow?.fieldClocksJson ?? {});
      for (final k in changed.keys) {
        clocks[k] = FieldClock(op.lamport, deviceId);
      }
      await db.into(db.sessionImages).insertOnConflictUpdate(
          sessionImageCompanionFromFields(map).copyWith(
        sessionImageId: Value(s.sessionImageId),
        lamport: Value(op.lamport),
        fieldClocksJson: Value(clocks),
      ));
      return stamped.copyWith(
        lamport: op.lamport,
        fieldClocks: {for (final e in clocks.entries) e.key: e.value.toJson()},
      );
    });
  }

  Future<SessionImageRow?> _sessionImageRow(String id) =>
      (db.select(db.sessionImages)
            ..where((t) => t.sessionImageId.equals(id)))
          .getSingleOrNull();

  Future<List<SessionImage>> sessionImagesOf(String sessionId) async {
    final rows = await (db.select(db.sessionImages)
          ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.ordinal),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.sessionImageId),
          ]))
        .get();
    // 同一 ordinal 只认一行（最早建的那行）。
    //
    // 为什么会有重复行：两端各自为同一页建行（手机按结果负载建、主机按自己的
    // 分析建），行 id 不同而 ordinal 相同；对端 op 落地时按 op 的 entity_id 写入，
    // 于是同一页在本机变成两行。页序与「N 张图片」都是按行数算的，不去重就会
    // 翻倍（2026-09-26 真机反馈：主机 1 张、手机显示「2 张图片」）。
    // 这里只收敛**读取**结果，不删行 —— 删行会派出墓碑 op，可能把对端合法的那行删掉。
    final seen = <int>{};
    final out = <SessionImage>[];
    for (final row in rows) {
      if (!seen.add(row.ordinal)) continue;
      out.add(sessionImageFromRow(row));
    }
    return out;
  }

  /// 同一页在本机已有的行（会话 + 页序）。用于把对端的页 op 落到本机既有行上。
  Future<SessionImageRow?> _sessionImageRowAt(
          String sessionId, int ordinal) =>
      (db.select(db.sessionImages)
            ..where((t) =>
                t.sessionId.equals(sessionId) &
                t.ordinal.equals(ordinal) &
                t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.sessionImageId),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// 页 op 是否可以落到「本机同一页的既有行」上。
  ///
  /// 只对**非删除** op 成立：删除类 op 必须按 op 自己的 entity_id 落地，否则会把
  /// 本机自己那一行（合法的页）误删成墓碑。
  Future<SessionImageRow?> _samePageRowForOp(
      Map<String, dynamic> fields) async {
    final deleted = fields['deleted_at'];
    if (deleted != null && (deleted is! num || deleted != 0)) return null;
    final sessionId = fields['session_id']?.toString() ?? '';
    final ordinal = (fields['ordinal'] as num?)?.toInt();
    if (sessionId.isEmpty || ordinal == null) return null;
    return _sessionImageRowAt(sessionId, ordinal);
  }

  /// 会话的页图片 hash 顺序（0 起）。**行数永远 ≥ 1**：历史数据没有
  /// session_images 行时退回 `sessions.image_hash`，两端兼容旧库。
  Future<List<String>> imageHashesOf(String sessionId) async {
    final rows = await sessionImagesOf(sessionId);
    if (rows.isNotEmpty) return rows.map((r) => r.imageHash).toList();
    final s = await getSession(sessionId, includeDeleted: true);
    if (s == null || s.imageHash.isEmpty) return const [];
    return [s.imageHash];
  }

  /// 幂等设置会话的页列表：按 ordinal 复用既有行（同 hash 同序不产生 op），
  /// 多出的旧行软删除。
  Future<void> setSessionImages(String sessionId, List<String> hashes) async {
    if (hashes.isEmpty) return;
    await db.transaction(() async {
      final existing = await sessionImagesOf(sessionId);
      for (var i = 0; i < hashes.length; i++) {
        SessionImage? reuse;
        for (final e in existing) {
          if (e.ordinal == i) {
            reuse = e;
            break;
          }
        }
        // 同序同 hash：已经是目标状态，直接跳过（否则每次都写 updated_at
        // 会派生出无意义的同步 op，两端反复空转）。
        if (reuse != null && reuse.imageHash == hashes[i]) continue;
        await upsertSessionImage(SessionImage(
          sessionImageId: reuse?.sessionImageId ?? newUuidV4(),
          sessionId: sessionId,
          ordinal: i,
          imageHash: hashes[i],
          createdAt: reuse?.createdAt ?? nowMs(),
          updatedAt: nowMs(),
          updatedBy: deviceId,
        ));
      }
      for (final extra in existing.where((e) => e.ordinal >= hashes.length)) {
        final op = await writer.delete(
            entity: SyncEntity.sessionImage,
            entityId: extra.sessionImageId,
            now: nowMs());
        await _tombstoneSessionImage(extra.sessionImageId, nowMs(), op.lamport);
      }
    });
  }

  Future<void> _tombstoneSessionImage(
      String id, int now, int lamport) async {
    final row = await _sessionImageRow(id);
    if (row == null) return;
    final clocks = Map<String, FieldClock>.from(row.fieldClocksJson);
    clocks['deleted_at'] = FieldClock(lamport, deviceId);
    await (db.update(db.sessionImages)
          ..where((t) => t.sessionImageId.equals(id)))
        .write(SessionImagesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      updatedBy: Value(deviceId),
      lamport: Value(lamport),
      fieldClocksJson: Value(clocks),
    ));
  }

  // ============================================================
  // images / devices（无 lamport / 字段时钟列，按主键合并）
  // ============================================================

  Future<ImageMeta> upsertImage(ImageMeta m) async {
    return db.transaction(() async {
      final existingRow = await (db.select(db.images)
            ..where((t) => t.hash.equals(m.hash)))
          .getSingleOrNull();
      final existing = existingRow == null ? null : imageFromRow(existingRow);
      final now = nowMs();
      final map = imageFieldMap(m)
        ..['created_at'] = existing?.createdAt ?? m.createdAt
        // localPath 传 null 表示「本次不关心本地文件」，不能把已有路径清掉，
        // 否则任何一次带其它字段的 upsert 都会让本地文件「失联」
        // （imagesMissingFile 会重新下载、离线队列找不到文件）。
        ..['local_path'] = m.localPath ?? existing?.localPath;
      final changed =
          diffFields(existing == null ? null : imageFieldMap(existing), map);
      // 本地专属列不进 op（data-model.md 2.4）。
      changed.removeWhere((k, _) => _imageLocalOnlyColumns.contains(k));
      if (existing != null && changed.isEmpty) return existing;

      await writer.upsert(
        entity: SyncEntity.image,
        entityId: m.hash,
        changedFields: changed,
        now: now,
      );
      await db.into(db.images).insertOnConflictUpdate(
          imageCompanionFromFields(map).copyWith(hash: Value(m.hash)));
      return existing ?? m;
    });
  }

  Future<ImageMeta?> getImage(String hash) async {
    final row = await (db.select(db.images)..where((t) => t.hash.equals(hash)))
        .getSingleOrNull();
    return row == null ? null : imageFromRow(row);
  }

  /// `local_path` 写回不产生 op（data-model.md 2.4）。
  Future<void> setImageLocalPath(String hash, String? path) async {
    await (db.update(db.images)..where((t) => t.hash.equals(hash)))
        .write(ImagesCompanion(localPath: Value(path)));
  }

  Future<DeviceInfo> upsertDevice(DeviceInfo d) async {
    return db.transaction(() async {
      final existingRow = await (db.select(db.devices)
            ..where((t) => t.deviceId.equals(d.deviceId)))
          .getSingleOrNull();
      final existing = existingRow == null ? null : deviceFromRow(existingRow);
      final now = nowMs();
      final map = deviceFieldMap(d)
        ..['paired_at'] = existing?.pairedAt ?? d.pairedAt;
      final changed =
          diffFields(existing == null ? null : deviceFieldMap(existing), map);
      // token_hash 仅 Windows 本地保存，不随 op 同步。
      changed.removeWhere((k, _) => _deviceLocalOnlyColumns.contains(k));
      if (existing != null && changed.isEmpty) return existing;

      await writer.upsert(
        entity: SyncEntity.device,
        entityId: d.deviceId,
        changedFields: changed,
        now: now,
      );
      await db.into(db.devices).insertOnConflictUpdate(
          deviceCompanionFromFields(map).copyWith(deviceId: Value(d.deviceId)));
      return existing ?? d;
    });
  }

  Future<List<DeviceInfo>> listDevices({bool includeRevoked = true}) async {
    final q = db.select(db.devices);
    if (!includeRevoked) {
      q.where((t) => t.revokedAt.isNull());
    }
    final rows = await q.get();
    return rows.map(deviceFromRow).toList();
  }

  /// 设备列表的库变更流（用户反馈：主界面药丸停在「未配对」不动）。
  ///
  /// 主界面顶栏那条配对状态原来只在挂载时查一次库（`FutureProvider` 且没有
  /// 任何失效时机），于是「App 先开着、手机后来才扫码配对」这条最平常的路径
  /// 永远显示「未配对」，非得重启应用才更新；在「设置 → 连接设备」里吊销设备
  /// 同样不会让药丸退回来。配对（`/pair`）与吊销都写同一张 `devices` 表，
  /// 所以这里直接给出流，谁写库谁就能让它变。
  Stream<List<DeviceInfo>> watchDevices({bool includeRevoked = false}) {
    final query = db.select(db.devices);
    if (!includeRevoked) {
      query.where((t) => t.revokedAt.isNull());
    }
    return query.watch().map((rows) => rows.map(deviceFromRow).toList());
  }

  Future<void> revokeDevice(String deviceId) async {
    final row = await (db.select(db.devices)
          ..where((t) => t.deviceId.equals(deviceId)))
        .getSingleOrNull();
    if (row == null) return;
    await upsertDevice(deviceFromRow(row).copyWith(revokedAt: nowMs()));
  }

  // ============================================================
  // 远端 op 应用（幂等 + 字段级 LWW + user_edited 保护）
  // ============================================================

  Future<ApplyRemoteResult> applyRemoteOp(SyncOp op) async {
    return db.transaction(() async {
      final dup = await (db.selectOnly(db.syncOps)
            ..addColumns([db.syncOps.opId])
            ..where(db.syncOps.opId.equals(op.opId)))
          .get();
      if (dup.isNotEmpty) {
        return const ApplyRemoteResult(
            duplicate: true, appliedFields: {}, protectedFields: {});
      }
      await db
          .into(db.syncOps)
          .insert(opToCompanion(op), mode: InsertMode.insertOrIgnore);
      clock.observe(op.lamport);

      // delete op 的字段兜底带上 deleted_at。
      // 注意：必须复制，_sparseXxxDefaults 会就地写入默认值，直接改
      // op.fields 会污染调用方的 SyncOp（若调用方复用/转发该 op 就会把
      // 伪造的默认值按原 lamport 传播出去）。
      var fields = Map<String, dynamic>.from(op.fields);
      if (op.opType == SyncOpType.delete && !fields.containsKey('deleted_at')) {
        fields = {...fields, 'deleted_at': op.createdAt};
      }

      switch (op.entity) {
        case SyncEntity.session:
          return _applyRemoteSession(op, fields);
        case SyncEntity.question:
          return _applyRemoteQuestion(op, fields);
        case SyncEntity.collection:
          return _applyRemoteCollection(op, fields);
        case SyncEntity.sessionImage:
          return _applyRemoteSessionImage(op, fields);
        case SyncEntity.image:
          return _applyRemoteImage(op, fields);
        case SyncEntity.device:
          return _applyRemoteDevice(op, fields);
        case SyncEntity.snapshot:
          // 快照折叠在 M6 实现；收到时先只记账。
          return ApplyRemoteResult(
              duplicate: false, appliedFields: {}, protectedFields: {});
      }
    });
  }

  Future<ApplyRemoteResult> _applyRemoteCollection(
      SyncOp op, Map<String, dynamic> fields) async {
    // M18 第 4 条：安卓端不跟随主机的删除（见 applyRemoteCollectionDeletes）。
    // 只记账不回写 —— op 已经在 applyRemoteOp 里入库、时钟也已 observe，
    // 所以拉取游标不会因为「跳过一次落地」而卡住。
    if (!applyRemoteCollectionDeletes &&
        fields['deleted_at'] != null &&
        (fields['deleted_at'] as num).toInt() > 0) {
      return ApplyRemoteResult(
        duplicate: false,
        appliedFields: const {},
        protectedFields: const {'deleted_at'},
      );
    }
    final row = await _collectionRow(op.entityId);
    Map<String, dynamic>? current;
    if (row != null) {
      current = collectionFieldMap(collectionFromRow(row))
        ..['lamport'] = row.lamport
        ..['updated_by'] = row.updatedBy;
    } else {
      _sparseCollectionDefaults(fields);
    }
    final result = LwwApplier.apply(
      currentRow: current,
      clocks: row?.fieldClocksJson ?? {},
      op: _opWithFields(op, fields),
    );
    await db.into(db.collections).insertOnConflictUpdate(
        collectionCompanionFromFields(_fullMap(current, fields)).copyWith(
          collectionId: Value(op.entityId),
          lamport: Value(result.rowLamport),
          updatedBy: Value(result.rowUpdatedBy),
          fieldClocksJson: Value(result.clocks),
        ));
    return ApplyRemoteResult(
        duplicate: false,
        appliedFields: result.appliedFields,
        protectedFields: const {});
  }

  Future<ApplyRemoteResult> _applyRemoteSessionImage(
      SyncOp op, Map<String, dynamic> fields) async {
    // 先按 op 的 entity_id 找；找不到时再按「同一页」（会话 + 页序）找本机既有行。
    // 两端各自为同一页建行、行 id 不同，若这里直接按 op 的 id 新建，同一页就会
    // 变成两行（页数翻倍）。复用时保留本机行的 id，只把字段按 LWW 合过去。
    final row =
        await _sessionImageRow(op.entityId) ?? await _samePageRowForOp(fields);
    Map<String, dynamic>? current;
    if (row != null) {
      current = sessionImageFieldMap(sessionImageFromRow(row))
        ..['lamport'] = row.lamport
        ..['updated_by'] = row.updatedBy;
    } else {
      _sparseSessionImageDefaults(fields);
    }
    final result = LwwApplier.apply(
      currentRow: current,
      clocks: row?.fieldClocksJson ?? {},
      op: _opWithFields(op, fields),
    );
    await db.into(db.sessionImages).insertOnConflictUpdate(
        sessionImageCompanionFromFields(_fullMap(current, fields)).copyWith(
          sessionImageId: Value(row?.sessionImageId ?? op.entityId),
          lamport: Value(result.rowLamport),
          updatedBy: Value(result.rowUpdatedBy),
          fieldClocksJson: Value(result.clocks),
        ));
    return ApplyRemoteResult(
        duplicate: false,
        appliedFields: result.appliedFields,
        protectedFields: const {});
  }

  Future<ApplyRemoteResult> _applyRemoteSession(
      SyncOp op, Map<String, dynamic> fields) async {
    final row = await _sessionRow(op.entityId);
    Map<String, dynamic>? current;
    if (row != null) {
      current = sessionFieldMap(sessionFromRow(row))
        ..['lamport'] = row.lamport
        ..['updated_by'] = row.updatedBy;
    } else {
      _sparseSessionDefaults(fields);
    }
    final result = LwwApplier.apply(
      currentRow: current,
      clocks: row?.fieldClocksJson ?? {},
      op: _opWithFields(op, fields),
    );
    await db.into(db.sessions).insertOnConflictUpdate(
        sessionCompanionFromFields(_fullMap(current, fields)).copyWith(
          sessionId: Value(op.entityId),
          lamport: Value(result.rowLamport),
          updatedBy: Value(result.rowUpdatedBy),
          fieldClocksJson: Value(result.clocks),
        ));
    return ApplyRemoteResult(
        duplicate: false,
        appliedFields: result.appliedFields,
        protectedFields: const {});
  }

  Future<ApplyRemoteResult> _applyRemoteQuestion(
      SyncOp op, Map<String, dynamic> fields) async {
    final row = await _questionRow(op.entityId);
    Map<String, dynamic>? current;
    if (row != null) {
      current = questionFieldMap(questionFromRow(row))
        ..['lamport'] = row.lamport
        ..['updated_by'] = row.updatedBy;
    } else {
      _sparseQuestionDefaults(fields);
    }

    // user_edited 保护：AI 侧（对端）的新结果不覆盖用户手改字段。
    // 但对端**用户手改**必须走正常字段 LWW（否则两端各保留自己的编辑、
    // 永久分歧）。判据是 op 是否显式携带该组的 `*_edited` 标记：
    // 用户手改（updateUserAnswer/updateUserAnalysis）会强制带上，
    // AI 落库不会（值没变就不在 changed 里）。
    final protected = <String>{};
    const answerFields = {'choice_json', 'answer_text'};
    const analysisFields = {'analysis'};
    final userDecidedAnswer = fields.containsKey('answer_edited');
    final userDecidedAnalysis = fields.containsKey('analysis_edited');
    var effective = fields;
    if (row != null) {
      if (!userDecidedAnswer &&
          row.answerEdited &&
          fields.keys.any(answerFields.contains)) {
        effective = {
          for (final e in fields.entries)
            if (!answerFields.contains(e.key)) e.key: e.value
        };
        protected.addAll(fields.keys.where(answerFields.contains));
      }
      if (!userDecidedAnalysis &&
          row.analysisEdited &&
          fields.keys.any(analysisFields.contains)) {
        effective = {
          for (final e in effective.entries)
            if (!analysisFields.contains(e.key)) e.key: e.value
        };
        protected.addAll(fields.keys.where(analysisFields.contains));
      }
    }

    final result = LwwApplier.apply(
      currentRow: current,
      clocks: row?.fieldClocksJson ?? {},
      op: _opWithFields(op, effective),
    );
    await db.into(db.questions).insertOnConflictUpdate(
        questionCompanionFromFields(_fullMap(current, effective)).copyWith(
          questionId: Value(op.entityId),
          lamport: Value(result.rowLamport),
          updatedBy: Value(result.rowUpdatedBy),
          fieldClocksJson: Value(result.clocks),
        ));

    if (protected.isNotEmpty) {
      // 记录「AI 已给出新结果，是否覆盖？」的待决提示（本地 settings，不同步）。
      await db.into(db.settings).insertOnConflictUpdate(SettingRow(
        key: 'pending_overwrite:${op.entityId}',
        value: jsonEncode({
          'op_id': op.opId,
          'lamport': op.lamport,
          'device_id': op.deviceId,
          'fields': {
            for (final e in fields.entries)
              if (protected.contains(e.key)) e.key: e.value
          },
        }),
      ));
    }
    return ApplyRemoteResult(
        duplicate: false,
        appliedFields: result.appliedFields,
        protectedFields: protected);
  }

  Future<ApplyRemoteResult> _applyRemoteImage(
      SyncOp op, Map<String, dynamic> fields) async {
    fields = {
      for (final e in fields.entries)
        if (!_imageLocalOnlyColumns.contains(e.key)) e.key: e.value
    };
    final row = await (db.select(db.images)
          ..where((t) => t.hash.equals(op.entityId)))
        .getSingleOrNull();
    if (row == null) {
      _sparseImageDefaults(fields);
      await db.into(db.images).insert(
          imageCompanionFromFields(fields).copyWith(hash: Value(op.entityId)));
      return ApplyRemoteResult(
          duplicate: false,
          appliedFields: fields.keys.toSet(),
          protectedFields: const {});
    }
    // 后到写入；本地 local_path 不受影响。
    final merged = imageFieldMap(imageFromRow(row))..addAll(fields);
    await db.into(db.images).insertOnConflictUpdate(
        imageCompanionFromFields(merged).copyWith(hash: Value(op.entityId)));
    return ApplyRemoteResult(
        duplicate: false,
        appliedFields: fields.keys.toSet(),
        protectedFields: const {});
  }

  Future<ApplyRemoteResult> _applyRemoteDevice(
      SyncOp op, Map<String, dynamic> fields) async {
    fields = {
      for (final e in fields.entries)
        if (!_deviceLocalOnlyColumns.contains(e.key)) e.key: e.value
    };
    final row = await (db.select(db.devices)
          ..where((t) => t.deviceId.equals(op.entityId)))
        .getSingleOrNull();
    if (row == null) {
      _sparseDeviceDefaults(fields);
      await db.into(db.devices).insert(
          deviceCompanionFromFields(fields)
              .copyWith(deviceId: Value(op.entityId)));
      return ApplyRemoteResult(
          duplicate: false,
          appliedFields: fields.keys.toSet(),
          protectedFields: const {});
    }
    final merged = deviceFieldMap(deviceFromRow(row))..addAll(fields);
    // 吊销不可被旧数据复活。
    if (row.revokedAt != null && !fields.containsKey('revoked_at')) {
      merged['revoked_at'] = row.revokedAt;
    }
    await db.into(db.devices).insertOnConflictUpdate(
        deviceCompanionFromFields(merged)
            .copyWith(deviceId: Value(op.entityId)));
    return ApplyRemoteResult(
        duplicate: false,
        appliedFields: fields.keys.toSet(),
        protectedFields: const {});
  }

  SyncOp _opWithFields(SyncOp op, Map<String, dynamic> fields) => SyncOp(
        opId: op.opId,
        deviceId: op.deviceId,
        lamport: op.lamport,
        entity: op.entity,
        entityId: op.entityId,
        opType: op.opType,
        fields: fields,
        createdAt: op.createdAt,
      );

  /// 合成落库用的完整字段表：行存在时 current 已被 LWW 原地更新；
  /// 行不存在时用（补过默认值的）op 字段。
  Map<String, dynamic> _fullMap(
      Map<String, dynamic>? current, Map<String, dynamic> opFields) {
    if (current != null) return current;
    return {...opFields};
  }

  void _sparseSessionDefaults(Map<String, dynamic> f) {
    f.putIfAbsent('image_hash', () => '');
    f.putIfAbsent('source_device', () => '');
    f.putIfAbsent('status', () => 'queued');
    f.putIfAbsent('created_at', () => 0);
    f.putIfAbsent('updated_at', () => 0);
    f.putIfAbsent('updated_by', () => '');
  }

  void _sparseCollectionDefaults(Map<String, dynamic> f) {
    f.putIfAbsent('name', () => '未命名合集');
    f.putIfAbsent('created_at', () => 0);
    f.putIfAbsent('updated_at', () => 0);
    f.putIfAbsent('updated_by', () => '');
  }

  void _sparseSessionImageDefaults(Map<String, dynamic> f) {
    f.putIfAbsent('session_id', () => '');
    f.putIfAbsent('ordinal', () => 0);
    f.putIfAbsent('image_hash', () => '');
    f.putIfAbsent('created_at', () => 0);
    f.putIfAbsent('updated_at', () => 0);
    f.putIfAbsent('updated_by', () => '');
  }

  void _sparseQuestionDefaults(Map<String, dynamic> f) {
    f.putIfAbsent('session_id', () => '');
    f.putIfAbsent('ordinal', () => 0);
    f.putIfAbsent('stem', () => '');
    f.putIfAbsent('material', () => '');
    f.putIfAbsent('type', () => 'subjective');
    f.putIfAbsent('created_at', () => 0);
    f.putIfAbsent('updated_at', () => 0);
    f.putIfAbsent('updated_by', () => '');
  }

  void _sparseImageDefaults(Map<String, dynamic> f) {
    f.putIfAbsent('size', () => 0);
    f.putIfAbsent('mime', () => 'image/jpeg');
    f.putIfAbsent('created_at', () => 0);
    f.putIfAbsent('uploaded_by', () => '');
  }

  void _sparseDeviceDefaults(Map<String, dynamic> f) {
    f.putIfAbsent('name', () => '');
    f.putIfAbsent('platform', () => 'android');
    f.putIfAbsent('paired_at', () => 0);
  }

  // ============================================================
  // settings（本地，不同步）
  // ============================================================

  Future<String?> getSetting(String key) async {
    final row =
        await (db.select(db.settings)..where((t) => t.key.equals(key)))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      db.into(db.settings).insertOnConflictUpdate(SettingRow(key: key, value: value));

  /// 读取（不清除）某题的「AI 新结果待覆盖」提示。
  Future<Map<String, dynamic>?> peekPendingOverwrite(String questionId) async {
    final raw = await getSetting('pending_overwrite:$questionId');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// 读取并清除某题的「AI 新结果待覆盖」提示。
  Future<Map<String, dynamic>?> takePendingOverwrite(String questionId) async {
    final key = 'pending_overwrite:$questionId';
    final raw = await getSetting(key);
    if (raw == null) return null;
    await (db.delete(db.settings)..where((t) => t.key.equals(key))).go();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// 用户显式点「用新结果覆盖」：清 edited 标记并应用暂存的字段。
  /// 只清**本次暂存字段覆盖到的**标记：原来无条件清 answer_edited，
  /// 会把用户手改的答案标记一起清掉（之后 AI 结果就能覆盖用户答案），
  /// 同时 analysis_edited 永远清不掉。
  Future<void> confirmPendingOverwrite(String questionId) async {
    final pending = await takePendingOverwrite(questionId);
    if (pending == null) return;
    final fields = Map<String, dynamic>.from(pending['fields'] as Map? ?? {});
    final q = await getQuestion(questionId, includeDeleted: true);
    if (q == null) return;
    var updated = q;
    final coversAnswer =
        fields.containsKey('choice_json') || fields.containsKey('answer_text');
    if (coversAnswer) {
      updated = updated.copyWith(answerEdited: false);
      if (fields.containsKey('choice_json')) {
        final choice = jsonDecode(fields['choice_json'] as String);
        updated = updated.copyWith(
            choice: choice is List
                ? choice.map((e) => e.toString()).toList()
                : const []);
      }
      if (fields.containsKey('answer_text')) {
        updated = updated.copyWith(answerText: fields['answer_text'] as String?);
      }
    }
    if (fields.containsKey('analysis')) {
      updated = updated.copyWith(
          analysis: fields['analysis'] as String? ?? '',
          analysisEdited: false);
    }
    await upsertQuestion(updated);
  }
}
