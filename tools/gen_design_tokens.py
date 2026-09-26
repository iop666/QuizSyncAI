#!/usr/bin/env python3
"""从 design/tokens.json 生成两端的样式产物（唯一来源 → 两端一起更新）。

产物（都带「请勿手改」头，由本脚本负责改写）：
  android/app/src/main/kotlin/com/quizsync/android/dev/DesignTokens.kt
  android/app/src/main/res/values/design_tokens.xml
  android/app/src/main/res/values-night/design_tokens.xml
  windows/QuizSync.App/DesignTokens.xaml

用法：
  python tools/gen_design_tokens.py            # 生成/更新
  python tools/gen_design_tokens.py --check    # 只校验产物与 token 一致（CI 用，不一致就退出 1）

两道闸门：
  ① **值从哪来**：token 的值必须等于老应用（1.1.0）视觉契约里的值 —— 由
     packages/quizsync_ui/test/design_token_parity_test.dart 在 Dart 侧逐条断言
     （用真 Flutter 跑 ColorScheme.fromSeed，不是手抄）。第五轮用户当场质问
     「我应用 1.1.0 原来是浅绿的，你用紫色干什么」就是这道闸门缺失的后果：
     前几轮先凭空发明品牌紫 #63519F，再花好几轮把两端往那个虚构规格上拉，
     而且方向正好修反（老应用是按钮圆角 10 / 标签 999 胶囊）。
  ② **产物一致性**：手改任何一侧的产物、或改了 token 忘了重新生成，--check 就红。

生成时还会做：
  * WCAG 对比度逐条校验（不达标直接失败）；
  * 产物必须能被 XML 解析、且注释里不许出现两个连字符
    （踩过：注释里写脚本名加那次选项，XML 规范禁止，XamlCompiler 静默退出 1，一点提示都没有）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKENS = ROOT / "design" / "tokens.json"

KOTLIN_OUT = ROOT / "android/app/src/main/kotlin/com/quizsync/android/dev/DesignTokens.kt"
ANDROID_VALUES_OUT = ROOT / "android/app/src/main/res/values/design_tokens.xml"
ANDROID_VALUES_NIGHT_OUT = ROOT / "android/app/src/main/res/values-night/design_tokens.xml"
WINDOWS_OUT = ROOT / "windows/QuizSync.App/DesignTokens.xaml"

GENERATED_BY = "tools/gen_design_tokens.py"
DO_NOT_EDIT = "本文件由 %s 从 design/tokens.json 生成，请勿手改。" % GENERATED_BY


# ---------------------------------------------------------------- token 读取


def load_tokens() -> dict:
    data = json.loads(TOKENS.read_text(encoding="utf-8"))
    for key in ("colors", "radii", "spacing", "contrast"):
        if key not in data:
            raise SystemExit(f"design/tokens.json 缺少 {key} 段")
    return data


def color_table(tokens: dict, theme: str) -> dict:
    return {c["name"]: c[theme] for c in tokens["colors"]}


def parse_hex(value: str) -> tuple[int, int, int]:
    text = value.lstrip("#")
    if len(text) != 6:
        raise SystemExit(f"颜色必须是 6 位十六进制：{value}")
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    def channel(raw: int) -> float:
        c = raw / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg: str, bg: str) -> float:
    lf, lb = relative_luminance(parse_hex(fg)), relative_luminance(parse_hex(bg))
    hi, lo = max(lf, lb), min(lf, lb)
    return (hi + 0.05) / (lo + 0.05)


def verify_contrast(tokens: dict) -> list[str]:
    """逐条校验对比度下限；返回人类可读的实测报表（不达标直接 SystemExit）。"""
    report: list[str] = []
    failures: list[str] = []
    for rule in tokens["contrast"]:
        table = color_table(tokens, rule["theme"])
        try:
            fg, bg = table[rule["fg"]], table[rule["bg"]]
        except KeyError as missing:
            raise SystemExit(f"contrast 引用了不存在的颜色：{missing}")
        ratio = contrast_ratio(fg, bg)
        line = f"{rule['name']}: {ratio:.2f}:1（下限 {rule['min']}:1）"
        report.append(line)
        if ratio + 1e-9 < rule["min"]:
            failures.append("  " + line + "  ← 不达标")
    if failures:
        raise SystemExit("对比度校验失败：\n" + "\n".join(failures) + "\n\n" + "\n".join(report))
    return report


def verify_xml(text: str, label: str) -> None:
    """生成的 XML 必须能被解析，且注释体里不能出现两个连字符。

    这条自检是被一次真实的坑逼出来的：DesignTokens.xaml 的头注释里写了脚本名加那次
    选项（两个连字符），XML 规范**禁止注释体内含它**，而 XamlCompiler.exe 对这种语法
    错误**静默退出 1**（stdout 空、连 output.json 都不写），现场只能看到 MSB3073。
    当时我按「StaticResource 作用域」猜了一轮、又做了 8 次构造二分才定位到注释 ——
    其实先花 1 秒把产物丢给 XML 解析器就能立刻看出来。
    """
    try:
        ET.fromstring(text)
    except ET.ParseError as error:
        raise SystemExit(f"{label} 不是合法 XML：{error}") from error
    for comment in re.findall(r"<!--(.*?)-->", text, re.DOTALL):
        if "--" in comment:
            raise SystemExit(f"{label} 的 XML 注释里出现了两个连字符（XML 规范禁止，XamlCompiler 会静默失败）")


# ---------------------------------------------------------------- Android

# token 名 → Compose 里的用途
KOTLIN_SCHEME_SLOTS = [
    ("primary", "brandPrimary"),
    ("onPrimary", "onBrandPrimary"),
    ("background", "canvas"),
    ("onBackground", "onSurface"),
    ("surface", "surface"),
    ("onSurface", "onSurface"),
    ("outline", "outline"),
    ("outlineVariant", "cardStroke"),
    ("onSurfaceVariant", "onSurfaceVariant"),
]


def kotlin_color(hex_value: str) -> str:
    r, g, b = parse_hex(hex_value)
    return f"Color(0xFF{r:02X}{g:02X}{b:02X})"


def snake(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def scheme_block(tokens: dict, theme: str) -> str:
    table = color_table(tokens, theme)
    return "\n".join(
        f"        {slot} = {kotlin_color(table[token])}," for slot, token in KOTLIN_SCHEME_SLOTS
    )


def render_kotlin(tokens: dict, report: list[str]) -> str:
    radii, spacing = tokens["radii"], tokens["spacing"]
    contrast_lines = "\n".join(f"//   {line}" for line in report)
    palette_lines = "\n".join(
        f"    val {name} = {kotlin_color(color_table(tokens, 'light')[name])}\n"
        f"    val {name}Dark = {kotlin_color(color_table(tokens, 'dark')[name])}"
        for name in (c["name"] for c in tokens["colors"])
    )
    return f"""// {DO_NOT_EDIT}
