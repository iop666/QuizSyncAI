// 本文件由 tools/gen_design_tokens.py 从 design/tokens.json 生成，请勿手改。
// 校验：跑一次 tools/gen_design_tokens.py，加参数 check
//
// 值来自老应用（1.1.0）的视觉契约 packages/quizsync_ui，
// 由 packages/quizsync_ui/test/design_token_parity_test.dart 逐条断言 —— 不要在这里手改数值。
//
// 生成时逐条校验过的 WCAG 对比度：
//   主按钮文字 / 填充: 6.48:1（下限 4.5:1）
//   主按钮文字 / 填充（暗）: 7.73:1（下限 4.5:1）
//   正文 / 卡片: 17.10:1（下限 4.5:1）
//   正文 / 卡片（暗）: 14.33:1（下限 4.5:1）
//   次要文字 / 页面底色: 8.51:1（下限 4.5:1）
//   次要文字 / 页面底色（暗）: 11.14:1（下限 4.5:1）
//   标签描边 / 卡片: 4.48:1（下限 3.0:1）
//   标签描边 / 卡片（暗）: 5.83:1（下限 3.0:1）
package com.quizsync.android.dev

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/// 跨端设计 token（与 Windows 的 DesignTokens.xaml 同源，值都来自老应用的视觉契约）。
object QsTokens {
    /// 圆角：**按钮 10 / 标签 999 胶囊 / 卡片 16** —— 与 AppRadius.control / chip / card 一致。
    /// （第五轮教训：上一版这里写反了，把按钮做成胶囊、标签做成圆角矩形。）
    val radiusCard = 16.dp
    val radiusControl = 10.dp
    val radiusChip = 999.dp

    val spaceXs = 4.dp
    val spaceSm = 8.dp
    val spaceMd = 12.dp
    val spaceLg = 16.dp
    val spaceXl = 24.dp

    // 单独取用的颜色（Compose 里不经过 ColorScheme 的那些）。
    val brandPrimary = Color(0xFF35693E)
    val brandPrimaryDark = Color(0xFF9CD4A0)
    val onBrandPrimary = Color(0xFFFFFFFF)
    val onBrandPrimaryDark = Color(0xFF003914)
    val brandSeed = Color(0xFF16A34A)
    val brandSeedDark = Color(0xFF16A34A)
    val canvas = Color(0xFFF3F5F4)
    val canvasDark = Color(0xFF0F1113)
    val surface = Color(0xFFFFFFFF)
    val surfaceDark = Color(0xFF101510)
    val onSurface = Color(0xFF181D18)
    val onSurfaceDark = Color(0xFFE0E4DB)
    val onSurfaceVariant = Color(0xFF414941)
    val onSurfaceVariantDark = Color(0xFFC1C9BE)
    val outline = Color(0xFF727970)
    val outlineDark = Color(0xFF8B9389)
    val cardStroke = Color(0xFFE3E7E5)
    val cardStrokeDark = Color(0xFF2A2F33)

    val lightScheme = lightColorScheme(
        primary = Color(0xFF35693E),
        onPrimary = Color(0xFFFFFFFF),
        background = Color(0xFFF3F5F4),
        onBackground = Color(0xFF181D18),
        surface = Color(0xFFFFFFFF),
        onSurface = Color(0xFF181D18),
        outline = Color(0xFF727970),
        outlineVariant = Color(0xFFE3E7E5),
        onSurfaceVariant = Color(0xFF414941),
    )

    val darkScheme = darkColorScheme(
        primary = Color(0xFF9CD4A0),
        onPrimary = Color(0xFF003914),
        background = Color(0xFF0F1113),
        onBackground = Color(0xFFE0E4DB),
        surface = Color(0xFF101510),
        onSurface = Color(0xFFE0E4DB),
        outline = Color(0xFF8B9389),
        outlineVariant = Color(0xFF2A2F33),
        onSurfaceVariant = Color(0xFFC1C9BE),
    )
}
