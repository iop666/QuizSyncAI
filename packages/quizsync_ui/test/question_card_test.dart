import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

/// 用户反馈 13/15 的共享界面回归：
/// 13 AI 不确定时命中项用**黄色**（不再用代表可信的绿色）；
/// 15 阅读材料默认折叠、可展开；主观题分点答案按行结构化渲染。
void main() {
  Widget wrap(Question q) => MaterialApp(
        theme: QuizSyncTheme.build(
            brightness: Brightness.light, accent: 0xFF16A34A),
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionCard(question: q, fontSize: 16),
          ),
        ),
      );

  Question q({
    required String stem,
    String material = '',
    QuestionType type = QuestionType.single,
    List<Option> options = const [
      Option(label: 'A', text: '选项甲'),
      Option(label: 'B', text: '选项乙'),
    ],
    List<String> choice = const ['A'],
    String? answerText,
    double confidence = 0.95,
    bool needReview = false,
    int ordinal = 0,
    String? questionNo,
  }) =>
      Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: ordinal,
        questionNo: questionNo,
        stem: stem,
        material: material,
        type: type,
        options: options,
        choice: choice,
        answerText: answerText,
        confidence: confidence,
        needReview: needReview,
        createdAt: 0,
        updatedAt: 0,
        updatedBy: 'windows-local',
      );

  /// 取某个选项行的左侧强调色（命中时会改成绿色/黄色）。
  Color? optionAccent(WidgetTester tester, String label) {
    final box = tester.widget<Container>(
        find.byKey(ValueKey('option-$label')));
    final decoration = box.decoration as BoxDecoration?;
    final border = decoration?.border as Border?;
    return border?.left.color;
  }

  group('标色（用户反馈 13）', () {    testWidgets('把握大 → 命中选项用绿色', (tester) async {
      await tester.pumpWidget(wrap(q(stem: '题干够长的一句话', confidence: 0.95)));
      expect(optionAccent(tester, 'A'), HighlightColors.lightText);
      expect(optionAccent(tester, 'B'), isNot(HighlightColors.lightText));
    });

    testWidgets('AI 不确定（confidence < 0.6）→ 命中选项用黄色', (tester) async {
      await tester.pumpWidget(wrap(q(stem: '题干够长的一句话', confidence: 0.4)));
      expect(optionAccent(tester, 'A'), HighlightColors.lightUncertainText,
          reason: '不确定时不能再用绿色（绿色 = 可信）');
      expect(find.byKey(const ValueKey('review-badge')), findsOneWidget);
    });

    testWidgets('need_review 显式为真 → 同样用黄色', (tester) async {
      await tester.pumpWidget(
          wrap(q(stem: '题干够长的一句话', confidence: 0.9, needReview: true)));
      expect(optionAccent(tester, 'A'), HighlightColors.lightUncertainText);
    });

    testWidgets('不确定的填空/主观答案区也用黄色', (tester) async {
      await tester.pumpWidget(wrap(q(
        stem: '简述原因',
        type: QuestionType.subjective,
        options: const [],
        choice: const [],
        answerText: '因为……',
        confidence: 0.4,
      )));
      final block = tester.widget<Container>(
          find.byKey(const ValueKey('answer-block')));
      final border =
          ((block.decoration as BoxDecoration).border as Border).left.color;
      expect(border, HighlightColors.lightUncertainText);
    });
  });

  group('阅读材料（用户反馈 15）', () {
    testWidgets('有材料 → 默认折叠，点标题条才展开', (tester) async {
      await tester.pumpWidget(wrap(q(
        stem: '下列说法正确的是',
        material: '材料第一段。\n材料第二段。',
      )));
      expect(find.byKey(const ValueKey('question-material')), findsOneWidget);
      expect(find.byKey(const ValueKey('material-body')), findsNothing,
          reason: '默认必须折叠（材料很长，展开会把题干和答案挤下去）');
      expect(find.textContaining('点击展开'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('material-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('material-body')), findsOneWidget);
      expect(find.textContaining('材料第二段。'), findsOneWidget);
    });

    testWidgets('没有材料 → 完全不渲染材料面板', (tester) async {
      await tester.pumpWidget(wrap(q(stem: '下列说法正确的是')));
      expect(find.byKey(const ValueKey('question-material')), findsNothing);
    });
  });

  group('主观题结构化（用户反馈 15）', () {
    testWidgets('分点答案逐行渲染，保留序号', (tester) async {
      await tester.pumpWidget(wrap(q(
        stem: '简述影响',
        type: QuestionType.subjective,
        options: const [],
        choice: const [],
        answerText: '①气候：全年高温多雨。\n②地形：以平原为主。\n③水源：河流众多。',
      )));
      expect(find.byKey(const ValueKey('answer-structured')), findsOneWidget);
      expect(find.textContaining('①气候：全年高温多雨。'), findsOneWidget);
      expect(find.textContaining('③水源：河流众多。'), findsOneWidget);
    });

    testWidgets('单行答案保持原样（不强行加项目符号）', (tester) async {
      await tester.pumpWidget(wrap(q(
        stem: '简述影响',
        type: QuestionType.subjective,
        options: const [],
        choice: const [],
        answerText: '气候与地形共同决定。',
      )));
      expect(find.byKey(const ValueKey('answer-structured')), findsNothing);
      expect(find.textContaining('气候与地形共同决定。'), findsOneWidget);
    });
  });

  group('标题行（M33 第 8/13 条）', () {
    testWidgets('序号显示但**不带点号**（用户澄清：只是不要「.」，不是不显示）',
        (tester) async {
      await tester.pumpWidget(wrap(q(stem: '题干', ordinal: 2, questionNo: '12')));
      // 第 3 题 → 序号就写「3」，没有「3.」。
      expect(find.byKey(const ValueKey('question-seq')), findsOneWidget);
      final seq = tester
          .widget<Text>(find.byKey(const ValueKey('question-seq')))
          .data;
      expect(seq, '3');
      expect(seq, isNot(contains('.')));
      // 题号徽标照旧是「第 12 题」（AI 读到的题号），两者都在。
      expect(find.text('第 12 题'), findsOneWidget);
    });

    testWidgets('没识别到题号时用「第 N 题」兜底，题型徽标紧随其后', (tester) async {
      await tester.pumpWidget(wrap(q(
        stem: '题干',
        ordinal: 4,
        questionNo: null,
        type: QuestionType.multi,
      )));
      expect(find.text('第 5 题'), findsOneWidget);
      expect(find.text('多选题'), findsOneWidget);
    });

    testWidgets('alwaysShowConfidence：把握 100% 时也显示（悬浮窗用）', (tester) async {
      final q100 = Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: 0,
        questionNo: '1',
        stem: '题干',
        type: QuestionType.blank,
        answerText: '答案',
        confidence: 1.0,
        createdAt: 0,
        updatedAt: 0,
        updatedBy: 'windows-local',
      );
      // 默认：confidence == 1 不显示把握率（主界面/安卓端的既有行为）。
      await tester.pumpWidget(wrap(q100));
      expect(find.textContaining('把握'), findsNothing);
      // 悬浮窗：总是显示。
      await tester.pumpWidget(MaterialApp(
        theme: QuizSyncTheme.build(
            brightness: Brightness.light, accent: 0xFF16A34A),
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuestionCard(
                question: q100, fontSize: 16, alwaysShowConfidence: true),
          ),
        ),
      ));
      expect(find.text('把握 100%'), findsOneWidget);
    });
  });
}
