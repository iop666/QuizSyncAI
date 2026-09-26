import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

/// M44 第 6 条（用户报「设置中部分说明文字还存在 `**`」）：
/// 设置页的说明文字统一走 [SettingsRichText]，`**重点**` 渲染成**真加粗**。
void main() {
  const base = TextStyle(
      fontSize: 12.5, color: Color(0xFF112233), fontWeight: FontWeight.w400);

  List<String> textsOf(List<TextSpan> spans) =>
      spans.map((s) => s.text ?? '').toList();

  List<FontWeight?> weightsOf(List<TextSpan> spans) =>
      spans.map((s) => s.style?.fontWeight).toList();

  test('成对的 ** 变成加粗，星号本身不显示', () {
    final spans = settingsMarkdownSpans('默认**关闭**，打开后记住状态', base);
    expect(textsOf(spans), ['默认', '关闭', '，打开后记住状态']);
    expect(weightsOf(spans), [FontWeight.w400, FontWeight.w600, FontWeight.w400]);
    expect(textsOf(spans).join(), isNot(contains('*')));
  });

  test('一段里多个重点都能加粗', () {
    final spans = settingsMarkdownSpans('a **b** c **d** e', base);
    expect(textsOf(spans), ['a ', 'b', ' c ', 'd', ' e']);
    expect(weightsOf(spans).where((w) => w == FontWeight.w600).length, 2);
  });

  test('落单的 ** 原样显示（绝不吞掉用户能看到的字符）', () {
    for (final raw in ['只有一个 ** 星号', '三个 **a** 与 ** b']) {
      final spans = settingsMarkdownSpans(raw, base);
      expect(textsOf(spans).join(), raw.replaceAll('**a**', 'a'),
          reason: '落单的星号必须留在文本里：$raw');
    }
  });

  test('`****`（掩码那种）不成对，原样保留', () {
    final raw = '已设置（尾 4 位 ****1234）';
    expect(textsOf(settingsMarkdownSpans(raw, base)).join(), raw);
  });

  test('没有星号时只有一个片段（不改变原样）', () {
    final spans = settingsMarkdownSpans('普通说明', base);
    expect(textsOf(spans), ['普通说明']);
    expect(spans.single.style, base);
  });

  testWidgets('SettingsRichText 真的渲染成加粗的 TextSpan', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SettingsRichText(
          '默认**关闭**，打开后会记住状态',
          style: TextStyle(fontSize: 12.5),
        ),
      ),
    ));
    final rich = tester.widget<Text>(find.byType(Text));
    final span = rich.textSpan! as TextSpan;
    final bold = span.children!.cast<TextSpan>().lastWhere(
        (s) => s.style?.fontWeight == FontWeight.w600);
    expect(bold.text, '关闭');
    // 界面上不该再看到星号。
    expect(find.textContaining('**'), findsNothing);
  });
}
