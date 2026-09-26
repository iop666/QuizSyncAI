import 'package:quizsync_core/quizsync_core.dart';

/// 导出（M6 任务 7；用户需求 9 增加合集导出）：
/// 单条会话 / 整个合集 / 全部历史 → Markdown / JSON。
class Exporter {
  /// 单条会话 → Markdown。
  static String sessionToMarkdown(Session session, List<Question> questions,
      {int? pageCount}) {
    final buf = StringBuffer();
    final t = DateTime.fromMillisecondsSinceEpoch(session.createdAt);
    buf.writeln('# 识别记录 ${t.toIso8601String()}');
    buf.writeln();
    buf.writeln('- 状态：${session.status.wire}');
    if (session.aiModel != null) buf.writeln('- 模型：${session.aiModel}');
    if (session.cached) buf.writeln('- 命中缓存');
    if (pageCount != null && pageCount > 1) buf.writeln('- 页数：$pageCount');
    buf.writeln();
    for (final q in questions) {
      buf.writeln(_questionHeading(q));
      buf.writeln();
      // 阅读材料（用户反馈 15）：导出的文档里放在题干之前，缩进引用块。
      if (q.hasMaterial) {
        buf.writeln('> **阅读材料**');
        for (final line in q.material.split('\n')) {
          buf.writeln('> $line');
        }
        buf.writeln();
      }
      buf.writeln(q.stem);
      buf.writeln();
      for (final o in q.options) {
        final hit = q.choice.contains(o.label);
        buf.writeln('- ${hit ? '**✓ ${o.label}.**' : '${o.label}.'} ${o.text}');
      }
      if (q.choice.isNotEmpty) {
        buf.writeln();
        buf.writeln('**答案：${q.choice.join('、')}**${q.answerGuessed ? '（AI 猜测）' : ''}');
      } else if (q.answerText != null && q.answerText!.isNotEmpty) {
        buf.writeln();
        buf.writeln('**答案：**${q.answerText}${q.answerGuessed ? '（AI 猜测）' : ''}');
      }
      if (q.analysis.isNotEmpty) {
        buf.writeln();
        buf.writeln('> 解析：${q.analysis}');
      }
      if (q.warnings.isNotEmpty) {
        buf.writeln();
        buf.writeln('> ⚠ ${q.warnings.join('；')}');
      }
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln('_答案由 AI 生成，仅供参考_');
    return buf.toString();
  }

  /// 题目标题：排序序号在前，识别到的题号在后（用户需求 3）。
  static String _questionHeading(Question q) {
    final flags = StringBuffer('（${questionTypeLabel(q.type)}');
    if (q.incomplete) flags.write(' · 题目不全');
    if (q.answerGuessed) flags.write(' · AI 猜测');
    flags.write('）');
    return '## ${q.displayTitle}$flags';
  }

  /// 单条会话 → JSON。
  static Map<String, dynamic> sessionToJson(Session session, List<Question> questions) => {
        ...session.toJson(),
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  /// 整个合集 → Markdown（**按识别顺序排序**，用户需求 9）。
  static String collectionToMarkdown(
    String collectionName,
    List<(Session, List<Question>)> records, {
    Map<String, int> pageCounts = const {},
  }) {
    final buf = StringBuffer();
    buf.writeln('# 任务合集：$collectionName');
    buf.writeln();
    buf.writeln('- 记录数：${records.length}');
    var total = 0;
    for (final (_, qs) in records) {
      total += qs.length;
    }
    buf.writeln('- 题目数：$total');
    buf.writeln();
    for (var i = 0; i < records.length; i++) {
      final (session, questions) = records[i];
      buf.writeln('## 第 ${i + 1} 次识别');
      buf.writeln();
      buf.writeln(sessionToMarkdown(session, questions,
          pageCount: pageCounts[session.sessionId]));
      buf.writeln();
    }
    return buf.toString();
  }

  /// 整个合集 → JSON。
  static Map<String, dynamic> collectionToJson(
    String collectionName,
    List<(Session, List<Question>)> records,
  ) =>
      {
        'exported_at': nowMs(),
        'collection_name': collectionName,
        'records': [
          for (final (s, qs) in records) sessionToJson(s, qs),
        ],
      };

  /// 全部历史 → Markdown。
  static String allToMarkdown(List<(Session, List<Question>)> records) {
    final buf = StringBuffer();
    buf.writeln('# AI 双端搜题（QuizSync AI）历史导出');
    buf.writeln();
    for (final (session, questions) in records) {
      buf.writeln(sessionToMarkdown(session, questions));
    }
    return buf.toString();
  }

  /// 全部历史 → JSON。
  static Map<String, dynamic> allToJson(List<(Session, List<Question>)> records) => {
        'exported_at': nowMs(),
        'records': [
          for (final (s, qs) in records) sessionToJson(s, qs),
        ],
      };
}

String questionTypeLabel(QuestionType t) => switch (t) {
      QuestionType.single => '单选题',
      QuestionType.multi => '多选题',
      QuestionType.judge => '判断题',
      QuestionType.blank => '填空题',
      QuestionType.subjective => '主观题',
    };