// 校验：跑一次 {GENERATED_BY}，加参数 check
//
// 值来自老应用（1.1.0）的视觉契约 packages/quizsync_ui，
// 由 packages/quizsync_ui/test/design_token_parity_test.dart 逐条断言 —— 不要在这里手改数值。
//
// 生成时逐条校验过的 WCAG 对比度：
{contrast_lines}
package com.quizsync.android.dev

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/// 跨端设计 token（与 Windows 的 DesignTokens.xaml 同源，值都来自老应用的视觉契约）。
object QsTokens {{
    /// 圆角：**按钮 10 / 标签 999 胶囊 / 卡片 16** —— 与 AppRadius.control / chip / card 一致。
    /// （第五轮教训：上一版这里写反了，把按钮做成胶囊、标签做成圆角矩形。）
    val radiusCard = {radii['card']}.dp
    val radiusControl = {radii['control']}.dp
    val radiusChip = {radii['chip']}.dp

    val spaceXs = {spacing['xs']}.dp
    val spaceSm = {spacing['sm']}.dp
    val spaceMd = {spacing['md']}.dp
    val spaceLg = {spacing['lg']}.dp
    val spaceXl = {spacing['xl']}.dp

    // 单独取用的颜色（Compose 里不经过 ColorScheme 的那些）。
{palette_lines}

    val lightScheme = lightColorScheme(
{scheme_block(tokens, 'light')}
    )

    val darkScheme = darkColorScheme(
{scheme_block(tokens, 'dark')}
    )
}}
"""


def render_android_colors(tokens: dict, theme: str) -> str:
    table = color_table(tokens, theme)
    qualifier = "" if theme == "light" else "（夜间）"
    entries = "\n".join(f'    <color name="qs_{snake(name)}">{value}</color>' for name, value in table.items())
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- {DO_NOT_EDIT}{qualifier} -->
<resources>
{entries}
</resources>
"""


