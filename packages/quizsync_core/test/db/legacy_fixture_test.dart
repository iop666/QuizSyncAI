import 'dart:io';

import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:quizsync_core/db/database.dart';

/// 生成「旧库样本」给 **Kotlin 内核**的兼容性用例读。
///
/// 为什么要有这个文件：Flutter 版（drift，schemaVersion 3）写出来的库必须能被
/// 原生 2.0 的 Android 内核打开并读出正确内容 —— 这是升级不能砸用户数据的前提。
/// 二进制样本没法在 Kotlin 侧现造（那要跑 Dart），所以由这条用例生成并提交：
///
///     dart test test/db/legacy_fixture_test.dart
///
/// 产物：`../../android/core/src/test/resources/legacy-drift-v3.db`
///
/// 用**原始 SQL** 插入而不是 drift 的生成构造器：构造器参数随版本变，
/// 而列名是协议 schema 固定下来的（那份 schema 本来就是从旧库反推的）。
void main() {
  test('生成旧库样本（Kotlin 兼容性用例的输入）', () async {
    final out = File('../../android/core/src/test/resources/legacy-drift-v3.db');
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('${out.path}$suffix');
      if (await f.exists()) {
        await f.delete();
      }
    }
    await out.parent.create(recursive: true);

    final db = QuizSyncDb(NativeDatabase(out));
    try {
      await db.customStatement(
        'INSERT INTO collections (collection_id, name, created_at, updated_at, updated_by, lamport) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['c-legacy', '旧库合集', 1700000000000, 1700000000000, 'legacy-device', 1],
      );
      await db.customStatement(
        'INSERT INTO sessions (session_id, image_hash, source_device, status, collection_id, question_count, '
        'created_at, updated_at, updated_by, lamport) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['s-legacy', 'hash-legacy', 'legacy-device', 'done', 'c-legacy', 2,
          1700000000000, 1700000000000, 'legacy-device', 2],
      );
      await db.customStatement(
        'INSERT INTO questions (question_id, session_id, ordinal, stem, type, options_json, choice_json, '
        'answer_text, analysis, confidence, created_at, updated_at, updated_by, lamport) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['q-legacy-1', 's-legacy', 0, '旧库里的选择题', 'single',
          '[{"label":"A","text":"甲"},{"label":"B","text":"乙"}]', '["B"]', null, '旧库解析', 0.9,
          1700000000000, 1700000000000, 'legacy-device', 3],
      );
      await db.customStatement(
        'INSERT INTO questions (question_id, session_id, ordinal, stem, type, options_json, choice_json, '
        'answer_text, analysis, confidence, created_at, updated_at, updated_by, lamport) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        ['q-legacy-2', 's-legacy', 1, '旧库里的填空题', 'blank', '[]', '[]', 'H2O', '', 0.8,
          1700000000000, 1700000000000, 'legacy-device', 4],
      );
    } finally {
      // 关连接让 WAL 合并进主文件，样本才是自包含的。
      await db.close();
    }

    expect(await out.exists(), isTrue, reason: '样本没写出来');
    final size = await out.length();
    expect(size, lessThan(2 * 1024 * 1024), reason: '样本过大：$size 字节');
    // ignore: avoid_print
    print('旧库样本已生成：${out.path}（$size 字节）');
  });
}
