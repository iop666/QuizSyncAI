import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart'
    show DriftKeyValueStore, SettingsController;

/// 与 Windows 主机的配对信息（token 走 Keystore 加密存储，SPEC §10）。
class PairingInfo {
  final String host;
  final int port;
  final String token;
  final String serverDeviceId;
  final String serverName;

  const PairingInfo({
    required this.host,
    required this.port,
    required this.token,
    required this.serverDeviceId,
    required this.serverName,
  });

  String get httpBase => 'http://$host:$port';

  Map<String, String> toJsonMap() => {
        'host': host,
        'port': port.toString(),
        'token': token,
        'server_device_id': serverDeviceId,
        'server_name': serverName,
      };

  static PairingInfo? fromJsonMap(Map<String, dynamic> map) {
    final token = map['token']?.toString();
    final host = map['host']?.toString();
    final port = int.tryParse(map['port']?.toString() ?? '');
    if (token == null || host == null || port == null) return null;
    return PairingInfo(
      host: host,
      port: port,
      token: token,
      serverDeviceId: map['server_device_id']?.toString() ?? '',
      serverName: map['server_name']?.toString() ?? '',
    );
  }
}

/// 解析二维码内容：quizsync://pair?host=..&port=..&code=..&sid=..&v=1
({String host, int port, String code, String sid})? parsePairQr(String raw) {
  if (!raw.startsWith('quizsync://pair?')) return null;
  final uri = Uri.parse(raw.replaceFirst('quizsync://pair', 'https://pair'));
  final host = uri.queryParameters['host'];
  final port = int.tryParse(uri.queryParameters['port'] ?? '');
  final code = uri.queryParameters['code'];
  final sid = uri.queryParameters['sid'] ?? '';
  if (host == null || port == null || code == null) return null;
  return (host: host, port: port, code: code, sid: sid);
}

/// Android 端全局状态（M4）：
/// 本地库 + 配对信息 + ApiClient + 离线队列 + 应用设置。
class AndroidAppState {
  static const _storageKey = 'pairing_info';

  final CoreRepository repo;
  final OfflineQueue queue;
  final SecureStore secureStore;
  final SettingsController settings;

  AndroidAppState(this.repo, this.queue, this.secureStore, this.settings);

  static Future<AndroidAppState> create({SecureStore? secureStore}) async {
    final support = await getApplicationSupportDirectory();
    final db = openQuizSyncDb('${support.path}/quizsync.db');
    // M18 第 4 条：安卓端**不跟随主机的删除合集**（用户明确要求修改 M17 的第 5 条
    // 「windows 端删除后安卓端不再同步跟着删除」）——主机删掉的合集在手机本地
    // 保留，历史里那个分组不会消失、下面的记录也不会被打散成「未分类」。
    final repo = CoreRepository(
      db: db,
      deviceId: 'android-local',
      applyRemoteCollectionDeletes: false,
    );
    await repo.init();
    final settings = SettingsController(DriftKeyValueStore(repo));
    await settings.load();
    return AndroidAppState(
        repo, OfflineQueue(db), secureStore ?? MemorySecureStore(), settings);
  }

  Future<PairingInfo?> loadPairing() async {
    final raw = await secureStore.read(_storageKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return PairingInfo.fromJsonMap(decoded);
    } catch (_) {}
    return null;
  }

  Future<void> savePairing(PairingInfo info) =>
      secureStore.write(_storageKey, jsonEncode(info.toJsonMap()));

  Future<void> clearPairing() => secureStore.delete(_storageKey);
}

/// 安全存储接口（真机走 flutter_secure_storage / Keystore；测试注入内存版）。
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemorySecureStore implements SecureStore {
  final Map<String, String> _map = {};
  @override
  Future<String?> read(String key) async => _map[key];
  @override
  Future<void> write(String key, String value) async => _map[key] = value;
  @override
  Future<void> delete(String key) async => _map.remove(key);
}

/// 一次「相册选图 → 上传 → 分析 → 本地入库」的会话结果（M4 主通路）。
class UploadOutcome {
  final String? sessionId;
  final String? errorCode;
  final String? errorMessage;
  final bool queuedOffline;

