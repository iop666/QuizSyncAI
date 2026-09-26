import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// 用户需求 2 / 3 / 4 / 5 / 8 / 9 的核心层回归。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  const device = 'windows-local';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: device);
    await repo.init();
  });

  tearDown(() async => db.close());

  Future<Session> newSession({
    String? collectionId,
    String hash = 'h1',
    int createdAt = 1000,
  }) =>
      repo.upsertSession(Session(
        sessionId: newUuidV4(),
        collectionId: collectionId,
        imageHash: hash,
        sourceDevice: device,
        status: TaskState.done,
        createdAt: createdAt,
        updatedAt: createdAt,
        updatedBy: device,
      ));

  group('合集（用户需求 8/9/13）', () {
    test('新建 / 列表 / 软删除 + 生成 collection op', () async {
      final c = await repo.upsertCollection(Collection(
        collectionId: newUuidV4(),
        name: '期末复习',
        createdAt: nowMs(),
        updatedAt: nowMs(),
        updatedBy: device,
      ));
      expect((await repo.listCollections()).map((e) => e.name), ['期末复习']);

      final ops = await db.select(db.syncOps).get();
      expect(ops.where((o) => o.entity == 'collection').length, 1);

      await repo.deleteCollection(c.collectionId);
      expect(await repo.listCollections(), isEmpty);
      expect(await repo.getCollection(c.collectionId), isNull);
      final ops2 = await db.select(db.syncOps).get();
      expect(ops2.where((o) => o.opType == 'delete').length, 1);
      // 幂等：再删一次不得产生第二条 delete op（否则 tombstone 被推后）。
      await repo.deleteCollection(c.collectionId);
      expect((await db.select(db.syncOps).get()).length, ops2.length);
    });

    test('按合集筛选会话 + 识别顺序升序', () async {
      final a = await repo.upsertCollection(Collection(
          collectionId: 'ca',
          name: 'A',
          createdAt: 1,
          updatedAt: 1,
          updatedBy: device));
      final b = await repo.upsertCollection(Collection(
          collectionId: 'cb',
          name: 'B',
          createdAt: 2,
          updatedAt: 2,
          updatedBy: device));
      await newSession(collectionId: a.collectionId, hash: 'h-a1', createdAt: 10);
      await newSession(collectionId: a.collectionId, hash: 'h-a2', createdAt: 20);
      await newSession(collectionId: b.collectionId, hash: 'h-b1', createdAt: 30);
      await newSession(hash: 'h-legacy', createdAt: 5);

      expect((await repo.listSessions(collectionId: a.collectionId)).length, 2);
      final asc = await repo.listSessionsAscending(collectionId: a.collectionId);
      expect(asc.map((s) => s.imageHash), ['h-a1', 'h-a2']);
      expect(await repo.sessionCountOfCollection(b.collectionId), 1);
      // 未指定合集：全量（含历史「未分类」记录）。
      expect((await repo.listSessions()).length, 4);
    });

    test('合集经同步 op 传播到对端', () async {
      final peer = QuizSyncDb(NativeDatabase.memory());
      final peerRepo = CoreRepository(db: peer, deviceId: 'peer');
      await peerRepo.init();

      final c = await repo.upsertCollection(Collection(
        collectionId: 'c-sync',
        name: '同步合集',
        createdAt: 5,
        updatedAt: 5,
        updatedBy: device,
      ));
      final op = (await db.select(db.syncOps).get())
          .firstWhere((o) => o.entity == 'collection');
      await peerRepo.applyRemoteOp(opFromRow(op));

      final got = await peerRepo.getCollection(c.collectionId);
      expect(got?.name, '同步合集');
      await peer.close();
    });
  });

  group('M18 第 4 条：主机活跃合集列表的镜像（只增改不删）', () {
    Collection host(String id, String name, {int updatedAt = 100}) => Collection(
          collectionId: id,
          name: name,
          createdAt: 50,
          updatedAt: updatedAt,
          updatedBy: 'windows-local',
        );

    test('差什么补什么：主机有、本地没有 → 插进来；重复镜像不再写', () async {
      expect(await repo.mirrorCollections([host('c-a', '期末复习')]), 1);
      expect((await repo.listCollections()).map((c) => c.name), ['期末复习']);

      // 幂等：同样的列表再镜像一次，一行都不写（界面不必重建）。
      expect(await repo.mirrorCollections([host('c-a', '期末复习')]), 0);
    });

    test('主机改名 → 本地跟着改名', () async {
      await repo.mirrorCollections([host('c-a', '期末复习')]);
      expect(await repo.mirrorCollections([host('c-a', '期中复习', updatedAt: 200)]),
          1);
      expect((await repo.listCollections()).single.name, '期中复习');
    });

    test('主机删掉的合集在本地保留（用户要求「不再同步跟着删除」）', () async {
      await repo.mirrorCollections([host('c-a', 'A'), host('c-b', 'B')]);
      // 主机把 c-b 删了：列表里只剩 c-a。
      expect(await repo.mirrorCollections([host('c-a', 'A')]), 0);
      expect((await repo.listCollections()).map((c) => c.collectionId),
          containsAll(['c-a', 'c-b']),
          reason: '镜像只增改不删：主机没了不等于本地要丢分组');
      expect((await repo.getCollection('c-b'))?.isDeleted, isFalse);
    });

    test('本机删掉的合集不会被镜像复活（删除是本机的明确动作）', () async {
      await repo.mirrorCollections([host('c-a', 'A')]);
      await repo.deleteCollection('c-a');
      expect(await repo.getCollection('c-a'), isNull);

      // 主机那边还是活着的（op 还没推过去）：镜像必须视而不见，否则
      // 用户会看到「删了又自己回来」。
      expect(await repo.mirrorCollections([host('c-a', 'A')]), 0);
      expect(await repo.getCollection('c-a'), isNull);
    });

    test('镜像是本地写入：不产生 sync op（合集的主写入方是 Windows）', () async {
      final before = (await db.select(db.syncOps).get()).length;
      await repo.mirrorCollections([host('c-a', 'A')]);
      final after = await db.select(db.syncOps).get();
      expect(after.length, before, reason: '镜像不该把主机的东西再推回主机');
      expect(after.where((o) => o.entity == 'collection'), isEmpty);
    });

    test('安卓端口径：远端「删除合集」的 op 不落地（但 op 照常入库）', () async {
      final phoneDb = QuizSyncDb(NativeDatabase.memory());
      final phone = CoreRepository(
        db: phoneDb,
        deviceId: 'android-local',
        applyRemoteCollectionDeletes: false,
      );
      await phone.init();
      addTearDown(phoneDb.close);

      // 主机建合集 → 手机镜像拿到它。
      final created = await repo.upsertCollection(Collection(
          collectionId: 'c-a',
          name: 'A',
          createdAt: 50,
          updatedAt: 100,
          updatedBy: device));
      await phone.mirrorCollections([created]);
      expect(await phone.getCollection('c-a'), isNotNull);

      // 主机删掉它（Windows 端「新建/选择合集」页里的删除按钮走的就是这条）。
      await repo.deleteCollection('c-a');
      final deleteOp = (await db.select(db.syncOps).get())
          .firstWhere((o) => o.opType == 'delete');
      final r = await phone.applyRemoteOp(opFromRow(deleteOp));

      expect(r.duplicate, isFalse, reason: 'op 本身要入库，否则拉取游标会卡住');
      expect(r.appliedFields, isNot(contains('deleted_at')));
      expect(await phone.getCollection('c-a'), isNotNull,
          reason: 'M18 第 4 条：windows 端删除后安卓端不再同步跟着删除');
      expect(phone.clock.value, greaterThanOrEqualTo(deleteOp.lamport));
    });

    test('桌面端口径不变：远端删除照常落地', () async {
      final peer = QuizSyncDb(NativeDatabase.memory());
      final peerRepo = CoreRepository(db: peer, deviceId: 'peer');
      await peerRepo.init();
      addTearDown(peer.close);

      final c = await repo.upsertCollection(Collection(
          collectionId: 'c-x',
          name: 'X',
          createdAt: 1,
          updatedAt: 1,
          updatedBy: device));
      final createOp = (await db.select(db.syncOps).get())
          .firstWhere((o) => o.entity == 'collection');
      await peerRepo.applyRemoteOp(opFromRow(createOp));
      expect(await peerRepo.getCollection(c.collectionId), isNotNull);

      await repo.deleteCollection('c-x');
      final deleteOp = (await db.select(db.syncOps).get())
          .firstWhere((o) => o.opType == 'delete');
      await peerRepo.applyRemoteOp(opFromRow(deleteOp));
      expect(await peerRepo.getCollection('c-x'), isNull,
          reason: '默认值 true = 两端口径一致（桌面端/单测不受 M18 影响）');
    });
  });

  group('多页识别（用户需求 4）', () {
    test('setSessionImages 保序、幂等、可收缩', () async {
      final s = await newSession();
      await repo.setSessionImages(s.sessionId, ['p1', 'p2', 'p3']);
      expect(await repo.imageHashesOf(s.sessionId), ['p1', 'p2', 'p3']);

      final opsBefore = (await db.select(db.syncOps).get()).length;
      await repo.setSessionImages(s.sessionId, ['p1', 'p2', 'p3']);
      expect((await db.select(db.syncOps).get()).length, opsBefore,
          reason: '同序同 hash 不得产生新 op');

      await repo.setSessionImages(s.sessionId, ['p1']);
      expect(await repo.imageHashesOf(s.sessionId), ['p1']);
    });

    test('旧库没有 session_images 行时退回 sessions.image_hash', () async {
      final s = await newSession(hash: 'legacy-hash');
      expect(await repo.imageHashesOf(s.sessionId), ['legacy-hash']);
    });

    // 2026-09-26 真机反馈：手机结果页显示「2 张图片」，而主机只有 1 张。
    // 根因是两端各自为同一页建行（行 id 不同），同步后同一 ordinal 上出现两行，
    // 而「N 张图片」与页序都是按行数算的。
    test('两端各自建页行（id 不同）时不得叠成两页', () async {
      final s = await newSession();
      // 客户端按结果负载落页序：**自建行 id**（真机上就是这条路径）。
      await repo.setSessionImages(s.sessionId, ['p1']);

      // 主机侧为同一会话的同一页也建了自己的一行，并把它的 op 同步过来。
      final peerDb = QuizSyncDb(NativeDatabase.memory());
      final peerRepo = CoreRepository(db: peerDb, deviceId: 'peer-host');
      await peerRepo.init();
      addTearDown(peerDb.close);
      await peerRepo.upsertSession(Session(
        sessionId: s.sessionId,
        imageHash: 'p1',
        sourceDevice: device,
        status: TaskState.done,
        createdAt: 1000,
        updatedAt: 1000,
        updatedBy: device,
      ));
      await peerRepo.setSessionImages(s.sessionId, ['p1']);
      final pageOp = (await peerDb.select(peerDb.syncOps).get())
          .firstWhere((o) => o.entity == 'session_image');

      await repo.applyRemoteOp(opFromRow(pageOp));

      expect(await repo.imageHashesOf(s.sessionId), ['p1'],
          reason: 'ordinal 才是页的身份：两端的行 id 不同不该变成两页');
      expect(await repo.sessionImagesOf(s.sessionId), hasLength(1));
    });

    test('库里已有同 ordinal 的重复页行时，读取按 ordinal 收敛', () async {
      final s = await newSession();
      await repo.upsertSessionImage(SessionImage(
        sessionImageId: newUuidV4(),
        sessionId: s.sessionId,
        ordinal: 0,
        imageHash: 'p1',
        createdAt: 1000,
        updatedAt: 1000,
        updatedBy: device,
      ));
      await repo.upsertSessionImage(SessionImage(
        sessionImageId: newUuidV4(),
        sessionId: s.sessionId,
        ordinal: 0,
        imageHash: 'p1',
        createdAt: 1100,
        updatedAt: 1100,
        updatedBy: 'android-local',
      ));
      expect((await db.select(db.sessionImages).get()).length, 2,
          reason: '前置条件：库里确实有两行（真机上就是这种脏数据）');

      expect(await repo.sessionImagesOf(s.sessionId), hasLength(1));
      expect(await repo.imageHashesOf(s.sessionId), ['p1'],
          reason: '同一页只有一行，页数与页序不得翻倍');
    });

    test('多页任务：AI 一次收到全部页，reanalyze 起新任务', () async {
      final dir = await Directory.systemTemp.createTemp('quizsync-mp-');
      final store = DirectoryImageStore(dir.path);
      final p1 = Uint8List.fromList([1, 2, 3]);
      final p2 = Uint8List.fromList([4, 5, 6]);
      final h1 = sha256Hex(p1);
      final h2 = sha256Hex(p2);
      await store.write(h1, p1);
      await store.write(h2, p2);

      final provider = FakeAiProvider(
          File('test/fixtures/multi_and_judge.json').absolute.path);
      final executor = ServerTaskExecutor(
        repo: repo,
        engine: AnalysisEngine(
          provider: provider,
          cache: AnalysisCache(repo),
          quota: QuotaGuard(db),
          deviceId: device,
          retry: const RetryPolicy(sleeper: _noSleep),
        ),
        imageStore: store,
        configProvider: () =>
            const AiConfig(apiKey: 'k', model: 'm', providerId: 'fake'),
      );

      final (status, sessionId) = await executor.submit(
        taskId: newUuidV4(),
        imageHash: h1,
        imageHashes: [h1, h2],
        sourceDevice: 'android-1',
        collectionId: 'c1',
      );
      expect(status, 'queued');

      // 串行任务队列是异步的：等 session 落到 done。
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      Session? session;
      while (DateTime.now().isBefore(deadline)) {
        session = await repo.getSession(sessionId!);
        if (session != null && session.status == TaskState.done) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(session?.status, TaskState.done);
      expect(provider.lastImageCount, 2, reason: '两页必须同一次请求送出');
      expect(await repo.imageHashesOf(sessionId!), [h1, h2]);
      expect(session?.collectionId, 'c1');
      expect(session?.questionCount, 2);

      // 重新生成：新 task、强制重新调用 AI。
      final callsBefore = provider.callCount;
      final re = await executor.reanalyze(
          sessionId: sessionId, sourceDevice: 'android-1');
      final newSessionId = re.sessionId;
      expect(re.taskId, isNotEmpty, reason: '要能把任务号回给客户端');
      final deadline2 = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline2)) {
        final s2 = await repo.getSession(newSessionId!);
        if (s2 != null && s2.status == TaskState.done) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(provider.callCount, greaterThan(callsBefore));
      await dir.delete(recursive: true);
    });
  });

  group('题目不全与 AI 猜测（用户需求 2/3）', () {
    test('只有答案无题干的条目被丢弃，不完整选项标记 incomplete + 猜测', () async {
      final json = ResponseParser.tryParseJson(
          await File('test/fixtures/incomplete_questions.json').readAsString());
      final parsed = ResponseParser.toQuestions(json!,
          sessionId: 's1', deviceId: device);
      expect(parsed.droppedEmpty, 1, reason: '只有答案的条目必须被丢弃');
      expect(parsed.questions.length, 2);

      final guess = parsed.questions[0];
      expect(guess.questionNo, '12');
      expect(guess.incomplete, isTrue);
      expect(guess.answerGuessed, isTrue);
      expect(guess.choice, ['A']);
      expect(guess.shouldShowReviewBadge, isTrue);
      expect(guess.displayTitle, '1. 第 12 题', reason: '序号在前、题号在后');

      final complete = parsed.questions[1];
      expect(complete.incomplete, isFalse);
      expect(complete.answerGuessed, isFalse);
      expect(complete.displayTitle, '2. 第 (3) 题');
    });

    test('未声明但选项不足的单选题也判为不全', () {
      final q = Question.fromAiJson({
        'stem': '选出正确的选项',
        'type': 'single',
        'options': [
          {'label': 'A', 'text': 'a'},
        ],
        'answer': {'choice': ['A']},
      }, questionId: 'q', sessionId: 's', ordinal: 0, deviceId: device, now: 1);
      expect(q.incomplete, isTrue);
      expect(q.answerGuessed, isTrue, reason: '不全题目给出的答案视为推断');
      expect(q.warnings.any((w) => w.contains('选项不全')), isTrue);
    });

    test('判断题自动补对/错后不算不全', () {
      final q = Question.fromAiJson({
        'stem': '地球是圆的。',
        'type': 'judge',
        'answer': {'choice': ['对']},
      }, questionId: 'q', sessionId: 's', ordinal: 0, deviceId: device, now: 1);
      expect(q.incomplete, isFalse);
      expect(q.answerGuessed, isFalse);
    });

    test('无题号时 displayTitle 只有序号', () {
      final q = Question.fromAiJson({
        'stem': '题干够长了',
        'type': 'blank',
        'answer': {'text': 'x'},
      }, questionId: 'q', sessionId: 's', ordinal: 4, deviceId: device, now: 1);
      expect(q.displayTitle, '5.');
    });

    test('标记经 DB 往返与同步 op 保留', () async {
      final s = await newSession();
      final q = await repo.upsertQuestion(Question(
        questionId: 'q1',
        sessionId: s.sessionId,
        ordinal: 0,
        stem: '被截断的题干',
        type: QuestionType.single,
        options: const [Option(label: 'A', text: 'a')],
        choice: const ['A'],
        incomplete: true,
        answerGuessed: true,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: device,
      ));
      expect(q.incomplete, isTrue);
      final reread = await repo.getQuestion('q1');
      expect(reread?.incomplete, isTrue);
      expect(reread?.answerGuessed, isTrue);

      final peer = QuizSyncDb(NativeDatabase.memory());
      final peerRepo = CoreRepository(db: peer, deviceId: 'peer');
      await peerRepo.init();
      for (final row in await db.select(db.syncOps).get()) {
        await peerRepo.applyRemoteOp(opFromRow(row));
      }
      final remote = await peerRepo.getQuestion('q1');
      expect(remote?.incomplete, isTrue);
      expect(remote?.answerGuessed, isTrue);
      await peer.close();
    });

    test('阅读材料 material 经 DB 往返与同步 op 保留（用户反馈 15）', () async {
      final s = await newSession();
      await repo.upsertQuestion(Question(
        questionId: 'qm',
        sessionId: s.sessionId,
        ordinal: 0,
        stem: '下列说法正确的是',
        material: '材料第一段。\n材料第二段。',
        type: QuestionType.single,
        options: const [
          Option(label: 'A', text: 'a'),
          Option(label: 'B', text: 'b'),
        ],
        choice: const ['A'],
        createdAt: 1,
        updatedAt: 1,
        updatedBy: device,
      ));
      final reread = await repo.getQuestion('qm');
      expect(reread?.material, '材料第一段。\n材料第二段。');
      expect(reread?.hasMaterial, isTrue);

      final peer = QuizSyncDb(NativeDatabase.memory());
      final peerRepo = CoreRepository(db: peer, deviceId: 'peer');
      await peerRepo.init();
      for (final row in await db.select(db.syncOps).get()) {
        await peerRepo.applyRemoteOp(opFromRow(row));
      }
      final remote = await peerRepo.getQuestion('qm');
      expect(remote?.material, '材料第一段。\n材料第二段。');
      await peer.close();
    });
  });

  group('图片缓存上限（用户需求 5）', () {
    test('maxFiles = 0 表示不设限；上限生效时删最旧', () async {
      for (var i = 0; i < 4; i++) {
        await repo.upsertImage(ImageMeta(
          hash: 'img$i',
          size: 1,
          mime: 'image/jpeg',
          localPath: 'C:/img$i.jpg',
          createdAt: i,
          uploadedBy: device,
        ));
      }
      final paths = <String>[];
      expect(
          await pruneImageFiles(repo, (h) => 'C:/$h.jpg',
              maxFiles: 0, onDelete: (p) async => paths.add(p)),
          0);
      expect((await repo.getImage('img0'))?.localPath, isNotNull);

      expect(
          await pruneImageFiles(repo, (h) => 'C:/$h.jpg',
              maxFiles: 2, onDelete: (p) async => paths.add(p)),
          2);
      expect(paths, ['C:/img0.jpg', 'C:/img1.jpg']);
      expect((await repo.getImage('img0'))?.localPath, isNull);
      expect((await repo.getImage('img3'))?.localPath, isNotNull);
    });
  });

  group('合集导出（用户需求 9）', () {
    test('按识别顺序排序，题号带序号前缀', () async {
      final records = <(Session, List<Question>)>[];
      for (var i = 0; i < 2; i++) {
        final s = await newSession(hash: 'e$i', createdAt: 100 + i);
        final q = await repo.upsertQuestion(Question(
          questionId: 'eq$i',
          sessionId: s.sessionId,
          ordinal: 0,
          questionNo: '${10 + i}',
          stem: '题干 $i',
          type: QuestionType.single,
          options: const [
            Option(label: 'A', text: 'a'),
            Option(label: 'B', text: 'b'),
          ],
          choice: const ['B'],
          incomplete: i == 1,
          answerGuessed: i == 1,
          createdAt: 100 + i,
          updatedAt: 100 + i,
          updatedBy: device,
        ));
        records.add((s, [q]));
      }
      final md = Exporter.collectionToMarkdown('期末复习', records);
      expect(md, contains('# 任务合集：期末复习'));
      expect(md, contains('## 第 1 次识别'));
      expect(md, contains('## 第 2 次识别'));
      expect(md, contains('1. 第 10 题'));
      expect(md, contains('题目不全'));
      expect(md, contains('AI 猜测'));
      expect(md.indexOf('第 1 次识别'), lessThan(md.indexOf('第 2 次识别')));
    });
  });
}

Future<void> _noSleep(Duration _) async {}
