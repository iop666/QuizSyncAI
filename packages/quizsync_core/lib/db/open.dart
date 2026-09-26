import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'database.dart';

/// 打开（或创建）一个文件型数据库。两端 App 用这个入口。
QuizSyncDb openQuizSyncDb(String path, {bool logStatements = false}) {
  return QuizSyncDb(LazyDatabase(() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(file, logStatements: logStatements);
  }));
}
