import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// 局域网客户端（Android / 测试）对 Windows 服务端的 HTTP 封装。
/// 错误统一抛 [ApiClientException]（携带 protocol.md 3.5 的 code）。
///
/// 关键约定：**任何**失败（连接被拒/超时/非 2xx/响应体不是 JSON）都以
/// [ApiClientException] 抛出。此前只有「能解析出 JSON 的非 2xx」才会转换，
/// 于是最常见的「Windows 不在线」会漏出 DioException，调用方（安卓同步、
/// 上传分析）catch 不到，用户看到的是未处理异常。
class ApiClientException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final int? retryAfterSeconds;

  const ApiClientException(
    this.statusCode,
    this.code,
    this.message, [
    this.retryAfterSeconds,
  ]);

  @override
  String toString() => 'ApiClientException($statusCode $code: $message)';
}

class UploadedImage {
  final String imageHash;
  final int size;
  final bool existed;

  const UploadedImage({
    required this.imageHash,
    required this.size,
    required this.existed,
  });
}

class TaskStatusView {
  final String taskId;
  final String status;
  final String? sessionId;
  final String? errorCode;
  final String? errorMessage;

  /// done 时的完整会话（含 questions）。
  final Session? session;
  final List<Question>? questions;

  /// 本次识别的页数（用户需求 7：显示「N 张图片识别中」）。
  final List<String> imageHashes;

  const TaskStatusView({
    required this.taskId,
    required this.status,
    this.sessionId,
    this.errorCode,
    this.errorMessage,
    this.session,
    this.questions,
    this.imageHashes = const [],
  });

  int get imageCount => imageHashes.isEmpty ? 1 : imageHashes.length;

  bool get done => status == 'done';
}

/// `GET /api/v1/tasks/active` 的响应（用户反馈 M15 第 4 条）。
///
/// 安卓端在「当前任务」页每秒问一次这个**只读**端点，作为 WS 推送的兜底：
/// 用户那台机器上 WS 可能根本连不上（HTTP 一直是好的），只有推送时界面会
/// 一直停在旧状态（用户原话：「又没有方法让他一直刷新，比如安卓端 1s 获取
/// 一次状态」）。
class ActiveTaskView {
  /// `idle` = 主机当前没有进行中 / 刚结束的识别任务。
  final String status;
  final String? taskId;
  final String? sessionId;
  final int imageCount;

  /// 失败原因（只有 `failed` 时有意义）。
  final String? message;

  /// 主机当前合集：轮询端据此把状态行从「电脑未连接」改回「已连接 · 合集名」。
  final String? activeCollectionId;
  final String? activeCollectionName;

  /// `done` 时的完整会话（与 WS `task_result` 里的 `session` 同构），
  /// 直接交给 `LiveUpdates` 就能复用同一条落库 + 通知逻辑。
  final Map<String, dynamic>? session;

  /// 主机记下这次状态的时间（毫秒）。
  final int updatedAt;

  /// 主机**本地 ops 的水位**（M17 第 5 条）：涨了说明主机那边有新改动
  /// （新建/删除合集、改题目…），客户端应当**只拉一次 ops**（pull-only），
  /// 而不是干等下一次全量同步。0 = 主机没上报（老版本）。
  final int opsLamport;

  /// 主机**当前活跃合集列表**（M18 第 4 条）。
  ///
  /// 用户原话：「安卓端现在识别不到无法同步 windows 端的分类，想办法完成同步」。
  /// 主机把这份列表直接放进每秒一次的状态探测里，客户端按它对齐本地库
  /// （[CoreRepository.mirrorCollections]）—— 这是「想要的结果」本身，不是
  /// `opsLamport` 那种间接信号，所以不会漏。空列表 = 老主机没上报。
  ///
  /// 语义：**只增改、不删**。主机已经删掉的合集不会出现在这份列表里，客户端
  /// 保留本地那份（用户明确要求「windows 端删除后安卓端不再同步跟着删除」）。
  final List<Collection> collections;

  const ActiveTaskView({
    required this.status,
    this.taskId,
    this.sessionId,
    this.imageCount = 0,
    this.message,
    this.activeCollectionId,
    this.activeCollectionName,
    this.session,
    this.updatedAt = 0,
    this.opsLamport = 0,
    this.collections = const [],
  });

