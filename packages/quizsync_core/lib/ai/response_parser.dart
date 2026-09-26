import 'dart:convert';

import '../model/question.dart';
import '../util/ids.dart';

/// 解析结果：规范化后的题目列表 + 被丢弃的空题干条数。
class ParsedQuestions {
  final List<Question> questions;

  /// 题干为空被丢弃的条数（schema 要求 stem minLength 1）。
  final int droppedEmpty;

  const ParsedQuestions({required this.questions, required this.droppedEmpty});
}

/// `ai-contract.md` 第 3 节的 5 步容错解析。
/// 本类只做前 3 步（纯文本 → JSON）；第 4 步（附加严格提醒重试）与
/// 第 5 步（标记失败保留原文）由 AnalysisEngine 在调用层完成。
class ResponseParser {
  /// 依次尝试：直接解码 → 剥离代码围栏 → 截取首尾大括号。
  /// 全部失败返回 null。
  static Map<String, dynamic>? tryParseJson(String text) {
    // 1. 直接 jsonDecode 整个响应文本。
    final direct = _decode(text);
    if (direct != null) return direct;

    // 2. 剥离 markdown 代码围栏（```json ... ``` 或 ``` ... ```）。
    final stripped = _stripCodeFence(text);
    if (stripped != null) {
      final decoded = _decode(stripped);
      if (decoded != null) return decoded;
    }

    // 3. 取文本中第一个 `{` 到最后一个 `}` 的子串再解。
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final decoded = _decode(text.substring(start, end + 1));
      if (decoded != null) return decoded;
    }
    return null;
  }

  static Map<String, dynamic>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String? _stripCodeFence(String text) {
    final fenced = RegExp(
      r'```(?:json)?\s*\n([\s\S]*?)\n\s*```',
      caseSensitive: false,
    ).firstMatch(text);
    if (fenced != null && fenced.groupCount >= 1) {
      return fenced.group(1);
    }
    return null;
  }

  /// 把 JSON 转成规范化题目列表（`Question.fromAiJson` 承担字段级规范化）。
  static ParsedQuestions toQuestions(
    Map<String, dynamic> json, {
    required String sessionId,
    required String deviceId,
    int? now,
  }) {
    final ts = now ?? nowMs();
    final rawQuestions = json['questions'];
    final questions = <Question>[];
    var dropped = 0;
    if (rawQuestions is List) {
      var ordinal = 0;
      for (final item in rawQuestions) {
        if (item is! Map) {
          dropped++;
          continue;
        }
        final q = Question.fromAiJson(
          Map<String, dynamic>.from(item),
          questionId: newUuidV4(),
          sessionId: sessionId,
          ordinal: ordinal,
          deviceId: deviceId,
          now: ts,
        );
        if (q.stem.trim().isEmpty) {
          dropped++; // schema：stem minLength 1
          continue;
        }
        questions.add(q);
        ordinal++;
      }
    }
    return ParsedQuestions(questions: questions, droppedEmpty: dropped);
  }
}
