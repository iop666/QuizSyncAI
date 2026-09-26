import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

/// M21 第 1 条：正文里的**化学式小标 / 表格 / 超长公式**都要显示得清楚。
///
/// 用例里的文本全部抄自用户的真实数据
/// （`QuizSync_AI-issue\测试数据\collection-111-…json`，题库里就是这些写法）。
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  const base = TextStyle(fontSize: 16);

  /// 取某个文字部件被上/下标平移了多少（负=上浮、正=下沉）。
  /// 用平移量的正负断言，不依赖字体的 `subs`/`sups` 特性。
  double dyOf(WidgetTester tester, Finder f) => tester
      .widget<Transform>(
          find.ancestor(of: f, matching: find.byType(Transform)).first)
      .transform
      .getTranslation()
      .y;

  // ---- 解析（纯函数） ----

  group('内容分块 parseContentBlocks', () {
    test('纯文本 → 只有一个纯文字段落（走 Text 快路径）', () {
      final blocks = parseContentBlocks('普通解析文本');
      expect(blocks, hasLength(1));
      final p = blocks.first as ParagraphBlock;
      expect(p.runs.single, isA<TextRun>());
      expect((p.runs.single as TextRun).text, '普通解析文本');
    });

    test(r'$$…$$ 与 \[…\] 一律独立成块', () {
      final blocks = parseContentBlocks(r'先 $$a=b$$ 再 \[c=d\] 完');
      expect(blocks.whereType<FormulaBlock>().map((b) => b.latex),
          ['a=b', 'c=d']);
    });

    test('短公式留在句子里，超长公式搬成块（阈值由调用方按宽度给）', () {
      final short = parseContentBlocks(r'得 $v=3$ 。', maxInlineChars: 40);
      expect(short.whereType<FormulaBlock>(), isEmpty);
      expect((short.first as ParagraphBlock).runs.whereType<MathRun>(),
          hasLength(1));

      // 用户数据里最长的一条（84 字符）
      const longLatex =
          r'v_m=\dfrac{FR}{B^2L^2}=\dfrac{0.50\times0.50}{0.40^2\times0.50^2}=6.25\ \mathrm{m/s}';
      final long = parseContentBlocks('最大速度 \$' '$longLatex' r'$，得解。',
          maxInlineChars: 40);
      expect(long.whereType<FormulaBlock>().single.latex, longLatex);
      // 公式前后的文字仍然各自成段，没有被吞掉
      expect(long.first, isA<ParagraphBlock>());
      expect(long.last, isA<ParagraphBlock>());
    });

    test('空格对齐的「表」识别成表格，且前后文字保留', () {
      const material = '某研究小组测定了如下数据：\n\n'
          '光照强度/klx    0    2    4    6    8\n'
          'CO₂变化量/mg    +44    +8    -22    -44    -44\n'
          '\n注：“+”表示增加，“-”表示减少。';
      final blocks = parseContentBlocks(material);
      final table = blocks.whereType<TableBlock>().single;
      expect(table.rows, hasLength(2));
      expect(table.rows.first,
          ['光照强度/klx', '0', '2', '4', '6', '8']);
      expect(table.rows.last,
          ['CO₂变化量/mg', '+44', '+8', '-22', '-44', '-44']);
      expect(table.header, isFalse, reason: '空格对齐表的第一行往往就是数据，不加表头样式');
      // 表格前后的说明文字都还在
      expect(blocks.whereType<ParagraphBlock>(), hasLength(2));
      expect(blocks.last, isA<ParagraphBlock>());
    });

    test('一行两个词、两行段数不同 → 不当表格（避免误判普通文字）', () {
      final blocks = parseContentBlocks('第一行  两段\n第二行  两段  三段  四段');
      expect(blocks.whereType<TableBlock>(), isEmpty);
    });

    test('Markdown 竖线表也认，并标记表头', () {
      final blocks = parseContentBlocks('| 物质 | 质量 |\n|---|---|\n| Zn | 65 |\n');
      final table = blocks.whereType<TableBlock>().single;
      expect(table.header, isTrue);
      expect(table.rows, [
        ['物质', '质量'],
        ['Zn', '65'],
      ]);
    });
  });

  // ---- 化学式 ----

  group('化学式判定 isChemicalFormula', () {
    test('用户数据里的真实写法都认', () {
      for (final s in [
        'ZnCO3', 'Fe2O3', 'SiO2', 'ZnSO4', 'H2O2', 'CO2', 'H2', 'H2O',
        'CH3OH', 'Fe2+', 'Fe3+', 'Cu2+', 'Cl-', 'Al3+',
        // 离子方程式里的电子（用户点名的 Cu²⁺ + 2e⁻）
        'e-', 'e+',
      ]) {
        expect(isChemicalFormula(s), isTrue, reason: '$s 应该被认成化学式');
      }
    });

    test('普通缩写/数字不能误判', () {
      for (final s in [
        'pH', 'MPa', 'Kp', 'A4', 'USB', '2026', 'K', 'H', 'AH', 'V', 'x2',
        // 单独的 e 没有电荷，不是电子；大写 E 不是元素
        'e', 'E-', 'ee',
      ]) {
        expect(isChemicalFormula(s), isFalse, reason: '$s 不是化学式');
      }
    });
  });

  testWidgets('化学式下标：ZnCO3 的 3 下沉、Fe2O3 的两个数字都下沉',
      (tester) async {
    await tester.pumpWidget(
        wrap(const MathText(text: 'ZnCO3 与 Fe2O3', style: base)));
    await tester.pumpAndSettle();

    // 连续的字母段合成一个文字部件，数字单独切出来
    expect(find.text('ZnCO'), findsOneWidget);
    expect(find.text('Fe'), findsOneWidget);
    expect(find.text('3'), findsNWidgets(2), reason: 'ZnCO3 与 Fe2O3 各一个 3');
    expect(find.text('2'), findsOneWidget);
    final sub3 = tester.widget<Text>(find.text('3').first);
    expect(sub3.style!.fontSize!, lessThan(16), reason: '下标要比正文小');

    expect(dyOf(tester, find.text('3')), greaterThan(0), reason: '原子个数=下标（向下）');
    expect(dyOf(tester, find.text('2')), greaterThan(0));
  });

  testWidgets('化学式电荷：Fe2+ 的 2 与 + 都上浮', (tester) async {
    await tester.pumpWidget(
        wrap(const MathText(text: '把 Fe2+ 氧化成 Fe3+', style: base)));
    await tester.pumpAndSettle();

    expect(find.text('Fe'), findsNWidgets(2));
    final plus = find.text('+');
    expect(plus, findsNWidgets(2));
    final two = find.text('2');
    expect(two, findsOneWidget);

    expect(dyOf(tester, two), lessThan(0), reason: 'Fe2+ 的 2 是电荷（向上）');
    expect(dyOf(tester, plus.first), lessThan(0), reason: '电荷符号也向上');
    expect(tester.widget<Text>(plus.first).style!.fontSize!, lessThan(16));
  });

  // ---- 用户反馈：电子 `e-` 的负号要上标，但同一行里的**减号**不能跟着上标 ----

  testWidgets('电子写成 e- 时要上标（Cu²⁺ + 2e⁻ 的 ⁻ 不能显示成 -）',
      (tester) async {
    await tester.pumpWidget(wrap(const MathText(
        text: '正极反应：Cu2+ + 2e- = Cu', style: base)));
    await tester.pumpAndSettle();

    // Cu2+ 被切成一个部件，右侧那个游离的 Cu 仍留在正文里（不算部件）
    expect(find.text('Cu'), findsOneWidget);
    expect(find.text('e'), findsOneWidget, reason: '电子 e 本体仍是正文大小');
    // 只有一个独立的 '-' 部件，就是电子那个上标负号
    expect(find.text('-'), findsOneWidget);
    expect(dyOf(tester, find.text('-')), lessThan(0), reason: 'e⁻ 的负号必须浮起来');
    expect(tester.widget<Text>(find.text('-')).style!.fontSize!, lessThan(16));
    // Cu2+ 依旧是上标 2 + 上标 +
    expect(dyOf(tester, find.text('2')), lessThan(0));
    expect(dyOf(tester, find.text('+')), lessThan(0));
  });

  testWidgets('用户点名的那一行：2H₂O - 4e⁻ 里减号是减号、负号才是电荷',
      (tester) async {
    await tester.pumpWidget(wrap(const MathText(
        text: '阳极：2H2O - 4e- = O2 + 4H+', style: base)));
    await tester.pumpAndSettle();

    // 正文里那个减号不是独立文字部件（留在段落里），所以只有一个 '-' 部件
    expect(find.text('-'), findsOneWidget);
    expect(dyOf(tester, find.text('-')), lessThan(0), reason: '只有 e⁻ 的负号上标');
    // H⁺ 的加号上标；中间的 '+' 号（= 号后面那个）留在正文里
    expect(find.text('+'), findsOneWidget);
    expect(dyOf(tester, find.text('+')), lessThan(0));
    // 水的 2 与 O2 的 2 都是下标（向下）
    expect(find.text('2'), findsNWidgets(2));
    expect(dyOf(tester, find.text('2').first), greaterThan(0));
  });

  testWidgets('不留空格也一样：2H2O-4e-=O2+4H+ 只把电荷上标', (tester) async {
    await tester.pumpWidget(wrap(const MathText(
        text: '2H2O-4e-=O2+4H+', style: base)));
    await tester.pumpAndSettle();

    // 紧贴的减号/加号若被误判成电荷，这里就会出现 2 个部件
    expect(find.text('-'), findsOneWidget, reason: 'H2O-4 的减号是运算符，不是电荷');
    expect(find.text('+'), findsOneWidget, reason: 'O2+4 的加号是运算符，不是电荷');
    expect(find.text('e'), findsOneWidget);
    expect(dyOf(tester, find.text('-')), lessThan(0));
    expect(dyOf(tester, find.text('+')), lessThan(0));
    expect(find.text('2'), findsNWidgets(2));
    expect(dyOf(tester, find.text('2').first), greaterThan(0), reason: 'H2O 的 2 是下标');
  });

  testWidgets('不能误伤：e-mail 与 1e-5 都不是电子', (tester) async {
    await tester.pumpWidget(wrap(const MathText(
        text: '发 e-mail 给他，误差在 1e-5 以内', style: base)));
    await tester.pumpAndSettle();
    expect(find.text('-'), findsNothing, reason: '这里没有任何上标负号');
    expect(find.text('e'), findsNothing);
    expect(find.textContaining('e-mail'), findsOneWidget);
    expect(find.textContaining('1e-5'), findsOneWidget);
  });

  testWidgets('化学平衡箭头 ⇌ 用 KaTeX 字形画（MiSans 本身缺这个字）',
      (tester) async {
    await tester.pumpWidget(wrap(const MathText(
        text: 'CO2(g) + 3H2(g) ⇌ CH3OH(g) + H2O(g)', style: base)));
    await tester.pumpAndSettle();
    // 箭头不再以裸文字出现，而是被换成公式部件
    expect(find.text('⇌'), findsNothing);
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing,
        reason: r'KaTeX 自带 \rightleftharpoons，不该回退');
    expect(find.textContaining('CH'), findsWidgets);
  });

  // ---- 表格渲染 ----

  testWidgets('材料里的表格画成真表格（不再挤成一行）', (tester) async {
    const material = '光照强度/klx    0    2    4    6    8\n'
        'CO₂变化量/mg    +44    +8    -22    -44    -44';
    await tester.pumpWidget(wrap(const MathText(text: material, style: base)));
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
    expect(find.text('光照强度/klx'), findsOneWidget);
    expect(find.text('CO₂变化量/mg'), findsOneWidget);
    for (final cell in ['0', '2', '4', '6', '8', '+44', '+8', '-22', '-44']) {
      expect(find.text(cell), findsWidgets, reason: '单元格 $cell 应该各占一格');
    }
  });

  testWidgets('阅读材料展开后就地渲染表格与公式（用户看到的那一步）',
      (tester) async {
    final card = QuestionCard(
      fontSize: 16,
      question: Question(
        questionId: 'q',
        sessionId: 's',
        ordinal: 0,
        stem: '该植物在 2 klx 下的呼吸速率约为多少 mg CO2·h-1？',
        type: QuestionType.blank,
        answerText: '44',
        material: '测定结果如下：\n\n'
            '光照强度/klx    0    2    4    6    8\n'
            'CO₂变化量/mg    +44    +8    -22    -44    -44',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'd',
      ),
    );
    await tester.pumpWidget(wrap(card));
    await tester.pumpAndSettle();

    // 默认折叠：表格还没画出来
    expect(find.byType(Table), findsNothing);
    await tester.tap(find.byKey(const ValueKey('material-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsOneWidget, reason: '展开材料就该看到表格');
  });

  // ---- 超长公式与整体不溢出 ----

  testWidgets('超长公式独占一行并可横向滚动，不再把整段挤出屏幕', (tester) async {
    const latex =
        r'v_m=\dfrac{FR}{B^2L^2}=\dfrac{0.50\times0.50}{0.40^2\times0.50^2}=6.25\ \mathrm{m/s}';
    await tester.pumpWidget(wrap(const MathText(
        text: '由平衡条件解得 \$' '$latex' r'$，所以最大速度为 6.25 m/s。',
        style: base)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing);
    expect(find.byType(SingleChildScrollView), findsWidgets,
        reason: '块级公式要能横向滚动，保证再长也看得全');
  });

  testWidgets('手机宽度下渲染真实材料 + 化学式 + 长公式：不溢出',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final card = QuestionCard(
      fontSize: 16,
      question: Question(
        questionId: 'q',
        sessionId: 's',
        ordinal: 0,
        stem: '某菱锌矿主要成分为 ZnCO3，含少量 Fe2O3、CuO、SiO2。'
            '加入 H2O2 将 Fe2+ 氧化为 Fe3+，写出离子方程式。',
        type: QuestionType.subjective,
        answerText: r'① $2Fe^{2+}+H_2O_2+2H^+=2Fe^{3+}+2H_2O$。'
            '\n'
            r'② $v_m=\dfrac{FR}{B^2L^2}=\dfrac{0.50\times0.50}{0.40^2\times0.50^2}=6.25\ \mathrm{m/s}$。',
        analysis: '锌粉置换铜，Zn被氧化为Zn2+，Cu2+被还原为Cu；'
            'CO2(g) + 3H2(g) ⇌ CH3OH(g) + H2O(g)。',
        material: '光照强度/klx    0    2    4    6    8\n'
            'CO₂变化量/mg    +44    +8    -22    -44    -44',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'd',
      ),
    );
    await tester.pumpWidget(wrap(card));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('material-toggle')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '窄屏不该有 overflow 异常');
    expect(find.byType(Table), findsOneWidget);
  });
}
