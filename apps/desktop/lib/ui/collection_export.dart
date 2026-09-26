import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';

import '../services/shell_open.dart';
import '../state/app_scope.dart';

/// 合集导出（用户需求 9）：把当前合集的全部识别记录按**识别顺序**导出。
///
/// 用户反馈 2（本轮）：不再默默写进数据目录 —— 点导出时弹**系统另存为对话框**，
/// 默认目录就是软件自己的数据目录（`<应用目录>/data/exports`），用户可以改到
/// 桌面 / U 盘等任意位置。Markdown 与 JSON 同名各写一份（改扩展名即可）。
///
/// 一个入口同时被主界面顶栏与设置页复用，行为（二次确认、文案、落盘位置）
/// 完全一致。
Future<void> exportCollection(
  BuildContext context,
  WidgetRef ref, {
  required Collection collection,
  required String dataRoot,
  bool confirm = true,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String msg, {SnackBarAction? action}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 6),
        action: action,
      ));
  }

  final repo = ref.read(repoProvider);
  final log = AppLogger.instance;
  final records = <(Session, List<Question>)>[];
  final pageCounts = <String, int>{};
  log.info('export', '导出集合「${collection.name}」开始');
  try {
    // 识别顺序（时间升序），不是列表的倒序：导出的文档要按时间正序读。
    final sessions =
        await repo.listSessionsAscending(collectionId: collection.collectionId);
    for (final s in sessions) {
      records.add((s, await repo.questionsOfSession(s.sessionId)));
      pageCounts[s.sessionId] = (await repo.imageHashesOf(s.sessionId)).length;
    }
  } catch (e, st) {
    log.warn('export', '导出集合失败（读数据）：$e\n$st');
    toast('导出失败：$e');
    return;
  }
  if (records.isEmpty) {
    toast('合集「${collection.name}」里还没有识别记录，先截屏搜一次题再导出');
    return;
  }

  var totalQuestions = 0;
  for (final (_, qs) in records) {
    totalQuestions += qs.length;
  }

  // 导出是耗时操作：先让用户确认要导出什么，避免点错合集白等。
  if (confirm) {
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('导出合集「${collection.name}」？'),
        content: Text('共 ${records.length} 条识别记录、$totalQuestions 道题。\n\n'
            '按识别顺序写入 Markdown 与 JSON 各一份，下一步会让你选择保存位置'
            '（默认就在软件自己的数据目录下）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('选择保存位置…')),
        ],
      ),
    );
    if (ok != true) return;
  }

  try {
    final dir = Directory('$dataRoot/exports');
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final stem = 'collection-${collectionFileStem(collection.name)}-$stamp';
    // 用户反馈 2：默认目录 = 软件数据目录下的 exports/；用户可以另选位置。
    final chosen = savePathChooser(
      title: '导出合集「${collection.name}」（Markdown；同名 .json 一起写出）',
      defaultDir: dir.path,
      defaultName: '$stem.md',
      extension: 'md',
      filterLabel: 'Markdown',
    );
    if (chosen == null) {
      log.warn('export', '导出集合：没有拿到保存路径（见上面的 shell 日志）');
      toast('已取消导出');
      return;
    }
    // 用平台分隔符拼路径：SnackBar 里给出的路径要和资源管理器里看到的一致。
    final md = File(chosen.toLowerCase().endsWith('.md') ? chosen : '$chosen.md');
    final base = md.path.substring(0, md.path.length - 3);
    final json = File('$base.json');
    await md.parent.create(recursive: true);
    await md.writeAsString(Exporter.collectionToMarkdown(
      collection.name,
      records,
      pageCounts: pageCounts,
    ));
    await json.writeAsString(const JsonEncoder.withIndent('  ')
        .convert(Exporter.collectionToJson(collection.name, records)));
    log.info('export', '导出集合成功：${md.path}（另有同名 .json）');
    toast(
      '已导出 ${records.length} 条记录：${md.path}（另有同名 .json）',
      action: SnackBarAction(
        label: '打开所在目录',
        onPressed: () => revealFolder(md.parent.path),
      ),
    );
  } catch (e, st) {
    log.warn('export', '导出集合失败（写文件）：$e\n$st');
    toast('导出失败：$e');
  }
}

/// 合集名 → 合法文件名片段（Windows 不允许 `\ / : * ? " < > |`）。
String collectionFileStem(String name) {
  var s = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  if (s.length > 40) s = s.substring(0, 40);
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  return s.isEmpty ? 'collection' : s;
}