# ---------------------------------------------------------------- Windows

# token 名 → Windows 画刷名
BRUSH_NAMES = {
    "brandPrimary": "QsBrandPrimaryBrush",
    "onBrandPrimary": "QsOnBrandPrimaryBrush",
    "brandSeed": "QsBrandSeedBrush",
    "canvas": "QsCanvasBrush",
    "surface": "QsSurfaceBrush",
    "onSurface": "QsOnSurfaceBrush",
    "onSurfaceVariant": "QsOnSurfaceVariantBrush",
    "outline": "QsOutlineBrush",
    "cardStroke": "QsCardStrokeBrush",
}


def xaml_color(hex_value: str) -> str:
    r, g, b = parse_hex(hex_value)
    return f"#FF{r:02X}{g:02X}{b:02X}"


def theme_dictionary(tokens: dict, theme: str, indent: str) -> str:
    table = color_table(tokens, theme)
    lines = [
        f'{indent}<SolidColorBrush x:Key="{brush}" Color="{xaml_color(table[name])}"/>'
        for name, brush in BRUSH_NAMES.items()
    ]
    # AccentButtonStyle 的悬停/按下/禁用态走这几个主题画刷；一起覆盖，
    # 免得 Normal 是品牌绿、一悬停又变回系统强调色。
    primary = xaml_color(table["brandPrimary"])
    lines.append(f"{indent}<!-- AccentButtonStyle 的交互态一起跟着 token 走 -->")
    lines.append(f'{indent}<SolidColorBrush x:Key="AccentFillColorDefaultBrush" Color="{primary}"/>')
    lines.append(f'{indent}<SolidColorBrush x:Key="AccentFillColorSecondaryBrush" Color="{primary}" Opacity="0.9"/>')
    lines.append(f'{indent}<SolidColorBrush x:Key="AccentFillColorTertiaryBrush" Color="{primary}" Opacity="0.8"/>')
    lines.append(f'{indent}<SolidColorBrush x:Key="AccentFillColorDisabledBrush" Color="{primary}" Opacity="0.4"/>')
    lines.append(f'{indent}<Color x:Key="SystemAccentColor">{primary}</Color>')
    return "\n".join(lines)


