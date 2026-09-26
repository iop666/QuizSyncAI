import 'dart:io';

import 'package:quizsync_core/quizsync_core.dart';

/// 合集导出结果（用户需求 9）。
class ExportResult {
  final bool ok;
  final String? path;
  final String? error;
  final int recordCount;
  final int questionCount;

  const ExportResult({
    required this.ok,
    this.path,
    this.error,
    this.recordCount = 0,
    this.questionCount = 0,
  });
}

/// 把一组识别记录导出成一个易读的 Markdown 文件。
///
/// - **按识别顺序排序**（`createdAt` 升序，用户需求 9）；
/// - 每条的页数一并写进文件（多页识别的「页数：N」）；
/// - 落盘位置由调用方给（真机用应用文档目录），失败返回 error 交给 UI 弹提示。
Future<ExportResult> exportSessions({
  required CoreRepository repo,
  required String collectionName,
  required List<Session> sessions,
  required Future<Directory> Function() baseDir,
  DateTime? now,
}) async {
  try {
    final sorted = [...sessions]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final records = <(Session, List<Question>)>[];
    final pageCounts = <String, int>{};
    var questions = 0;
    for (final s in sorted) {
      final qs = await repo.questionsOfSession(s.sessionId);
      records.add((s, qs));
      questions += qs.length;
      pageCounts[s.sessionId] = (await repo.imageHashesOf(s.sessionId)).length;
    }
    final markdown = Exporter.collectionToMarkdown(
      collectionName,
      records,
      pageCounts: pageCounts,
    );
    final dir = await baseDir();
    await dir.create(recursive: true);
    final file = File('${dir.path}/${exportFileName(collectionName, now)}');
    await file.writeAsString(markdown, flush: true);
    return ExportResult(
      ok: true,
      path: file.path,
      recordCount: records.length,
      questionCount: questions,
    );
  } catch (e) {
    return ExportResult(ok: false, error: '$e');
  }
}

/// `quizsync_合集名_20260916_143012.md`（文件名里的非法字符替换掉）。
String exportFileName(String collectionName, DateTime? now) {
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${t.year}${two(t.month)}${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  final safe = collectionName
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'quizsync_${safe.isEmpty ? 'export' : safe}_$stamp.md';
}
