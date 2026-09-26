import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_android/services/host_gateway.dart';
import 'package:quizsync_android/services/host_status_poller.dart';
import 'package:quizsync_android/state/app_state.dart';
import 'package:quizsync_android/state/providers.dart';

/// 测试用主机网关：不联网，按需返回「在线 / 未选合集 / 离线」。
class FakeHostGateway implements HostGateway {
  FakeHostGateway({
    this.deviceName = '测试电脑',
    this.activeCollectionId,
    this.activeCollectionName,
    this.availableCollections = const [],
    this.infoError,
  });

  String deviceName;
  String? activeCollectionId;
  String? activeCollectionName;
  List<Collection> availableCollections;
  Object? infoError;

  int infoCalls = 0;
  int reanalyzeCalls = 0;
  String? reanalyzeSessionId;
  String? selectedCollectionId;
  Object? reanalyzeError;

  @override
  Future<ServerInfo> info() async {
    infoCalls++;
    if (infoError != null) throw infoError!;
    return ServerInfo(
      deviceId: 'server-1',
      deviceName: deviceName,
      platform: 'windows',
      protocolVersion: 1,
      appVersion: '1.0.0',
      aiConfigured: true,
      capabilities: const ['analyze'],
      activeCollectionId: activeCollectionId,
      activeCollectionName: activeCollectionName,
    );
  }

  @override
  Future<({String? id, String? name})> activeCollection() async =>
      (id: activeCollectionId, name: activeCollectionName);

  @override
  Future<CollectionList> collections() async => CollectionList(
      collections: availableCollections,
      activeCollectionId: activeCollectionId);

  @override
  Future<TaskStatusView> createTask({
    required String taskId,
    required String imageHash,
    required String sourceDevice,
    List<String>? imageHashes,
    String? collectionId,
  }) async =>
      TaskStatusView(taskId: taskId, status: 'analyzing');

  @override
  Future<TaskStatusView> getTask(String taskId) async =>
      TaskStatusView(taskId: taskId, status: 'done');

  @override
  Future<TaskStatusView> reanalyze(String sessionId) async {
    reanalyzeCalls++;
    reanalyzeSessionId = sessionId;
    if (reanalyzeError != null) throw reanalyzeError!;
    return const TaskStatusView(taskId: 'task-1', status: 'analyzing');
  }

  @override
  Future<void> selectCollection(String collectionId) async {
    selectedCollectionId = collectionId;
    activeCollectionId = collectionId;
  }

  @override
  Future<UploadedImage> uploadImage(Uint8List jpeg) async => UploadedImage(
      imageHash: sha256Hex(jpeg), size: jpeg.length, existed: false);
}

/// 内存库 + 假网关的 AndroidAppState（widget 测试的入口）。
Future<AndroidAppState> makeTestApp(QuizSyncDb db) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // 与 `AndroidAppState.create` 完全一致（含 M18 第 4 条的「不跟随主机删除合集」），
  // 否则测试里的语义与真机不是同一个。
  final repo = CoreRepository(
    db: db,
    deviceId: 'android-local',
    applyRemoteCollectionDeletes: false,
  );
  await repo.init();
  final app = AndroidAppState(
    repo,
    OfflineQueue(db),
    MemorySecureStore(),
    SettingsController(MemoryKeyValueStore()),
  );
  await app.settings.load();
  return app;
}

/// 测试用配对客户端：不联网，直接返回一次成功的配对响应。
///
/// `flutter_test` 会把所有真实 HTTP 请求挡成 400，没有这个替身就覆盖不了
/// 「配对成功之后」的分支（M14 第 5 条：切回「当前任务」并收起配对页）。
class FakePairingClient extends ApiClient {
  FakePairingClient({
    this.issuedToken = 'new-token',
    this.serverName = '测试电脑',
    this.aiConfigured = true,
  }) : super(baseUrl: 'http://127.0.0.1:1', token: '');

  /// 配对成功后下发的长期 token（`token` 是 [ApiClient] 自己的字段，不能重名）。
  final String issuedToken;
  final String serverName;
  final bool aiConfigured;

  @override
  Future<ServerInfo> fetchInfo() async => ServerInfo(
        deviceId: 'server-1',
        deviceName: serverName,
        platform: 'windows',
        protocolVersion: 1,
        appVersion: '1.0.0',
        aiConfigured: aiConfigured,
        capabilities: const ['analyze'],
      );