def render_windows(tokens: dict, report: list[str]) -> str:
    radii, spacing = tokens["radii"], tokens["spacing"]
    contrast_lines = "\n".join(f"     {line}" for line in report)
    light = theme_dictionary(tokens, "light", "            ")
    dark = theme_dictionary(tokens, "dark", "            ")
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- {DO_NOT_EDIT}
     校验：跑一次 {GENERATED_BY}，加参数 check。
     值来自老应用（1.1.0）的视觉契约 packages/quizsync_ui，不要在这里手改数值。

     生成时逐条校验过的 WCAG 对比度：
{contrast_lines}
-->
<ResourceDictionary
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <ResourceDictionary.ThemeDictionaries>
        <ResourceDictionary x:Key="Light">
{light}
        </ResourceDictionary>
        <ResourceDictionary x:Key="Dark">
{dark}
        </ResourceDictionary>
        <ResourceDictionary x:Key="HighContrast">
{light}
        </ResourceDictionary>
    </ResourceDictionary.ThemeDictionaries>

    <!-- 主按钮：圆角 {radii['control']}（AppRadius.control，M9 按 Fluent 观感收的值），品牌绿填充。
         第五轮教训：这里曾经被改成 999 胶囊，是往我凭空发明的规格上拉。 -->
    <Style x:Key="QsPrimaryButtonStyle" TargetType="Button" BasedOn="{{StaticResource AccentButtonStyle}}">
        <Setter Property="Background" Value="{{ThemeResource QsBrandPrimaryBrush}}" />
        <Setter Property="Foreground" Value="{{ThemeResource QsOnBrandPrimaryBrush}}" />
        <Setter Property="BorderBrush" Value="{{ThemeResource QsBrandPrimaryBrush}}" />
        <Setter Property="CornerRadius" Value="{radii['control']}" />
        <Setter Property="Padding" Value="20,8" />
        <Setter Property="FontSize" Value="14" />
        <Setter Property="UseSystemFocusVisuals" Value="True" />
    </Style>

    <!-- 能力标签：圆角 {radii['chip']}（AppRadius.chip = 全胶囊），描边用 outline
         （**功能边界**要用 outline，不能用 cardStroke —— 后者对比度天生很低，是装饰用的）。 -->
    <Style x:Key="QsTagBorderStyle" TargetType="Border">
        <Setter Property="Padding" Value="10,4" />
        <Setter Property="CornerRadius" Value="{radii['chip']}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="BorderBrush" Value="{{ThemeResource QsOutlineBrush}}" />
        <Setter Property="Background" Value="{{ThemeResource QsSurfaceBrush}}" />
    </Style>

    <!-- Fluent 卡片：圆角 {radii['card']}（AppRadius.card）+ 装饰描边（cardStroke）。 -->
    <Style x:Key="QsCardStyle" TargetType="Border">
        <Setter Property="CornerRadius" Value="{radii['card']}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="BorderBrush" Value="{{ThemeResource QsCardStrokeBrush}}" />
        <Setter Property="Background" Value="{{ThemeResource QsSurfaceBrush}}" />
        <Setter Property="Padding" Value="{spacing['xl']}" />
    </Style>

    <!-- 底部状态条：通栏条带，底色 = 页面底色 canvas、文字 = 次要文字。 -->
    <Style x:Key="QsStatusBarBorderStyle" TargetType="Border">
        <Setter Property="Padding" Value="16,8" />
        <Setter Property="BorderThickness" Value="0,1,0,0" />
        <Setter Property="BorderBrush" Value="{{ThemeResource QsCardStrokeBrush}}" />
        <Setter Property="Background" Value="{{ThemeResource QsCanvasBrush}}" />
    </Style>

    <Style x:Key="QsStatusTextStyle" TargetType="TextBlock">
        <Setter Property="FontSize" Value="12" />
        <Setter Property="TextWrapping" Value="Wrap" />
        <Setter Property="Foreground" Value="{{ThemeResource QsOnSurfaceVariantBrush}}" />
    </Style>

    <Style x:Key="QsTagTextStyle" TargetType="TextBlock">
        <Setter Property="FontSize" Value="12" />
        <Setter Property="Foreground" Value="{{ThemeResource QsOnSurfaceVariantBrush}}" />
    </Style>

    <Style x:Key="QsBodyTextStyle" TargetType="TextBlock">
        <Setter Property="FontSize" Value="14" />
        <Setter Property="TextWrapping" Value="Wrap" />
        <Setter Property="Foreground" Value="{{ThemeResource QsOnSurfaceBrush}}" />
    </Style>

    <Style x:Key="QsSecondaryTextStyle" TargetType="TextBlock">
        <Setter Property="FontSize" Value="13" />
        <Setter Property="TextWrapping" Value="Wrap" />
        <Setter Property="Foreground" Value="{{ThemeResource QsOnSurfaceVariantBrush}}" />
    </Style>
</ResourceDictionary>
"""


# ---------------------------------------------------------------- 主流程


def outputs() -> dict[Path, str]:
    tokens = load_tokens()
    report = verify_contrast(tokens)
    files = {
        KOTLIN_OUT: render_kotlin(tokens, report),
        ANDROID_VALUES_OUT: render_android_colors(tokens, "light"),
        ANDROID_VALUES_NIGHT_OUT: render_android_colors(tokens, "dark"),
        WINDOWS_OUT: render_windows(tokens, report),
    }
    for path, content in files.items():
        if path.suffix in (".xml", ".xaml"):
            verify_xml(content, path.name)
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="生成跨端设计 token 产物")
    parser.add_argument("--check", action="store_true", help="只校验，不写盘；有差异退出 1")
    args = parser.parse_args()

    files = outputs()
    if args.check:
        stale = []
        for path, content in files.items():
            try:
                current = path.read_text(encoding="utf-8")
            except FileNotFoundError:
                stale.append(f"{path.relative_to(ROOT)}（缺失）")
                continue
            if current != content:
                stale.append(str(path.relative_to(ROOT)))
        if stale:
            print("设计 token 产物与 design/tokens.json 不一致：", file=sys.stderr)
            for item in stale:
                print(f"  - {item}", file=sys.stderr)
            print(f"\n跑 `python {GENERATED_BY}` 重新生成；**不要**手改产物。", file=sys.stderr)
            return 1
        print(f"设计 token 一致：{len(files)} 个产物与 design/tokens.json 同步")
        return 0

    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")
        print(f"写入 {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
