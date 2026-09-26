import 'package:flutter/material.dart';

/// 双端共用的视觉基线（M8 界面优化）：
/// 统一的圆角、描边卡片、输入框、按钮、SnackBar 与配色。
///
/// 约束：SPEC 4.3 的「标绿」颜色由 [HighlightColors] 固定，**不随主题种子色变化**。
class AppRadius {
  static const card = 16.0;

  /// 控件圆角（输入框 / 按钮 / 导航项）：M9 按 Fluent 观感收到 10。
  static const control = 10.0;
  static const chip = 999.0;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class QuizSyncTheme {
  /// 画布色（比卡片略深，用来把卡片「托」起来）。
  static Color canvas(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF0F1113) : const Color(0xFFF3F5F4);

  /// 卡片描边色。
  static Color outline(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF2A2F33) : const Color(0xFFE3E7E5);

  /// 次级填充色（输入框、代码块底）。
  static Color subtleFill(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF191C1F) : const Color(0xFFF2F5F3);

  static ThemeData build({
    required Brightness brightness,
    required int accent,
    String? fontFamily,
    List<String> fontFamilyFallback = const [],
  }) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(accent),
      brightness: brightness,
      // 浅色下用纯白卡片（用户当面决策），画布另用浅灰。
      surface: dark ? null : Colors.white,
    );
    final edge = outline(brightness);
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas(brightness),
      visualDensity: VisualDensity.standard,
    );
    // 先把各层级的字重定下来，再套字体族与 wght 轴 —— 顺序反了的话
    // fontVariations 会停在旧字重（wght=400），把上面刚设的 w700 覆盖掉。
    final weighted = base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    // 用户反馈 1：Windows 端整体换成 MiSans（可变字体）。
    final text = fontFamily == null
        ? weighted
        : _withFamily(weighted, fontFamily, fontFamilyFallback);

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: scheme.onSurface,
        ),
        shape: Border(bottom: BorderSide(color: edge)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: edge),
        ),
      ),
      dividerTheme: DividerThemeData(color: edge, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: subtleFill(brightness),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: edge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: edge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          side: BorderSide(color: edge),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: edge),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xFF2A3034) : const Color(0xFF23282B),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: edge),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: edge)),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 4,
        showValueIndicator: ShowValueIndicator.onlyForDiscrete,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A3034) : const Color(0xFF23282B),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(!dark ? true : true),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
      ),
    );
  }
}

/// 把整套 textTheme 换成指定字体；每个样式带上 `wght` 轴（可变字体）。
TextTheme _withFamily(
    TextTheme t, String family, List<String> fallback) {
  TextStyle fix(TextStyle? s) {
    final weight = (s?.fontWeight ?? FontWeight.w400).value.toDouble();
    return (s ?? const TextStyle()).copyWith(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontVariations: [FontVariation('wght', weight)],
    );
  }

  return t.copyWith(
    displayLarge: fix(t.displayLarge),
    displayMedium: fix(t.displayMedium),
    displaySmall: fix(t.displaySmall),
    headlineLarge: fix(t.headlineLarge),
    headlineMedium: fix(t.headlineMedium),
    headlineSmall: fix(t.headlineSmall),
    titleLarge: fix(t.titleLarge),
    titleMedium: fix(t.titleMedium),
    titleSmall: fix(t.titleSmall),
    bodyLarge: fix(t.bodyLarge),
    bodyMedium: fix(t.bodyMedium),
    bodySmall: fix(t.bodySmall),
    labelLarge: fix(t.labelLarge),
    labelMedium: fix(t.labelMedium),
    labelSmall: fix(t.labelSmall),
  );
}

/// 字重档位（用户反馈 1）：MiSans 的 wght 轴 100–900，这里取常用五档。
FontWeight fontWeightOf(int wght) {
  final index = ((wght / 100).round() - 1).clamp(0, 8);
  return FontWeight.values[index];
}

/// 题目正文的字重样式：`fontWeight` 与 `wght` 轴都要给（可变字体）。
TextStyle questionWeightStyle(int wght, {TextStyle? base}) =>
    (base ?? const TextStyle()).copyWith(
      fontWeight: fontWeightOf(wght),
      fontVariations: [FontVariation('wght', wght.toDouble())],
    );
