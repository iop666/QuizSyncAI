import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';

import 'package:quizsync_core/db/database.dart';
import 'package:quizsync_core/db/repository.dart';

// 每个用例独立内存库，drift 的「同一 executor 重复建库」告警是误报。
void _silenceDuplicateWarning() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// 测试用内存库。
/// 依赖链（drift → sqlite3 3.x）通过 Dart 原生 build hook 自动编译 sqlite3，
/// 本机无需手工放置 dll。
QuizSyncDb createTestDb() {
  _silenceDuplicateWarning();
  return QuizSyncDb(NativeDatabase.memory());
}

CoreRepository createTestRepo(QuizSyncDb db, String deviceId) =>
    CoreRepository(db: db, deviceId: deviceId);