  @override
  Future<PairResponse> pair(PairRequest req) async => PairResponse(
        token: issuedToken,
        serverDeviceId: 'server-1',
        serverName: serverName,
        protocolVersion: 1,
      );
}

/// 注入假网关 + 关闭真实 WS 的 ProviderScope 包装。
///
/// [hostPolling] 默认关闭、[probe] 默认不注入，理由与 `liveSync` 相同：
/// 测试里既没有真主机、也没必要每秒去连一次；要覆盖 M15 第 4 条的轮询兜底，
/// 用例自己传 `hostPolling: true` 和一个假探测。
Widget wrapApp(
  AndroidAppState app, {
  required Widget home,
  HostGateway? gateway,
  PairingInfo? pairing,
  bool liveSync = false,
  bool hostPolling = false,
  HostStatusProbeFactory? probe,
  ApiClient Function(String baseUrl)? pairingClient,
}) {
  final fake = gateway ?? FakeHostGateway();
  return ProviderScope(
    overrides: [
      androidAppProvider.overrideWithValue(app),
      hostGatewayFactoryProvider.overrideWithValue((_) => fake),
      liveSyncEnabledProvider.overrideWithValue(liveSync),
      hostPollingEnabledProvider.overrideWithValue(hostPolling),
      if (probe != null) hostStatusProbeFactoryProvider.overrideWithValue(probe),
      if (pairingClient != null)
        pairingClientFactoryProvider.overrideWithValue(pairingClient),
      if (pairing != null) pairingProvider.overrideWith((ref) => pairing),
    ],
    child: MaterialApp(
      theme: QuizSyncTheme.build(
          brightness: Brightness.light, accent: 0xFF16A34A),
      home: home,
    ),
  );
}

/// 挂上 `quizsync/capture` 通道的假实现（真机行为在测试机不可用）。
/// 返回调用日志，便于断言「识别模块关闭时确实把悬浮球隐藏了」、
/// 「配对页首次进入没有申请相机权限」。
List<String> installCaptureChannelMock({
  bool overlayGranted = true,
  bool captureOk = true,
  bool cameraGranted = true,
  bool notificationsGranted = true,
}) {
  final log = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('quizsync/capture'),
    (call) async {
      log.add(call.method);
      switch (call.method) {
        case 'isCaptureAvailable':
          return {
            'main': true,
            'accessibility': false,
            'sessionLost': false,
            'overlayGranted': overlayGranted,
          };
        case 'getPermissionStatus':
          return {
            'notifications': notificationsGranted,
            'overlay': overlayGranted,
            'battery': true,
            'accessibility': false,
          };
        case 'getCaptureState':
          return {'mode': 'main', 'ballVisible': true};
        case 'setBallVisible':
          return true;
        case 'requestNotificationPermission':
          return notificationsGranted;
        case 'requestCameraPermission':
          return cameraGranted;
        case 'captureScreen':
          return captureOk ? <int>[0xff, 0xd8, 0xff, 0xd9] : null;
        default:
          return null;
      }
    },
  );
  return log;
}

void clearCaptureChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('quizsync/capture'), null);
}

/// 往某个会话里塞一条题目（结果页/历史列表断言用）。
Future<void> addSession(
  AndroidAppState app,
  String id, {
  int questionCount = 1,
  String? collectionId,
  String? stem,
  String? questionNo,
  bool incomplete = false,
  bool answerGuessed = false,
  int? createdAt,
}) async {
  final at = createdAt ?? nowMs();
  await app.repo.upsertSession(Session(
    sessionId: id,
    collectionId: collectionId,
    imageHash: 'h-$id',
    sourceDevice: 'android-local',
    status: TaskState.done,
    questionCount: questionCount,
    createdAt: at,
    updatedAt: at,
    updatedBy: 'android-local',
  ));
  if (stem != null) {
    await app.repo.upsertQuestion(Question(
      questionId: 'q-$id',
      sessionId: id,
      ordinal: 0,
      questionNo: questionNo,
      stem: stem,
      type: QuestionType.blank,
      answerText: '答案',
      incomplete: incomplete,
      answerGuessed: answerGuessed,
      createdAt: at,
      updatedAt: at,
      updatedBy: 'android-local',
    ));
  }
}
