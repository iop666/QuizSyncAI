import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

class CountingProvider extends QuizAiProvider {
  int callCount = 0;
  final String text;

  CountingProvider(this.text);

  @override
  String get id => 'counting';

  @override
  Future<AiRawResponse> analyze({
    required List<Uint8List> jpegBytesList,
    required String prompt,
    required AiConfig config,
  }) async {
    callCount++;
    return AiRawResponse(text: text, latencyMs: 10);
  }
}

const okJson = '{"questions":[{"stem":"光的折射","type":"single",'
    '"options":[{"label":"A","text":"a"},{"label":"B","text":"b"}],'
    '"answer":{"choice":["B"]},"analysis":"","confidence":0.9}]}';

Future<CoreRepository> seedDoneSession(
  QuizSyncDb db, {
  required String imageHash,
  required String model,
  String promptVersion = 'unset',
  int? createdAt,
}) async {
  final repo = CoreRepository(db: db, deviceId: 'dev');
  final ts = createdAt ?? nowMs();
  await repo.upsertSession(Session(
    sessionId: 'seed-$imageHash-$model',
    imageHash: imageHash,
    sourceDevice: 'dev',
    status: TaskState.done,
    aiModel: model,
    promptVersion: promptVersion == 'unset' ? computePromptVersion() : promptVersion,
    questionCount: 1,
    createdAt: ts,
    updatedAt: ts,
    updatedBy: 'dev',
  ));
  await repo.upsertQuestion(Question(
    questionId: 'seedq-$imageHash-$model',
    sessionId: 'seed-$imageHash-$model',
    ordinal: 0,
    stem: '光的折射',
    type: QuestionType.single,
    options: const [Option(label: 'A', text: 'a'), Option(label: 'B', text: 'b')],
    choice: const ['B'],
    createdAt: ts,
    updatedAt: ts,
    updatedBy: 'dev',
  ));
  return repo;
}

QuizSyncDb mkDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return QuizSyncDb(NativeDatabase.memory());
}