  const UploadOutcome({
    this.sessionId,
    this.errorCode,
    this.errorMessage,
    this.queuedOffline = false,
  });

  bool get ok => errorCode == null && !queuedOffline;
}

/// 上传并等待结果：轮询（2s 间隔，上限 90s，protocol.md 4.1）。
/// [saveFile] 提供时把字节落盘（离线队列补跑的前提）。
/// [collectionId] 为本次任务归属的合集（用户需求 8/12；主机未选时服务端 409）。
Future<UploadOutcome> uploadAndAnalyze(
  ApiClient api,
  CoreRepository repo,
  Uint8List jpeg, {
  required String deviceId,
  Future<void> Function(String hash, Uint8List bytes)? saveFile,
  String? collectionId,
}) async {
  final hash = sha256Hex(jpeg);
  await repo.upsertImage(ImageMeta(
    hash: hash,
    size: jpeg.length,
    mime: 'image/jpeg',
    createdAt: nowMs(),
    uploadedBy: deviceId,
  ));
  if (saveFile != null) {
    try {
      await saveFile(hash, jpeg);
    } catch (_) {}
  }

  final uploaded = await api.uploadImage(jpeg);
  final taskId = newUuidV4();
  await api.createTask(
    taskId: taskId,
    imageHash: uploaded.imageHash,
    sourceDevice: deviceId,
    collectionId: collectionId,
  );
  return pollTaskUntilDone(api, repo, taskId);
}

/// 多页识别（用户需求 4）：各页在收集阶段已经上传成功，
/// 这里只用它们的 hash 一次创建多页任务，然后等结果。
Future<UploadOutcome> createMultiPageTaskAndAnalyze(
  ApiClient api,
  CoreRepository repo,
  List<String> imageHashes, {
  required String deviceId,
  String? collectionId,
}) async {
  if (imageHashes.isEmpty) {
    return const UploadOutcome(errorCode: 'empty_task', errorMessage: '没有可用页面');
  }
  final taskId = newUuidV4();
  await api.createTask(
    taskId: taskId,
    imageHash: imageHashes.first,
    sourceDevice: deviceId,
    imageHashes: imageHashes,
    collectionId: collectionId,
  );
  return pollTaskUntilDone(api, repo, taskId);
}

/// 轮询任务直到 done/failed（2s 间隔，上限 90s）：结果落本地库。
Future<UploadOutcome> pollTaskUntilDone(
  ApiClient api,
  CoreRepository repo,
  String taskId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 2));
    final task = await api.getTask(taskId);
    if (task.status == 'done' && task.session != null) {
      // 结果落本地库（历史可离线查看）。
      final session = task.session!;
      await repo.upsertSession(session.copyWith(taskId: taskId));
      // 题目落库与 WS 的 `task_result`（`live_updates.dart` 的 `_taskResult`）
      // 同一口径：走 `applyAnalysisResult` 才能保住用户手改的 answer_edited /
      // analysis_edited。逐题 `upsertQuestion` 会把这两个标记连同用户的答案
      // 一起盖掉，本机随后还会把被盖掉的值当成本地改动同步回主机。
      await repo.applyAnalysisResult(
        sessionId: session.sessionId,
        input: AnalysisResultInput(
          aiProvider: session.aiProvider,
          aiModel: session.aiModel,
          promptVersion: session.promptVersion,
          rawResponse: session.rawResponse,
          latencyMs: session.latencyMs,
          cached: session.cached,
          questions: [
            for (final q in task.questions ?? const <Question>[])
              q.copyWith(sessionId: session.sessionId),
          ],
        ),
      );
      if (task.imageHashes.isNotEmpty) {
        await repo.setSessionImages(session.sessionId, task.imageHashes);
      }
      return UploadOutcome(sessionId: session.sessionId);
    }
    if (task.status == 'failed' || task.status == 'cancelled') {
      return UploadOutcome(
        errorCode: task.errorCode,
        errorMessage: task.errorMessage,
      );
    }
  }
  return const UploadOutcome(
      errorCode: 'timeout', errorMessage: '等待结果超时');
}
