import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_ui/quizsync_ui.dart';

/// 用户反馈 2（M14）：「api 配置里有些名称后有 ⓘ，毫无作用」。
///
/// 设置项标题后的 ⓘ 原来是一个 14px 的裸 Icon 套 Tooltip：点击没有任何反应。
/// 这里锁定修复后的行为：**有说明**时悬停出 Tooltip、点击出全文对话框；
/// **没有说明**（null 或空串）时根本不渲染 ⓘ，不留死图标。
void main() {
  const info = '用 Windows DPAPI 加密后存在本机数据目录，界面只回显尾 4 位；'
      '保存成功后输入框立刻清空，不会长期明文显示。';

  Widget wrap(Widget child) => MaterialApp(
        theme: QuizSyncTheme.build(
            brightness: Brightness.light, accent: 0xFF16A34A),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('有说明时：点 ⓘ 弹出对话框并显示完整说明', (tester) async {
    await tester.pumpWidget(wrap(const SettingsRow(
      title: 'API Key',
      subtitle: '已设置（尾 4 位 ****1234）',
      info: info,
    )));

    expect(find.byKey(const ValueKey('info-API Key')), findsOneWidget,
        reason: '有说明就必须渲染可点的 ⓘ');
    // 命中区域要比原来那个 14px 的裸图标大得多，且不随平台变（28×28）。
    expect(tester.getSize(find.byKey(const ValueKey('info-API Key'))),
        const Size(28, 28));
    // Tooltip 里也要有真实文字：悬停即可一瞥，不再是空提示。
    final tooltip = tester.widget<Tooltip>(find.ancestor(
      of: find.byKey(const ValueKey('info-API Key')),
      matching: find.byType(Tooltip),
    ));
    expect(tooltip.message, info);

    await tester.tap(find.byKey(const ValueKey('info-API Key')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-info-dialog')), findsOneWidget,
        reason: '点击 ⓘ 必须弹出全文对话框（原来点不动）');
    expect(find.text(info), findsOneWidget, reason: '对话框里要有那段说明文字');

    await tester.tap(find.byKey(const ValueKey('settings-info-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-info-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SettingsField 的 ⓘ 同样可点出对话框', (tester) async {
    await tester.pumpWidget(wrap(const SettingsField(
      title: 'Base URL',
      info: '本项目会在结尾拼上 /chat/completions（OpenAI 兼容格式）。',
      child: SizedBox(width: 40),
    )));

    await tester.tap(find.byKey(const ValueKey('info-Base URL')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-info-dialog')), findsOneWidget);
    expect(find.textContaining('/chat/completions'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('悬停 ⓘ 就出 Tooltip（说明文字不再藏在点不动的图标里）', (tester) async {
    await tester.pumpWidget(wrap(const SettingsRow(title: '模型名称', info: info)));

    final icon = find.byKey(const ValueKey('info-模型名称'));
    expect(find.text(info), findsNothing, reason: '还没悬停时不应有提示浮层');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(icon));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(info), findsOneWidget, reason: '桌面端悬停必须能读到说明');

    // 收起浮层再卸载，避免留下 pending timer。
    await gesture.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('没有说明时不渲染 ⓘ：info 省略、null、空串、纯空白都不画', (tester) async {
    await tester.pumpWidget(wrap(const Column(children: [
      SettingsRow(title: '没有说明'),
      SettingsRow(title: '空串说明', info: ''),
      SettingsRow(title: '空白说明', info: '   '),
      SettingsField(title: '字段没有说明', child: SizedBox(width: 40)),
      SettingsField(title: '字段空串说明', info: '', child: SizedBox(width: 40)),
    ])));

    for (final title in const [
      '没有说明',
      '空串说明',
      '空白说明',
      '字段没有说明',
      '字段空串说明',
    ]) {
      expect(find.byKey(ValueKey('info-$title')), findsNothing,
          reason: '「$title」没有说明文字，不能留一个点了没反应的 ⓘ');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
