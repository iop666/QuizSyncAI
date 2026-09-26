import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:quizsync_core/quizsync_core.dart';

/// 备份与恢复（M6 任务 8）：数据库 + 图片目录 → zip；从 zip 恢复。
/// 纯 Dart（archive 包），Windows 端 UI 一键调用。
class BackupManager {
  /// 生成备份 zip 字节：db 文件 + images/ 下全部文件。
  static Uint8List createBackup({
    required String dbPath,
    required String imagesDir,
  }) {
    final archive = Archive();
    final db = File(dbPath);
    if (db.existsSync()) {
      // WAL 模式下先 checkpoint：复制三件套（db/-wal/-shm）保证一致。
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$dbPath$suffix');
        if (f.existsSync()) {
          final bytes = f.readAsBytesSync();
          archive.addFile(ArchiveFile(
            'quizsync.db$suffix', bytes.length, bytes));
        }
      }
    }
    final dir = Directory(imagesDir);
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final bytes = entity.readAsBytesSync();
        final rel = entity.path
            .substring(dir.path.length + 1)
            .replaceAll('\\', '/');
        archive.addFile(
            ArchiveFile('images/$rel', bytes.length, bytes));
      }
    }
    final encoder = ZipEncoder();
    return Uint8List.fromList(encoder.encode(archive)!);
  }

  /// 从备份恢复：覆盖 db 与图片目录。恢复前自动备份当前数据为 .pre-restore。
  ///
  /// 返回 true = 已经换库（调用方需重启应用加载新库）；
  /// 返回 false = 现库文件被占用，已**暂存**为 `<dbPath>.restore-pending`，
  /// 下次启动时由 [applyPendingRestore] 换入。
  ///
  /// Windows 上 sqlite 打开的库文件不带 FILE_SHARE_DELETE，直接改名会
  /// `OS Error 32（另一个程序正在使用此文件）`——正是运行期点「恢复备份」
  /// 什么都不发生的原因。
  static Future<bool> restore({
    required Uint8List zipBytes,
    required String dbPath,
    required String imagesDir,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // 先落盘新库文件到临时路径。
    final tmpDb = '$dbPath.restore';
    for (final suffix in ['', '-wal', '-shm']) {
      try {
        File('$tmpDb$suffix').deleteSync();
      } catch (_) {}
    }
    var hasDb = false;
    for (final f in archive) {
      final name = f.name;
      if (name == 'quizsync.db' ||
          name == 'quizsync.db-wal' ||
          name == 'quizsync.db-shm') {
        final suffix = name == 'quizsync.db' ? '' : name.substring('quizsync.db'.length);
        File('$tmpDb$suffix').writeAsBytesSync(f.content as List<int>);
        if (suffix.isEmpty) {
          hasDb = File('$tmpDb$suffix').lengthSync() > 0;
        }
      }
    }

    // 包里没有数据库时**不能**动现有数据：原实现无条件把 db/-wal/-shm 改名，
    // 恢复一个只含图片的包会让用户的库直接消失。
    var applied = false;
    if (hasDb) {
      try {
        // 当前数据留底。
        for (final suffix in ['', '-wal', '-shm']) {
          final f = File('$dbPath$suffix');
          if (f.existsSync()) {
            f.renameSync('$dbPath$suffix.pre-restore-${nowMs()}');
          }
        }
        for (final suffix in ['', '-wal', '-shm']) {
          final tmp = File('$tmpDb$suffix');
          if (tmp.existsSync()) {
            tmp.renameSync('$dbPath$suffix');
          }
        }
        applied = true;
      } catch (_) {
        // 现库被占用（应用正在运行）：暂存，等下次启动换入。
        try {
          File('$dbPath.restore-pending').deleteSync();
        } catch (_) {}
        File(tmpDb).renameSync('$dbPath.restore-pending');
      }
    } else {
      for (final suffix in ['', '-wal', '-shm']) {
        try {
          File('$tmpDb$suffix').deleteSync();
        } catch (_) {}
      }
    }

    // 图片：只允许写到 imagesDir 内部（防 zip-slip：条目名里的 ../ 可以
    // 把文件写到目录之外，构造的备份包 = 任意文件写入）。
    final dir = Directory(imagesDir);
    await dir.create(recursive: true);
    final rootPath = dir.absolute.path;
    for (final f in archive) {
      if (!f.name.startsWith('images/')) continue;
      final rel = f.name.substring('images/'.length);
      final segments = rel.split('/');
      if (segments.isEmpty || segments.any((s) => s.isEmpty || s == '..' || s == '.')) {
        continue; // 跳过空段/回溯段，绝不写到 imagesDir 之外
      }
      final out = File(
          '$rootPath${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}');
      final normalized = out.absolute.path;
      if (!normalized.startsWith('$rootPath${Platform.pathSeparator}')) {
        continue; // 双保险：规范化后仍在目录内才写
      }
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
    }
    return applied;
  }

  /// 是否有「暂存的恢复」等待下次启动换入。
  static bool hasPendingRestore(String dbPath) =>
      File('$dbPath.restore-pending').existsSync();

  /// 启动时（打开数据库**之前**）调用：把暂存的库换入。
  /// 返回 true 表示确实换入了。
  static bool applyPendingRestore(String dbPath) {
    final pending = File('$dbPath.restore-pending');
    if (!pending.existsSync() || pending.lengthSync() == 0) return false;
    final ts = nowMs();
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (f.existsSync()) {
        try {
          f.renameSync('$dbPath$suffix.pre-restore-$ts');
        } catch (_) {
          // 换不掉就放弃本次恢复，绝不删用户数据。
          return false;
        }
      }
    }
    try {
      pending.renameSync(dbPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}
