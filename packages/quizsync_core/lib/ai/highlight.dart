import '../model/question.dart';
import '../model/question_type.dart';

/// 标绿结论：端侧显示的**唯一**依据（`ai-contract.md` 第 5 节 + `SPEC.md` 4.3）。
/// 配色与图标由各端主题层实现，本类只给逻辑结论。
class HighlightResult {
  /// 需要标绿的选项行 label 集合（单选 1 个、多选多个、判断 1 个）。
  final Set<String> optionLabels;

  /// 填空 / 主观：answer.text 在「答案」区块用绿色文字 + 浅绿底显示。
  final bool highlightAnswerText;

  /// 无答案可标：显示「未识别出答案」并标记需复核。
  final bool noAnswer;

  /// 黄色徽标「AI 不确定，建议复核」（confidence < 0.6 或 need_review）。
  final bool needsReview;

  /// 题型为判断（UI 用「对 / 错」两个按钮呈现）。
  final bool isJudge;

  const HighlightResult({
    this.optionLabels = const {},
    this.highlightAnswerText = false,
    this.noAnswer = false,
    this.needsReview = false,
    this.isJudge = false,
  });

  bool get hasAnyHighlight => optionLabels.isNotEmpty || highlightAnswerText;
}

/// `ai-contract.md` 第 5 节伪码的逐字实现。
/// 用户手改答案后，用用户的值走同一套逻辑（调用方传入手改后的 Question 即可）。
HighlightResult computeHighlight(Question q) {
  final answer = q.answer;
  final needsReview = q.confidence < 0.6 || q.needReview;
  final isJudge = q.type == QuestionType.judge;

  if (!answer.isChoiceEmpty && q.options.isNotEmpty) {
    final hits = answer.matchedOptionLabels(q.options);
    if (hits.isNotEmpty) {
      // judge → 在「对 / 错」中把命中的那个标绿；其他 → 把所有命中选项行标绿。
      return HighlightResult(
        optionLabels: hits,
        needsReview: needsReview,
        isJudge: isJudge,
      );
    }
    return HighlightResult(noAnswer: true, needsReview: true, isJudge: isJudge);
  }
  if (!answer.isTextEmpty) {
    return HighlightResult(
      highlightAnswerText: true,
      needsReview: needsReview,
      isJudge: isJudge,
    );
  }
  return HighlightResult(noAnswer: true, needsReview: true, isJudge: isJudge);
}
