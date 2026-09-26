// 生成与 exe 同目录的《使用说明.txt》。
//
// 用户要求：exe 生成时同一文件夹里放一个 txt，简要说明启动命令、配置设置与使用指南。
//
// 运行：dart run tool/make_guide.dart build      （目标目录，默认 build）
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quizsync_server/src/config.dart';
import 'package:quizsync_server/src/constants.dart';

/// 章节顺序（用户口径）：先首次配置 → 配对手机 → 热键 → 数据在哪 → 常用命令 →
/// 常见问题（后台运行方式放在这里）→ 关于（含项目地址）。
String guideText() => '''
$kServerProductName v$kServerVersion — 使用说明
================================================

一句话：在 Windows 上按热键截屏 → 自动调用 AI 识别 → 结果直接推给手机 App。
本程序不显示答案（手机是展示端）。

第一次用，照着下面第一到第四节走一遍就能跑起来：
先配 AI（第一节）→ 手机扫码配对（第二节）→ 按热键截图识别（第三节）。


一、首次配置（4 步，每步直接回车就用默认值）
------------------------------------------------
  第一次启动会一步一步问，一屏只问一项，输入数字即可。

  第 1 步 Provider：接口协议
      1 = openai-compatible   DeepSeek、OpenAI、通义千问、智谱、Kimi 等
      2 = anthropic           Anthropic 官方 Claude 接口
      3 = gemini              Google Gemini 官方接口
      （DeepSeek 属于第 1 种，别选成第 2 种）

  第 2 步 Base URL：服务地址
      1 = https://api.deepseek.com
      2 = https://api.openai.com/v1
      也可以直接粘贴自己的地址（不要带 /chat/completions 这种尾巴）

  第 3 步 API Key：形如 sk-xxxxxxxx（只存在这台电脑上，不是登录密码）
      DeepSeek 申请入口：https://platform.deepseek.com/api_keys

  第 4 步 Model：必须是「能看图」的多模态模型
      1 = deepseek-flash（默认）   2 = gpt-4o-mini
      3 = qwen-vl-max              4 = glm-4v-plus

  改配置不用重装，也不用重新走引导：在启动窗口里敲命令即可
      ai                       看当前配置
      set-api-key <key>        换 Key
      set-model <name>         换模型
      set-base-url <url>       换服务地址
      set-provider <id>        换接口协议（openai-compatible / anthropic / gemini）


二、配对手机
------------------------------------------------
  1) 手机与电脑连同一个 Wi-Fi；
  2) 手机 App 里点「扫码配对」，扫电脑窗口里那个二维码；
  3) 扫不出来就手动输入窗口里显示的「地址 + 配对码」，或者把那行
     quizsync://pair?... 链接发到手机上，在「扫码配对」页粘贴；
  4) 配好之后窗口状态里会显示已配对的手机名，之后不用再配对。

  配对码 5 分钟过期：过期且还没有手机连上时会自动换一个并重印二维码。
  想立刻换一个：在窗口里敲 pair。手机被吊销（App 里解除配对）后，
  它会从「已配对」列表里消失，需要重新扫码。


三、热键（只有两个动作，一个动作一条键）
------------------------------------------------
  截屏识别   ${ServerConfig.kDefaultHotkeyCapture}
      按一下：截取鼠标所在那块屏幕 → 立刻识别 → 结果推到手机。

  多页模式   ${ServerConfig.kDefaultHotkeyMultipage}
      按一下：进入多页模式并抓第 1 张（一题跨屏时用）；
      继续按：继续追加下一张；
      抓满 $kHardMaxPagesPerTask 张：自动上传识别，不用再按；
      没满：按「截屏识别」键立即结束多页并上传已抓的所有图片。

  改热键（在启动窗口里敲命令）:
      hotkey capture F10       改「截屏识别」热键
      hotkey multipage F9      改「多页模式」热键
      hotkeys reset            两个键恢复默认

  注意：热键是「全局」的，按下时应用里对应的按键会被抢走。如果提示
  registration failed，说明那个键被别的程序占用，换一个就行（窗口里会
  列出本机空闲的 F 键）。


四、数据与配置放在哪
------------------------------------------------
  默认就放在 exe 同目录的应用同名目录里（拷走整个文件夹就带走了配对与历史）:
      <exe 所在目录>\\QuizSyncAI_Server\\config.json    配置（AI 四项 + 热键 + 端口）
      <exe 所在目录>\\QuizSyncAI_Server\\state.json     状态（已配对手机 / 识别历史）
      <exe 所在目录>\\QuizSyncAI_Server\\images\\        截图原图
      <exe 所在目录>\\QuizSyncAI_Server\\server.log     日志（一直写，出错先看它）
      <exe 所在目录>\\QuizSyncAI_Server\\runtime.json   运行信息（退出时自动删除）

  exe 所在目录不可写（例如装在 Program Files）时会自动改用 %APPDATA%，日志里会写明。
  也可以用 --config <目录> 指定别的位置。

  启动标识：每次启动都会在状态里和 server.log 里记一行
  「第 N 次启动 · 首次 … · 上次 …」，一眼能看出这台机器上用过几次。


五、常用命令介绍（启动后直接在窗口里输入）
------------------------------------------------
  help          全部命令
  status        重新显示状态
  qr            重新显示配对二维码
  pair          刷新配对码并显示新二维码
  hidden        转到后台运行（窗口消失，服务继续跑）
  stop          停止服务
  devices       已配对的手机
  ai            当前 AI 配置
  hotkey ...    改热键（见上面第三节）
  hotkeys reset 热键恢复默认
  set-api-key / set-model / set-base-url / set-provider   改 AI 配置
  quit          退出（后台实例的命令行窗口里 = 只关这个窗口）


六、常见问题
------------------------------------------------
  1) 怎么让它后台运行（关掉窗口也继续跑）？
     三种方式，任选一种：
       · 已经在窗口里：直接输入 hidden
       · 启动时就后台：QuizSyncAI_Server.exe --hidden
       · 连黑窗口都不想看见（放「启动」文件夹 / 快捷方式用这个）：
         QuizSyncAI_Server.exe --background
     后台运行是「彻底脱离控制台」：窗口真的消失（不是最小化），关掉终端、
     关掉窗口都不影响它。条件都是「AI 已配置 + 至少配对过一台手机」；
     不满足时会保持窗口可见并说明缺哪一项（不然你没法扫码配对）。

  2) 后台运行之后窗口没了，怎么再敲命令？
     再打开一次 QuizSyncAI_Server.exe 就行：它不会起第二个服务，而是直接给
     那个后台实例当命令行窗口 —— 屏幕上会写「后台实例正在运行（PID …）· 端口 …」，
     你在这里敲的 status / qr / hotkey / stop 都送到那个进程上执行。
     只想明确要一个命令行窗口：QuizSyncAI_Server.exe --console。

  3) 关掉命令行窗口，服务会停吗？
     不会。后台运行脱离了控制台，窗口关掉、终端关掉都不影响它；
     只有 stop 或 --stop 才会停。

  4) 怎么停止服务？
     在它的命令行窗口里输入 stop，或在别处执行 QuizSyncAI_Server.exe --stop。

  5) 怎么确认它到底在不在跑 / 启动过几次？
     另开一个命令行执行 QuizSyncAI_Server.exe --status（会报在不在跑、端口、
     第几次启动、数据目录）。也可以直接看 <数据目录>\\server.log。

  6) 提示 hotkey registration failed：
     那个组合键被别的程序占用了，按提示换一个（窗口里会列出本机空闲的 F 键）。

  7) 按了热键没反应：
     先确认窗口里状态行的热键没有标「(未生效)」；有些输入法、投屏工具、截图工具
     会把特定按键「吃掉」（注册成功却收不到），换一个键即可：
     hotkey capture F10 / hotkey multipage F9。
     如果两个键都标着「(未生效)」而且换键也失败，重启一次本程序（热键注册跟着
     运行它的那条线程走，重启是最省事的复位）。

  8) 手机连不上电脑：
     确认同一 Wi-Fi、防火墙放行该端口、地址是电脑的局域网 IP（不是 127.0.0.1）。

  9) 识别失败：
     看窗口里的 [错误] 行（后台运行时看 server.log）；常见是 API Key 无效、
     余额不足、模型名不是多模态模型。

  10) 想换 AI 服务商：
     用 set-provider / set-base-url / set-model / set-api-key 改，改完立即生效。

  11) 查看全部启动参数：QuizSyncAI_Server.exe --help


七、关于
------------------------------------------------
  $kServerProductName v$kServerVersion
  项目地址（源码与更新都在这里）：
      https://github.com/iop666/QuizSyncAI

  它是「AI 双端搜题」的 Windows 端小工具：截图 → AI 识别 → 结果同步给手机。
  与桌面端共用同一套配对与结果协议，手机端不需要任何改动。
''';

Future<void> main(List<String> args) async {
  final outDir = args.isEmpty ? 'build' : args.first;
  final dir = Directory(outDir);
  if (!await dir.exists()) await dir.create(recursive: true);
  final file = File(p.join(dir.path, '使用说明.txt'));
  // 带 UTF-8 BOM：记事本等老工具打开中文才不会乱码。
  await file.writeAsBytes(
      [0xEF, 0xBB, 0xBF, ...utf8.encode(guideText())], flush: true);
  stdout.writeln('已生成：${file.path}');
}
