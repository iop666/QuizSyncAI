import 'dart:io';
import 'dart:typed_data';

/// 服务端图片文件存储：hash.jpg 存目录；测试可用内存实现。
abstract class ImageFileStore {
  Future<void> write(String hash, Uint8List bytes);
  Future<Uint8List?> read(String hash);
  Future<bool> exists(String hash);

  /// 这张图落盘后的**本地绝对路径**（内存实现返回 null）。
  ///
  /// 服务端收到手机上传的图后要把它写进 `images.local_path`，Windows 主界面的
  /// 缩略图 / 「重新分析」都靠这一列找文件（用户反馈 M15 第 2 条：手机传来的图
  /// 在 Windows 端一直没有缩略图，就是因为上传处理器没写这一列）。
  String? pathFor(String hash) => null;
}

class DirectoryImageStore implements ImageFileStore {
  final String dir;
  DirectoryImageStore(this.dir);

  File _file(String hash) => File('$dir/$hash.jpg');

  @override
  String? pathFor(String hash) => _file(hash).path;

  @override
  Future<void> write(String hash, Uint8List bytes) async {
    final f = _file(hash);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> read(String hash) async {
    final f = _file(hash);
    if (!await f.exists()) return null;
    return Uint8List.fromList(await f.readAsBytes());
  }

  @override
  Future<bool> exists(String hash) => _file(hash).exists();
}

class MemoryImageStore implements ImageFileStore {
  final Map<String, Uint8List> _map = {};

  /// 内存实现没有真实文件：调用方要自己决定 localPath 用不用（见
  /// `_handleImageUpload`，那边是 `pathFor(hash) ?? 已有记录的 localPath`）。
  @override
  String? pathFor(String hash) => null;

  @override
  Future<void> write(String hash, Uint8List bytes) async => _map[hash] = bytes;

  @override
  Future<Uint8List?> read(String hash) async => _map[hash];

  @override
  Future<bool> exists(String hash) async => _map.containsKey(hash);
}
