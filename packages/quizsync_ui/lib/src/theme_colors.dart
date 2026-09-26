import 'package:flutter/material.dart';

/// SPEC 4.3 标绿配色（逐字）。深色主题必须用独立绿色值，不能复用浅色值。
class HighlightColors {
  static const lightText = Color(0xFF16A34A);
  static const lightBackground = Color(0xFFDCFCE7);
  static const darkText = Color(0xFF4ADE80);
  static const darkBackground = Color(0xFF14351F);

  /// 用户反馈 13：AI **自己没把握**（`confidence < 0.6` 或 `need_review`）时，
  /// 命中的选项与答案区不能再用绿色（绿色 = 可信），改用黄色警示。
  static const lightUncertainText = Color(0xFFD97706);
  static const lightUncertainBackground = Color(0xFFFEF3C7);
  static const darkUncertainText = Color(0xFFFBBF24);
  static const darkUncertainBackground = Color(0xFF322712);

  static Color text(bool dark, {bool uncertain = false}) => uncertain
      ? (dark ? darkUncertainText : lightUncertainText)
      : (dark ? darkText : lightText);

  static Color background(bool dark, {bool uncertain = false}) => uncertain
      ? (dark ? darkUncertainBackground : lightUncertainBackground)
      : (dark ? darkBackground : lightBackground);

  /// 答案区块（填空 / 主观）：绿色文字 + 浅绿底。
  static const lightAnswerBackground = Color(0xFFDCFCE7);
  static const darkAnswerBackground = Color(0xFF14351F);

  /// 提示/告警**正文**色（用户反馈 9）：徽标底色是浅黄，直接用琥珀色写字
  /// 对比度太低，正文另给一档更深的颜色。
  static const lightWarnText = Color(0xFF92400E);
  static const darkWarnText = Color(0xFFFCD34D);

  static Color warnText(bool dark) => dark ? darkWarnText : lightWarnText;

  /// 置信度徽标（黄色）。
  static const reviewBadge = Color(0xFFF59E0B);
  static const reviewBadgeBackground = Color(0xFFFEF3C7);

  /// 题目不全（用户需求 2）：整张卡片黄框 + 黄底徽标。
  static const incompleteLight = Color(0xFFEAA100);
  static const incompleteDark = Color(0xFFFACC15);
  static const incompleteLightBackground = Color(0xFFFFF8E1);
  static const incompleteDarkBackground = Color(0xFF2A2410);

  static Color incomplete(bool dark) =>
      dark ? incompleteDark : incompleteLight;

  static Color incompleteBackground(bool dark) =>
      dark ? incompleteDarkBackground : incompleteLightBackground;
}

/// 题型中文名（UI 显示用）。
const questionTypeLabels = {
  'single': '单选题',
  'multi': '多选题',
  'judge': '判断题',
  'blank': '填空题',
  'subjective': '主观题',
};
