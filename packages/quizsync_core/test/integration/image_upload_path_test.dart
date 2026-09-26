import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

/// M15 第 2 条（用户反馈）：**安卓传上来的图片在 Windows 端既没进截图目录、
/// 主界面也没有缩略图**。
///
/// 两件事各一条测试：
/// 1. 服务端收到的图必须真的落到 `imageStore` 的目录里（Windows 端把它配成
///    与本机截图相同的 `<数据目录>/images`）；
/// 2. 同一张图的 `images.local_path` 必须写上 —— Windows 主界面的缩略图、
///    结果页与「重新分析」都靠这一列找文件。原来上传处理器在**写完文件之后**
///    又查了一次库（写文件不会建 `images` 行），拿到的 localPath 必然是 null，
///    于是手机传来的记录永远显示占位图标。
void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late QuizSyncServer server;
  late Directory imageDir;
  late int port;
  late String token;
  const serverDeviceId = 'windows-local';
  const clientDeviceId = 'android-device-1';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: serverDeviceId);
    await repo.init();
    imageDir = await Directory.systemTemp.createTemp('m15-images-');
    final store = DirectoryImageStore(imageDir.path);
    server = QuizSyncServer(
      repo: repo,
      imageStore: store,
      executor: ServerTaskExecutor(
        repo: repo,
        engine: AnalysisEngine(
          provider: FakeAiProvider(
              File('test/fixtures/multi_and_judge.json').absolute.path),
          cache: AnalysisCache(repo),
          quota: QuotaGuard(db),
          deviceId: serverDeviceId,
        ),
        imageStore: store,
        configProvider: () => const AiConfig(
            providerId: 'openai-compatible', apiKey: 'k', model: 'm'),
      ),
      deviceId: serverDeviceId,
      serverName: 'TEST-HOST',
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
    await db.close();
    await imageDir.delete(recursive: true);
  });

  Uint8List jpeg() => Uint8List.fromList([
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46,
        0x00, 0x01, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9,
      ]);

  test('手机上传的图落在服务端图片目录里，并且 local_path 指向它', () async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);
    final bytes = jpeg();
    final uploaded = await api.uploadImage(bytes);
    final hash = sha256Hex(bytes);

    expect(uploaded.imageHash, hash);
    final file = File('${imageDir.path}/$hash.jpg');
    expect(file.existsSync(), isTrue,
        reason: '文件必须落在服务端图片目录（Windows 端配成与本机截图同一个目录）');

    final meta = await repo.getImage(hash);
    expect(meta, isNotNull);
    expect(meta!.localPath, isNotNull,
        reason: 'M15 第 2 条的回归点：Windows 缩略图靠这一列');
    expect(meta.localPath, file.path);
  });

  test('重复上传同一张图不会把已有的 local_path 抹掉', () async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);
    final bytes = jpeg();
    await api.uploadImage(bytes);
    final hash = sha256Hex(bytes);
    final first = (await repo.getImage(hash))!.localPath;

    final again = await api.uploadImage(bytes);
    expect(again.existed, isTrue, reason: '按 hash 幂等');
    expect((await repo.getImage(hash))!.localPath, first);
  });

  test('数据库里已有记录（local_path 为空）时，再传一次会补上路径', () async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:$port', token: token);
    final bytes = jpeg();
    final hash = sha256Hex(bytes);
    // 模拟旧版本遗留的行：有记录、没有 local_path。
    await repo.upsertImage(ImageMeta(
      hash: hash,
      size: bytes.length,
      mime: 'image/jpeg',
      createdAt: nowMs(),
      uploadedBy: clientDeviceId,
    ));
    expect((await repo.getImage(hash))!.localPath, isNull);

    await api.uploadImage(bytes);

    expect((await repo.getImage(hash))!.localPath, isNotNull,
        reason: '重传要自愈历史数据（用户那边已经有传好的图）');
  });
}
