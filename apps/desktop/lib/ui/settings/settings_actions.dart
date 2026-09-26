import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';

import '../../services/shell_open.dart';
import '../../state/app_scope.dart';
import '../home_page.dart' show dataRootProvider;

/// 数据管理页用到的几个文件操作（M9 从旧设置页原样搬出）。
/// 全部在应用数据目录下操作，失败一律给出可见提示而不是静默。
const windowNewline = '\r\n';

/// 一键备份：数据库 + 图片 → zip，落在 `<数据目录>/backups/`。
Future<void> backupNow(WidgetRef ref, BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final root = ref.read(dataRootProvider);
    final zip = BackupManager.createBackup(
      dbPath: '$root/quizsync.db',
      imagesDir: '$root/images',
    );
    final dir = Directory('$root/backups');
    await dir.create(recursive: true);
    final file = File(
        '${dir.path}/quizsync-backup-${DateTime.now().millisecondsSinceEpoch}.zip');
    await file.writeAsBytes(zip);
    messenger.showSnackBar(SnackBar(content: Text('备份完成：${file.path}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('备份失败：$e')));
  }
}

/// 从最近一次备份恢复；恢复前自动留底，数据库被占用时下次启动生效。
Future<void> restoreFromLatestBackup(WidgetRef ref, BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final root = ref.read(dataRootProvider);
  final dir = Directory('$root/backups');
  final files = dir.existsSync()
      ? dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'))
          .toList()
      : <File>[];
  if (files.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('没有可用的备份')));
    return;
  }
  files.sort((a, b) => b.path.compareTo(a.path));
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('确认恢复？'),
      content: Text('恢复操作会覆盖当前数据。\n'
          '将使用 ${files.first.path.split(Platform.pathSeparator).last}\n'
          '恢复前会自动为当前数据留底。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认恢复')),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    final applied = await BackupManager.restore(
      zipBytes: await files.first.readAsBytes(),
      dbPath: '$root/quizsync.db',
      imagesDir: '$root/images',
    );
    messenger.showSnackBar(SnackBar(
        content: Text(applied
            ? '恢复完成，请重启应用以加载新数据库'
            : '备份已就绪：应用正在运行、数据库文件被占用，下次启动时自动恢复')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('恢复失败：$e')));
  }
}

/// 导出全部历史（Markdown / JSON）。用户反馈 2：弹「另存为」让用户选位置，
/// 默认目录是软件自己的数据目录（`<应用目录>/data/exports`）。
Future<void> exportAllHistory(WidgetRef ref, BuildContext context,
    {required bool markdown}) async {
  final messenger = ScaffoldMessenger.of(context);
  final log = AppLogger.instance;
  try {
    log.info('export', '导出全部历史开始（${markdown ? 'md' : 'json'}）');
    final repo = ref.read(repoProvider);
    final sessions = await repo.listSessions(limit: 1000000);
    final records = <(Session, List<Question>)>[];
    for (final s in sessions) {
      records.add((s, await repo.questionsOfSession(s.sessionId)));
    }
    final root = ref.read(dataRootProvider);
    final dir = Directory('$root/exports');
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final chosen = savePathChooser(
      title: markdown ? '导出全部历史（Markdown）' : '导出全部历史（JSON）',
      defaultDir: dir.path,
      defaultName: 'all-$stamp.${markdown ? 'md' : 'json'}',
      extension: markdown ? 'md' : 'json',
      filterLabel: markdown ? 'Markdown' : 'JSON',
    );
    if (chosen == null) {
      log.warn('export', '导出全部历史：没有拿到保存路径（见上面的 shell 日志）');
      messenger.showSnackBar(const SnackBar(content: Text('已取消导出')));
      return;
    }
    final file = File(chosen);
    await file.parent.create(recursive: true);
    await file.writeAsString(markdown
        ? Exporter.allToMarkdown(records)
        : jsonEncode(Exporter.allToJson(records)));
    log.info('export', '导出全部历史成功：$chosen（${records.length} 条）');
    messenger.showSnackBar(SnackBar(
      content: Text('已导出 ${records.length} 条：${file.path}'),
      action: SnackBarAction(
        label: '打开所在目录',
        onPressed: () => revealFolder(file.parent.path),
      ),
    ));
  } catch (e, st) {
    log.warn('export', '导出全部历史失败：$e\n$st');
    messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
  }
}

/// 导出日志（不含 API Key 与 Token）。同样弹「另存为」选位置。
Future<void> exportLogFile(WidgetRef ref, BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final log = AppLogger.instance;
  try {
    final root = ref.read(dataRootProvider);
    final dir = Directory('$root/logs');
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final chosen = savePathChooser(
      title: '导出日志',
      defaultDir: dir.path,
      defaultName: 'quizsync-log-$stamp.txt',
      extension: 'txt',
      filterLabel: '文本',
    );
    if (chosen == null) {
      log.warn('export', '导出日志：没有拿到保存路径（见上面的 shell 日志）');
      messenger.showSnackBar(const SnackBar(content: Text('已取消导出')));
      return;
    }
    final file = File(chosen);
    await file.parent.create(recursive: true);
    await file.writeAsString(AppLogger.instance.export().join(windowNewline));
    log.info('export', '日志已导出：$chosen');
    messenger.showSnackBar(SnackBar(
      content: Text('日志已导出：${file.path}'),
      action: SnackBarAction(
        label: '打开所在目录',
        onPressed: () => revealFolder(file.parent.path),
      ),
    ));
  } catch (e, st) {
    log.warn('export', '导出日志失败：$e\n$st');
    messenger.showSnackBar(SnackBar(content: Text('导出日志失败：$e')));
  }
}
