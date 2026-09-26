import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../quizsync_server_core.dart';
import 'config.dart';
import 'constants.dart';

/// 一台已配对设备（协议里只暴露 [info]，token 的 sha256 只在本地存）。
class PairedDevice {
  final DeviceInfo info;
  final String tokenHash;

  const PairedDevice({required this.info, required this.tokenHash});

  Map<String, dynamic> toJson() => {
        ...info.toJson(),
        'token_hash': tokenHash,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        info: DeviceInfo.fromJson(json),
        tokenHash: json['token_hash']?.toString() ?? '',
      );
}

/// 一次识别（一条历史记录）：会话 + 题目 + 页序。
class StoredSession {
  final Session session;
  final List<Question> questions;
  final List<String> imageHashes;

  const StoredSession({
    required this.session,
    required this.questions,
    required this.imageHashes,
  });

  /// 协议 JSON（WS `task_result` / `/tasks/active` 的 `session` 字段）：
  /// 与 Desktop 版同构，**额外**带 `image_hashes` 与 `image_count`，
  /// 安卓端据此显示「N 张图片识别中…」。
  Map<String, dynamic> toProtocolJson() => {
        ...session.toJson(),
        'image_hashes': imageHashes,
        'image_count': imageHashes.length,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  Map<String, dynamic> toJson() => {
        'session': session.toJson(),
        'questions': questions.map((q) => q.toJson()).toList(),
        'image_hashes': imageHashes,
      };

  factory StoredSession.fromJson(Map<String, dynamic> json) => StoredSession(
        session: Session.fromJson(
            Map<String, dynamic>.from(json['session'] as Map)),
        questions: (json['questions'] is List ? json['questions'] as List : const [])
            .whereType<Map>()
            .map((q) => Question.fromJson(Map<String, dynamic>.from(q)))
            .toList(),
        imageHashes: (json['image_hashes'] is List
                ? json['image_hashes'] as List
                : const [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// 图片元数据（字节落在 `images/<hash>.jpg`）。
class StoredImage {
  final String hash;
  final int size;
  final String mime;
  final int? width;
  final int? height;
  final int createdAt;

  const StoredImage({
    required this.hash,
    required this.size,
    this.mime = 'image/jpeg',
    this.width,
    this.height,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'size': size,
        'mime': mime,
        'width': width,
        'height': height,
        'created_at': createdAt,
      };

  factory StoredImage.fromJson(Map<String, dynamic> json) => StoredImage(
        hash: json['hash'].toString(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        mime: json['mime']?.toString() ?? 'image/jpeg',
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// Server 的全部持久状态：设备 / 会话 / 题目 / 图片 / 合集。
///
/// 刻意**不用数据库**（需求：Server 只加载最小依赖，越轻越好）：
/// 一个 `state.json` + 一个 `images/` 目录就够了，容量按「最近 N 次识别」封顶。
/// 协议里的 ops（字段级同步日志）是 Desktop 与 Android 之间「互相改数据」用的，
/// Server 只有一条「截图 → AI → 推结果」的单向流水线，不产生也不需要 ops，
/// 因此 `/sync/ops` 恒返回空、`ops_lamport` 恒为 0（安卓端据此不做无谓拉取）。
class ServerStore {
  /// 本地保留的会话上限（更老的记录直接丢掉，避免 JSON 无限增长）。
  static const int maxSessions = 300;

  /// 同步端点去重用的 op_id 上限。
  static const int maxOpIds = 2000;

  final ConfigPaths paths;

  /// 本机（Server）的 device_id：UUID v4，首次启动生成后持久化。
  String deviceId;

  /// 面板与配对响应里的 server_name（默认用机器名）。
  String serverName;

  /// Server 固定的默认合集（见 [kDefaultCollectionName]）。
  Collection collection;

  final Map<String, PairedDevice> devices = {};

  /// sessionId → 会话（LinkedHashMap 保序 = 创建顺序）。
  final Map<String, StoredSession> sessions = {};

  /// imageHash → 元数据。
  final Map<String, StoredImage> images = {};

  /// 已接收过的 op_id（幂等）。
  final Set<String> appliedOpIds = {};

  /// 启动标识（用户 1.0.0 优化：「启动一次后就要有一定的标识」）。
  ///
  /// 第几次启动、首次启动时间、上次启动时间。它让「这份数据被这个程序用过没有、
  /// 用过几次」一眼可见 —— 也让用户能确认自己刚才那次启动确实生效了。
  int runCount = 0;
  int? firstRunAt;
  int? lastRunAt;

  Future<void> _saveChain = Future<void>.value();

  ServerStore._({
    required this.paths,
    required this.deviceId,
    required this.serverName,
    required this.collection,
  });

  /// 记一次启动：次数 +1、刷新首次/上次启动时间，并落盘。
  ///
  /// 返回本次的启动序号（1 = 第一次启动）。
  Future<int> noteStartup() async {
    final now = nowMs();
    runCount += 1;
    firstRunAt ??= now;
    lastRunAt = now;
    await save();
    return runCount;
  }

  /// 打开（不存在则创建）状态文件。
  static Future<ServerStore> open(ConfigPaths paths,
      {String? serverName}) async {
    await paths.ensure();
    final name = (serverName == null || serverName.trim().isEmpty)
        ? Platform.localHostname
        : serverName.trim();

    ServerStore store;
    final file = paths.stateFile;
    Map<String, dynamic>? json;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) json = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 状态文件损坏：**不要**让服务起不来，改名留档后重建（数据可丢，
        // 服务必须能起）。用户至少还能用截图识别。
        try {
          await file.rename('${file.path}.broken');
        } catch (_) {}
      }
    }

    final now = nowMs();
    if (json == null) {
      final did = newUuidV4();
      store = ServerStore._(
        paths: paths,
        deviceId: did,
        serverName: name,
        collection: Collection(
          collectionId: newUuidV4(),
          name: kDefaultCollectionName,
          createdAt: now,
          updatedAt: now,
          updatedBy: did,
        ),
      );
      await store.save();
      return store;
    }

    store = ServerStore._(
      paths: paths,
      deviceId: json['device_id']?.toString() ?? newUuidV4(),
      serverName: json['server_name']?.toString().trim().isNotEmpty == true
          ? json['server_name'].toString().trim()
          : name,
      collection: json['collection'] is Map
          ? Collection.fromJson(Map<String, dynamic>.from(json['collection'] as Map))
          : Collection(
              collectionId: newUuidV4(),
              name: kDefaultCollectionName,
              createdAt: now,
              updatedAt: now,
              updatedBy: json['device_id']?.toString() ?? 'server',
            ),
    );
    for (final raw in (json['devices'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final d = PairedDevice.fromJson(Map<String, dynamic>.from(raw));
      store.devices[d.info.deviceId] = d;
    }
    for (final raw in (json['sessions'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final s = StoredSession.fromJson(Map<String, dynamic>.from(raw));
      store.sessions[s.session.sessionId] = s;
    }
    for (final raw in (json['images'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final img = StoredImage.fromJson(Map<String, dynamic>.from(raw));
      // 自愈：字节文件已经不在（用户手工清理过）就丢掉这条元数据。
      if (await store.imageFile(img.hash).exists()) {
        store.images[img.hash] = img;
      }
    }
    for (final raw in (json['applied_op_ids'] as List? ?? const [])) {
      store.appliedOpIds.add(raw.toString());
    }
    // 启动标识（老的 state.json 里没有这几项 → 从 0 开始）。
    final stats = json['stats'];
    if (stats is Map) {
      store.runCount = (stats['run_count'] as num?)?.toInt() ?? 0;
      store.firstRunAt = (stats['first_run_at'] as num?)?.toInt();
      store.lastRunAt = (stats['last_run_at'] as num?)?.toInt();
    }
    // 1.0.0 早期的合集名「默认合集」→「Server」：Server 识别出来的记录要在手机
    // 历史里一眼认得出来。只改自己自动建的那一个，用户没机会在这里建别的合集。
    if (store.collection.name == kLegacyCollectionName) {
      store.collection = store.collection.copyWith(
        name: kDefaultCollectionName,
        updatedAt: nowMs(),
        updatedBy: store.deviceId,
      );
      await store.save();
    }
    return store;
  }

  // ------------------------------------------------------------
  // 图片
  // ------------------------------------------------------------

  File imageFile(String hash) => File(p.join(paths.imageDir.path, '$hash.jpg'));

  String pathFor(String hash) => imageFile(hash).path;

  Future<StoredImage> writeImage(Uint8List bytes,
      {int? width, int? height}) async {
    final hash = sha256Hex(bytes);
    final existed = images[hash];
    if (!await paths.imageDir.exists()) {
      await paths.imageDir.create(recursive: true);
    }
    final file = imageFile(hash);
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    final meta = StoredImage(
      hash: hash,
      size: bytes.length,
      width: width ?? existed?.width,
      height: height ?? existed?.height,
      createdAt: existed?.createdAt ?? nowMs(),
    );
    images[hash] = meta;
    await save();
    return meta;
  }

  Future<Uint8List?> readImage(String hash) async {
    final file = imageFile(hash);
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------
  // 设备
  // ------------------------------------------------------------

  PairedDevice? deviceByTokenHash(String hash) {
    for (final d in devices.values) {
      if (d.tokenHash == hash) return d;
    }
    return null;
  }

  Future<void> upsertDevice(PairedDevice device) async {
    devices[device.info.deviceId] = device;
    await save();
  }

  Future<void> revokeDevice(String deviceId) async {
    final existing = devices[deviceId];
    if (existing == null) return;
    devices[deviceId] = PairedDevice(
      info: existing.info.copyWith(revokedAt: nowMs()),
      tokenHash: existing.tokenHash,
    );
    await save();
  }

  /// 未吊销的已配对设备（CLI 面板的 Mobile 状态）。
  List<PairedDevice> get activeDevices =>
      devices.values.where((d) => !d.info.isRevoked).toList();

  // ------------------------------------------------------------
  // 会话
  // ------------------------------------------------------------

  StoredSession? getSession(String sessionId) => sessions[sessionId];

  Future<void> putSession(StoredSession stored) async {
    sessions[stored.session.sessionId] = stored;
    _pruneSessions();
    await save();
  }

  void _pruneSessions() {
    if (sessions.length <= maxSessions) return;
    final ordered = sessions.values.toList()
      ..sort((a, b) => a.session.createdAt.compareTo(b.session.createdAt));
    final drop = sessions.length - maxSessions;
    for (var i = 0; i < drop; i++) {
      sessions.remove(ordered[i].session.sessionId);
    }
  }

  /// 应用一条已接收的 op_id（幂等）；返回是否是新 op。
  bool markOpApplied(String opId) {
    if (appliedOpIds.contains(opId)) return false;
    appliedOpIds.add(opId);
    if (appliedOpIds.length > maxOpIds) {
      appliedOpIds.remove(appliedOpIds.first);
    }
    return true;
  }

  // ------------------------------------------------------------
  // 持久化
  // ------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'format': 1,
        'device_id': deviceId,
        'server_name': serverName,
        'collection': collection.toJson(),
        'devices': devices.values.map((d) => d.toJson()).toList(),
        'sessions': sessions.values.map((s) => s.toJson()).toList(),
        'images': images.values.map((i) => i.toJson()).toList(),
        'applied_op_ids': appliedOpIds.toList(),
        'stats': {
          'run_count': runCount,
          'first_run_at': firstRunAt,
          'last_run_at': lastRunAt,
        },
      };

  /// 串行化落盘：多个并发改动不会互相覆盖，也不需要调用方 await。
  Future<void> save() {
    _saveChain = _saveChain.then((_) => _write());
    return _saveChain;
  }

  Future<void> _write() async {
    await paths.ensure();
    final tmp = File('${paths.stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    if (await paths.stateFile.exists()) await paths.stateFile.delete();
    await tmp.rename(paths.stateFile.path);
  }
}
