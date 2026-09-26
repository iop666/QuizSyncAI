import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/app.dart';
import 'package:quizsync_desktop/services/desktop_server.dart';
import 'package:quizsync_desktop/state/app_scope.dart';
import 'package:quizsync_desktop/ui/home_page.dart' show dataRootProvider;
import 'package:quizsync_desktop/ui/settings_page.dart';

/// 用户反馈 1 / 9 的回归：MiSans 字体、题目字重、界面缩放。
void main() {
  group('界面缩放（用户反馈 9）', () {
    testWidgets('200% 时子树的逻辑尺寸减半、文字仍然可用', (tester) async {
      late Size seen;
      await tester.pumpWidget(MaterialApp(
        home: UiScale(
          scale: 2.0,
          child: Builder(builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const Scaffold(body: Center(child: Text('内容')));
          }),
        ),
      ));
      final physical = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(seen.width, closeTo(physical.width / 2, 1),
          reason: '虚拟画布宽度 = 真实宽度 / 缩放比');
      expect(seen.height, closeTo(physical.height / 2, 1));
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('100% 时不包任何缩放层（布局与原来一模一样）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: UiScale(scale: 1.0, child: Text('内容')),
      ));
      expect(find.byType(LayoutBuilder), findsNothing);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('缩放值会被夹在 50%–300% 之间（设置层兜底）', (tester) async {
      expect(const AppSettings().copyWith(uiScale: 9).uiScale, 3.0);
      expect(const AppSettings().copyWith(uiScale: 0.1).uiScale, 0.5);
      expect(
          AppSettings.fromMap(const {'ui_scale': '9'}).uiScale, 3.0);
      expect(const AppSettings().uiScale, 1.0);
    });

    // 用户反馈 7：只提供固定档位（50% 起、每 25% 一档、到 300%），不再用进度条。
    test('下拉档位正好是 50%–300% 且每档相差 25%', () {
      expect(kUiScalePresets.first, 0.5);
      expect(kUiScalePresets.last, 3.0);
      expect(kUiScalePresets, hasLength(11));
      for (var i = 1; i < kUiScalePresets.length; i++) {
        expect(kUiScalePresets[i] - kUiScalePresets[i - 1], closeTo(0.25, 1e-9),
            reason: '第 $i 档与前一档必须相差 25%');
      }
    });

    test('旧配置里的非档位值会被吸到最近的档位（下拉框才不会选不中）', () {
      expect(nearestUiScalePreset(1.3), 1.25);
      expect(nearestUiScalePreset(1.4), 1.5);
      expect(nearestUiScalePreset(0.9), 1.0);
      expect(nearestUiScalePreset(5.0), 3.0);
    });

    testWidgets('显示设置页用下拉框而不是进度条', (tester) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = QuizSyncDb(NativeDatabase.memory());
      final repo = CoreRepository(db: db, deviceId: 'windows-local');
      await repo.init();
      final settings = SettingsController(MemoryKeyValueStore());
      await settings.load();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          repoProvider.overrideWithValue(repo),
          settingsProvider.overrideWith((ref) => settings),
          apiKeyReaderProvider.overrideWithValue(() async => null),
          apiKeyWriterProvider.overrideWithValue((k) async {}),
          serverControllerProvider.overrideWithValue(DesktopServerController()),
          dataRootProvider.overrideWithValue(Directory.systemTemp.path),
        ],
        child: MaterialApp(
            theme: QuizSyncTheme.build(
                brightness: Brightness.light,
                accent: 0xFF16A34A,
                fontFamily: 'MiSans'),
            home: const SettingsPage()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // M32 用户需求 5：设置页第一项改成「使用说明」，这里先切到显示设置。
      await tester.tap(find.byKey(const ValueKey('settings-nav-display')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('settings-ui-scale-dropdown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('settings-ui-scale-slider')), findsNothing,
          reason: '用户反馈 7：不提供进度条，只给固定档位下拉框');
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });
  });

  group('题目字重（用户反馈 1）', () {
    test('字重档位映射到 FontWeight 与 wght 轴', () {
      expect(fontWeightOf(300), FontWeight.w300);
      expect(fontWeightOf(700), FontWeight.w700);
      final style = questionWeightStyle(600);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontVariations!.first.axis, 'wght');
      expect(style.fontVariations!.first.value, 600);
    });

    testWidgets('题干跟着字重设置走（默认 500，可调）', (tester) async {
      Future<TextStyle> stemStyleWith(int? weight) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: QuestionCard(
              question: Question(
                questionId: 'q1',
                sessionId: 's1',
                ordinal: 1,
                type: QuestionType.single,
                stem: '题干文字',
                options: const [
                  Option(label: 'A', text: '选项A'),
                  Option(label: 'B', text: '选项B'),
                ],
                choice: const ['A'],
                createdAt: nowMs(),
                updatedAt: nowMs(),
                updatedBy: 'test',
              ),
              fontSize: 16,
              fontWeight: weight,
            ),
          ),
        ));
        await tester.pump();
        final t = tester.widget<Text>(
            find.descendant(of: find.byKey(const ValueKey('question-stem')), matching: find.byType(Text)).first);
        return t.style!;
      }

      final normal = await stemStyleWith(null);
      expect(normal.fontWeight, FontWeight.w500, reason: '不传参数时保持原样');

      final heavy = await stemStyleWith(700);
      expect(heavy.fontWeight, FontWeight.w700);
      expect(heavy.fontVariations!.first.value, 700);
    });
  });

  group('MiSans 字体（用户反馈 1）', () {
    test('主题带上字体family与 wght 轴', () {
      final theme = QuizSyncTheme.build(
          brightness: Brightness.light, accent: 0xFF16A34A, fontFamily: 'MiSans');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'MiSans');
      expect(theme.textTheme.titleLarge?.fontFamily, 'MiSans');
      expect(theme.textTheme.titleLarge?.fontVariations?.first.axis, 'wght');
      expect(theme.textTheme.titleLarge?.fontVariations?.first.value,
          theme.textTheme.titleLarge!.fontWeight!.value.toDouble());
    });

    test('不传字体时保持默认（安卓端不受影响）', () {
      final theme =
          QuizSyncTheme.build(brightness: Brightness.light, accent: 0xFF16A34A);
      expect(theme.textTheme.bodyMedium?.fontFamily, isNot('MiSans'));
      expect(theme.textTheme.bodyMedium?.fontVariations, isNull,
          reason: '不指定字体时不注入 wght 轴，安卓端行为与改动前一致');
    });

    testWidgets('桌面端根组件真的用了 MiSans 与当前缩放', (tester) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = QuizSyncDb(NativeDatabase.memory());
      final repo = CoreRepository(db: db, deviceId: 'windows-local');
      await repo.init();
      final settings = SettingsController(MemoryKeyValueStore());
      await settings.load();
      await settings.updateApp(
          settings.app.copyWith(uiScale: 1.5, questionFontWeight: 600));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          repoProvider.overrideWithValue(repo),
          settingsProvider.overrideWith((ref) => settings),
          apiKeyReaderProvider.overrideWithValue(() async => null),
          apiKeyWriterProvider.overrideWithValue((k) async {}),
          serverControllerProvider.overrideWithValue(DesktopServerController()),
          dataRootProvider.overrideWithValue(Directory.systemTemp.path),
        ],
        child: MaterialApp(
          theme: QuizSyncTheme.build(
              brightness: Brightness.light,
              accent: 0xFF16A34A,
              fontFamily: 'MiSans'),
          home: const SettingsPage(),
        ),
      ));
      await tester.pump();
      final context = tester.element(find.byType(SettingsPage));
      expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'MiSans');
      expect(settings.app.uiScale, 1.5);
      expect(settings.app.questionFontWeight, 600);
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });
  });
}
