import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

/// 跨端设计 token（`design/tokens.json`）与**老应用视觉契约**的一致性守卫。
///
/// 为什么需要这个测试（第五轮，用户当场质问「我应用 1.1.0 原来是浅绿的，你用紫色干什么」）：
/// 原生 2.0 的前几轮里，我先凭空发明了品牌紫 `#63519F`、按钮=胶囊、标签=圆角矩形，
/// 再花好几轮把 Android 与 Windows「拉齐」到那个虚构规格上 —— 而且方向正好修反：
/// 老应用是 `AppRadius.control = 10`（按钮圆角 10）与 `AppRadius.chip = 999`（标签全胶囊），
/// Windows 原来那一侧才是对的。
///
/// 根因是两端都能「各自顺手取值」，而没有任何东西约束取值必须等于**产品真实的**视觉契约。
/// 这个测试就是那道约束：token 的每个颜色/圆角/间距都要能在 `quizsync_ui` 里找到出处，
/// 且 `ColorScheme.fromSeed` 的结果要**用真 Flutter 算出来逐字比对**（不是手抄）。
///
/// 谁改了老应用主题、token 没跟着改 → 这里红；
/// 谁在 token 里凭空写一个值 → 这里也红。
void main() {
  // packages/quizsync_ui/test/ → 仓库根
  final tokensFile = File('../../design/tokens.json');

  late Map<String, dynamic> tokens;
  late Map<String, String> light;
  late Map<String, String> dark;

  String hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Map<String, String> tableOf(String theme) => {
        for (final entry in (tokens['colors'] as List).cast<Map<String, dynamic>>())
          entry['name'] as String: entry[theme] as String,
      };

  setUpAll(() {
    expect(tokensFile.existsSync(), isTrue,
        reason: '找不到 ${tokensFile.path}（应按 packages/quizsync_ui 为工作目录运行）');
    tokens = jsonDecode(tokensFile.readAsStringSync()) as Map<String, dynamic>;
    light = tableOf('light');
    dark = tableOf('dark');
  });

  group('品牌种子：必须就是老应用的那个品牌绿', () {
    test('品牌绿 = AccentPresets 第一项（品牌绿），且 token 与之一致', () {
      final (label, seed) = AccentPresets.presets.first;
      expect(label, '品牌绿');
      expect(hex(seed), light['brandSeed'],
          reason: 'token 的 brandSeed 必须等于 AccentPresets 的「品牌绿」');
      expect(hex(seed), dark['brandSeed']);
    });
  });

  group('由种子派生的配色：用真 Flutter 算出来比，不手抄', () {
    // token 名 → ColorScheme 里对应的槽位
    const slots = <String, Color Function(ColorScheme)>{
      'brandPrimary': _primary,
      'onBrandPrimary': _onPrimary,
      'surface': _surface,
      'onSurface': _onSurface,
      'outline': _outline,
      'onSurfaceVariant': _onSurfaceVariant,
    };

    for (final (themeName, brightness) in [
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      test('$themeName 主题的派生色与 token 一致', () {
        final scheme = ColorScheme.fromSeed(
          seedColor: AccentPresets.presets.first.$2,
          brightness: brightness,
          // 与 QuizSyncTheme.build 同一句：浅色下卡片用纯白（用户当面决策）。
          surface: brightness == Brightness.dark ? null : Colors.white,
        );
        final expected = themeName == 'light' ? light : dark;
        for (final entry in slots.entries) {
          expect(hex(entry.value(scheme)), expected[entry.key],
              reason: '${entry.key}（$themeName）与 ColorScheme.fromSeed 的结果不一致');
        }
      });
    }
  });

  group('页面底色 / 装饰描边：必须等于 QuizSyncTheme 的三个静态值', () {
    test('canvas(light/dark)', () {
      expect(hex(QuizSyncTheme.canvas(Brightness.light)), light['canvas']);
      expect(hex(QuizSyncTheme.canvas(Brightness.dark)), dark['canvas']);
    });

    test('cardStroke = QuizSyncTheme.outline', () {
      expect(hex(QuizSyncTheme.outline(Brightness.light)), light['cardStroke']);
      expect(hex(QuizSyncTheme.outline(Brightness.dark)), dark['cardStroke']);
    });
  });

  group('圆角与间距：必须等于 AppRadius / AppSpacing', () {
    test('圆角 card / control / chip', () {
      final radii = tokens['radii'] as Map<String, dynamic>;
      expect(radii['card'], AppRadius.card);
      expect(radii['control'], AppRadius.control,
          reason: '按钮圆角（第五轮我把这里错改成 999 胶囊，方向是反的）');
      expect(radii['chip'], AppRadius.chip,
          reason: '能力标签圆角（第五轮我把这里错改成 8 圆角矩形，方向是反的）');
    });

    test('间距 xs / sm / md / lg / xl', () {
      final spacing = tokens['spacing'] as Map<String, dynamic>;
      expect(spacing['xs'], AppSpacing.xs);
      expect(spacing['sm'], AppSpacing.sm);
      expect(spacing['md'], AppSpacing.md);
      expect(spacing['lg'], AppSpacing.lg);
      expect(spacing['xl'], AppSpacing.xl);
    });
  });
}

// 下面几个是 ColorScheme 槽位的取值器：写成函数是为了让上面的表既短又不吃闭包。
Color _primary(ColorScheme s) => s.primary;
Color _onPrimary(ColorScheme s) => s.onPrimary;
Color _surface(ColorScheme s) => s.surface;
Color _onSurface(ColorScheme s) => s.onSurface;
Color _outline(ColorScheme s) => s.outline;
Color _onSurfaceVariant(ColorScheme s) => s.onSurfaceVariant;
