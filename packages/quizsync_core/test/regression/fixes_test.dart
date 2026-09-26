import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:test/test.dart';

import '../db/support.dart';

/// 本轮修复的回归测试（每条都对应一个已复现的真实缺陷）。
void main() {
  group('AI 引擎：缓存与 force_reanalyze', () {
    test('useCache:false 时即使有命中缓存也必须真实调用 AI', () async {
      final db = createTestDb();
      final repo = createTestRepo(db, 'dev-a');
      var calls = 0;
      final provider = _CountingProvider(() {
        calls++;
        return _fixture('single_choice.json');
      });
      final engine = AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: QuotaGuard(db),
        deviceId: 'dev-a',
      );
      const config = AiConfig(model: 'm');

      // 造一条 done 会话 + 题目作为缓存条目。
      await repo.upsertSession(Session(
        sessionId: 'cached-s',
        imageHash: 'h1',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        aiModel: 'm',
        promptVersion: computePromptVersion(),
        questionCount: 1,
        createdAt: nowMs(),
        updatedAt: nowMs(),
        updatedBy: 'dev-a',
      ));
      await repo.upsertQuestion(Question(
        questionId: 'cached-q',
        sessionId: 'cached-s',
        ordinal: 0,
        stem: '缓存题干',
        type: QuestionType.blank,
        answerText: '缓存答案',
        createdAt: nowMs(),
        updatedAt: nowMs(),
        updatedBy: 'dev-a',
      ));

      // 默认路径命中缓存，不调 AI。
      final hit = await engine.analyzeImage(
          jpegBytes: Uint8List.fromList([1]), imageHash: 'h1', config: config);
      expect(hit.fromCache, isTrue);
      expect(calls, 0);

      // force_reanalyze 语义：必须真的再问一次。
      final forced = await engine.analyzeImage(
        jpegBytes: Uint8List.fromList([1]),
        imageHash: 'h1',
        config: config,
        useCache: false,
      );
      expect(forced.fromCache, isFalse);
      expect(calls, 1, reason: '跳过缓存必须真实调用 provider');
      await db.close();
    });
  });

  group('服务端任务执行器', () {
    test('force_reanalyze 的新任务真的调用 AI，且新会话有题目', () async {
      final db = createTestDb();
      final repo = createTestRepo(db, 'server-1');
      await repo.init();
      var calls = 0;
      final provider = _CountingProvider(() {
        calls++;
        return _fixture('single_choice.json');
      });
      final store = MemoryImageStore();
      final engine = AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: QuotaGuard(db),
        deviceId: 'server-1',
      );
      final executor = ServerTaskExecutor(
        repo: repo,
        engine: engine,
        imageStore: store,
        configProvider: () => const AiConfig(apiKey: 'k', model: 'm'),
      );

      await store.write('h1', Uint8List.fromList([1, 2, 3]));
      await repo.upsertImage(ImageMeta(
        hash: 'h1',
        size: 3,
        mime: 'image/jpeg',
        createdAt: nowMs(),
        uploadedBy: 'server-1',
      ));

      // 第一次分析。
      await executor.submit(
          taskId: 't1', imageHash: 'h1', sourceDevice: 'android-1');
      await _waitIdle(db);
      expect(calls, 1);

      // 第二次带 force_reanalyze + 新 task_id：必须再调一次 AI，
      // 而且新会话必须真的拿到题目（原来会命中缓存、写成 done + 0 道题）。
      final (_, sessionId) = await executor.submit(
        taskId: 't2',
        imageHash: 'h1',
        sourceDevice: 'android-1',
        forceReanalyze: true,
      );
      await _waitIdle(db);
      expect(calls, 2, reason: 'force_reanalyze 必须绕开缓存');
      final questions = await repo.questionsOfSession(sessionId!);
      expect(questions, isNotEmpty, reason: '新会话不能是 0 道题');
      final session = await repo.getSession(sessionId);
      expect(session!.status, TaskState.done);
      expect(session.questionCount, questions.length);
      await db.close();
    });
  });

  group('备份与恢复', () {
    test('zip-slip：images/../ 条目不得写到图片目录之外', () async {
      final root = await Directory.systemTemp.createTemp('quizsync-zip-');
      final imagesDir = '${root.path}/images';
      final escaped = '${root.path}/escaped.jpg';

      final archive = Archive()
        ..addFile(ArchiveFile('images/../escaped.jpg', 3, [1, 2, 3]))
        ..addFile(ArchiveFile('images/../../escaped2.jpg', 3, [1, 2, 3]));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);

      await BackupManager.restore(
        zipBytes: zip,
        dbPath: '${root.path}/quizsync.db',
        imagesDir: imagesDir,
      );
      expect(File(escaped).existsSync(), isFalse, reason: '不得写到 images 之外');
      expect(File('${root.path}/../escaped2.jpg').existsSync(), isFalse);
      await root.delete(recursive: true);
    });

    test('包里没有数据库时不得删掉现有数据库', () async {
      final root = await Directory.systemTemp.createTemp('quizsync-keep-');
      final dbPath = '${root.path}/quizsync.db';
      await File(dbPath).writeAsBytes([9, 9, 9]);

      // 只有图片的包。
      final archive = Archive()
        ..addFile(ArchiveFile('images/a.jpg', 2, [1, 2]));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);

      await BackupManager.restore(
        zipBytes: zip,
        dbPath: dbPath,
        imagesDir: '${root.path}/images',
      );
      expect(File(dbPath).existsSync(), isTrue, reason: '现有数据库必须保留');
      expect(File(dbPath).readAsBytesSync(), [9, 9, 9]);
      await root.delete(recursive: true);
    });

    test('启动时换入暂存的库（暂存恢复的唯一生效通路）', () async {
      final root = await Directory.systemTemp.createTemp('quizsync-stage2-');
      final dbPath = '${root.path}/quizsync.db';

      // 备份里的库（含一条会话）。
      final srcDir = await Directory.systemTemp.createTemp('quizsync-src2-');
      final srcDbPath = '${srcDir.path}/quizsync.db';
      final srcDb = openQuizSyncDb(srcDbPath);
      final repo = CoreRepository(db: srcDb, deviceId: 'dev-a');
      await repo.upsertSession(Session(
        sessionId: 'staged-s',
        imageHash: 'h',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      await srcDb.close();

      // 现有库 + 上一个运行期留下的暂存文件。
      await File(dbPath).writeAsBytes([1, 2, 3]);
      File(srcDbPath).copySync('$dbPath.restore-pending');
      expect(BackupManager.hasPendingRestore(dbPath), isTrue);

      expect(BackupManager.applyPendingRestore(dbPath), isTrue);
      expect(BackupManager.hasPendingRestore(dbPath), isFalse);
      // 旧库留底，新库可用。
      final backups = root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.pre-restore-'))
          .toList();
      expect(backups, isNotEmpty, reason: '换入前要留底');
      final db2 = openQuizSyncDb(dbPath);
      final repo2 = CoreRepository(db: db2, deviceId: 'dev-a');
      expect((await repo2.listSessions()).single.sessionId, 'staged-s');
      await db2.close();

      await root.delete(recursive: true);
      await srcDir.delete(recursive: true);
    });

    test('库文件被占用时恢复不破坏现有数据', () async {
      final root = await Directory.systemTemp.createTemp('quizsync-lock-');
      final dbPath = '${root.path}/quizsync.db';
      await File(dbPath).writeAsBytes([1, 2, 3]);

      final archive = Archive()
        ..addFile(ArchiveFile('quizsync.db', 4, [5, 6, 7, 8]));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final lock = File(dbPath).openSync(mode: FileMode.append);
      final applied = await BackupManager.restore(
        zipBytes: zip,
        dbPath: dbPath,
        imagesDir: '${root.path}/images',
      );
      lock.close();

      expect(File(dbPath).existsSync(), isTrue, reason: '恢复不能把现有库弄丢');
      if (!applied) {
        // 被占用 → 暂存，等下次启动。
        expect(BackupManager.hasPendingRestore(dbPath), isTrue);
        expect(File(dbPath).readAsBytesSync(), [1, 2, 3]);
      }
      await root.delete(recursive: true);
    });
  });

  group('仓库：本地路径 / 幂等删除 / 手改保护', () {
    test('upsertImage 不会因为其它字段变化而清掉 local_path', () async {
      final db = createTestDb();
      final repo = createTestRepo(db, 'dev-a');
      await repo.upsertImage(ImageMeta(
        hash: 'h1',
        size: 10,
        mime: 'image/jpeg',
        localPath: 'C:/img/h1.jpg',
        createdAt: 1,
        uploadedBy: 'dev-a',
      ));
      await repo.upsertImage(ImageMeta(
        hash: 'h1',
        size: 10,
        mime: 'image/jpeg',
        width: 100,
        height: 50,
        createdAt: 1,
        uploadedBy: 'dev-a',
      ));
      final meta = await repo.getImage('h1');
      expect(meta!.localPath, 'C:/img/h1.jpg', reason: '传 null = 不改变已有路径');
      await db.close();
    });

    test('deleteSession 幂等：第二次不再产生 delete op、不推迟 GC', () async {
      final db = createTestDb();
      final repo = createTestRepo(db, 'dev-a');
      await repo.upsertSession(Session(
        sessionId: 's1',
        imageHash: 'h1',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      await repo.deleteSession('s1');
      final first = await repo.getSession('s1', includeDeleted: true);
      await repo.deleteSession('s1');
      final second = await repo.getSession('s1', includeDeleted: true);
      expect(second!.deletedAt, first!.deletedAt);
      final deleteOps = (await db.select(db.syncOps).get())
          .where((o) => o.opType == 'delete')
          .toList();
      expect(deleteOps.length, 1, reason: '一条软删除只对应一条 delete op');
      await db.close();
    });

    test('对端用户手改的答案按 LWW 合入（不会被 user_edited 保护吃掉）', () async {
      final dbA = createTestDb();
      final dbB = createTestDb();
      final a = createTestRepo(dbA, 'dev-a');
      final b = createTestRepo(dbB, 'dev-b');

      Question q(String device) => Question(
            questionId: 'q1',
            sessionId: 's1',
            ordinal: 0,
            stem: '题干',
            type: QuestionType.single,
            options: const [
              Option(label: 'A', text: 'a'),
              Option(label: 'B', text: 'b'),
              Option(label: 'C', text: 'c'),
            ],
            choice: const ['A'],
            createdAt: 1,
            updatedAt: 1,
            updatedBy: device,
          );
      await a.upsertQuestion(q('dev-a'));
      await b.upsertQuestion(q('dev-b'));

      // B 手改答案 → A 应用（B 的 lamport 更高）。
      await b.updateUserAnswer('q1', const AnswerValue(choice: ['B']));
      for (final op in await dbB.select(dbB.syncOps).get()) {
        await a.applyRemoteOp(opFromRow(op));
      }
      expect((await a.getQuestion('q1'))!.choice, ['B'], reason: '对端手改要生效');

      // A 再手改（lamport 更高）→ B 应用 → 两端一致于 A 的值。
      await a.updateUserAnswer('q1', const AnswerValue(choice: ['C']));
      for (final op in await dbA.select(dbA.syncOps).get()) {
        await b.applyRemoteOp(opFromRow(op));
      }
      expect((await b.getQuestion('q1'))!.choice, ['C'],
          reason: '两端必须收敛到最新的用户手改');
      await dbA.close();
      await dbB.close();
    });

    test('applyRemoteOp 不修改调用方传入的 op.fields', () async {
      final db = createTestDb();
      final repo = createTestRepo(db, 'dev-a');
      final op = SyncOp(
        opId: 'op-1',
        deviceId: 'dev-b',
        lamport: 5,
        entity: SyncEntity.question,
        entityId: 'q1',
        opType: SyncOpType.upsert,
        fields: const {'stem': '只有题干'},
        createdAt: 5,
      );
      await repo.applyRemoteOp(op);
      expect(op.fields.keys.toSet(), {'stem'},
          reason: '不得把补的默认值写回调用方的 op');
      await db.close();
    });
  });

  group('检索：FTS5 缺失时退化 LIKE', () {
    test('虚拟表被删掉后 searchQuestions 仍能返回结果', () async {
      final db = createTestDb();
      final repo = createTestRepo(db, 'dev-a');
      await repo.upsertSession(Session(
        sessionId: 's1',
        imageHash: 'h1',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      await repo.upsertQuestion(Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: 0,
        stem: 'hello world',
        type: QuestionType.blank,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      // 模拟不支持 FTS5 的设备：把虚拟表删掉。
      await db.customStatement('DROP TABLE questions_fts');
      final hits = await repo.searchQuestions('hello');
      expect(hits.single.stem, 'hello world');
      await db.close();
    });

    test('短查询的 LIKE 会转义 _ 与 %', () async {
      final db = createTestDb();
      final repo = createTestRepo(db, 'dev-a');
      await repo.upsertSession(Session(
        sessionId: 's1',
        imageHash: 'h1',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      await repo.upsertQuestion(Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: 0,
        stem: 'abc',
        type: QuestionType.blank,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      expect(await repo.searchQuestions('a_'), isEmpty,
          reason: '_ 是通配符，必须转义成字面量');
      await db.close();
    });
  });

  group('离线队列', () {
    test('坏任务超过重试上限后不再阻塞后面的任务', () async {
      final db = createTestDb();
      final queue = OfflineQueue(db, maxAttempts: 2);
      await queue.enqueue(imageHash: 'bad', sourceDevice: 'dev-a');
      await queue.enqueue(imageHash: 'good', sourceDevice: 'dev-a');

      // 第一次：坏任务失败 → 停手（attempts=1）。
      var drained = await queue.drain((t) async => t.imageHash == 'good');
      expect(drained, 0);
      // 第二次：attempts 到 2 → 判死信并继续 → 后面的好任务被处理。
      drained = await queue.drain((t) async => t.imageHash == 'good');
      expect(drained, 1, reason: '死信不得永久堵住队列');
      final rows = await db.select(db.tasks).get();
      expect(rows.firstWhere((t) => t.imageHash == 'bad').status, 'failed');
      expect(rows.firstWhere((t) => t.imageHash == 'good').status, 'done');
      await db.close();
    });
  });

  group('AI provider：非 JSON 错误体', () {
    test('状态码仍被正确分类（可重试 / 鉴权）', () async {
      Future<HttpServer> stub(int code, String body) async {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        s.listen((req) async {
          req.response
            ..statusCode = code
            ..headers.contentType = ContentType.html
            ..write(body);
          await req.response.close();
        });
        return s;
      }

      final s500 = await stub(500, '<html>bad gateway</html>');
      final s401 = await stub(401, 'plain text unauthorized');

      final p500 = OpenAiCompatibleProvider();
      await expectLater(
        p500.analyze(
          jpegBytesList: [Uint8List.fromList([1])],
          prompt: 'p',
          config: AiConfig(
              apiKey: 'k',
              model: 'm',
              baseUrl: 'http://127.0.0.1:${s500.port}',
              providerId: 'openai-compatible'),
        ),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.serverError)),
        reason: '5xx 必须可重试，不能因为响应体不是 JSON 就变成 unknown',
      );

      final p401 = OpenAiCompatibleProvider();
      await expectLater(
        p401.analyze(
          jpegBytesList: [Uint8List.fromList([1])],
          prompt: 'p',
          config: AiConfig(
              apiKey: 'k',
              model: 'm',
              baseUrl: 'http://127.0.0.1:${s401.port}',
              providerId: 'openai-compatible'),
        ),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.auth)),
      );
      await s500.close(force: true);
      await s401.close(force: true);
    });
  });

  group('ApiClient：传输层失败统一为 ApiClientException', () {
    test('主机未运行 → network_error', () async {
      // 端口 1 基本不会有人监听。
      final api = ApiClient(baseUrl: 'http://127.0.0.1:1', token: 't');
      await expectLater(
        api.fetchInfo(),
        throwsA(isA<ApiClientException>()
            .having((e) => e.code, 'code', 'network_error')),
      );
    });
  });
}

Future<void> _waitIdle(QuizSyncDb db, {int maxMs = 5000}) async {
  final start = DateTime.now();
  while (DateTime.now().difference(start).inMilliseconds < maxMs) {
    // 全部读出来在 Dart 侧过滤，避免依赖 drift 的表达式运算符扩展。
    final all = await db.select(db.tasks).get();
    final active =
        all.where((t) => t.status == 'queued' || t.status == 'analyzing');
    if (active.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

class _CountingProvider extends QuizAiProvider {
  final String Function() next;
  _CountingProvider(this.next);

  @override
  String get id => 'counting';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async =>
      AiRawResponse(text: next(), latencyMs: 1);
}
