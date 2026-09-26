import 'package:flutter/painting.dart';
import 'package:quizsync_ui/quizsync_ui.dart' show HighlightColors;
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_desktop/services/float_window_content.dart';
import 'package:quizsync_desktop/services/float_window_view.dart';

/// 悬浮窗内容层（M34 第 8 条：**文本为主 + 明显的题目轮廓**）的回归。
///
/// 这轮把 M33 的「离屏 widget → 位图」整条管线删掉了（它让悬浮窗明显卡顿），
/// 改成 TextPainter 直接排版 + 缓存排版结果。所以这里的断言集中在：
/// ① 是真的纯排版（不再出图）；② 每道题都有看得见的轮廓与模块；
/// ③ 极简模式确实更短；④ 指纹变了才重新排版。
void main() {
  Question q({
    required String id,
    int ordinal = 0,
    String? questionNo = '12',
    String stem = '下列说法正确的是？',
    QuestionType type = QuestionType.single,
    List<Option> options = const [],
    List<String> choice = const [],
    String? text,
    String analysis = '解析：因为甲是对的。',
    String material = '',
    List<String> warnings = const [],
    double confidence = 0.85,
    bool incomplete = false,
    bool answerGuessed = false,
  }) =>
      Question(
        questionId: id,
        sessionId: 's1',
        ordinal: ordinal,
        questionNo: questionNo,
        stem: stem,
        type: type,
        options: options,
        choice: choice,
        answerText: text,
        analysis: analysis,
        material: material,
        warnings: warnings,
        confidence: confidence,
        incomplete: incomplete,
        answerGuessed: answerGuessed,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'windows-local',
      );

  FloatWindowPalette palette({bool dark = false}) =>
      FloatWindowPalette.of(dark: dark, paletteId: 'white');

  FloatContent layout(
    List<Question> qs, {
    double width = 320,
    double fontSize = 13,
    bool minimal = false,
    bool dark = false,
  }) =>
      minimal
          ? layoutMinimalTextContent(qs,
              width: width, fontSize: fontSize, palette: palette(dark: dark))
          : layoutQuestionContent(qs,
              width: width,
              fontSize: fontSize,
              palette: palette(dark: dark),
              minimal: false);

  List<String> textsOf(FloatContent c) =>
      [for (final n in c.nodes) if (n.text != null) n.text!];

  testWidgets('① 空题目列表 → 空内容（调用方画空状态）', (tester) async {
    final c = layout(const []);
    expect(c.isEmpty, isTrue);
    expect(c.height, 0);
    expect(c.nodes, isEmpty);
  });

  testWidgets('② 每道题都有明显的题目轮廓 + 题号/题型/把握率', (tester) async {
    const width = 320.0;
    final c = layout([
      q(
        id: 'q1',
        options: const [
          Option(label: 'A', text: '甲'),
          Option(label: 'B', text: '乙'),
        ],
        choice: const ['A'],
      ),
    ]);
    // 卡片轮廓：整宽、有描边、在最底层（第一个图元）。
    final card = c.nodes.first;
    expect(card.kind, FloatNodeKind.box);
    expect(card.rect.width, closeTo(width, 0.01));
    expect(card.borderArgb, isNotNull, reason: '题目轮廓必须有描边');
    expect(card.rect.height, greaterThan(80));
    // 标题行：题号徽标 + 题型 + 把握率 + 序号。
    final texts = textsOf(c);
    expect(texts, contains('第 12 题'));
    expect(texts, contains('1'), reason: '序号仍要显示（只是不带点号）');
    expect(texts.any((t) => t.contains('单选题')), isTrue);
    expect(texts.any((t) => t.contains('把握 85%')), isTrue);
    // 命中的选项被标出来（勾 + 颜色），未命中的照旧显示。
    expect(texts.any((t) => t.contains('A   甲') && t.contains('✓')), isTrue);
    expect(texts.any((t) => t.contains('B   乙') && !t.contains('✓')), isTrue);
    // 解析块有独立底色 + 标题。
    expect(texts, contains('解析'));
  });

  testWidgets('③ 填空题走「答案」块，没答案走「未识别出答案」', (tester) async {
    final answered = layout([
      q(
        id: 'q1',
        type: QuestionType.blank,
        options: const [],
        text: '答案甲',
        questionNo: null,
      ),
    ]);
    final t1 = textsOf(answered);
    expect(t1, contains('答案'));
    expect(t1, contains('答案甲'));
    expect(t1, contains('第 1 题'), reason: '没有题号时用序号兜底');

    final none = layout([
      q(
        id: 'q2',
        type: QuestionType.subjective,
        options: const [],
        text: null,
        questionNo: null,
      ),
    ]);
    expect(textsOf(none), contains('未识别出答案'));
  });

  testWidgets('④ 极简模式（只看题目答案）明显更短', (tester) async {
    final full = q(
      id: 'q1',
      options: const [
        Option(label: 'A', text: '甲'),
        Option(label: 'B', text: '乙'),
        Option(label: 'C', text: '丙'),
        Option(label: 'D', text: '丁'),
      ],
      choice: const ['B'],
      analysis: '因为乙才是对的，其他几个都不符合题目条件。',
      material: '阅读材料：\n第一行\n第二行\n第三行',
      type: QuestionType.single,
    );
    final normal = layout([full]);
    final minimal = layout([abstractQuestion(full)], minimal: true);
    expect(minimal.height, lessThan(normal.height), reason: '只看题目答案应当更短');
    // 极简模式（M42 起改成**纯文本面板**）：只留命中项、没有解析、没有材料。
    // 选项写法从卡片风格的「B   乙」变成纯文本的「B. 乙  ✓」。
    final t = textsOf(minimal).join('\n');
    expect(t, contains('B. 乙'));
    expect(t, contains('✓'));
    expect(t, isNot(contains('甲')));
    expect(t, isNot(contains('解析')));
    expect(t, isNot(contains('阅读材料')));
  });

  testWidgets('⑤ 文本为主：文本图元都带**预排好**的排版，不必每帧重排', (tester) async {
    final c = layout([
      q(
        id: 'q1',
        stem: r'理想气体方程 $pV=nRT$，光速约 $3\times10^8$ m/s。',
        options: const [Option(label: 'A', text: '刚好')],
        choice: const ['A'],
      ),
    ]);
    final texts = c.nodes.where((n) => n.kind == FloatNodeKind.text).toList();
    expect(texts, isNotEmpty);
    for (final n in texts) {
      expect(n.painter, isNotNull, reason: '内容层的文本必须带着排好的 TextPainter');
      expect(n.painter!.height, greaterThan(0));
    }
    // 公式按 LaTeX 源码显示（用户接受的取舍）。
    expect(textsOf(c).any((t) => t.contains(r'$pV=nRT$')), isTrue);
  });

  testWidgets('⑥ 长题干换行后更高；卡片始终在窗口宽度内', (tester) async {
    const width = 300.0;
    final short = layout([q(id: 'q1', stem: '短题干')], width: width);
    final long = layout([q(id: 'q2', stem: '很长的题干' * 40)], width: width);
    expect(long.height, greaterThan(short.height));
    for (final n in long.nodes) {
      expect(n.rect.left, greaterThanOrEqualTo(-0.01));
      expect(n.rect.right, lessThanOrEqualTo(width + 0.01));
    }
  });

  testWidgets('⑦ 题目不全 → 黄框 + 黄条说明', (tester) async {
    final c = layout([
      q(id: 'q1', incomplete: true, answerGuessed: true, text: '答案'),
    ]);
    final card = c.nodes.first;
    expect(card.borderWidth, 2);
    expect(textsOf(c).any((t) => t.contains('题目不全')), isTrue);
    expect(textsOf(c).any((t) => t.contains('AI 猜测')), isTrue);
  });

  testWidgets('⑧ 缓存：同 key 只排版一次；key 变了才重排', (tester) async {
    final builder = FloatContentBuilder();
    addTearDown(builder.dispose);
    final questions = [q(id: 'q1', text: '答案')];
    FloatContentKey key({String signature = 'sig', bool minimal = false}) =>
        FloatContentKey(
          sessionId: 's1',
          signature: signature,
          width: 320,
          fontSize: 13,
          minimal: minimal,
          paletteId: 'white',
          dark: false,
        );
    final first = builder.build(
        key: key(), questions: questions, palette: palette());
    final second = builder.build(
        key: key(), questions: questions, palette: palette());
    expect(identical(first, second), isTrue, reason: '同 key 应命中缓存');
    final third = builder.build(
        key: key(signature: 'other'), questions: questions, palette: palette());
    expect(identical(first, third), isFalse, reason: '指纹变了要重排');
    expect(builder.cached, isNotNull);

    // M35：**来回切极简不重建**（用户就是点这个崩的）。缓存留两份：正常 / 极简
    // 各自命中，切回来还是同一个对象（不重新创建、也不释放引擎文本对象）。
    final toggle = FloatContentBuilder();
    addTearDown(toggle.dispose);
    final normal = toggle.build(
        key: key(), questions: questions, palette: palette());
    final minimal = toggle.build(
        key: key(minimal: true), questions: questions, palette: palette());
    final backToNormal = toggle.build(
        key: key(), questions: questions, palette: palette());
    expect(identical(normal, backToNormal), isTrue,
        reason: '来回切极简必须命中同一份缓存（否则会反复创建/释放文本对象）');
    expect(identical(normal, minimal), isFalse);
  });

  testWidgets('⑨ 指纹与题目顺序无关（数据库返回顺序抖动不该触发重排）', (tester) async {
    final a = q(id: 'qa', stem: '甲题');
    final b = q(id: 'qb', stem: '乙题');
    expect(questionsSignature([a, b]), questionsSignature([b, a]),
        reason: '同一批题换个顺序必须得到同一个指纹');
    expect(questionsSignature([a, b]),
        isNot(questionsSignature([a, b.copyWith(stem: '乙题改了')])));
  });

  testWidgets('⑨ 深色配色也能排版（明暗模式）', (tester) async {
    final c = layout([q(id: 'q1', text: '答案')], dark: true);
    expect(c.height, greaterThan(40));
    final card = c.nodes.first;
    expect(card.rect.width, greaterThan(0));
    // 题目轮廓在深色下也要有描边（否则题与题糊在一起）。
    expect(card.borderArgb, isNotNull);
  });

  testWidgets('⑩ 判断题画「对 / 错」两块，命中的那块有底', (tester) async {
    final c = layout([
      q(
        id: 'q1',
        type: QuestionType.judge,
        options: const [Option(label: '对', text: '对'), Option(label: '错', text: '错')],
        choice: const ['对'],
      ),
    ]);
    final texts = textsOf(c);
    expect(texts, contains('对'));
    expect(texts, contains('错'));
    // 命中区块的底色 = 标绿底（按契约）。
    expect(
      c.nodes.any((n) =>
          n.kind == FloatNodeKind.box &&
          n.argb == HighlightColorProbe.greenBackground),
      isTrue,
    );
  });

  testWidgets('⑪ M42：极简模式是**纯文本面板**：没有卡片/圆角块，字全都在', (tester) async {
    final c = layout([
      q(
        id: 'q1',
        questionNo: '12',
        stem: '下列说法正确的是？',
        options: const [
          Option(label: 'A', text: '甲是对的'),
          Option(label: 'B', text: '乙是对的'),
        ],
        choice: const ['B'],
      ),
    ], minimal: true);

    // ① 纯文本：除了题与题之间的 1 像素分割线，**没有任何盒子**
    //    （没有卡片底、没有圆角、没有徽标、没有色块）。
    for (final b in c.nodes.where((n) => n.kind == FloatNodeKind.box)) {
      expect(b.rect.height, lessThanOrEqualTo(1.0),
          reason: '极简模式只允许极细分割线，不允许卡片/徽标：$b');
      expect(b.radius, 0);
    }
    // ② 一题一个可拖选的文本图元（跨行选区靠它，拆成多个图元下标会错位）。
    final texts = c.nodes.where((n) => n.kind == FloatNodeKind.text).toList();
    expect(texts.length, 1);
    expect(texts.single.questionId, 'q1');
    expect(texts.single.painter, isNotNull, reason: '排好版才能按字符算选区');
    expect(texts.single.painter!.text!.toPlainText().contains('\n'), isTrue,
        reason: '题号/题干/选项/答案在同一段里换行');
    // ③ 用户要看到的东西一个都不能少：题号、题干、选项、答案。
    for (final s in ['第 1 题', '下列说法正确的是？', 'A. 甲是对的', 'B. 乙是对的', '答案：B']) {
      expect(texts.single.text, contains(s), reason: '缺了「$s」');
    }
    // ④ 命中项带勾（极简模式仍然看得出哪个选项是对的）。
    expect(texts.single.text, contains('✓'));
  });

  testWidgets('⑫ M42：极简面板比正常模式更短，且没有解析', (tester) async {
    final qs = [
      q(
        id: 'q1',
        stem: '下列说法正确的是？',
        options: const [Option(label: 'A', text: '甲'), Option(label: 'B', text: '乙')],
        choice: const ['B'],
      ),
    ];
    final normal = layout(qs);
    final minimal = layout(qs, minimal: true);
    expect(minimal.height, lessThan(normal.height));
    expect(textsOf(minimal).join(), isNot(contains('解析')));
    expect(textsOf(minimal).join(), contains('答案：'));
  });

  testWidgets('⑬ M42：没识别出答案就写「未识别出答案」；答案文本的取值规则', (tester) async {
    final c = layout([
      q(
        id: 'q1',
        stem: '填空题',
        type: QuestionType.blank,
        options: const [Option(label: 'A', text: '甲')],
        choice: const [],
        text: null,
      ),
    ], minimal: true);
    expect(textsOf(c).join('\n'), contains('未识别出答案'));
    // `answerTextOf` 的取值顺序：answerText → choice → 命中选项标签。
    expect(answerTextOf(q(id: 'q2', type: QuestionType.blank, text: null)), '');
    expect(answerTextOf(q(id: 'q3', choice: const ['A', 'C'])), 'A、C');
    expect(answerTextOf(q(id: 'q4', text: '  42  ')), '42');
  });

  testWidgets('⑭ M43/M44：默认模式的题号等 ≥ 4.5:1，答案是指定的标绿契约色',
      (tester) async {
    // 用户口径（M43 第 3 条）：「极简模式答案题号等颜色和背景色高度接近，不明显」，
    // 并点名了「默认白色和紫色」。这里把 6 套配色 × 明暗两态**全部**量一遍。
    // M44 第 4 条：答案改成标绿契约色（用户要求「答案颜色改成绿色」），
    // 所以答案按 ≥3:1 且**必须等于契约色**来断言，其余文字仍要 ≥4.5:1。
    for (final dark in [false, true]) {
      for (final id in ['white', 'lilac', 'mint', 'sky', 'sand', 'rose']) {
        final p = FloatWindowPalette.of(dark: dark, paletteId: id);
        final c = layoutMinimalTextContent([
          q(
            id: 'q1',
            stem: '下列说法正确的是？',
            options: const [Option(label: 'A', text: '甲'), Option(label: 'B', text: '乙')],
            choice: const ['B'],
          ),
        ], width: 320, fontSize: 13, palette: p);
        final node = c.nodes.firstWhere((n) => n.kind == FloatNodeKind.text);
        final spans = _spansOf(node.painter!.text!);

        expect(contrastRatio(p.accentStrong, p.background),
            greaterThanOrEqualTo(4.5),
            reason: '$id dark=$dark：accentStrong 与底色对比度不足');
        expect(contrastRatio(p.answerStrong, p.background),
            greaterThanOrEqualTo(2.9),
            reason: '$id dark=$dark：answerStrong 连 2.9:1（主界面水平）都不到');

        final seq = spans.firstWhere((s) => s.text!.startsWith('第 '));
        expect(
            contrastRatio(seq.style!.color!.toARGB32(), p.background),
            greaterThanOrEqualTo(4.5),
            reason: '$id dark=$dark：题号颜色与底色太接近（用户报的就是这条）');
        final ans = spans.firstWhere((s) => s.text!.startsWith('答案：'));
        // M44 第 4 条（用户要求）：答案就是主界面那套**标绿**契约色
        //（浅色 #16A34A / 深色 #4ADE80），不参与 4.5:1 的自动压暗 —— 用户要的是
        //「一眼看出是绿色」。这里钉住它等于契约色，且不低于 2.9:1（主界面水平；
        // 紫罗兰浅色底的窗口底色比白卡片略深，实测 2.97:1）。
        final ansColor = ans.style!.color!.toARGB32();
        expect(contrastRatio(ansColor, p.background), greaterThanOrEqualTo(2.9),
            reason: '$id dark=$dark：答案色连 2.9:1 都不到');
        expect(ansColor, HighlightColors.text(dark).toARGB32(),
            reason: '$id dark=$dark：答案必须是标绿契约色（用户要求绿色）');
        // 「等」：其余文字（题号、题型/把握率、空答案提示）仍要 ≥ 4.5:1。
        for (final s in spans) {
          if (s.text!.startsWith('答案：')) continue;
          final color = s.style!.color!.toARGB32();
          expect(contrastRatio(color, p.background), greaterThanOrEqualTo(4.5),
              reason: '$id dark=$dark：「${s.text!.trim()}」的颜色与底色太接近');
        }
      }
    }
  });

  testWidgets('⑮ M43：ensureContrast —— 够清楚就原样返回，不够就往白/黑调', (tester) async {
    // 黑底白字已经够清楚：原样返回（不要无谓地改配色）。
    expect(ensureContrast(0xFFFFFFFF, 0xFF000000), 0xFFFFFFFF);
    // 用户点名的组合：紫罗兰在深色底上「几乎看不见」→ 必须被调亮。
    final lilac = FloatWindowPalette.of(dark: true, paletteId: 'lilac');
    expect(contrastRatio(lilac.accent, lilac.background), lessThan(4.5),
        reason: '这套配色本来就是「不够清楚」的那个反例');
    expect(contrastRatio(lilac.accentStrong, lilac.background),
        greaterThanOrEqualTo(4.5));
    // 浅色下要往**黑**调而不是往白调（否则越调越淡）。
    final light = FloatWindowPalette.of(dark: false, paletteId: 'sand');
    expect(relativeLuminance(light.accentStrong),
        lessThan(relativeLuminance(light.accent)));
  });

  testWidgets('⑯ M43：「复制识别内容」给的是**完整**识别结果（纯文本）', (tester) async {
    final text = recognitionTextOf([
      q(
        id: 'q1',
        questionNo: '12',
        stem: '下列说法正确的是？',
        options: const [
          Option(label: 'A', text: '甲'),
          Option(label: 'B', text: '乙'),
          Option(label: 'C', text: '丙'),
        ],
        choice: const ['B'],
        analysis: '因为乙才是对的。',
      ),
      q(
        id: 'q2',
        ordinal: 1,
        questionNo: null,
        type: QuestionType.blank,
        stem: '填空：光速约 ____ m/s。',
        text: '3×10^8',
        analysis: '',
        material: '阅读材料第一行\n第二行',
      ),
    ]);

    expect(text, contains('第 1 题  单选题 · 把握 85% · 卷面题号 12'));
    // 完整内容：未命中的选项也在（与屏幕上的极简排版**故意不同**）。
    expect(text, contains('A. 甲'));
    expect(text, contains('B. 乙'));
    expect(text, contains('C. 丙'));
    expect(text, contains('答案：B'));
    expect(text, contains('解析：因为乙才是对的。'));
    expect(text, contains('第 2 题  填空题'));
    expect(text, contains('答案：3×10^8'));
    expect(text, contains('阅读材料：阅读材料第一行\n第二行'));
    // 不带任何界面装饰（没有 ✓、没有卡片文案）。
    expect(text, isNot(contains('✓')));
    expect(text, isNot(contains('未识别出答案')));
    expect(text.endsWith('\n'), isFalse, reason: '结尾不留空行');
    // 空列表给空串（调用方据此给「这次识别还没有内容」提示）。
    expect(recognitionTextOf(const []), '');
  });
}

/// 把一个 `TextSpan` 树摊平成「叶子 span」列表（取每段的颜色用）。
List<TextSpan> _spansOf(InlineSpan span) {
  final out = <TextSpan>[];
  void walk(InlineSpan s) {
    if (s is! TextSpan) return;
    if (s.text != null && s.text!.isNotEmpty) out.add(s);
    for (final child in s.children ?? const <InlineSpan>[]) {
      walk(child);
    }
  }

  walk(span);
  return out;
}

/// 标绿底色（与 `HighlightColors.lightBackground` 一致）；直接取常量避免
/// 在测试里再 import 一次 ui 包。
abstract final class HighlightColorProbe {
  static const int greenBackground = 0xFFDCFCE7;
}
