import 'dart:typed_data';

import 'package:quizsync_core/quizsync_core.dart';

/// 主机（Windows 内置服务端）网关接口（用户需求 12）。
///
/// 页面只依赖这个接口，不直接 new [ApiClient]：
/// - 真机走 [ApiHostGateway]（dio + 局域网 HTTP）；
/// - widget 测试注入假实现，就能在没有设备/没有网络的机器上覆盖
///   「未配对 / 主机离线 / 主机未选合集 / 识别进度 / 重新生成」全部分支。
abstract class HostGateway {
  Future<ServerInfo> info();

  Future<CollectionList> collections();

  Future<void> selectCollection(String collectionId);

  Future<UploadedImage> uploadImage(Uint8List jpeg);

  Future<TaskStatusView> createTask({
    required String taskId,
    required String imageHash,
    required String sourceDevice,
    List<String>? imageHashes,
    String? collectionId,
  });

  Future<TaskStatusView> getTask(String taskId);

  /// 「重新生成」（用户需求 7）。
  Future<TaskStatusView> reanalyze(String sessionId);

  /// 主机当前选中的合集；连不上时抛 [ApiClientException]。
  Future<({String? id, String? name})> activeCollection() async {
    final i = await info();
    return (id: i.activeCollectionId, name: i.activeCollectionName);
  }
}

/// 真机实现：薄薄一层转发到 [ApiClient]（协议细节全在 core 里）。
class ApiHostGateway implements HostGateway {
  final ApiClient client;

  ApiHostGateway(this.client);

  @override
  Future<ServerInfo> info() => client.fetchInfo();

  @override
  Future<CollectionList> collections() => client.fetchCollections();

  @override
  Future<void> selectCollection(String collectionId) =>
      client.selectCollection(collectionId);

  @override
  Future<UploadedImage> uploadImage(Uint8List jpeg) => client.uploadImage(jpeg);

  @override
  Future<TaskStatusView> createTask({
    required String taskId,
    required String imageHash,
    required String sourceDevice,
    List<String>? imageHashes,
    String? collectionId,
  }) =>
      client.createTask(
        taskId: taskId,
        imageHash: imageHash,
        sourceDevice: sourceDevice,
        imageHashes: imageHashes,
        collectionId: collectionId,
      );

  @override
  Future<TaskStatusView> getTask(String taskId) => client.getTask(taskId);

  @override
  Future<TaskStatusView> reanalyze(String sessionId) =>
      client.reanalyzeSession(sessionId);

  @override
  Future<({String? id, String? name})> activeCollection() async {
    final i = await info();
    return (id: i.activeCollectionId, name: i.activeCollectionName);
  }
}

/// 未选合集时统一的用户文案（用户需求 12）：主机的 409 也归到这一句，
/// 避免「静默失败」或直接抛出一句英文协议错误。
const String kNoActiveCollectionMessage = '请先在电脑上选择任务合集';