  /// 主机没有任何任务（连上一轮的终态都没有）。
  bool get idle => status == 'idle';

  factory ActiveTaskView.fromJson(Map<String, dynamic> json) {
    final rawSession = json['session'];
    final rawCollections = json['collections'];
    return ActiveTaskView(
      status: json['status']?.toString() ?? 'idle',
      taskId: json['task_id']?.toString(),
      sessionId: json['session_id']?.toString(),
      imageCount: (json['image_count'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString(),
      activeCollectionId: json['active_collection_id']?.toString(),
      activeCollectionName: json['active_collection_name']?.toString(),
      session: rawSession is Map
          ? Map<String, dynamic>.from(rawSession)
          : null,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      opsLamport: (json['ops_lamport'] as num?)?.toInt() ?? 0,
      collections: (rawCollections is List ? rawCollections : const [])
          .whereType<Map>()
          .map((c) => Collection.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
    );
  }
}

class SyncOpsPage {
  final List<SyncOp> ops;
  final bool hasMore;
  final int? nextCursor;

  const SyncOpsPage({required this.ops, required this.hasMore, this.nextCursor});
}

/// `GET /api/v1/collections` 响应。
class CollectionList {
  final List<Collection> collections;
  final String? activeCollectionId;

  const CollectionList({
    required this.collections,
    this.activeCollectionId,
  });
}

class ApiClient {
  final Dio dio;
  final String token;
  final String appVersion;

  ApiClient({
    required String baseUrl,
    required this.token,
    this.appVersion = '1.0.0',
    Dio? dio,
  }) : dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (s) => true,
            )) {
    this.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer $token';
        options.headers['X-QS-Client-Version'] = appVersion;
        handler.next(options);
      },
    ));
  }

  /// 把 Dio 的传输层异常统一翻译成 [ApiClientException]。
  static ApiClientException _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiClientException(0, 'timeout', '连接主机超时');
      case DioExceptionType.connectionError:
        return const ApiClientException(0, 'network_error', '无法连接主机（Windows 端未运行？）');
      case DioExceptionType.badCertificate:
        return const ApiClientException(0, 'network_error', '证书校验失败');
      case DioExceptionType.cancel:
        return const ApiClientException(0, 'cancelled', '请求已取消');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        return ApiClientException(status, 'internal', 'HTTP $status');
      case DioExceptionType.unknown:
      default:
        final raw = e.error?.toString() ?? e.message ?? '';
        if (raw.contains('SocketException') ||
            raw.contains('Connection refused') ||
            raw.contains('Failed host lookup')) {
          return const ApiClientException(0, 'network_error', '无法连接主机（Windows 端未运行？）');
        }
        return ApiClientException(0, 'internal', raw.isEmpty ? '未知网络错误' : raw);
    }
  }

  /// 所有请求的统一出口：传输层异常 → ApiClientException。
  Future<Response<dynamic>> _send(Future<Response<dynamic>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  static Map<String, dynamic> _map(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  static Never _throw(Response<dynamic> resp) {
    var code = 'internal';
    var message = resp.statusMessage ?? '';
    int? retryAfter;
    try {
      final body = resp.data;
      if (body is Map) {
        code = body['code']?.toString() ?? code;
        message = body['message']?.toString() ?? message;
        retryAfter = (body['retry_after_seconds'] as num?)?.toInt();
      } else if (body is String && body.isNotEmpty) {
        message = body.length > 200 ? body.substring(0, 200) : body;
      } else if (body is List<int> && body.isNotEmpty) {
        message = 'HTTP ${resp.statusCode ?? 0}';
      }
    } catch (_) {}
    throw ApiClientException(resp.statusCode ?? 0, code, message, retryAfter);
  }

  // ------------------------------------------------------------
  // 无需鉴权的端点
  // ------------------------------------------------------------

  Future<ServerInfo> fetchInfo() async {
    final resp = await _send(() => dio.get<dynamic>('/api/v1/info'));
    if (resp.statusCode != 200) _throw(resp);
    return ServerInfo.fromJson(_map(resp.data));
  }

  Future<PairResponse> pair(PairRequest req) async {
    final resp = await _send(() => dio.post<dynamic>(
          '/api/v1/pair',
          data: req.toJson(),
        ));
    // M47：重复配对按 `protocol.md` 2.2 回 **409 already_paired**，body 里带的
    // 是**新** token（旧的已作废）—— 和 200 一样要当成成功解析，否则用户
    // 「重新配对」时会看到一个莫名其妙的错误。
    if (resp.statusCode != 200 && resp.statusCode != 409) _throw(resp);
    return PairResponse.fromJson(_map(resp.data));
  }

  // ------------------------------------------------------------
  // 图片
  // ------------------------------------------------------------

  Future<UploadedImage> uploadImage(Uint8List jpegBytes) async {
    final resp = await _send(() {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(jpegBytes, filename: 'shot.jpg'),
      });
      return dio.post<dynamic>('/api/v1/images', data: form);
    });
    if (resp.statusCode != 200) _throw(resp);
    final data = _map(resp.data);
    return UploadedImage(
      imageHash: data['image_hash'].toString(),
      size: (data['size'] as num?)?.toInt() ?? 0,
      existed: data['existed'] == true,
    );
  }

  Future<Uint8List?> downloadImage(String hash) async {
    final resp = await _send(() => dio.get<dynamic>('/api/v1/images/$hash',
        options: Options(responseType: ResponseType.bytes)));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) _throw(resp);
    final data = resp.data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  // ------------------------------------------------------------
  // 任务
  // ------------------------------------------------------------

  Future<TaskStatusView> createTask({
    required String taskId,
    required String imageHash,
    required String sourceDevice,
    List<String>? imageHashes,
    String? collectionId,
    bool forceReanalyze = false,
  }) async {
    final hashes = (imageHashes == null || imageHashes.isEmpty)
        ? <String>[imageHash]
        : imageHashes;
    final resp = await _send(() => dio.post<dynamic>(
          '/api/v1/tasks',
          data: {
            'task_id': taskId,
            'image_hash': hashes.first,
            'image_hashes': hashes,
            'source_device': sourceDevice,
            'collection_id': ?collectionId,
            'created_at': nowMs(),
            'force_reanalyze': forceReanalyze,
          },
        ));
    if (resp.statusCode != 202 && resp.statusCode != 200) _throw(resp);
    final data = _map(resp.data);
    return TaskStatusView(
      taskId: taskId,
      status: data['status'].toString(),
      sessionId: data['session_id']?.toString(),
    );
  }

  /// 「重新生成」（用户需求 7）：让主机按既有会话的页序重跑一次。
  Future<TaskStatusView> reanalyzeSession(String sessionId) async {
    final resp = await _send(() => dio
        .post<dynamic>('/api/v1/sessions/$sessionId/reanalyze'));
    if (resp.statusCode != 202 && resp.statusCode != 200) _throw(resp);
    final data = _map(resp.data);
    return TaskStatusView(
      taskId: data['task_id']?.toString() ?? '',
      status: data['status'].toString(),
      sessionId: data['session_id']?.toString(),
    );
  }

  /// 主机上的合集列表 + 当前选中项（用户需求 8/12）。
  Future<CollectionList> fetchCollections() async {
    final resp = await _send(() => dio.get<dynamic>('/api/v1/collections'));
    if (resp.statusCode != 200) _throw(resp);
    final data = _map(resp.data);
    final raw = data['collections'];
    return CollectionList(
      collections: (raw is List ? raw : const [])
          .whereType<Map>()
          .map((c) => Collection.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
      activeCollectionId: data['active_collection_id']?.toString(),
    );
  }

  /// 在手机上直接切换主机当前合集。
  Future<void> selectCollection(String collectionId) async {
    final resp = await _send(() => dio
        .post<dynamic>('/api/v1/collections/$collectionId/select'));
    if (resp.statusCode != 200) _throw(resp);
  }

  Future<TaskStatusView> getTask(String taskId) async {
    final resp = await _send(() => dio.get<dynamic>('/api/v1/tasks/$taskId'));
    if (resp.statusCode != 200) _throw(resp);
    final data = _map(resp.data);
    final sessionJson = data['session'];
    List<Question>? questions;
    Session? session;
    var imageHashes = <String>[];
    if (sessionJson is Map) {
      final m = Map<String, dynamic>.from(sessionJson);
      session = Session.fromJson(m);
      final rawHashes = m['image_hashes'];
      if (rawHashes is List) {
        imageHashes = rawHashes.map((e) => e.toString()).toList();
      }
      final qs = m['questions'];
      if (qs is List) {
        questions = qs
            .whereType<Map>()
            .map((q) => Question.fromJson(Map<String, dynamic>.from(q)))
            .toList();
      }
    }
    return TaskStatusView(
      taskId: data['task_id'].toString(),
      status: data['status'].toString(),
      sessionId: data['session_id']?.toString(),
      errorCode: data['error_code']?.toString(),
      errorMessage: data['error_message']?.toString(),
      session: session,
      questions: questions,
      imageHashes: imageHashes,
    );
  }

  /// 「主机现在在识别什么」的只读探测（用户反馈 M15 第 4 条：轮询兜底）。
  ///
  /// 与 [getTask] 的区别：不需要先知道 task_id —— 桌面端的本机截屏**不经过
  /// 任务队列**，客户端根本拿不到它的任务 id，只能让主机自己报。
  Future<ActiveTaskView> fetchActiveTask() async {
    final resp = await _send(() => dio.get<dynamic>('/api/v1/tasks/active'));
    if (resp.statusCode != 200) _throw(resp);
    return ActiveTaskView.fromJson(_map(resp.data));
  }

  Future<void> retryTask(String taskId) async {
    final resp = await _send(
        () => dio.post<dynamic>('/api/v1/tasks/$taskId/retry'));
    if (resp.statusCode != 200) _throw(resp);
  }

  // ------------------------------------------------------------
  // 同步
  // ------------------------------------------------------------

  Future<int> pushOps(List<SyncOp> ops) async {
    final resp = await _send(() => dio.post<dynamic>(
          '/api/v1/sync/ops',
          data: {'ops': ops.map((o) => o.toJson()).toList()},
        ));
    if (resp.statusCode != 200) _throw(resp);
    return (_map(resp.data)['applied'] as num?)?.toInt() ?? 0;
  }

  Future<SyncOpsPage> pullOps({
    required int sinceLamport,
    required String fromDevice,
    int? cursor,
  }) async {
    final resp = await _send(() => dio.get<dynamic>(
          '/api/v1/sync/ops',
          queryParameters: {
            'since_lamport': sinceLamport,
            'from_device': fromDevice,
            'cursor': ?cursor,
          },
        ));
    if (resp.statusCode != 200) _throw(resp);
    final data = _map(resp.data);
    final rawOps = data['ops'];
    final ops = (rawOps is List ? rawOps : const [])
        .whereType<Map>()
        .map((o) => SyncOp.fromJson(Map<String, dynamic>.from(o)))
        .toList();
    return SyncOpsPage(
      ops: ops,
      hasMore: data['has_more'] == true,
      nextCursor: (data['next_cursor'] as num?)?.toInt(),
    );
  }

  /// 拉到 has_more == false 为止。
  Future<List<SyncOp>> pullAllOps({
    required int sinceLamport,
    required String fromDevice,
  }) async {
    final all = <SyncOp>[];
    int? cursor;
    var guard = 0;
    while (true) {
      final page = await pullOps(
          sinceLamport: sinceLamport, fromDevice: fromDevice, cursor: cursor);
      all.addAll(page.ops);
      if (!page.hasMore) break;
      if (page.nextCursor == null || page.ops.isEmpty) break; // 防死循环
      cursor = page.nextCursor;
      if (++guard > 200) break; // 200 * 500 op 上限，异常时不要无限拉
    }
    return all;
  }

  // ------------------------------------------------------------
  // 设备
  // ------------------------------------------------------------

  Future<void> revokeDevice(String deviceId) async {
    final resp = await _send(
        () => dio.delete<dynamic>('/api/v1/devices/$deviceId'));
    if (resp.statusCode != 200) _throw(resp);
  }
}
