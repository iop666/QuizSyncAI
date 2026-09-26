import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// M14 第 6 条（用户反馈）：**双端静默互显**。
///
/// 用户原话：「windows端识别后Windows端不要跳出界面，在后台静默识别，安卓端显示
/// 识别界面……现在windows端识别完windows端会跳出来，安卓端一点反应没有，也不同步。」
///
/// 这里把两端真的接到一起跑：真 `QuizSyncServer`（主机）+ 真 `SyncSocket`（手机），
/// 断言三件事：
/// 1. 本机截屏的广播**不触发** `onTaskUpdateHook`（那个钩子会让 Windows 主窗口
///    自己弹到前台抢焦点）；
/// 2. 手机提交的任务**仍然**触发钩子（否则「安卓识别 → Windows 显示识别界面」会坏）；
/// 3. 手机在识别过程中才连上来时，主机把进行中的状态**补发**一次
///    （否则手机停在「没有任务」，用户看到的就是「安卓端一点反应没有」）。
void main() {
  late QuizSyncDb serverDb;
  late CoreRepository serverRepo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late String token;
  const serverDeviceId = 'windows-local';
  const clientDeviceId = 'android-device-1';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    serverDb = QuizSyncDb(NativeDatabase.memory());
    serverRepo = CoreRepository(db: serverDb, deviceId: serverDeviceId);
    await serverRepo.init();
    imageDir = await Directory.systemTemp.createTemp('m14-img-');
    final store = DirectoryImageStore(imageDir.path);

    server = QuizSyncServer(
      repo: serverRepo,
      imageStore: store,
      executor: ServerTaskExecutor(
        repo: serverRepo,
        engine: AnalysisEngine(
          provider: FakeAiProvider(
              File('test/fixtures/multi_and_judge.json').absolute.path),
          cache: AnalysisCache(serverRepo),
          quota: QuotaGuard(serverDb),
          deviceId: serverDeviceId,
        ),
        imageStore: store,
        configProvider: () => const AiConfig(
            providerId: 'openai-compatible', apiKey: 'k', model: 'm'),
      ),
      deviceId: serverDeviceId,
      serverName: 'TEST-HOST',
      // preferredPort: 0 = 系统分配随机端口（回环测试用）。
      options: const QuizSyncServerOptions(preferredPort: 0),
    );
    port = await server.start();
    token = (await ApiClient(baseUrl: 'http://127.0.0.1:$port', token: '')
            .pair(PairRequest(
      code: server.pairingCode,
      deviceId: clientDeviceId,
      deviceName: 'Pixel',
      platform: 'android',
      appVersion: '1.0.0',
    )))
        .token;
  });

  tearDown(() async {
    await server.stop();
    await serverDb.close();
    await imageDir.delete(recursive: true);
  });

  /// 连一个「手机」上来，返回它的消息流（并等握手 + hello 落定）。
  Future<({SyncSocket socket, List<Map<String, dynamic>> messages})>
      connectPhone() async {
    final socket = SyncSocket(
      wsUri: Uri.parse('ws://127.0.0.1:$port/ws'),
      token: token,
      deviceId: clientDeviceId,
    );
    final messages = <Map<String, dynamic>>[];
    socket.messages.listen(messages.add);
    await socket.connect();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return (socket: socket, messages: messages);
  }

  /// 手机收到过的 `task_update`（只关心某一个会话的）。
  List<Map<String, dynamic>> updatesOf(
          List<Map<String, dynamic>> messages, String sessionId) =>
      messages
          .where((m) =>
              m['type'] == 'task_update' && m['session_id'] == sessionId)
          .toList();

  test('本机截屏：只广播状态，绝不触发「把窗口带到前台」的钩子', () async {
    final hooks = <String>[];
    server.onTaskUpdateHook = (status, sessionId) => hooks.add(status);
    final phone = await connectPhone();

    server.notifyLocalSession('sess-local-1', 'analyzing', imageCount: 3);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(hooks, isEmpty,
        reason: 'Windows 本机截屏必须后台静默，不能弹出主窗口（用户反馈 M14 第 6 条）');
    final updates = updatesOf(phone.messages, 'sess-local-1');
    expect(updates, hasLength(1), reason: '手机仍要收到「识别中」');
    expect(updates.single['status'], 'analyzing');
    expect(updates.single['image_count'], 3, reason: '手机据此显示「3 张图片识别中…」');

    await phone.socket.dispose();
  });

  test('手机提交的任务：钩子照旧触发（安卓识别 → Windows 显示识别界面）', () async {
    final hooks = <String>[];
    server.onTaskUpdateHook = (status, sessionId) => hooks.add(status);

    server.notifyTaskUpdate('task-phone-1', 'analyzing', 'sess-phone-1');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(hooks, ['analyzing'], reason: '这条路径要保住，不能一起静默掉');
  });

  test('手机在识别中途才连上：主机补发进行中的状态', () async {
    // 主机先开始识别（此时手机还没连上）。
    server.notifyLocalSession('sess-local-2', 'analyzing', imageCount: 2);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final phone = await connectPhone();
    final updates = updatesOf(phone.messages, 'sess-local-2');
    expect(updates, isNotEmpty,
        reason: '重连/中途连上也要看到「识别中」，否则用户看到的是「安卓端一点反应没有」');
    expect(updates.last['status'], 'analyzing');
    expect(updates.last['image_count'], 2);

    await phone.socket.dispose();
  });

  test('本机识别已结束：新连上的手机不会再收到旧状态（不会莫名跳结果页）', () async {
    server.notifyLocalSession('sess-local-3', 'analyzing', imageCount: 1);
    server.notifyLocalSession('sess-local-3', 'done');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final phone = await connectPhone();
    expect(updatesOf(phone.messages, 'sess-local-3'), isEmpty,
        reason: '已完成的旧任务不能每次重连都补发');

    await phone.socket.dispose();
  });
}
