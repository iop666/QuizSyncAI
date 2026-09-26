import 'dart:io';

import 'package:quizsync_server/quizsync_server_core.dart';
import 'package:quizsync_server/src/config.dart';
import 'package:quizsync_server/src/constants.dart';
import 'package:quizsync_server/src/store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late ConfigPaths paths;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('quizsync-server-store');
    paths = ConfigPaths(temp);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  StoredSession sampleSession(String sessionId,
          {String? taskId, int createdAt = 1}) =>
      StoredSession(
        session: Session(
          sessionId: sessionId,
          taskId: taskId ?? sessionId,
          imageHash: 'hash-1',
          sourceDevice: 'server-device',
          status: TaskState.done,
          questionCount: 1,
          createdAt: createdAt,
          updatedAt: createdAt,
          updatedBy: 'server-device',
        ),
        questions: [
          Question(
            questionId: 'q1',
            sessionId: sessionId,
            ordinal: 0,
            stem: '题干',
            type: QuestionType.single,
            options: const [Option(label: 'A', text: '甲')],
            choice: const ['A'],
            createdAt: 1,
            updatedAt: 1,
            updatedBy: 'server-device',
          ),
        ],
        imageHashes: const ['hash-1'],
      );

  test('首次打开：生成 device_id 与固定默认合集，并落盘', () async {
    final store = await ServerStore.open(paths);
    expect(store.deviceId, isNotEmpty);
    expect(store.collection.name, kDefaultCollectionName);
    expect(store.collection.collectionId, isNotEmpty);
    expect(paths.stateFile.existsSync(), isTrue);

    // 再开一次：device_id 与合集必须**沿用**（否则手机端会以为自己换了主机）。
    final again = await ServerStore.open(paths);
    expect(again.deviceId, store.deviceId);
    expect(again.collection.collectionId, store.collection.collectionId);
  });

  test('会话 + 题目 + 页序往返', () async {
    final store = await ServerStore.open(paths);
    await store.putSession(sampleSession('s1'));

    final reloaded = await ServerStore.open(paths);
    final got = reloaded.getSession('s1');
    expect(got, isNotNull);
    expect(got!.questions.single.stem, '题干');
    expect(got.questions.single.choice, ['A']);
    expect(got.imageHashes, ['hash-1']);
    expect(got.session.status, TaskState.done);
    // 协议 JSON 必须带 page 信息（安卓端要显示「N 张图片识别中…」）。
    expect(got.toProtocolJson()['image_count'], 1);
    expect(got.toProtocolJson()['image_hashes'], ['hash-1']);
    expect(got.toProtocolJson()['questions'], hasLength(1));
  });

  test('图片写盘/读回，元数据落进状态文件', () async {
    final store = await ServerStore.open(paths);
    final meta = await store.writeImage(kJpegBytes, width: 1600, height: 900);
    expect(meta.hash, sha256Hex(kJpegBytes));
    expect(store.imageFile(meta.hash).existsSync(), isTrue);
    expect(await store.readImage(meta.hash), kJpegBytes);

    final reloaded = await ServerStore.open(paths);
    expect(reloaded.images[meta.hash]!.width, 1600);
  });

  test('图片文件被手工删掉后，元数据自愈', () async {
    final store = await ServerStore.open(paths);
    final meta = await store.writeImage(kJpegBytes);
    store.imageFile(meta.hash).deleteSync();

    final reloaded = await ServerStore.open(paths);
    expect(reloaded.images.containsKey(meta.hash), isFalse);
  });

  test('设备：按 token hash 查找 / 吊销 / 只列未吊销', () async {
    final store = await ServerStore.open(paths);
    await store.upsertDevice(PairedDevice(
      info: DeviceInfo(
        deviceId: 'phone-1',
        name: 'Pixel 7',
        platform: 'android',
        tokenHash: sha256Hex('tok'.codeUnits),
        pairedAt: 1,
      ),
      tokenHash: sha256Hex('tok'.codeUnits),
    ));
    expect(store.deviceByTokenHash(sha256Hex('tok'.codeUnits))!.info.name, 'Pixel 7');
    expect(store.activeDevices, hasLength(1));

    await store.revokeDevice('phone-1');
    expect(store.activeDevices, isEmpty);
    expect(store.deviceByTokenHash(sha256Hex('tok'.codeUnits))!.info.isRevoked, isTrue);
  });

  test('ops 幂等记录有上限', () async {
    final store = await ServerStore.open(paths);
    expect(store.markOpApplied('op-1'), isTrue);
    expect(store.markOpApplied('op-1'), isFalse);
    for (var i = 0; i < ServerStore.maxOpIds + 20; i++) {
      store.markOpApplied('bulk-$i');
    }
    expect(store.appliedOpIds.length, lessThanOrEqualTo(ServerStore.maxOpIds));
  });

  test('会话数量按上限裁剪（丢掉最老的）', () async {
    final store = await ServerStore.open(paths);
    for (var i = 0; i < ServerStore.maxSessions + 10; i++) {
      await store.putSession(sampleSession('s-$i', createdAt: i));
    }
    expect(store.sessions.length, ServerStore.maxSessions);
    expect(store.getSession('s-0'), isNull);
    expect(store.getSession('s-${ServerStore.maxSessions + 9}'), isNotNull);
  });

  test('状态文件损坏时重建（服务必须能起），旧文件留档', () async {
    await File(paths.stateFile.path).writeAsString('{ this is not json');
    final store = await ServerStore.open(paths);
    expect(store.deviceId, isNotEmpty);
    expect(File('${paths.stateFile.path}.broken').existsSync(), isTrue);
  });
}
