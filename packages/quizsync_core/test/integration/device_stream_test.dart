import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:test/test.dart';

/// 用户反馈：Windows 主界面右上角的配对状态**一直显示「未配对」**。
///
/// 根因不在文案而在数据来源：药丸只在挂载时查一次库，之后谁配对、谁吊销都
/// 不会让它重算。所以这里用**真服务端 + 真 HTTP 配对**验证那条链路本身——
/// `watchDevices()` 必须把 `/pair` 写库的结果推出来，吊销时也要再推一次。
///
/// （药丸自己的文案与自更新由 `apps/desktop/test/home_page_test.dart` 的
/// widget 用例覆盖；这一条管的是「库变更能不能流到界面」。）
void main() {
  late QuizSyncDb serverDb;
  late CoreRepository serverRepo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late StreamSubscription<List<DeviceInfo>> sub;
  final emissions = <List<DeviceInfo>>[];
  const clientDeviceId = 'android-device-1';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    emissions.clear();
    serverDb = QuizSyncDb(NativeDatabase.memory());
    serverRepo = CoreRepository(db: serverDb, deviceId: 'server-device-1');
    await serverRepo.init();
    imageDir = await Directory.systemTemp.createTemp('quizsync-images-');

    final engine = AnalysisEngine(
      provider: FakeAiProvider(
          File('test/fixtures/multi_and_judge.json').absolute.path),
      cache: AnalysisCache(serverRepo),
      quota: QuotaGuard(serverDb),
      deviceId: 'server-device-1',
    );
    server = QuizSyncServer(
      repo: serverRepo,
      imageStore: DirectoryImageStore(imageDir.path),
      executor: ServerTaskExecutor(
        repo: serverRepo,
        engine: engine,
        imageStore: DirectoryImageStore(imageDir.path),
        configProvider: () => const AiConfig(
          providerId: 'openai-compatible',
          apiKey: 'test-key',
          model: 'test-model',
        ),
      ),
      deviceId: 'server-device-1',
      serverName: 'TEST-HOST',
      options: const QuizSyncServerOptions(preferredPort: 0),
    );
    port = await server.start();
    // 订阅要在配对之前建立，模拟「应用早就开着，手机后来才配对」。
    sub = serverRepo.watchDevices().listen(emissions.add);
  });

  tearDown(() async {
    await sub.cancel();
    await server.stop();
    await serverDb.close();
    await imageDir.delete(recursive: true);
  });

  /// 轮询已收到的推送，等到符合条件的那一次（drift 的流是异步推送）。
  Future<List<DeviceInfo>> waitFor(
    bool Function(List<DeviceInfo>) ok, {
    int from = 0,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      for (var i = from; i < emissions.length; i++) {
        if (ok(emissions[i])) return emissions[i];
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('等不到符合条件的推送；共收到 ${emissions.length} 次：$emissions');
  }

  test('配对与吊销都会推到 watchDevices()：药丸不必重启就能变', () async {
    final noAuth = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '');
    final empty = await waitFor((list) => list.isEmpty);
    expect(empty, isEmpty, reason: '还没配对时推的是空列表（药丸据此写「未配对」）');

    final paired = await noAuth.pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel 7',
      platform: 'android',
      appVersion: '1.0.0',
    ));

    final afterPair = await waitFor(
        (list) => list.any((d) => d.deviceId == clientDeviceId));
    final device = afterPair.singleWhere((d) => d.deviceId == clientDeviceId);
    expect(device.platform, 'android');
    expect(device.isRevoked, isFalse);

    await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: paired.token)
        .revokeDevice(clientDeviceId);

    // 吊销后必须再推一次，且默认（includeRevoked: false）里已经没有它。
    final from = emissions.indexOf(afterPair) + 1;
    final afterRevoke = await waitFor((list) => list.isEmpty, from: from);
    expect(afterRevoke, isEmpty, reason: '吊销掉的设备不算已配对，药丸要退回「未配对」');

    // 参数语义：要历史设备就显式 includeRevoked。
    final all = await serverRepo.listDevices();
    expect(all.singleWhere((d) => d.deviceId == clientDeviceId).isRevoked, isTrue);
    expect(await serverRepo.watchDevices(includeRevoked: true).first,
        hasLength(1));
  });
}
