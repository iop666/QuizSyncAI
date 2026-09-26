import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets(r'公式渲染：美元符号包裹的公式正常渲染', (tester) async {
    await tester.pumpWidget(wrap(const MathText(
      text: '因为 \$x^2=4\$ 所以',
      style: TextStyle(fontSize: 16),
    )));
    await tester.pumpAndSettle();
    // 普通文本部分（Text.rich 行内排版 → 按渲染纯文本匹配）
    expect(find.textContaining('因为 '), findsOneWidget);
    expect(find.textContaining(' 所以'), findsOneWidget);
    // 公式部分不是 fallback
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing);
  });

  testWidgets('公式渲染失败 → 回退等宽字体原样显示（不白屏）', (tester) async {
    await tester.pumpWidget(wrap(const MathText(
      text: '坏公式 \$\frac{\$ 结束',
      style: TextStyle(fontSize: 16),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('math-fallback')), findsWidgets,
        reason: '解析失败的 LaTeX 必须回退显示，不能白屏');
  });

  testWidgets('无公式文本原样显示', (tester) async {
    await tester.pumpWidget(wrap(const MathText(
      text: '普通解析文本',
      style: TextStyle(fontSize: 16),
    )));
    await tester.pumpAndSettle();
    expect(find.text('普通解析文本'), findsOneWidget);
  });

  testWidgets('题目卡片：解析区含公式时正常渲染（MathText 集成）', (tester) async {
    final card = QuestionCard(
      question: _q(analysis: r'解：$x = \frac{-b}{2a}$，代入即得'),
      fontSize: 16,
    );
    await tester.pumpWidget(wrap(card));
    await tester.pumpAndSettle();
    expect(find.textContaining('解：'), findsOneWidget);
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing,
        reason: '合法 LaTeX 不应回退');
  });

  // ---- 用户反馈：物理公式整段显示成源码（定界符 `\(...\)` 不认） ----
  //
  // 下面两段文本是**从用户真实库里抄出来的原文**（physics 那道题的
  // stem / answer，AI 没按 prompt 用 `$...$`，用的是 LaTeX 原生定界符）。

  testWidgets(r'\(...\)：物理题的行内公式要渲染，不能把 \( \) 原样画出来',
      (tester) async {
    const stem = r'光滑水平面上，物块A质量 \(m_A = 1\,\mathrm{kg}\)，以 '
        r'\(v_0 = 4\,\mathrm{m/s}\) 向右运动；物块B质量 \(m_B = 2\,\mathrm{kg}\)，'
        '静止在水平面上，其左侧连接一轻弹簧，弹簧处于原长。';
    await tester.pumpWidget(wrap(const MathText(
      text: stem,
      style: TextStyle(fontSize: 16),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing,
        reason: r'\(...\) 里的内容本身是合法 LaTeX，不应回退');
    expect(find.textContaining(r'\('), findsNothing,
        reason: r'定界符不能被当成普通文字画在屏幕上（这正是用户看到的「不显示」）');
    expect(find.textContaining(r'\)'), findsNothing);
    expect(find.textContaining('光滑水平面上'), findsOneWidget);
  });

  testWidgets(r'\(...\)：解答里连续多段公式全部渲染（真实库原文）', (tester) async {
    const answer = r"① 弹簧最大弹性势能为 \(E_p=\frac{16}{3}\,\mathrm{J}\)。"
        '\n'
        r'② 两者共速时弹簧压缩最大，由动量守恒 \(m_Av_0=(m_A+m_B)v\)。'
        '\n'
        r"③ \(E_p=\frac12 m_Av_0^2-\frac12(m_A+m_B)v^2=\frac{16}{3}\,\mathrm{J}\)。";
    await tester.pumpWidget(wrap(const MathText(
      text: answer,
      style: TextStyle(fontSize: 16),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing);
    expect(find.textContaining(r'\('), findsNothing);
    expect(find.textContaining('弹簧最大弹性势能为'), findsOneWidget);
  });

  testWidgets(r'\[...\]：独立公式同样认', (tester) async {
    await tester.pumpWidget(wrap(const MathText(
      text: r'由牛顿第二定律 \[F = ma\] 得',
      style: TextStyle(fontSize: 16),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing);
    expect(find.textContaining(r'\['), findsNothing);
    expect(find.textContaining('由牛顿第二定律'), findsOneWidget);
  });

  testWidgets('两种定界符混在一段里也各归各位（美元写法照旧）', (tester) async {
    await tester.pumpWidget(wrap(const MathText(
      text: r'先看 $x^2=4$，再看 \(y^2=9\)，最后 $$z^2=16$$ 收尾',
      style: TextStyle(fontSize: 16),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('math-fallback')), findsNothing);
    expect(find.textContaining(r'\('), findsNothing);
    expect(find.textContaining(r'$$'), findsNothing);
    expect(find.textContaining('先看 '), findsOneWidget);
  });
}

Question _q({required String analysis}) {
  return Question(
    questionId: 'q',
    sessionId: 's',
    ordinal: 0,
    stem: '题干',
    type: QuestionType.blank,
    answerText: '42',
    analysis: analysis,
    createdAt: 1,
    updatedAt: 1,
    updatedBy: 'd',
  );
}