void main() {
  group('AnalysisCache（ai-contract.md 第 4 节）', () {
    test('同一 hash+prompt+model 连续两次：第二次不触发 provider', () async {
      final db = mkDb();
      final repo = await seedDoneSession(db, imageHash: 'h1', model: 'm1');
      final provider = CountingProvider(okJson);
      final engine = AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: QuotaGuard(db, dailyLimit: 200),
        deviceId: 'dev',
        retry: const RetryPolicy(sleeper: _noSleep),
      );

      final bytes = Uint8List.fromList([1]);
      final first = await engine.analyzeImage(
          jpegBytes: bytes, imageHash: 'h1', config: const AiConfig(model: 'm1'));
      expect(first.fromCache, isTrue, reason: '已有 done 会话 → 直接命中');
      expect(first.questions.first.choice, ['B']);
      expect(provider.callCount, 0, reason: '缓存命中绝不调用 API');

      final second = await engine.analyzeImage(
          jpegBytes: bytes, imageHash: 'h1', config: const AiConfig(model: 'm1'));
      expect(second.fromCache, isTrue);
      expect(provider.callCount, 0);
      await db.close();
    });

    test('不同 model → 不命中，真实调用', () async {
      final db = mkDb();
      final repo = await seedDoneSession(db, imageHash: 'h1', model: 'm1');
      final provider = CountingProvider(okJson);
      final engine = AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: QuotaGuard(db, dailyLimit: 200),
        deviceId: 'dev',
        retry: const RetryPolicy(sleeper: _noSleep),
      );
      final out = await engine.analyzeImage(
          jpegBytes: Uint8List.fromList([1]),
          imageHash: 'h1',
          config: const AiConfig(model: 'm2'));
      expect(out.fromCache, isFalse);
      expect(provider.callCount, 1);
      await db.close();
    });

    test('超过 30 天 → 不命中', () async {
      final db = mkDb();
      final repo = await seedDoneSession(
        db,
        imageHash: 'h1',
        model: 'm1',
        createdAt: 1000,
      );
      final provider = CountingProvider(okJson);
      final engine = AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo, now: () => 1000 + 31 * 24 * 3600 * 1000),
        quota: QuotaGuard(db, dailyLimit: 200),
        deviceId: 'dev',
        retry: const RetryPolicy(sleeper: _noSleep),
      );
      final out = await engine.analyzeImage(
          jpegBytes: Uint8List.fromList([1]),
          imageHash: 'h1',
          config: const AiConfig(model: 'm1'));
      expect(out.fromCache, isFalse);
      expect(provider.callCount, 1);
      await db.close();
    });
  });

  group('QuotaGuard', () {
    test('达到每日上限：明确失败且不调用 provider，缓存命中不计入', () async {
      final db = mkDb();
      final repo = await seedDoneSession(db, imageHash: 'h1', model: 'm1');
      final quota = QuotaGuard(db, dailyLimit: 2);
      // 预置 2 条今日用量
      await quota.recordUsage(
          model: 'm1', promptVersion: 'v1', imageHash: 'x', ok: true);
      await quota.recordUsage(
          model: 'm1', promptVersion: 'v1', imageHash: 'y', ok: false);

      final provider = CountingProvider(okJson);
      final engine = AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: quota,
        deviceId: 'dev',
        retry: const RetryPolicy(sleeper: _noSleep),
      );

      // 缓存命中不受配额影响
      final cached = await engine.analyzeImage(
          jpegBytes: Uint8List.fromList([1]),
          imageHash: 'h1',
          config: const AiConfig(model: 'm1'));
      expect(cached.fromCache, isTrue);

      // 未命中 + 配额已满 → ai_quota_exceeded，provider 未被调用
      final blocked = await engine.analyzeImage(
          jpegBytes: Uint8List.fromList([1]),
          imageHash: 'h2',
          config: const AiConfig(model: 'm1'));
      expect(blocked.errorCode, 'ai_quota_exceeded');
      expect(blocked.errorMessage, contains('今日调用已达上限'));
      expect(provider.callCount, 0);
      expect(await quota.usedToday(), 2);
      await db.close();
    });

    test('用量记录包含模型 / prompt 版本 / 耗时 / 成败', () async {
      final db = mkDb();
      final repo = CoreRepository(db: db, deviceId: 'dev');
      final provider = CountingProvider(okJson);
      final engine = AnalysisEngine(
        provider: provider,
        cache: AnalysisCache(repo),
        quota: QuotaGuard(db),
        deviceId: 'dev',
        retry: const RetryPolicy(sleeper: _noSleep),
      );
      final out = await engine.analyzeImage(
          jpegBytes: Uint8List.fromList([1]),
          imageHash: 'hq',
          config: const AiConfig(model: 'm1'));
      expect(out.errorCode, isNull);
      final rows = await db.select(db.aiUsage).get();
      expect(rows.length, 1);
      expect(rows.first.model, 'm1');
      expect(rows.first.ok, isTrue);
      expect(rows.first.promptVersion, computePromptVersion());
      await db.close();
    });

    // M44 第 2 条（用户要求「每日调用上限添加一个不设上限」）：上限 ≤ 0 = 不设上限，
    // 用量照样记录（只做统计），但永不拦住调用。
    test('不设上限（dailyLimit = 0 / 负数）：照样调用，用量照记', () async {
      for (final limit in [0, -1]) {
        final db = mkDb();
        final repo = CoreRepository(db: db, deviceId: 'dev');
        final quota = QuotaGuard(db, dailyLimit: limit);
        expect(quota.unlimited, isTrue);
        expect(await quota.canCall, isTrue);
        final provider = CountingProvider(okJson);
        final engine = AnalysisEngine(
          provider: provider,
          cache: AnalysisCache(repo),
          quota: quota,
          deviceId: 'dev',
          retry: const RetryPolicy(sleeper: _noSleep),
        );
        // 连续 3 次都要真的调 provider（不会因为「用量超过 0」被拦）。
        for (var i = 0; i < 3; i++) {
          final out = await engine.analyzeImage(
              jpegBytes: Uint8List.fromList([1]),
              imageHash: 'h-unlimited-$limit-$i',
              config: const AiConfig(model: 'm1'));
          expect(out.errorCode, isNull);
        }
        expect(provider.callCount, 3);
        expect(await quota.usedToday(), 3, reason: '不设上限也要记录用量（统计用）');
        await db.close();
      }
    });

    test('有限上限时 unlimited = false（默认 200）', () async {
      final db = mkDb();
      final quota = QuotaGuard(db);
      expect(quota.dailyLimit, 200);
      expect(quota.unlimited, isFalse);
      expect(await quota.canCall, isTrue);
      await db.close();
    });
  });
}

Future<void> _noSleep(Duration d) async {}
