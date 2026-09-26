import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_android/services/collection_export.dart';
import 'package:quizsync_android/services/android_sync.dart';
import 'package:quizsync_android/state/app_state.dart';

import 'support.dart';

/// 合集导出（用户需求 9）与安卓端本地图片固定保留张数
/// （M14 第 7 条：用户要求固定 20 张，缓存上限选项已移除）。
void main() {
  late QuizSyncDb db;
  late AndroidAppState app;

  setUp(() async {
    db = QuizSyncDb(NativeDatabase.memory());
    app = await makeTestApp(db);
  });

  tearDown(() async => db.close());

  test('合集导出：按识别顺序排序 + 写进文件名规范的 Markdown 文件', () async {
    final dir = await Directory.systemTemp.createTemp('qs-export-');
    // 故意用「新的先入库」的顺序，验证导出会按 createdAt 升序排。
    await addSession(app, 's2', stem: '第二次识别的题', createdAt: 2000, questionNo: '12');
    await addSession(app, 's1', stem: '第一次识别的题', createdAt: 1000, questionNo: '3');
    await app.repo.setSessionImages('s1', ['h1', 'h2']);

    final sessions = await app.repo.listSessionsAscending();
    final result = await exportSessions(
      repo: app.repo,
      collectionName: '期末复习',
      sessions: sessions,
      baseDir: () async => dir,
      now: DateTime(2026, 9, 16, 14, 30, 12),
    );

    expect(result.ok, isTrue, reason: result.error ?? '');
    expect(result.recordCount, 2);
    expect(result.questionCount, 2);
    expect(result.path, endsWith('quizsync_期末复习_20260916_143012.md'));

    final content = await File(result.path!).readAsString();
    final first = content.indexOf('第一次识别的题');
    final second = content.indexOf('第二次识别的题');
    expect(first, greaterThanOrEqualTo(0));
    expect(second, greaterThan(first), reason: '按识别顺序（时间升序）');
    expect(content.contains('第 1 次识别'), isTrue);
    expect(content.contains('第 2 次识别'), isTrue);
    // 页数来自 imageHashesOf（永远 ≥1）。
    expect(content.contains('- 页数：2'), isTrue);
    // 题号用 displayTitle（需求 3）。
    expect(content.contains('1. 第 3 题'), isTrue);

    await dir.delete(recursive: true);
  });

  test('导出失败（目录不可用）返回 error，不抛异常', () async {
    await addSession(app, 's1', stem: '题', createdAt: 1000);
    final sessions = await app.repo.listSessionsAscending();
    final result = await exportSessions(
      repo: app.repo,
      collectionName: 'x',
      sessions: sessions,
      baseDir: () async => throw const FileSystemException('磁盘不可写'),
    );
    // 落盘失败必须变成 UI 能处理的 error，绝不能是未处理异常。
    expect(result.ok, isFalse);
    expect(result.error, contains('磁盘不可写'));
  });

  test('导出文件名：非法字符被替换', () {
    expect(
      exportFileName('期末/复习:第1轮?', DateTime(2026, 1, 2, 3, 4, 5)),
      'quizsync_期末_复习_第1轮_20260102_030405.md',
    );
    expect(exportFileName('   ', DateTime(2026, 1, 2, 3, 4, 5)),
        startsWith('quizsync_export_'));
  });

  test('M14 第 7 条：固定只保留最近 20 张原图（选项已移除，不再读设置）', () async {
    final dir = await Directory.systemTemp.createTemp('qs-img-');
    final sync = AndroidSync(app: app, imageDir: dir.path);
    // 造 22 张：createdAt 递增，越早越旧。
    for (var i = 0; i < 22; i++) {
      final jpeg = fakeJpeg(i);
      final hash = sha256Hex(jpeg);
      await app.repo.upsertImage(ImageMeta(
        hash: hash,
        size: jpeg.length,
        mime: 'image/jpeg',
        createdAt: 1000 + i,
        uploadedBy: 'android-local',
      ));
      await sync.saveImageFile(hash, jpeg);
    }
    expect(dir.listSync().whereType<File>().length, 22);

    // 对安卓端已经失效的设置项故意写成「不设限」：清理结果必须还是 20 张。
    await app.settings.updateApp(app.settings.app.copyWith(imageCacheLimit: 0));

    expect(await sync.pruneImages(), 2, reason: '22 - 20 = 删掉最旧的 2 张');
    // 用文件名比较：Windows 上 `dir.listSync()` 给的是反斜杠路径，
    // 而 `saveImageFile` 拼的是正斜杠，直接比完整路径会全部不相等。
    final left = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(left.length, kAndroidLocalImageLimit);
    for (var i = 0; i < 2; i++) {
      expect(left.contains('${sha256Hex(fakeJpeg(i))}.jpg'), isFalse,
          reason: '删掉的必须是 $i 号（最旧的）');
    }
    expect(left.contains('${sha256Hex(fakeJpeg(21))}.jpg'), isTrue,
        reason: '最新的那张要留着');

    await dir.delete(recursive: true);
  });
}

/// 3 个不同的假 JPEG。
Uint8List fakeJpeg(int i) =>
    Uint8List.fromList([0xff, 0xd8, 0x10 + i, 0xff, 0xd9]);
