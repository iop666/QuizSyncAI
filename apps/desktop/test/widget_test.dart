import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_ui/quizsync_ui.dart';

Question mk({
  QuestionType type = QuestionType.single,
  List<Option> options = const [],
  List<String> choice = const [],
  String? answerText,
  double confidence = 0.9,
  bool needReview = false,
  String stem = '题干内容',
}) =>
    Question(
      questionId: 'q1',
      sessionId: 's1',
      ordinal: 0,
      stem: stem,
      type: type,
      options: options,
      choice: choice,
      answerText: answerText,
      confidence: confidence,
      needReview: needReview,
      createdAt: 1,
      updatedAt: 1,
      updatedBy: 'd',
    );

const abcd = [
  Option(label: 'A', text: '选项甲'),
  Option(label: 'B', text: '选项乙'),
  Option(label: 'C', text: '选项丙'),
  Option(label: 'D', text: '选项丁'),
];

Widget wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// 按内容找到对应 Text 的 TextStyle（不依赖容器包装层级）。
TextStyle textOf(WidgetTester tester, String content) =>
    tester.widget<Text>(find.text(content)).style!;

void main() {
  testWidgets('1. 单选 B 标绿 #FF16A34A，A/C/D 不标，B 有 ✓', (tester) async {
    await tester.pumpWidget(wrap(QuestionCard(
        question: mk(type: QuestionType.single, options: abcd, choice: ['B']),
        fontSize: 16)));
    await tester.pumpAndSettle();

    expect(textOf(tester, '选项乙').color, const Color(0xFF16A34A));
    expect(textOf(tester, '选项甲').color, isNot(const Color(0xFF16A34A)));
    expect(textOf(tester, '选项丙').color, isNot(const Color(0xFF16A34A)));
    expect(textOf(tester, '选项丁').color, isNot(const Color(0xFF16A34A)));

    expect(find.byKey(const ValueKey('check-B')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-A')), findsNothing);
    expect(find.byKey(const ValueKey('check-C')), findsNothing);
  });

  testWidgets('2. 深色主题：B 标绿 #FF4ADE80，行背景 #FF14351F', (tester) async {
    await tester.pumpWidget(wrap(
        QuestionCard(
            question:
                mk(type: QuestionType.single, options: abcd, choice: ['B']),
            fontSize: 16),
        brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(textOf(tester, '选项乙').color, const Color(0xFF4ADE80));
    expect(textOf(tester, '选项甲').color, isNot(const Color(0xFF4ADE80)));

    final row = tester.widget<Container>(find.byKey(const ValueKey('option-B')));
    final deco = row.decoration as BoxDecoration;
    expect(deco.color, const Color(0xFF14351F));
    expect((deco.border as Border).left.width, 4);
    expect((deco.border as Border).left.color, const Color(0xFF4ADE80));
  });

  testWidgets('3. 多选 B、D 都标绿', (tester) async {
    await tester.pumpWidget(wrap(QuestionCard(
        question:
            mk(type: QuestionType.multi, options: abcd, choice: ['B', 'D']),
        fontSize: 16)));
    await tester.pumpAndSettle();

    expect(textOf(tester, '选项乙').color, const Color(0xFF16A34A));
    expect(textOf(tester, '选项丁').color, const Color(0xFF16A34A));
    expect(textOf(tester, '选项甲').color, isNot(const Color(0xFF16A34A)));
    expect(textOf(tester, '选项丙').color, isNot(const Color(0xFF16A34A)));
    expect(find.byKey(const ValueKey('check-B')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-D')), findsOneWidget);
  });

  testWidgets('4. 判断题（对）：只有「对」标绿', (tester) async {
    const judge = [Option(label: '对', text: '对'), Option(label: '错', text: '错')];
    await tester.pumpWidget(wrap(QuestionCard(
        question: mk(type: QuestionType.judge, options: judge, choice: ['对']),
        fontSize: 16)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('option-对')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-对')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-错')), findsNothing);

    final wrong =
        tester.widget<Container>(find.byKey(const ValueKey('option-错')));
    final deco = wrong.decoration as BoxDecoration;
    expect(deco.color, isNull);
    expect(textOf(tester, '对').color, const Color(0xFF16A34A));
    expect(textOf(tester, '错').color, isNot(const Color(0xFF16A34A)));
  });

  testWidgets('5. 填空题：答案文本绿色显示', (tester) async {
    await tester.pumpWidget(wrap(QuestionCard(
        question: mk(type: QuestionType.blank, answerText: 'x = 1'),
        fontSize: 16)));
    await tester.pumpAndSettle();

    final block =
        tester.widget<Container>(find.byKey(const ValueKey('answer-block')));
    final text = tester.widget<Text>(find.text('x = 1'));
    expect(text.style!.color, const Color(0xFF16A34A));
    expect((block.decoration as BoxDecoration).color, const Color(0xFFDCFCE7));
  });

  testWidgets('6. confidence 0.4 → 「AI 不确定，建议复核」徽标', (tester) async {
    await tester.pumpWidget(wrap(QuestionCard(
        question: mk(options: abcd, choice: ['A'], confidence: 0.4),
        fontSize: 16)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-badge')), findsOneWidget);
    expect(find.text('AI 不确定，建议复核'), findsOneWidget);

    await tester.pumpWidget(wrap(QuestionCard(
        question: mk(options: abcd, choice: ['A'], confidence: 0.9),
        fontSize: 16)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-badge')), findsNothing);
  });

  test('7. 三个会话的「上一次 / 下一次 / 回到本次」跳转（SPEC 第 5 节）', () {
    Session s(int createdAt, String id) => Session(
        sessionId: id,
        imageHash: 'h$id',
        sourceDevice: 'w',
        status: TaskState.done,
        createdAt: createdAt,
        updatedAt: createdAt,
        updatedBy: 'w');
    final nav = SessionNav([s(3000, 's3'), s(2000, 's2'), s(1000, 's1')]);

    expect(nav.current!.sessionId, 's3', reason: '默认停在「本次」（最新）');
    expect(nav.positionLabel, '第 1 / 3 条记录');

    nav.goPrev();
    expect(nav.current!.sessionId, 's2');
    nav.goPrev();
    expect(nav.current!.sessionId, 's1');
    expect(nav.canGoPrev, isFalse, reason: '最旧一条不能再往前');
    expect(nav.isAtLatest, isFalse, reason: '翻旧会话不改变「本次」');

    nav.goNext();
    expect(nav.current!.sessionId, 's2');
    nav.backToLatest();
    expect(nav.current!.sessionId, 's3');
    expect(nav.isAtLatest, isTrue);
    expect(nav.canGoNext, isFalse);
  });

  test('8. 字号持久化：调到 24 → 重启（新控制器 + 同一存储）仍为 24', () async {
    final store = MemoryKeyValueStore();
    final c1 = SettingsController(store);
    await c1.load();
    expect(c1.app.fontSize, 16, reason: '默认 16');

    await c1.updateApp(c1.app.copyWith(fontSize: 24));
    expect(c1.app.fontSize, 24);

    final c2 = SettingsController(store);
    await c2.load();
    expect(c2.app.fontSize, 24);
  });

  testWidgets('8b. 字号 24 → 题干 MathText.style.fontSize == 24', (tester) async {
    await tester.pumpWidget(wrap(QuestionCard(
        question: mk(options: abcd, choice: ['A']), fontSize: 24)));
    await tester.pumpAndSettle();
    final stem =
        tester.widget<MathText>(find.byKey(const ValueKey('question-stem')));
    expect(stem.style.fontSize, 24);
  });

  testWidgets('9. 一个会话 5 道题 → 5 张卡片在同一滚动视图', (tester) async {
    final questions = List.generate(
      5,
      (i) => Question(
        questionId: 'q$i',
        sessionId: 's1',
        ordinal: i,
        stem: '第 $i 题的题干内容',
        type: QuestionType.blank,
        answerText: '答案 $i',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'd',
      ),
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          controller: controller,
          itemCount: questions.length,
          itemBuilder: (_, i) => QuestionCard(
              question: questions[i], fontSize: 16),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 同一个滚动视图装载全部 5 题（懒构建：断言 itemCount，再滚动验证首尾都可达）。
    final delegate =
        tester.widget<ListView>(find.byType(ListView)).childrenDelegate;
    expect((delegate as SliverChildBuilderDelegate).childCount, 5);
    expect(find.byType(QuestionCard), findsWidgets);

    await tester.dragUntilVisible(
      find.text('答案 4'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('答案 4'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('答案 0'),
      find.byType(ListView),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('答案 0'), findsOneWidget);
  });
}
