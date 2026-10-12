# QuizSync AI — Agent 执行入口（Flutter 正线）

> **本仓是 Flutter 正线**（GitHub: `iop666/QuizSyncAI`，默认分支 `flutter`）。原生线在另一个仓：`iop666/QuizSyncAI_Native`（默认分支 `native`，版本号带 `-native` 后缀）。
> 两条线**长期并存、互不影响**：各自独立历史、独立版本号、独立发布。本仓继续接需求、发版本。
> 两线共享四份契约（`SPEC.md` / `protocol.md` / `data-model.md` / `ai-contract.md`），改动须保持两边一致。





**一句话**：局域网内的跨端搜题工具。Windows 截屏 → 多模态 AI 解题 → 结果同步到 Android；Android 悬浮球截屏 → 上传 Windows 分析 → 结果回传两端显示。





本文件是 agent 的唯一入口。开工前按顺序读：本文件 → `docs/DECISIONS.md` → `docs/milestones.md` → 需要时再读 `docs/SPEC.md` / `docs/protocol.md` / `docs/data-model.md` / `docs/ai-contract.md`。





---





## 0. 无人值守工作守则（最重要）





你将在**没有人可以提问**的情况下持续工作。因此：





1. **不要提问、不要等待确认。** 遇到文档未定义的选择，按此优先级自行决定：


   ① 与 `docs/` 下的契约保持一致 → ② 选最小可行实现 → ③ 把选择与理由追加到 `docs/DECISIONS.md` 的「实施期决策」表格，然后继续往下做。


2. **每个里程碑结束必须提交一次**：跑通该里程碑的验收命令 → 把实际输出摘要追加到 `docs/progress.md` → `git add -A && git commit -m "M<n>: <一句话>"`。不要把两个里程碑混进一个提交，也不要一个里程碑拆成十几个提交。


3. **不得为了让测试通过而删改测试或放宽断言。** 测试确实写错时可以改，但必须在 `docs/DECISIONS.md` 里写清哪个测试、为什么原断言是错的。


4. **不得为了迁就实现而修改 `docs/` 下的契约。** 如果契约本身有误（例如字段缺失导致无法实现），改契约并在 `docs/DECISIONS.md` 记录原因；否则一律以契约为准。


5. **核心逻辑必须能在本机跑单测。** 这个机器上没有 Android 设备也没有模拟器（见第 1 节），任何放在 Kotlin 平台通道里的业务逻辑都无法被验证。协议、解析、同步、状态机一律写进 `packages/quizsync_core`，平台通道只做「取字节 / 显示窗口」这一层。


6. **不要安装需要管理员权限或需要注册账号的软件。** 依赖一律走 pub / Gradle 镜像。打包工具缺失时跳过该步骤并记录，不要为了打包去装 Inno Setup。


7. **碰到构建卡住先看第 1 节的网络事实**，`maven.google.com` 在本机不通，这是已知问题，不是你的配置错误。





---





## 1. 环境事实（2026-09-16 实测，不要重复探测）





| 项                       | 状态                                                                                                                                |


| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------- |


| Flutter                 | ✅ 3.47.0 stable，Dart 3.13.0，位于 `D:\Windows\Apps\flutter\flutter`                                                                  |


| Android SDK             | ✅ 36.0.0（platform **android-36**、build-tools 36.0.0），位于 `D:\Windows\Apps\Android\Sdk`                                             |


| adb                     | ✅ `D:\Windows\Apps\Android\Sdk\platform-tools\adb.exe`                                                                            |


| JDK（用于 Gradle）          | ✅ 17.0.18，位于 `D:\Windows\Apps\Java\jdk-17.0.18`，**已写入 `flutter config --jdk-dir`**                                                |


| 系统 PATH 里的 java         | ⚠️ 版本 **26**。不要用它跑 Gradle，AGP 不支持                                                                                                 |


| `JAVA_HOME`             | ⚠️ **未设置**。`flutter build` 会用上面的 jdk-dir，但直接调用 `gradlew` 前需要先 `export JAVA_HOME="D:\Windows\Apps\Java\jdk-17.0.18"`               |


| Visual Studio           | ✅ 生成工具 2026 18.8.0 + Windows SDK 10.0.26100（`C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools`），Flutter Windows 桌面可构建 |


| Android 模拟器 / 设备        | ❌ **都没有**。`adb devices` 为空，SDK 里没装 emulator，也没有 AVD                                                                               |


| .NET SDK                | ❌ 未安装（所以技术栈不选 .NET，见 `docs/DECISIONS.md`）                                                                                         |


| Inno Setup / NSIS / WiX | ✅ Inno Setup 6（`D:\Windows\Apps\InnoSetup\ISCC.exe`），安装包已固化进 `tools/build_all.ps1` 末步 |


| 本机 PowerShell | ⚠️ **5.1**（不是 pwsh 7）。`Get-Content`/`Set-Content` 默认按 GBK 读写，**用它改 UTF-8 源码会把中文改成乱码**（M10 实测损坏 7 个设置页文件，已用 git 恢复）。改文本一律用编辑器工具或 Python（显式 `encoding="utf-8"`），不要用 PowerShell 管道改写源码。**注意：`Get-Content <utf8文件>` 只是「显示」成乱码，文件本身是好的**（M11 实测虚惊一场）——怀疑文件被改坏时，用 `read` 工具或 Python 复核，不要急着重写 |


| 图标资源 | 两张源图在仓库根 `icon\`（`QuizSync_AI.png` 应用图标 / `Statusbar.png` 托盘图标）。重新生成：`cd apps\desktop; dart run tool\make_icons.dart` → 写出 `windows\runner\resources\app_icon.ico`（**带圆角**，Windows 不会替应用图标加圆角）、`assets\app_icon.png`（关于页用）、`assets\statusbar.ico`（托盘用）。产物已提交，平时不需要跑 |


| 数据目录 | 应用数据（库/图片/备份/导出/日志）默认在 **`<exe 所在目录>\userdata`**；不可写或有旧版数据时自动退回系统数据目录。写测试/脚本时不要假设 `%APPDATA%`。**注意 `<exe>\data` 是 Flutter 引擎载荷（`app.so`/`flutter_assets`/`icudtl.dat`），绝不能拿来放用户数据**（M11 实测：清理它会让程序起不来） |


| ⚠️ 交付红线（M11 实测踩到） | **不要在 `build\windows\...\Release\` 里直接跑 exe 之后就打包**：应用会把数据写到 exe 旁边的 `userdata\`，甚至把 `%APPDATA%` 下的真实库与截图搬进来，一打包就把用户数据打进交付物。`tools\package_windows.ps1` 现在**打包前强制删除并复核** `userdata`（zip 里也再查一次，`installer.iss` 额外写了 `Excludes: "userdata\*"`）。冒烟测试完请手动确认该目录已清掉。冒烟/采样请走 `tools\probe_memory.ps1`（在临时副本里跑、跑完清理） |


| 交付物带 VC 运行库（M26） | `tools\package_windows.ps1` 会在打包前把 VS 的 `VC\Redist\MSVC\<ver>\x64\Microsoft.VC*.CRT` **整目录 10 个 DLL** 复制进 `Release\`，并逐文件复核（zip 里再查一次）。所以 Release 目录里出现 `msvcp140*.dll` / `vcruntime140*.dll` / `concrt140.dll` / `vccorlib140.dll` 是**故意的**，不要当成垃圾清理掉 —— exe 动态链接 MSVC 运行库，缺了它们干净机器上双击就是缺 DLL。**注意必须排除 `\onecore\` 目录**：那是 OneCore/UWP 的精简版，同名但不同文件 |


| PowerShell 脚本编码 | `tools\*.ps1` 必须存成 **UTF-8 with BOM**：本机是 PowerShell 5.1，无 BOM 时会把 UTF-8 中文按 GBK 解码，脚本里的中文字符串/注释会把解析器搞崩（报 `The string is missing the terminator`）。新增/改写 ps1 后用 Python 写 `encoding='utf-8-sig'`。**另一个实测陷阱**：脚本里读原生命令输出**不要用 `2>$null`** —— stderr 的每一行都会被包成 ErrorRecord，而脚本开头是 `$ErrorActionPreference = "Stop"`，于是**第一行 stderr 就终止整个脚本**（M24 实测：`audit_android.ps1` 被 `apksigner.bat` 的 JVM 警告静默打断，只剩一个 exit 1、连 FAIL 汇总都没打印）；正确写法是临时 `Continue` + `2>&1` + 只保留 `$_ -is [string]` 的行 |


| 清理构建产物 | 删 `build\windows` 后必须 `flutter clean` + `pub get` 再构建：Flutter 的增量构建**不会**发现 `data\` 被删掉，会直接复用残缺输出（表现：exe 报 `Can't load AOT data ... app.so; no such file` 秒退） |


| ⚠️ `windowManager.setBrightness` 在 Windows 上是废的 | window_manager 0.4.3 的 Windows 实现把「应用要深色」和「系统当前是深色」做了 AND（`enable_dark_mode = light_mode == 0 && brightness == "dark"`，`light_mode` 读 `AppsUseLightTheme`）：**系统是浅色时永远无效**，标题栏白着。标题栏深浅一律走 `apps/desktop/lib/services/window_theme.dart` 自己调 `DwmSetWindowAttribute`（20 / Win10 1809 用 19；Win11 22000+ 再设 34/35/36 配色）。本机 `AppsUseLightTheme=1`，正好是必然复现的环境 |


| ⚠️ `GetSaveFileNameW` 的 `lpstrFile` 不能混用正反斜杠（M12 实测） | `Directory('$root/exports')` 会留下 `/`，拼出来的 `…\userdata/exports\x.md` 会被资源管理器对话框判为**非法文件名**，直接返回 0 并把 `CommDlgExtendedError` 置成 **`0x3002` = `FNERR_INVALIDFILENAME`**（注意：`0x3000` 段是 **FNERR_**，不是 CDERR_*）。所有交给对话框的路径走 `normalizeForDialog()`。另外「返回 0」要区分用户取消（错误码 0）与真实错误（非 0），后者必须报错而不是假装取消 |


| ⚠️ `RegisterHotKey` 是**线程级**的，Dart isolate 线程会被复用（M12 实测） | `RegisterHotKey(NULL, id, …)` 把热键绑在**线程**的消息队列上，而 isolate 退出 ≠ 线程退出（线程回 VM 线程池复用）：旧注册会跟着线程活下来，新 isolate 落到同一线程时同 id 注册失败（表现为「改了热键不生效、回退到别的键」），而**旧键照常生效**、它的 `WM_HOTKEY` 会被该线程上另一个槽位的轮询泵读走（表现为「按截图键执行了追加页」）。正确写法见 `apps/desktop/lib/services/hotkey_service.dart`：**单 isolate + 每槽位固定 id + 每次注册前 `UnregisterHotKey` + 退出前显式注销全部** |
| ⚠️ **长期存活的 isolate，线程号并不固定**：每条 `await` 之后都可能落在另一条池线程上（M45f 实测 28 秒 327 次换手） | 只要 isolate 让出执行权（`await Future.delayed` 这种），VM 就可能把它调度到线程池里的另一条线程。对「注册/句柄绑在线程上」的 Win32 调用（`RegisterHotKey`，以及任何 `hWnd=NULL` 的线程消息队列用法）这是致命的：持有注册的那条线程被 VM 收走 → 系统里的注册**悄悄消失**，进程还活着、界面还写着「F8」，按下去谁都不响应，**Win32 不给任何通知**；反过来，注册还在但泵跑在别的线程上时，`WM_HOTKEY` 会投递到没人读的队列。两个结论：① **要线程稳，就别 await**（Server 的做法：`PeekMessageW` + `Sleep` 的同步循环，命令改走共享内存轮询 + 就绪握手；代价是不能再用 `SendPort` 收消息）；② 无论怎么写，都留一道**定期自检**（Server：每 2 秒拿同一个 id 再 `RegisterHotKey` 一次 —— 还持有必然 1409，成功即说明丢了，顺手补回来）。桌面端的热键服务目前仍是 isolate + `await` 轮询，若收到「热键用着用着就没反应」的反馈，先按这两条查 |
| ⚠️ **全局热键现在是「两个 + 单按功能键」**（M46 第 1 条） | 桌面端默认热键 = **F8**（截屏识别；在多页模式里＝结束多页并上传已抓的图）与 **F9**（多页模式；抓满 6 张自动上传）。`hotkeyRejectReason` 给单按 F1–F12 开口子（单按字母/数字仍然要求带修饰键）；候选键表仍保留 `Ctrl+Alt+Q` / `Ctrl+Alt+A` 一类兜底。桌面热键服务已照 M45f 的结论**整条重写**：后台循环一次 `await` 都不做（同步 `PeekMessageW` + `Sleep(15)`）、命令走共享内存 + 就绪握手、每 2 秒「同 id 再注册」自检补回、线程异常自动重建，触发写 `热键触发：<槽位>（<键>）` |
| ⚠️ 本机 **F12 被别的程序占着**（M46 探针实测） | 拿空闲功能键当「负向对照」前必须先逐个试：启动前实测 F1–F11 空闲、**F12 注册返回 0（1409）**。第一版探针用 F12 做对照，把「App 确实持有 F8/F9」这个正确结论误判成了「判据不可信」 |
| ⚠️ Dart 的 `RegExp` **不支持** `(?m)` 这类内联标志（M47 实测） | `RegExp(r'(?m)^version:…')` 直接抛 `FormatException: Invalid group`；要写 `RegExp(r'^version:…', multiLine: true)`。而 PowerShell 用的是 .NET 正则，**支持** `(?m)` —— 同一段正则在 `tools\*.ps1` 与 Dart 里不能照抄（M47 写 `version_consistency_test` 时踩到） |
| ⚠️ 版本号**唯一来源**是 pubspec（M47 起） | `apps/desktop/pubspec.yaml`（桌面）/ `apps/android/pubspec.yaml`（安卓）是源：`package_windows.ps1` / `package_android.ps1` / `audit_android.ps1` 的 `-Version` 留空时从它读，`installer.iss` 由 `package_windows.ps1` 用 `/DAppVersion=<版本>` 传入（`#ifndef` 兜底默认值）。`Runner.rc` 与 `kAppVersion` 仍是手改，但 `apps/desktop/test/version_consistency_test.dart` 会断言三处一致 —— **改版本时只改 pubspec + 这两处，别再去脚本里找** |


| 分层窗口（悬浮球）的两个坑（M12 实测） | ① `UpdateLayeredWindow` 之前必须真的建好 DIB（`CreateDIBSection` + `_bits != nullptr`）——先给「当前尺寸」赋值会让「尺寸没变 → 不用建」的分支跳过建位图，窗口建出来却**什么都没画**（日志一切正常，屏幕上空的）；② **移动窗口别只靠 `UpdateLayeredWindow` 的 `pptDst`**，实测窗口位置不跟，要补一次 `SetWindowPos`。像素必须是**预乘 alpha 的 BGRA** + `ULW_ALPHA`，`WS_EX_NOACTIVATE` 防止点球抢焦点 |


| ⚠️ Flutter 引擎在 **Android 15（API 35）及以上不设状态栏底色**（M13 反编译实测） | 反编译本项目实际使用的引擎产物（`javap -p -c -cp <flutter>/bin/cache/artifacts/engine/android-arm64-release/flutter.jar io.flutter.plugin.platform.PlatformPlugin`）可见：`setSystemChromeSystemUIOverlayStyle` 里 `statusBarColor != null` 之后紧接 `if (SDK_INT >= 35) 跳过 window.setStatusBarColor`（`navigationBarColor` 同理），**只有图标明暗那支没有版本限制**（走 `WindowInsetsControllerCompat.setAppearanceLightStatusBars`）。所以「给状态栏显式配色」这条路在 15+ 机器上注定无效（M10/M11 连修两轮都被它挡掉）：底色必须**由 App 自己画**（`ThemedSystemUi` 的顶部条带），图标明暗走自家 Kotlin 桥（`quizsync/system_ui`）。另外引擎的 `enableEdgeToEdge()` 会 `decorView.setSystemUiVisibility(0)` **清掉 light-status-bar 标志**，再按自己的 `currentTheme` 恢复 —— 窗口获焦 / Activity 重建后必须由原生侧重贴，不能指望 Dart 的 `_latestStyle` 缓存 |


| ⚠️ 根节点的**紧约束**会把「虚拟画布」夹回窗口尺寸（M14 实测） | `MaterialApp.builder` 拿到的约束是**紧的**（= 窗口逻辑尺寸）。`Transform.scale(scale: 0.5, child: SizedBox(虚拟尺寸))` 里那个 `SizedBox` 会被夹回窗口尺寸 → 界面按窗口尺寸布局、再被缩小到一半，**只画在左上角**，其余是没有任何 widget 覆盖的区域（引擎清屏色，深色主题下就是「那片黑」）。要让子树按更大的逻辑尺寸布局，必须用 `OverflowBox(min/max = 虚拟尺寸)` 显式撑开（`apps/desktop/lib/app.dart` 的 `UiScale`）；判断「有没有铺满」用 `tester.getRect` 取缩放后的全局矩形，别只看尺寸日志 |


| ⚠️ 剪贴板里的 DIB 大多是 **`BI_BITFIELDS`**，且 `GlobalSize` 不可靠（M14 实测） | 本机用 `Clipboard.SetImage` 放一张 120×80 的图后枚举剪贴板：`CF_DIB` 存在、`GlobalLock` 成功、`GlobalSize=38452`，但 `biCompression = 3 = BI_BITFIELDS`（截图工具 / 浏览器 / .NET 都这么放图；`CF_DIBV5` 也在，头 124 字节）。**只认 `BI_RGB` 会「每一步都成功、最后静默返回 null」**，用户看到的就是「剪贴板监听毫无作用」。正确做法：`CF_DIB` → `CF_DIBV5` 依次试、按掩码取通道、像素字节数由 DIB 头自己算（`头 + 掩码(40 字节头 + BI_BITFIELDS 时 +12) + 4 字节对齐的行 × 高`，实测与 `GlobalSize` 完全吻合）。另外 `GlobalLock` 对 `CF_BITMAP`（GDI 句柄）返回 null，走不通；`biHeight` 为负 = 自上而下，读 int32 必须**真做符号扩展** |


| 悬浮球（分层窗口）切状态要缓存像素（M14 实测） | 球图是固定素材，原来每次切状态都 `decodePng` + `copyResize` + 逐像素预乘：进程内探针反复切 300 次（每 100 次改一次外观），RSS **163.5 → 216.6 MB 且仍在涨**（用户观感「打开悬浮球内存飙升」）。按「状态 + 尺寸 + 描边 + 透明度」缓存预乘 BGRA（上限 8 条，尺寸一变整体作废）后 **159.2 → 175.0 MB 并停住**，GDI/USER 句柄全程稳定。验证分层窗口渲染用 `PrintWindow(hwnd, hdc, 2)` 回读中心像素，不要用 GDI 截屏 |


| ⚠️ Riverpod 的 `ChangeNotifierProvider`：直接 `listen` 整个 provider 时 **`prev == next`**（M15 实测） | `settingsProvider` 是 `ChangeNotifierProvider<SettingsController>`，**它的值就是 controller 实例本身**：通知到达时 `prev` 与 `next` 是同一个对象，且两边读到的都是**已经更新过**的 `app`。于是「用 `prev.app` 与 `next.app` 比较签名」永远判定为「没变」，设置改完不生效（M15 第 1 条：悬浮球的大小/透明度/描边/开关**四项全都调不动**）。正确写法是 `provider.select((s) => 签名(s.app))` —— `select` 的 `prev/next` 才是真正的旧值/新值。`apps/desktop/test/settings_listener_test.dart` 把这个坑钉住了（断言 `identical(prev, next)` 且 `prev.app` 已是新值） |


| ⚠️ 上传图片要自己把 `local_path` 写进库（M15 实测） | 服务端 `_handleImageUpload` 原来「写完文件之后又 `getImage(hash)`」——写文件**不会**建 `images` 行，拿到的 `localPath` 必然是 null，于是手机传到 Windows 的图**永远没有缩略图**（主界面只有占位图标，结果页/「重新分析」也找不到原图）。要么用 `imageStore.pathFor(hash)`，要么显式 `setImageLocalPath`；**注意 `upsertImage` 的「有变化吗」判定不含 `local_path`**（本地专属列不进 op），只改这一列会走「无变化 → 直接返回」的短路 |


| 截屏前后恢复主窗口**不能抢焦点**（M15 实测） | `hideWindowWhile` 原来用 `ShowWindow(hwnd, SW_SHOW)` + 无条件 `SetForegroundWindow(hwnd)`：`SW_SHOW` 本身就会激活窗口，等于每识别一次都把主窗口抢到前台。用热键时看不出来（人本来就在本程序里），**用悬浮球时人在别的应用里，界面就自己跳出来**（用户反馈 M15 第 3 条）。恢复要 `SW_SHOWNOACTIVATE`，并且只有「藏之前本来就是前台窗口」时才还焦点 |


| 验证分层窗口别用 GDI 截屏 | 本机的 `CopyFromScreen` / `BitBlt`（DPI-unaware 进程）**拍不到**分层窗口，看截图会误判「球没渲染」。用 `PrintWindow(hwnd, hdc, 2)` 回读窗口自身内容，或从 Dart 侧断言位图。另外 `GetSystemMetrics(SM_CXSCREEN)` 返回的是**物理**像素（进程是 per-monitor DPI aware），而未 aware 的进程读 `GetWindowRect` 会拿到虚拟化坐标（本机差 2 倍），两边对比坐标时先统一口径 |


| ⚠️ `WM_TIMER` 是**优先级最低**的消息，长按判定不能靠它（M16 实测） | `SetTimer` 产生的 `WM_TIMER` 只在队列里**没有别的消息**时才生成。用户按住悬浮球不放时，松手产生的 `WM_LBUTTONUP` 会先被处理，`_endDrag` 顺手 `KillTimer` → 一次长按被判成**单击**（用户反馈 M16 第 2 条：「长按要等于右键」）。发布版探针实测同一条 700ms 长按：一次在松手后约 1.8s 才出现攒页效果，另一次松手 1.2s 后仍是「待识别」（采样窗口里状态一次都没变）。**手势判定改成松手时按按住时长结算**（`BallGestureTracker`），不依赖任何计时器消息，长按与右键走同一条分支 |


| 悬浮球描边必须**向外**画（要给画布留余量）（M16 实测） | 球素材是「主色圆 + 白色内芯」（`assets/floating_ball_*.png`，圆形铺满整张 256×256）。以「画布边缘半径」为中心往**里**画的环带，颜色又取状态主色 → 与球自己的主色完全相同、压在球上，**等于没有描边**（用户反馈 M16 第 1 条）。向外画就得把画布做大：`窗口 = 球 × DPR + 2 × 描边宽 × DPR`，环带落在「半径 ∈ [球半径, 球半径+描边]」。像素取证用 `PrintWindow` 回读中线剖面：新实现 x=0..11 = 加深色、x=12 起 = 球自身颜色；另外描边色按通道 ×0.72 加深才看得出对比 |


| 悬浮球外观只在「圆整后尺寸变了」时才重画 → 只改描边透明度会**一像素都不变**（M16 实测） | `applyAppearance` 原来只在 `px != _bitmapSize` 时才置 `_pixelsDirty`，而 `_render()` 开头就 `if (!_pixelsDirty) return;`。于是「描边透明度」这种不改尺寸的项调了等于没调（M15 第 1 条修了监听、但这一半仍漏着）。外观字段一改就置脏标记即可 —— 像素缓存按「状态+尺寸+描边参数」做键，重画不会多花力气 |


| 本仓库**没有**用 `dart format` 统一格式（M16 实测） | `dart format --set-exit-if-changed lib` 在 `apps/android` 会改动 22/25 个文件（作者手写换行），所以**不要**为了改一处的缩进就去跑 `dart format`（会得到几千行无关 diff）。手改缩进时用 Python 按行号加/减空格，别用 PowerShell 管道（见上文的 GBK 坑） |


| 想验证「某个手势/动作有没有抢前台」，先把主窗口**收进托盘再操作**（M16 实测） | 探针里 `GetForegroundWindow()` 前后对比不可靠（别的窗口可能自己关掉、焦点自然转移）。可靠做法：`PostMessage(mainWnd, WM_CLOSE)` 让应用隐藏到托盘（`IsWindowVisible=False`），再做那个手势，最后查 `IsWindowVisible` —— 只要走了 `_reveal()`（`windowManager.show()+focus()`）它必然变回可见。同一个探针里「缺 API Key 时的收尾提示」会把它带回来，正好证明这个检查有效。键盘/鼠标合成用 `SetCursorPos` + `PostMessage(WM_LBUTTONDOWN/UP)` 即可（分层窗口是 `WS_EX_NOACTIVATE`，不会因为合成点击而激活） |


| ⚠️ **不要用第二个 Flutter 引擎做桌面浮层**（M32 实测） | 悬浮窗要显示题目、按钮、公式还要能点 —— 看起来只能再起一个 Flutter 引擎（`desktop_multi_window` 那类）。实测结论是**不要**：多引擎要在新引擎上重注册 `path_provider`/`drift`/`sqlite3_flutter_libs` 才能读库，而 `window_manager`/`tray_manager` 都是**单窗口假设**的插件，重注册会把主窗口的托盘/窗口控制搅乱；`desktop_multi_window` 在 Flutter 3.4x 上也已不再维护。现在的做法是「Dart 离屏渲染 + 原生分层窗口」：布局是纯函数（可单测）、`PictureRecorder.toImage` 出像素、`UpdateLayeredWindow` 合成。**注意 widget 树不能这么用** —— 没有受支持的入口把指针事件送进离屏树，命中判定会退化成手写第二份坐标 |


| ⚠️ `tray_manager` 的勾选项必须是 `MenuItem.checkbox`（M32 实测） | 托盘菜单里想要一个「显示悬浮窗 ✓」的开关，用 `MenuItem(key: …, label: …, checked: true)` **在 Windows 上没有勾**：插件的 C++ 实现（`windows/tray_manager_plugin.cpp`）只在 `type == "checkbox"` 时才 `uFlags |= MF_CHECKED`，普通项的 `checked` 字段会被忽略。必须用 `MenuItem.checkbox(checked: …)` |


| ⚠️ 离屏渲染 widget 别用 `GlobalKey` 量高度（M33 实测） | 想把 `QuestionCard` 渲成位图（悬浮窗要公式/模块区分与主界面一致），第一版用 `GlobalKey` 在 `buildOwner.buildScope` 之后取 `currentContext.findRenderObject().size.height` —— `currentContext` 是 **null**，于是量到 0 高度、直接返回 null（白排一遍还查不出原因）。正确做法：把 `RenderRepaintBoundary` 放进 `RenderPositionedBox`（= `Align`），它会拿到**松约束**并按内容自然尺寸收拢，`boundary.size` 就是内容高度，`boundary.toImage()` 出的图正好是内容大小，**一遍排版一次出图**就够。另外 `Picture.toImage` 在 `flutter_test` 里必须包 `tester.runAsync`，否则 Future 永不完成、测试直接卡死（M32/M33 各踩一次） |

| ⚠️ 桌面浮层的「设置 → 界面」要**正交**，别让两项设置互相打架（M33 实测） | 悬浮窗第一版有「明暗模式（跟随/明亮/深色）」和「配色（6 套，其中一套是深色石墨）」两组设置，选「明亮 + 石墨」时按哪个？实测直接打架。改成：**配色只决定色系（6 套全是浅色），明暗由明暗模式决定**，两者正交。同类问题还有「拖拽区」：整窗可拖与内容区滚动/点选冲突，最终改成只有顶部第一栏能拖（用户也是这么要求的） |

| ⚠️ **`edit` 工具会剥掉 UTF-8 BOM**（M32 实测） | 用 `edit` 改过的 `tools\*.ps1` 与 `tools\installer.iss` 会**丢掉开头的 BOM**（实测：`installer.iss` / `package_windows.ps1` 只改一行版本号，BOM 就没了，`git show HEAD:<file>` 对比确认）。本机 PS 5.1 会把无 BOM 的 UTF-8 当 GBK 读 → 带中文的 ps1 **直接解析失败**（报 `Missing ')' in method call` / `The string is missing the terminator`；M32 的探针脚本就这么挂的）；`installer.iss` 无 BOM 则 Inno 按 ANSI 读、中文全乱码。**改完必须补 BOM**（Python：`b=io.open(p,'rb').read(); io.open(p,'wb').write(b'\xef\xbb\xbf'+b)`）。新建的 ps1 同理 |


| ⚠️ 原生分层窗口的**位置换算依赖 DPR，而 DPR 必须提前给**（M32 实测） | 悬浮窗首次显示时日志写「(1016,120) 尺寸 560×252」，看着没毛病，**探针实测窗口却落在屏幕中间偏左**：原生侧 `_dpr` 只在 `setFrame` 里更新，而 `setPosition(逻辑坐标)` 在那之前就被调用了 → 按 1:1 换成物理坐标，200% 缩放的机器上差了 2 倍。修法：加 `FloatWindowSurface.setDevicePixelRatio()`，在 `setPosition`/`show` 之前显式调用一次。**另一条教训**：`show()` 里打印的尺寸/位置是「首帧之前」的**占位值**（560×252 是字段默认值），真实几何要等第一帧贴上去才准 —— 日志打在 `setFrame` 之后，否则排查会被自己带偏一轮 |


| ⚠️ 用 PowerShell 改写文本还有两个翻车方式（M17 实测） | ① **`Set-Content -NoNewline` 传数组会把所有行拼成一行**（`-NoNewline` 是「不加分隔符」而不是「不加结尾换行」）：M17 用它改 `pubspec.yaml` 的版本号，整个文件被压成一行（`git checkout --` 恢复）。② `[System.IO.File]::ReadAllBytes('相对路径')` 走的是**进程 CWD**，不是 PowerShell 的 `Set-Location` 结果，写脚本时一律用绝对路径。改源码就用 `edit` 工具（或 Python `encoding='utf-8'`），PowerShell 只用来跑命令与看输出 |


| ⚠️ **不要用「注销热键」表达 UI 状态**（M30/M31 实测，用户连报两轮「热键失效」） | 「进热键设置页 → `unregister()` 全部热键，离开 → 重新注册」有一个隐藏前提：**页面一定会被卸载**。实测不成立 —— 窗口收进托盘 / 最小化时页面不 dispose，标志一直是 true，热键就被**永久**锁死：用户在页面里看不出异常（那里本来就不该触发），换到别的程序里按同样毫无反应（用户原话「重写为现在只有在点进自定义热键页面时不会触发，其他均可以」）。正确写法：**热键始终注册着**，在**触发那一刻**问一次「现在要不要吞掉」——`services/hotkeys.dart` 的 `gatedTrigger` + `_DesktopShell._hotkeyBlocked()`（页面挂载 **且** 本窗口是前台窗口，`appWindowIsForeground()`）。判断依据是当场的窗口状态而非任何「进/出页面」的书签，结构上锁不死；被吞掉的触发必须写日志（M30 就卡在「静默注销，什么都看不出来」） |


| ⚠️ 按窗口标题找自己的窗口，标题只能有 `kAppName` **一个来源**（M31 实测） | `screen_capture.dart` 的 `hideWindowWhile` 留着 M17 改名前的老标题字面量 `'QuizSync AI'`，而实际窗口标题是 `kAppName`「AI 双端搜题」→ `FindWindow` 返回 **0**、**主窗口从来没被藏**，只要窗口可见就被拍进发给 AI 的图（探针实测：`FindWindowW(NULL,"QuizSync AI")=0`，`FindWindowW(NULL,"AI 双端搜题")=主窗口句柄）。统一走 `findAppWindow(kAppName)`；**改应用名/窗口标题时，全仓库搜一遍老标题** |


| 非 ASCII 进 Windows 打包产物要看**各自的编码约定**（M17 实测） | 中文应用名要写进三个构建脚本产物：`Runner.rc` **已经有 `#pragma code_page(65001)`**（Flutter 模板自带），所以文件保持 UTF-8（无 BOM）即可，rc.exe 会按 UTF-8 解；`tools\installer.iss` **必须存成 UTF-8 with BOM**（Inno Setup 6 认 BOM；无 BOM 时按系统 ANSI 码页读，中文全变乱码），改完用 `System.Text.UTF8Encoding($true)` 重写一次；`windows\runner\main.cpp` 里的 `L"..."` 预标题**保持 ASCII**（MSVC 默认按系统 ANSI 读源码，除非加 `/utf-8`），真正的窗口标题由 `window_manager` 在启动时设置 |


| ⚠️ `Stack` 里的层级**只由孩子顺序决定**（后画的在上面），而「浮层被内容盖住」用 `findsOneWidget` 测不出来（M18 实测） | 安卓结果页那条「电脑正在识别中 / 识别完成」浮层 M16 起就存在，但被放在 `Stack` 的**第一个**孩子 → 被 `Positioned.fill` 的题目内容整片盖住，用户报「渲染在识别结果题目下」。**浮层 / 角标一律放在孩子列表末尾**；测试要在断言层级本身（`Stack.children.last` 是那个浮层、第一个是内容），只断言 `findsOneWidget` 在「画了但被盖住」时同样是绿的。另一个相关坑：想让整块面板半透明就用**它自己的底色 alpha**（`color.withValues(alpha: 0.85)`），别包 `Opacity` —— `Opacity` 会把文字/图标一起变淡，压在内容上反而更难读 |





| ⚠️ 用 `TextPainter` 手画的按钮文字/图标**必须按行高垂直居中**（M34 实测） | 浮动按钮里的文字图元如果直接 `rect = 按钮矩形`、按 `rect.top` 画，字形会**贴住按钮上沿**：23 逻辑像素高的按钮里，10.5pt 的字形带落在 y 0.5–8.5，下面空 14 像素 —— 用户看到的是「文字和边框异常」（看着像按钮画坏了）。正确做法是先 `floatParagraph` 量出行高，再把文字矩形放到 `button.top + (buttonH - tp.height) / 2`（顺便把量好的 `TextPainter` 挂到图元上，省掉每帧重排）。M33 的顶部图标按钮同样贴顶，这一轮一起修掉 |

| ⚠️ 悬浮窗内容区**不要**用「离屏 widget → 位图」整条管线（M34 实测，用户报「异常卡顿」） | M33 为了让悬浮窗与主界面格式完全同源，把 `QuestionCard` 用 `PipelineOwner + RenderView + RenderRepaintBoundary → toImage()` 渲成一张位图再合成。格式确实一致，但**每一次推帧**都要跑一整条 widget → 位图管线、还要出/贴一张高图（12 道长题 = 8000+ 逻辑像素高）。M34 改回 `TextPainter` 直排（`layoutQuestionContent`），并把排好的 `TextPainter` 按指纹缓存到 `FloatNode.painter` 上：命中缓存时每帧只做画布合成。同机基准（JIT，flutter_test）：整帧渲染 116 → 56 ms、一次悬停推帧 96 → 33 ms。**代价要写清楚**：公式按 LaTeX 源码显示 |

| ⚠️ `ImageByteFormat.rawStraightRgba` 会让引擎多做一次反预乘（M34 实测） | 分层窗口要的是**预乘 alpha 的 BGRA**：用 `rawStraightRgba` 取像素时引擎要先在 CPU 上把百万像素反预乘一遍，Dart 侧再乘回去（`b * a / 255`）。改用 `rawRgba`（本身就是预乘）后只需换通道序 + 乘一次窗口透明度，`UpdateLayeredWindow` 的语义与它天然一致。顺带把「透明度 100%」这条常见路径做成纯换通道、不做乘法 |

| ⚠️ 「纯净白」这类**中性**配色不能给绿色种子（M33 埋、M34 用户报） | 配色表每套只给一个 `seed`，它同时决定窗口底色（种子按 7%–13% 叠在白/近黑上）与主色。M33 给 `white` 填了 `0xFF16A34A`（绿，和「薄荷绿」`0xFF0F9D58` 几乎同色）→ 选「纯净白」也是满窗发绿（用户第 6 条）。改成中性灰蓝 `0xFF64748B` 后标题栏是 `235,237,240`（三通道差 5）。**教训**：种子色的语义是「整套配色的色相」，叫「白/灰」的配色必须给中性色 |



| ⚠️ **别在切换/轮询的那一刻显式释放引擎文本对象**（M35 实测，用户报「点按钮就崩」） | `TextPainter.dispose()` 会释放它持有的原生 `ui.Paragraph`。悬浮窗在「切极简 / 内容刷新」时重建内容并释放旧 paragraph，实测会让进程在 `flutter_windows.dll` 里以 `0xC0000005` 崩掉（点完几秒后、空闲时触发；用户原话「点击上面按钮来回点就崩溃」）。把释放去掉（交给 Dart GC）+ 内容缓存留两份（正常/极简），两条必崩路径都稳定。**排查教训**：四组对照只覆盖了 hover/滚轮、没覆盖用户报的「点按钮切换」，第一轮因此被带偏到像素路径上（还做了一次无用且观感更差的原生GDI 重构）——定位崩溃必须把用户描述的动作原样复现一遍 |

| ⚠️ **悬浮窗内容要「与主界面同源」就用离屏 widget 管线，但要按片**（M40 实测，用户两轮不接受公式显示成源码） | M34 为了治卡顿把内容改成 `TextPainter` 直排，代价是公式按 LaTeX 源码显示、化学式没上下标、表格退化。做法：直接用**主界面同一套 `QuestionCard`** 离屏渲染（`PipelineOwner + RenderView + RenderRepaintBoundary`，M33 那套），但**按 M39 的切片**出图 —— 一帧只出可见区那 1–2 片，所以「每帧跑一遍 widget 管线」的卡顿源头不存在。三个实测要点：① **只量高度时不要 `flushPaint`/`toImage`**（量一次 662 ms → 几十毫秒）；② 内容区底色**必须由渲染器铺满**，分层窗口里透明像素会直接露出桌面（探针实测读回是黑的）；③ 内容区没有图元了，合成器的内容键要靠 `contentSignature`（题目指纹 + 宽度/字号/配色/明暗）区分，否则「高度一样但内容不同」会命中错缓存；④ **片高要按渲染成本给**：图元直排很便宜（1024 逻辑像素/片提高命中率），而离屏 widget 管线**一片 260–660 ms**，片太小就会「每滚十几格重跑一次」→ 用户实测「默认模式滑动卡的不行」，富文本路线必须把片给到 8192 逻辑像素（通常整篇只有一片，滚动纯拷贝） |
| ⚠️ **长内容不能塞进一张位图：分层窗口的位图高度有硬上限**（M39 实测，用户报「悬浮窗在默认模式下显示不全被截断」） | 一块位图的高度被 `clamp(1, 8192)` **物理像素**卡住，而内容可以很长：用户真实数据里 20 题的识别结果内容高 **4659 逻辑像素**，DPR2 = 9318 物理像素 → 整块出图被截到 8192，滚到底部时最后 563 逻辑像素（约两题）永远看不见、那里是一片纯底色（取证：滚到底后内容区底部带 **颜色数=1、最常见色占比 100%**）。修法是**按片出图**（1024 逻辑像素一片）：一帧只要可见区覆盖的 1–2 片（+1 片预取），高度不再有上限，每片更小 ⇒ 首屏出图 571→324 ms，内存按片缓存上限封顶。**配套教训**：分片拷贝不能"一片一次连续 memcpy" —— 目标行距是**窗口宽**、被拷宽度是**内容区宽**，当成一整块连续内存拷会每行漂移（pw−bodyW）像素，内容被切斜；两侧有留白时必须逐行拷（M39 的 `⑫` 回归就是靠"底部一行必须是内容"抓出这个漂移的）。**还有一条**：切片的出图原点必须带 `bodyRect.topLeft` —— `layoutFloatWindow` 已经把内容图元平移到了内容区左上角（`n.intoBody(delta)`），原点写成 `(0, 片顶)` 会让内容整体下移一个表头高、右移一个左边距（用户报「不顶头 / 底部被识别按钮压住 / 左右边距不对等」）。取证：内容区首行有墨的物理行号 192 → 96（内容区顶就是 96）；`⑭` 回归把窗口坐标写进像素来钉住 |
| ⚠️ **热路径上别 `await` 纯同步的原生调用**（M38 实测，用户连报三轮「卡的不能用 / 1 fps」） | `FloatWindowPresenter._push` 原来是 `await window.setFrame(...)`，而 `setFrame` 的实现体里**一个 await 都没有**（纯 win32：写 DIB + `UpdateLayeredWindow`）。悬浮窗的滚轮/悬停回调是从**窗口过程**（原生回调）进到 Dart 的，此时排下的微任务要等**平台线程下一次唤醒**才会被跑到，而平台线程只在「有 Dart 定时器到期」或「来了新的窗口消息」时才醒 —— 同一份 exe 的 A/B：贴窗 await 在「有 200ms 定时器」时 1–6 ms、**没有定时器时 390–670 ms**，平均整帧 7 ms → 671 ms、帧率掉到 ~1 fps。修法是热路径**一次 await 都不做**（同步合成 + `unawaited(_blit(...))`，失败在 `catchError` 里写日志）。**诊断陷阱**：卡顿期间你会看到「合成」或「贴窗」段几百毫秒，但那只是**等待被调度**的时间挂在当前段上，别照着段名去优化渲染 —— 先用一个 0ms/200ms 定时器做 A/B，能立刻区分「这段真的慢」还是「根本没被调度」 |
| ⚠️ **分块缓存要按「用户能同时翻的状态组合数」留份数**（M38 实测，用户报「频繁点上面按钮崩溃」） | M36 每种块只留**一个**槽位，而顶部按钮是**来回切**的：`极简 × 锁定` 一共 **4 种外观组合**，两个指纹互相顶掉 → 实测 60 次点击出了 **192 张图**、RSS 冲到 **789 MB**、单帧 0.3–1.3 s（一张内容图 665×8192 ≈ 22 MB）。容量要给够：外观块 4、浮层块 6、内容块 2（一张 22 MB）。**取证口径**：日志里的 `出图 N 次 / 合成 M 帧` 一涨就知道在重出图 —— 点按钮的轮次里它应该几乎不涨 |
| ⚠️ **桌面分层窗口的「每帧出图」要拆成块缓存**（M36 实测，用户连报两轮「很卡」） | 原来的做法是每帧 `PictureRecorder → Picture.toImage → toByteData`（342×760@DPR2 就是每次 4 MB 回读）再逐像素换通道：同一套分段计时实测**每次推帧 40–52 ms，其中 38–52 ms 全在渲染段**。而滚动/悬停帧其实只改一点点内容。改成「窗口外观 / 内容区 / 浮层」三块各自按指纹缓存位图、每帧只在 Dart 里 memcpy 合成之后：滚动与悬停帧**完全不出图**（合成 5 ms、贴窗 2 ms），出图只发生在「新结果 / 切极简 / 改外观」。配套要点：指纹要**含 DPR**（漏了会复用错尺寸旧图）、输出缓冲要复用（否则每帧喂 GC 4 MB）、内容拷贝在整块可见时走**一次连续 memcpy**（别逐行 1140 次）、整窗透明度交给 `SourceConstantAlpha`（别每帧乘 4×100 万次） |

### 网络（本机实测，决定了构建能不能跑通）





| 目标 | 结果 | 影响 |


|---|---|---|


| `maven.google.com` | ❌ **20s 超时** | **Gradle 默认配置会卡死。必须在 `settings.gradle.kts` 里把 `google()` 换成阿里云镜像** |


| `maven.aliyun.com/repository/google` | ✅ 200 / 0.08s | 替代 `google()` |


| `maven.aliyun.com/repository/public` | ✅ 200 / 0.07s | 替代 `mavenCentral()` |


| `pub.dev` | ✅ 200 / 3.5s | pub 依赖正常 |


| `storage.googleapis.com` | ✅ 200 / 1.7s | Flutter 引擎产物正常 |


| `repo.maven.apache.org` | ✅ 200 / 1.6s | 备用 |


| `services.gradle.org` | ✅ 200 / 2.4s | Gradle 发行版可下载 |
| `github.com`（git push / fetch，M45i 实测） | ⚠️ **全局代理是坏的**：`http.proxy=127.0.0.1:31180`、`https.proxy=127.0.0.1:31181` 都不在监听 → 报 `Failed to connect to github.com:443 over proxy`。v2rayN 的 xray 端口**会变**（M45i 记的是 `10808`，第五轮实测已经是 **`10810`**）—— 用之前先 `Get-NetTCPConnection -State Listen` 查一下当前端口，别照抄旧值：`git -c http.proxy=http://127.0.0.1:<端口> -c https.proxy=http://127.0.0.1:<端口> …`；直连（`-c http.proxy= -c https.proxy=`）时通时不通，别依赖 | `gh`（2.100.0，已登录 `iop666`，有 `repo` 权限）走的是另一条路、一直可用，所以**查远端用 `gh api`、传代码用 git + 上面的代理**。另两个 PS 5.1 坑：① `gh api … --jq '<含空格的表达式>'` 会报 `accepts 1 arg(s), received N`，改成 `gh api <path> \| ConvertFrom-Json`；② `>` 重定向会把二进制输出写成 UTF-16（37 MB 的 tar.gz 头两字节是 `ff fe`），下载二进制用 `curl.exe -L -o <文件> <url>` |





Android 端 `settings.gradle.kts` 的镜像写法（M0 必须完成，否则后面所有 Android 构建都会卡死）：





```kotlin


pluginManagement {


    repositories {


        maven { url = uri("https://maven.aliyun.com/repository/google") }


        maven { url = uri("https://maven.aliyun.com/repository/public") }


        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }


        google()


        mavenCentral()


        gradlePluginPortal()


    }


}


dependencyResolutionManagement {


    repositories {


        maven { url = uri("https://maven.aliyun.com/repository/google") }


        maven { url = uri("https://maven.aliyun.com/repository/public") }


        google()


        mavenCentral()


    }


}


```





---





## 2. 技术栈（已锁定，不要更换）





**两端都是 Flutter / Dart，共享一个纯 Dart 包。**





选择理由（这些是实测结论，不是偏好）：


- Flutter 3.47 在本机**已经完全就绪并通过 `flutter doctor` 全部检查**，Windows 桌面与 Android 两条目标都可构建；本机**没有 .NET SDK**，选 .NET 需要先安装。


- 本项目最大的风险是两端协议与数据模型不一致。放进共享 Dart 包后，两端用的是同一份模型、同一份序列化、同一份同步引擎，从结构上消灭这类 bug。


- 本机**没有 Android 设备也没有模拟器**，安卓侧无法运行验证。把逻辑集中在共享包 + 本机单测，是把「无法验证」的范围压到最小的唯一办法。





已知代价（接受）：Flutter Windows 桌面比原生 WPF 多约 30–50 MB 内存、冷启动多约 0.5s。用户的要求是「占用低、速度快优先，其次 UI 美观」，这个代价在当前工具链现实下是划算的。





| 用途 | 选型 |


|---|---|


| 状态管理 | `flutter_riverpod` |


| 本地数据库 | `drift` + `sqlite3_flutter_libs`（自带含 FTS5 的 SQLite） |


| HTTP / WebSocket 客户端 | `dio` + `web_socket_channel` |


| Windows 内置服务端 | `shelf` + `shelf_router` + `shelf_web_socket`（纯 Dart，两端同一技术栈） |


| 二维码 | 生成 `qr_flutter`；Android 扫码 `mobile_scanner` |


| Windows 托盘 / 热键 / 截屏 | `tray_manager` / `hotkey_manager` / `win32`（GDI BitBlt，需 per-monitor DPI aware） |


| 密钥存储 | `flutter_secure_storage`（Windows 走 DPAPI，Android 走 Keystore） |


| 公式渲染 | M0–M5 先以等宽字体原样显示 LaTeX 源码；M6 再用 `flutter_math_fork`（纯 Dart，两端通用，不需要 WebView） |





### Android 平台通道（Kotlin，保持极薄）





| 能力 | 实现 | 优先级 |


|---|---|---|


| 截屏 | 前台服务 `foregroundServiceType="mediaProjection"` + 常驻复用单个 `MediaProjection`/`VirtualDisplay`/`ImageReader` | **主路径**（已定） |


| 截屏备选 | `AccessibilityService.takeScreenshot()`（API 30+） | 备选，设置项里可切换 |


| 悬浮球 | 原生 `View` + `WindowManager` `TYPE_APPLICATION_OVERLAY`（**不要**在 overlay 里跑 Flutter 引擎，避免第二引擎与生命周期坑） | 必须 |


| 版本 | `minSdk 26` / `targetSdk 34` / `compileSdk 36`；若 Flutter 生成值与编译冲突，以能编译通过为准并记录 |





### 打包





- Windows：`flutter build windows --release` → 压成便携版 zip。**仅当**机器上存在 `ISCC.exe` 时额外编译 Inno Setup 安装包，否则跳过并记录。


- Android：`flutter build apk --split-per-abi --release`（arm64-v8a / armeabi-v7a / x86_64），keystore 首次生成后备份到 `keystore/` 并在 `.gitignore` 排除明文口令。





---





## 3. 仓库结构（目标形态）





```


D:\ZCode\QuizSync\        （Flutter 正线仓库，GitHub: iop666/QuizSyncAI）


├── AGENTS.md                  ← 本文件


├── README.md                  ← 给人看的：怎么跑、怎么构建、怎么配对


├── .gitignore


├── docs/


│   ├── DECISIONS.md           ← 已定决策 + 实施期决策追加表


│   ├── SPEC.md                ← 功能规格


│   ├── protocol.md            ← 局域网协议契约


│   ├── data-model.md          ← SQLite 表结构与同步算法


│   ├── ai-contract.md         ← prompt 全文 + AI 输出 JSON schema + 标绿规则


│   ├── milestones.md          ← M0–M7 任务与验收


│   └── progress.md            ← 每个里程碑的完成记录与验收输出


├── packages/


│   ├── quizsync_core/         ← 纯 Dart 共享包（协议 / 模型 / drift / 同步引擎 / AI 客户端 / 解析）


│   └── quizsync_ui/           ← 两端共享 Flutter 组件（题目卡片 / 配色 / 会话导航）


│       ├── lib/


│       └── test/


├── apps/


│   ├── desktop/               ← Flutter Windows 端（内含 shelf 服务端）


│   └── android/               ← Flutter Android 端（内含 Kotlin 平台通道）


├── tools/


    └── build_all.ps1          ← 一键：analyze + test + 两端构建


└── server/                    ← 独立 Windows 服务端（纯 Dart CLI：全局热键截屏 → AI → 手机；主项目零改动，见 server/README.md）


```





---





## 4. 构建与验收命令





```bash


FLUTTER=/d/Windows/Apps/flutter/flutter/bin/flutter


DART=/d/Windows/Apps/flutter/flutter/bin/dart





# 依赖


(cd packages/quizsync_core && $FLUTTER pub get)


(cd apps/desktop        && $FLUTTER pub get)


(cd apps/android        && $FLUTTER pub get)





# 静态检查 + 单测（每次改动都要跑）


(cd packages/quizsync_core && $FLUTTER analyze && $DART test)


(cd apps/desktop        && $FLUTTER analyze)


(cd apps/android        && $FLUTTER analyze)





# 构建


(cd apps/desktop && $FLUTTER build windows --release --no-tree-shake-icons)


(cd apps/android && $FLUTTER build apk --split-per-abi --release --no-tree-shake-icons)





# 一体化（推荐：上面全部步骤 + 打包成 dist\ 交付物，末行打印 ALL GREEN）


powershell -File tools/build_all.ps1





# 只读的交付物安全审计（包名/版本/权限白名单/备份策略/明文开关/签名/包内红线；三个 ABI 共 60 项）


powershell -File tools/audit_android.ps1





# 内存探针：对真实 release exe 采样 RSS / 私有内存 / 句柄 / GDI / USER


# （在临时副本里跑，不污染 build 目录；发现已有实例在运行会直接 ABORT，绝不替你杀进程）


powershell -File tools/probe_memory.ps1


```





**不需要设备的集成测试**（这是本项目最重要的自动化验证手段，M4 起必须存在）：


在 `packages/quizsync_core/test/` 下起一个 shelf 服务端监听 `127.0.0.1` 随机端口，用一个假的 AI provider 返回固定 fixture，然后走完整链路：`配对 → 上传图片 → 创建任务 → 轮询/WS 收到结果 → 校验 JSON 字段 → 校验同步 op 生成`。它在 CI 与本机都能跑，覆盖了除「真实像素」和「真实 AI」之外的全部协议逻辑。





---





## 5. 里程碑索引





详细任务、验收命令与 DoD 见 `docs/milestones.md`。





| 里程碑 | 内容 | 能否无人值守验证 |


|---|---|---|


| M0 | 脚手架、镜像、双端空壳可构建 | ✅ 完全可验证 |


| M1 | 共享核心：协议模型 + drift schema + 单测 | ✅ 完全可验证 |


| M2 | AI 接入：prompt、JSON 解析、容错、重试、假 provider | ✅ 完全可验证（用 fixture） |


| M3 | **Windows 单机闭环**：截屏→AI→多题显示（标绿）→落库→历史导航 | ✅ 除真实 AI 外可验证（真实 AI 需 Key） |


| M4 | 网络层：shelf 服务端 + 配对 + WS + 回环集成测试 | ✅ 可验证（loopback） |


| M5 | Android 采集：悬浮球 + 前台服务 + MediaProjection | ⚠️ **只能验证「编译通过 + 逻辑单测」**，真机行为需人工 |


| M6 | 同步与离线队列、公式渲染、搜索/收藏/导出/备份 | ✅ 逻辑可验证 |


| M7 | 打包、签名、日志、README | ✅ 可验证（安装包可选） |


| M8 | 需求第 2 轮：任务合集 / 多页识别 / 题目不全与 AI 猜测 / 题号 / 缓存上限 / 双端界面与导航重做 / 主题三态 / 安卓识别模块二级页与悬浮球手势 / 合集导出 / 历史删除 | ✅ 除「安卓真机手势与截屏像素」外全部可验证（analyze + 单测 + 两端构建） |


| M9 | Windows 设置页重构：左侧固定导航 + 7 个分类页（显示设置 / API 配置 / 连接设备 / 识别设置 / 热键设置 / 数据管理 / 关于），统一 8px 间距与基础组件，不改任何设置项的功能与落库键位 | ✅ 完全可验证（四包 analyze + 单测；`settings_shell_test` 逐项断言原有功能与最小窗口不溢出） |


| M10 | 用户反馈轮 15 项：MiSans 字体 + 题目字重 + 界面缩放 50–300% / 热键模块与设置页重写 / 图标字体不裁剪 / 托盘图标 / 主机本地识别也广播状态 / 安卓端 9 项（当前任务页只做结果显示器、静默执行、状态栏跟随主题、首开不自动扫码、悬浮球默认右侧等） | ✅ 除「安卓真机手势/状态栏/悬浮球初始位置」外全部可验证（analyze + 单测 + 两端构建 + exe 冒烟 + LoadImage 验图标） |


| M11 | 用户反馈轮 2 共 16 项：圆角应用图标 + 关于页用应用图标与字体许可 / 导出弹「另存为」且数据放软件目录 / 设置白底模块与去动效 / 缩放下拉档位并自动调整窗口 / API 默认 DeepSeek + 进连接页自动刷配对码 / 多页硬上限 6 / 双端静默互显（含下一轮悬浮窗）/ AI 不确定标黄 / 阅读材料折叠与主观题结构化 / 多页自行排序与材料页 | ✅ 除「安卓真机的新交互」外全部可验证；`questions.material` 是**唯一一次动数据模型**（schemaVersion 3），已写 v2→v3 迁移与往返测试；人工清单见 `docs/manual-test-android.md` 第 16–23 项 |


| M12 | 用户反馈轮 3 共 12 项：托盘圆角图标 / **导出全部失败的真凶**（`FNERR_INVALIDFILENAME`）/ 设置标题带底色与模块间距 / 连接设备去双层背景 / 热键页暂停热键 / **热键串键根因**（线程级注册泄漏）/ 「恢复默认热键」/ 序号移到题号徽标外 / 缩放跟住内容边界 / 安卓长文本换行 / **Windows 悬浮球**（原生分层窗口三态）/ MiSans 链接 | ✅ 除「安卓真机观感」与「悬浮球点击后的完整识别链路（需 API Key + 已选合集）」外全部可验证：四条 bug 都先用发布版探针/真跑拿到证据再改，另有 `PrintWindow` 回读球面像素、窗口尺寸前后对照；人工清单见 `docs/manual-test-android.md` 第 24 项 |


| M13 | 用户反馈轮 4 共 1 项：**安卓状态栏跟随主题**（第三次报同一条） | ✅ 除「真机观感」外全部可验证：反编译引擎产物拿到硬证据（Android 15 / API 35 起 `PlatformPlugin` **跳过** `setStatusBarColor`），故改为「App 自绘底色条带 + 自家 Kotlin 桥设图标明暗并在获焦/回前台重贴 + 启动窗口系统栏透明」三层，新增 3 条回归；人工清单见 `docs/manual-test-android.md` 第 25 项（**必须装构建 4**，构建 2/3 在此条上注定无效） |


| M14 | 用户反馈轮 5 共 8 项：**缩放黑块真凶**（紧约束把虚拟画布夹回窗口） / 设置 ⓘ 变成真能弹说明 / **剪贴板监听真凶 `BI_BITFIELDS`** / 悬浮球默认开 + 渲染缓存（RSS 216→175 MB） / 配对成功切「当前任务」 / **双端静默互显回归**（本机截屏误触发弹窗钩子 + 手机漏掉断线期间的推送） / 手机图片与本机截图同目录 + 安卓固定留 20 张并去掉缓存选项 / 主界面标题前显示应用图标 | ✅ 除「安卓真机」与「悬浮球在用户机器上是否显示」外全部可验证：剪贴板与缩放都先用探针跑出证据（真实剪贴板 DIB、`ui_scale_test` 断言铺满），悬浮球内存用进程内 300 次切换探针量化，双端互显有 core 侧真服务端+真 WS 客户端回环测试；人工清单见 `docs/manual-test-android.md` 第 26 项（**构建 5**） |


| M15 | 用户反馈轮 6 共 4 项：**悬浮球四项设置全都调不动**（Riverpod：直接 `listen` `ChangeNotifierProvider` 时 `prev == next` → 改走 `select`）/ **手机上传的图在 Windows 没有缩略图**（上传处理器写完文件后又查库，`local_path` 恒为 null）/ **悬浮球识别后主窗口自己跳出**（`hideWindowWhile` 恢复用 `SW_SHOW` + 无条件 `SetForegroundWindow`）/ 安卓「当前任务」加 1 秒轮询兜底（WS 仍保留） | ✅ 除「截屏恢复不抢焦点」这条（只有 Windows 既有语义 + 人工复看）外全部可验证：悬浮球设置经发布版复核（`ball_size=96` → 球窗口 112→192px；`ball_enabled=0` → 无球窗口），缩略图链路有真服务端 + 真 HTTP 上传 3 条，监听语义有 3 条断言把 Riverpod 的坑钉住；人工清单见 `docs/manual-test-android.md` 第 27 项（**构建 6**） |


| M16 | 用户反馈轮 7 共 3 项：**悬浮球描边要向外 + 加深**（原来以画布边缘为中心往**里**画，颜色又和球自身主色相同 → 等于没有描边；改成「画布 = 球 + 两侧描边余量」+ 通道 ×0.72 加深，抽成纯函数 `services/ball_paint.dart`）/ **左键长按 = 右键**（原来靠 `WM_TIMER`（队列最低优先级）判长按，松手消息先到就被判成单击；改成松手时按按住时长结算 `BallGestureTracker`，两条分支合成一条）/ **停在结果页也看得见电脑进度**（结果页加浮层「电脑正在识别中…／识别完成，正在打开新结果…」，用新加的 `ActiveTask.hostInitiated` 排除本机识别回声，跳页仍只有「当前任务」页一个出口） | ✅ 除「安卓真机观感」外全部可验证：描边方向/配色与手势语义都用**发布版 exe + `PrintWindow` 回读像素 + 合成鼠标消息**取证（新实现窗口 136px、球外 12px 是 `#1560B5`；日志出现「左键长按 / 单击 / 右键」三条；主窗口收进托盘后做多页手势仍保持隐藏=静默）；安卓侧 5 条 widget 测试含「真实结构下新结果页被推上来」；人工清单见 `docs/manual-test-android.md` 第 28 项（**构建 7**） |


| M17 | 用户反馈轮 8 共 6 项：**悬浮球默认 40 / 70% / 描边开·宽 4·不透明 25%** + 描边垫在球**下面**并向内重叠 2 填缝（几何改动在 `composeBallFrame(insetPx:)`）/ **中文名「AI 双端搜题」**（窗口标题·托盘·exe 属性·安装包·AndroidManifest label 全改，项目名仍 `QuizSync AI`）/ **关于页补 GitHub 地址**、两端版本统一 `1.0.0` / **安卓前台轮询再次漏刷新**（两个根因：只记「我通知过什么」→ 加 `uiSignature` 比对界面；`done` 的跳过条件看本地库 → 改成看界面）/ **Windows 删合集同步到安卓**（core 本来就能同步，缺的是触发：`/tasks/active` 加 `ops_lamport`，水位涨了就 `pullFromPeer` 只拉不推）/ **API Key 页给出 DeepSeek 申请入口** | ✅ 除「安卓真机观感」外全部可验证：core 有「真服务端删合集 → 客户端 pull-only → 本地也没了」的集成测试；安卓新增 3 条轮询测试（补发 / 尊重忽略 / 同图复用仍通知）；桌面用 `ball_paint_test` 钉住向内重叠与默认值；exe 显示名与版本用 `VersionInfo` 复核；人工清单见 `docs/manual-test-android.md` 第 29 项（**构建 8**） |


| M18 | 用户反馈轮 9 共 4 项：**1.0.0 就是正式版、界面不再写构建号**（两端关于页只显示 `v1.0.0`，删掉 `kAppBuildNumber`；出包序号只留 pubspec `1.0.0+9`，仅供 `versionCode` 覆盖升级）/ **安卓端可长按选中合集并批量删除**（多选操作栏 + 二次确认，不级联删记录）/ **结果页浮层画在最上层 + 底色 85% 不透明**（`Stack` 孩子顺序：后画的在上；只淡底色、文字仍完全不透明）/ **合集同步改走「主机活跃列表镜像」**（`/tasks/active` 带 `collections` + 轮询首次即回调 + `mirrorCollections` 只增改不删）并**反转 M17 第 5 条**：Windows 删合集不再让安卓跟着删（`applyRemoteCollectionDeletes: false`） | ✅ 除「安卓真机观感」外全部可验证：core 新增镜像 6 条 + 活跃列表 2 条 + 端到端镜像 1 条（192 项全绿）；安卓新增 5 条（合集镜像首次即回调 / 失败重试 / 只靠轮询就看得见主机合集 / 长按多选删除 / 浮层层级与 0.85 透明度），83 项全绿；ui 21、desktop 132 不变；人工清单见 `docs/manual-test-android.md` 第 30 项（**出包序号 9**，用「关于页有没有（构建 N）括号」分辨新旧包） |


| M19 | 用户反馈轮 10 共 3 项：**顶栏药丸改报配对状态**（`已配对设备：安卓设备` / `未配对`；服务没起来仍写 `服务未启动`，端口退到 tooltip；文案走纯函数 `serverPillLabel`，安卓端按平台统一写「安卓设备」）/ **Windows 端随时都能删合集**（「切换任务合集」弹窗每行加垃圾桶 + 二次确认，删的是当前合集就退回未选中，不级联删记录）/ **安卓识别模块写明耗时代价**（`kRecognitionSlowNote` + `RecognitionSlowNote` 警示条，挂在开关下方与二级页顶部） | ✅ 除「安卓真机观感」与「真服务端下的药丸文案」（单测里 `DesktopServerController.server` 只在 `start()` 成功后才有值）外全部可验证：桌面新增 5 条纯函数断言 + 2 条 widget 断言（tooltip 里的配对状态来自库、吊销的不算）+ 1 条弹窗删除用例（取消 / 确认 / 记录仍在），安卓在两条既有用例里补「说明存在且文案与常量相等」；四包 analyze 无 issue、测试全绿；人工清单见 `docs/manual-test-android.md` 第 31 项（**出包序号 10**） |


| M20 | 用户反馈轮 11 共 2 项：**药丸的配对状态不更新**（一直显示「未配对」）—— M19 的药丸只在挂载时查一次库、没有任何失效时机，「App 先开着、手机后来才扫码配对」永远看不到；新增 `CoreRepository.watchDevices()`（`devices` 表的 drift 流）并把桌面 `_pairedDevicesProvider` 由 `FutureProvider` 改成 `StreamProvider`，配对与吊销即写即变 / **物理公式整段显示成源码**（双端）—— 真凶是定界符：模型对物理题吐 LaTeX 原生的 `\(…\)`，而 `MathText` 只认 `$…$`；改为认四种定界符（`$$…$$` / `\[…\]` / `$…$` / `\(…\)`），`$` 路径逐字不变 | ✅ 两条都先复现/取证再改：药丸那条新用例改前是红的（真服务端 + 真 HTTP 配对 + 真吊销的 core 集成测试另钉一遍）；公式那条从用户真实库里读出「数学题 37 处 `$…$` 正常、物理题 10 处 `\(…\)` 一处 `$` 都没有」，用例文本直接用库里的原文；四包 analyze 无 issue、测试全绿（core 193 / ui 25 / desktop 137 / android 83）；人工清单见 `docs/manual-test-android.md` 第 32 项（**出包序号 11**） |


| M21 | 用户反馈轮 12 共 2 项：**展开材料时公式/化学式/表格显示不清晰**（`MathText` 重写成内容块渲染器：裸化学式 `ZnCO3`/`Fe2+` 切出化学小标、材料里的空格对齐表与 Markdown 表画成真表格、`$$…$$` 与超长行内公式搬成可横向滚动的块级、行内公式改 `MathStyle.text`、`⇌` 借 KaTeX 字形）/ **删掉顶栏配对药丸**（M19 加、M20 修的 `_ServerPill` 整条链路按用户要求移除，配对状态回到「设置 → 连接设备」独家承担） | ✅ 除「真机观感」外全部可验证：先用用户真实数据取证（15 条记录 / 59 题：裸化学式 36 处、空格对齐表 4 题、行内公式 308 条最长 84 字符、`⇌` 10 次、逐字符核对随包字体只缺这一个字）；ui 新增 15 条用例（分块解析 / 化学式判定与上下标方向 / 表格 / 展开材料后就地出表 / 窄屏不溢出），**测试先逼出一个真 bug**（纯文本快路径漏判化学式）；四包 analyze 无 issue、测试全绿（core 193 / ui 40 / desktop 133 / android 83）；人工清单见 `docs/manual-test-android.md` 第 33 项（**出包序号 12**） |


| M22 | 用户反馈轮 13 共 1 项：**化学式里电子的负号 `e⁻` 显示成普通 `-`**，且「`2H₂O - 4e⁻` 里减号与负号要分开」 | ✅ 先核对真实数据（用户的导出里 `e-` 28 次、`e⁻`/`e−` 各 0 次 → AI 写的是普通连字符，要在渲染时上标）；`_chemRe` 增加 `e[+\u2212-]` 电子写法，并把结尾后顾断言收紧为 `(?![\dA-Za-z])`，让 `2H2O-4e-`（不留空格）里的减号不被当成电荷；`isChemicalFormula` 放行小写 `e`；ui 新增 4 条回归（`Cu2+ + 2e-`、空格版与无空格版的 `2H2O-4e-=O2+4H+`、`e-mail`/`1e-5` 不误伤），测试全绿（core 193 / **ui 44** / desktop 133 / android 83）；人工清单见 `docs/manual-test-android.md` 第 34 项（**出包序号 13**） |





> 顺序是刻意的：M3 就交付「PC 截屏 → 出答案」这个核心价值，M5（风险最高、最不可验证）排在后面，且前面所有工作都不依赖它。





### M23–M27 · 优化轮（用户提供方案 → 审阅成 `docs/optimization-plan.md` → 执行）





| 里程碑 | 内容 | 能否无人值守验证 |


|---|---|---|


| M23 | 优化轮 1：静态基线收口（`packages/quizsync_core` 补 `flutter_lints`、两个 app 包加 `unreachable_from_main`；修 core 14 条 + desktop 1 条死代码） | ✅ 完全可验证：`unreachable_from_main` 第一次跑就报出 `tool/make_icons.dart` 里没人引用的 `debugCornerTransparent`（已删）；lint 还抓出一条**写错的测试断言**（`o.entity == 'snapshot'` 拿枚举和字符串比，恒为 false）；四包 analyze 0 issue、测试数不变（193 / 44 / 133 / 83） |


| M24 | 优化轮 2：安卓交付物安全审计（`allowBackup=false` + `dataExtractionRules` 排除换机直传、配对 token 换 EncryptedSharedPreferences、包名换 `com.quizsync.android`、新增 `tools/audit_android.ps1` 并挂进 `build_all.ps1`） | ✅ 60 项审计全绿且**负向运行会红**（错版本号 / 不存在的 APK 各测一次）；否决了要上传 APK 到第三方的 `flutterguard_cli` 与会关掉明文 HTTP 的 `flutter_build_guard --fix`。除「真机装新包 / 重新配对 / 备份策略」外全部可验证；人工清单第 35 项 |


| M25 | 优化轮 3：内存与泄漏（14 处 disposable 静态审计 + 负向对照证明「挂起计时器」检查有效 + 新增 `tools/probe_memory.ps1`） | ✅ 14 处**全部有释放**、无需修的泄漏（服务端那条订阅经逐路径核对为不可达，按不改记录）；负向对照实测确实会红；release exe 稳态 RSS **277 MB、漂移 -1 MB**、句柄/GDI/USER 平稳。「进出 50 次」那条**未做**（进程外没有 UI 驱动接口），替代口径写在 `progress.md` |


| M26 | 优化轮 4：便携版随包 VC 运行库（10 个 DLL / 1.9 MB、三重复核，**排除 onecore 精简版**）+ `docs/DEV.md` 新增 Windows 崩溃取证流程 | ✅ zip `entries=64`、`userdata=0`、10 个 DLL 与 desktop 版源目录**逐文件哈希一致**、安装包由 ISCC 重新编译；⚠️ 无法在真正干净的机器上验证（本机装了 VS，系统里本就有运行库） |


| M27 | 优化轮收口：交付复核（出包序号 +1、`tools/build_all.ps1` 全量重打并过审计、产物逐项复核、文档同步） | ✅ 见 `docs/progress.md` M27 一节 |





### M28–M38 · 用户反馈轮（代码清理回退 + 热键两连修 + Windows 悬浮窗六轮）





| 里程碑 | 内容 | 能否无人值守验证 |


|---|---|---|


| M28 | 公共 API 出口审计（`tools/dead_code_scan.dart`，删 3 处真死代码） | ⚠️ **M29 已整条回退**（用户报「热键失效」）；工具与两类误报口径记在 `docs/DECISIONS.md` |


| M29 | 按用户要求 `git revert` M28（保留历史）；**取证结论**：热键失效与清理无关，源码从 M22 起一行没动，根因是默认键 `Ctrl+Alt+Q` 被别的程序占用而应用按设计回退到 `Ctrl+Alt+X` | ✅ A/B 实验（带/不带随包 CRT 的两次启动日志逐行一致）+ 独立注册探针（Q 被占用、X/A/S/G/W 空闲） |


| M30 | **热键失效真凶（第二次）**：进热键设置页会**静默注销**全部热键，而在该页**改键/重置**又经 `_setupHotkey()` 把键注册回去 → 用户「按半天没反应，改一下键就突然能用」。修：暂停期间真的不注册 + 暂停/恢复写日志 + 识别失败把窗口带回前台 + 设置页写清「在这里按键不会有反应」 | ✅ 在用户**正在跑的实例**上注入按键复现（同一键在全新进程注册却成功 = 它当时没持有该键） |


| M31 | **用户拍板重写抑制范围**：热键**永远注册着**，抑制改到**触发那一刻**判断（页面挂载 **且** 本窗口前台）；顺手修掉 `hideWindowWhile` 用旧标题找窗口导致**主窗口从未被藏**（自己的界面被拍进 AI 请求） | ✅ 日志取证（暂停后再无「恢复」行 = 页面没被卸载）+ 标题探针 + 3 条闸门单测（desktop 136 项全绿）+ 全量 `build_all.ps1` ALL GREEN |


| M32 | 用户反馈轮 14（**只动 Windows**）：**悬浮窗**（12 条细则：置顶/拖动锁定/透明度与无极比例/窗内字号与重新识别/20:9 与拉伸边界/默认右侧不贴边与归位/顶部模块与七个按钮/极简模式/底部两个识别按钮与多页三按钮/识别中浮层与取消/明暗模式/默认关闭） + 安装目录改英文 `QuizSyncAI` + 「连接设备」默认关闭的开关（打开才起服务、才申请网络权限） + 托盘两个浮层开关 + 设置第一项改「使用说明」 + 版本 1.0.1 | ✅ 除「真机上肉眼观感」外全部可验证：布局/命中区/极简模式/多页按钮组/渲染格式都有单测（`float_window_view_test` 9 条、`float_window_presenter_test` 10 条），设置页十个分类与开关状态有 `settings_shell_test` 钉住 |


| M33 | 用户反馈轮 15（**只动 Windows，15 条**）：悬浮窗**默认竖屏 9:20**；顶部按钮改**图标 + 悬停提示**并重排顺序；**只有顶部第一栏能拖**；删掉「识别中禁用两个按钮 + 取消识别」；内容**改为主界面同一套 `QuestionCard` 离屏渲染**（公式/模块区分与主界面一致）；极简模式改成**只看题目答案**；题号**只去掉尾随点号**（序号仍显示）、后面跟上**题型与把握率**；**6 套浅色配色**；识别中提示贴内容区**下部**；**删掉边界拉伸**只留三种外观；默认透明度 **90%**；托盘两个开关**文字随状态变**；首次识别提示挪到**保存 API Key 之后** | ✅ 除「真机手感」外全部可验证：离屏渲染真的有单测（`float_window_content_test` 6 条，含公式题与极简模式的高度对比）、外壳/图标/提示/拖拽区有 9 条、presenter 11 条；发布版探针用**用户真实数据库**跑通（窗口 684×1520 物理 = 竖屏 9:20、可点区域 8 个、拖拽区 342×75、帧内 721 种颜色、答案区浅绿底 22322 像素） |

| M34 | 用户反馈轮 16（**只动 Windows，8 条**）：隐私告知改成**只在首次保存 API Key 时**提示一次（识别流程里不再弹）；悬浮窗标题栏**删掉「共 N 题 / N 张图片」**；右上角上一条/下一条**位置互换**；底部两个识别按钮先按用户要求做成 **macOS Dock 式悬停放大**，执行后被用户撤回（「太奇怪」）→ 回到**适度尺寸的整条按钮**，并修掉**文字贴按钮顶沿**；**删掉窗内字号按钮**（字号只留设置页）；**纯净白配色改用中性种子**（M33 错填绿色 = 套了薄荷绿）；设置页**不再出现任何构建过程描述**（`Mxx 第 N 条` / `用户反馈 N`）；内容区从「离屏渲染整张 `QuestionCard`」**改回 `TextPainter` 直排 + 明显的题目轮廓**（M33 那条就是悬浮窗卡顿的来源） | ✅ 除真机手感外全部可验证：四包 analyze 0 issue、测试**全绿**（core 193 / ui 47 / **desktop 170** / android 83）；发布版探针用**用户真实数据库**复核（342×760@DPR2、可点区域 6 个、拖拽区 342×43、底部按钮 23 逻辑像素高、悬停前后**零重画**、标题栏三通道差 5 = 中性白）；另有**逐像素复核**（按钮里文字上下各留 7/8 逻辑像素）与**排版/整帧成本基准**（冷排 9–14 ms、命中缓存 ≈0.01–0.04 ms、整帧渲染 116→56 ms） |

| M35 | **悬浮窗崩溃真凶**（用户报「点击上面按钮来回点就崩溃」）：内容重建时对每个 `TextPainter` 调 `dispose()`（释放原生 `ui.Paragraph`）会让进程在 `flutter_windows.dll` 里以 `0xC0000005` 崩掉 → 去掉显式释放（交给 GC）+ 内容缓存留两份（正常/极简）+ 题目指纹按 id 排序；期间做过的「原生 GDI 绘制」重构因崩溃未修好且观感更差整段回退（留档 `git stash`） | ✅ 两条必崩路径（200 格滚轮 + 90 秒空闲；反复点极简/锁定 + 100 格滚轮 + 60 秒空闲）修复后**全程存活**；desktop 171 项全绿 |

| M36 | 版本 **1.0.2**（只动 Windows）+ **悬浮窗卡顿优化**：一帧拆成 chrome（外观）/ content（内容）/ overlay（提示）三块各自缓存，滚动与悬停帧**不再出图**，只做内存拷贝合成；配整数哈希指纹、输出缓冲复用、内容拷贝连续快路、整窗透明度交给原生 `SourceConstantAlpha`；顺带把慢帧分段计时（首屏/内容排版/再布局/合成/贴窗）常驻进日志 | ✅ 四包 analyze 0 issue、desktop **179 项全绿**（新增 `float_window_compose_test` 8 条，含真渲染端到端）；发布版探针：200 格滚轮 + 悬停 + 空闲 90 秒存活、内存 480→305→315 MB（优化前 574→690→崩）、200 格滚轮只出图 14 次、合成 5 ms（优化前每次推帧 40–52 ms） |
| M49 | **用户实测反馈三条（1.1.0 交付后第二轮）**：① **安卓多页手势看齐 Windows 端** —— 多页模式里「短按」**只提交已经截好的页**，不再补截一张（桌面端 F8 就是「结束多页并上传**已抓的**图」）；抓满上限自动提交并退出多页模式本来就是 M47 的行为，本轮写进说明与用例 ② **过程提示不再排队回放**（原话「等完成后回到安卓应用后，app内会把app累积的提示一个一个跳出来，直到结束」）—— 后台不入队（那一侧由系统 Toast 提示）、前台只留最新一条、回前台再清一次队列；`CaptureBridge.showToast` 也改成新提示 `cancel()` 掉旧的 ③ **设置里写明「同时只支持连接一台安卓设备」**（含换手机先吊销旧设备的顺序，连接设备页三个分支各一条） | ✅ 四包 analyze 0 issue；core 212 / ui 57 / desktop **228**（+1）/ android **88**（+3）全绿；①② 都做了**负向对照**（把修复退回旧实现，新用例必红：① 短按又去截一张 → `multipage_capture_test` 两条红；② 不清队列/后台照收 → `snack_queue_test` 两条红）；③ 只能真机验证的部分写进 `docs/manual-test-android.md` 第 38 项；出包序号 +33 / +22（versionCode 1022/2022/4022） |
| M48 | **用户实测反馈三条**（1.1.0 交付后立刻报的；第 ① 条是 M47 自己加的功能判据错了）：① **删掉「设置 → 连接设备」的安全提示**（原话「一秒一个无效链接尝试的提示，删掉他」）——根因是手机端前台每秒轮询 `/tasks/active`，未配对/换过 token 时那些**合法轮询**被判成「无效尝试」；整块移除计数 + 控制器透出 + 设置页模块，`SPEC.md` §8 改成「拒绝，但不再显示提示」 ② **手机连上后「当前连接状态」不更新** —— 那张卡原来只读 WS 连接数，而手机前台走 HTTP 轮询（不建 WS）；新增 `activeDeviceCount` = 「WS 连着 ∪ 最近 15 秒内有已认证请求」 ③ **安卓关悬浮球后屏幕共享没停** —— `setBallVisible(false)` 里补 `CaptureService.stop()`，前台服务与 `MediaProjection` 一并释放（下次截屏重新弹授权框） | ✅ 四包 analyze 0 issue；core 212 / ui 57 / desktop **227**（+1）/ android 85 全绿；② 的回归点做了两层用例（core 服务端 + desktop 真 HTTP 配对与轮询后断言页面显示「已连接 · 1 台设备在线」）；③ 只能真机验证，验收项写进 `docs/manual-test-android.md` 第 37 项；出包序号 +32 / +21（versionCode 1021/2021/4021），build_all ALL GREEN + 审计 60 项 PASS，产物覆盖交付目录 `1.1.0\` |
| M47 | **代码审查修复轮**（用户拿另一份 AI 的全库审查来问"有什么要修的"，逐条核实后按序修）：① **数据正确性** —— 迁移补 `tasks.payload_json` + 打开时自愈缺列的老库；**删除 vs 修改的收敛**（lamport 大者赢、输的一方跟着改，`data-model.md` 2.9 不允许"一端删一端在"）；手机端 `task_result` 改走 `applyAnalysisResult`（保住用户手改）；"结束多页"补合集/Key 闸门且不再清空暂存区 ② **端侧状态机** —— `_busy` 同步置位（连按 F8 不再调两次 AI）、热键线程死后**真的重新 spawn**、取消置顶改 `_hwndNotTopmost + SWP_NOZORDER`、点击阈值按 DPR、悬浮球缓存键快照；安卓：到上限自动提交、球开关落库、轮询闩锁改"会话+版本"、队满单独提示、剪枝跳过排队中的原图 ③ **服务端/协议** —— op 归属必须等于认证设备、上传边读边限长 + 每设备 30 次/分限流、snapshot 分页、队列深度上限、426 版本协商、`already_paired` 409、配对锁定落库（「陌生设备尝试提示」在 M48 已按用户要求删除）④ **契约与发布包** —— SPEC 四行过期事实 + **删掉从未实现的开机自启条款**（用户拍板）、Gradle wrapper 三文件进版本库、LICENSE/CHANGELOG/README 换真实内容、`Runner.rc` 去 `com.example`、`.env*` 进排除集、删 4 个零引用依赖、剪贴板用例不再静默整段跳过、`raw_response` 补覆盖、版本号收敛成"从 pubspec 读"（+ `version_consistency_test`）、脚本工具路径加回退 ⑤ **加固** —— 悬浮窗缓存加字节上限、DPAPI 缓冲清零、设置只写变化键 ⑥ **独立 Server 对齐四条并出 v1.0.1** | ✅ 五份 analyze 0 issue；core **212** / ui **57** / desktop **226** / android **85** / server **90** 全绿；新增 25+ 条用例；**逐个做过反向对照**（把修复退回旧实现，对应用例必须红）：闸门/流式限长/LiveUpdates 保护/删除收敛四条都实测会红；审查里的错报与"本就有意为之"的条目（安卓 AccessibilityService、`/sync/ops` 多余、悬浮球默认关、core 复制冻结、M18 合集删除语义）逐条写进 `DECISIONS.md` 并**明确不改** |
| M46 | 版本 **1.1.0**（双端统一；用户一次给 7 条）：① **热键只留两个** —— 截屏识别默认 **F8**（在多页模式里＝结束多页并上传已抓的图）、多页模式默认 **F9**（第一下进多页抓第一张、继续按追加、**抓满 6 张自动上传**），判定抽成纯函数；顺带把桌面热键服务**整条照搬 Server 的线程模型**（后台循环一次 `await` 都不做 + 共享内存命令 + 每 2 秒自检补注册）② 悬浮窗设置页**如实声明不支持显示公式** ③ **删赞助页与两张收款码图片**，赞助支持挪到「关于」页最下面（爱发电 `https://afdian.com/a/iop666`）④ 双端版本 **1.1.0**（桌面 +30 / 安卓 +19）⑤ 安卓配对页过时文案改成「设置 → 连接设备」⑥⑦ 新增 `tools/package_source.ps1`：源码包**带 19MB MiSans 字体**、剔除内部构建记录（AGENTS.md / DECISIONS / milestones / progress / DEV 等），界面文案里也不再写「构建脚本 / 每一轮改动」 | ✅ 四包 analyze 0 issue、core 195 / ui 56 / desktop **219** / android 83 全绿；发布版探针（临时副本）：`register[capture] id=1 vk=119 -> F8 OK` / `register[multipage] id=2 vk=120 -> F9 OK`、别的进程注册 F8/F9 都 1409（对照 F1 成功）、合成按键后日志出现「热键触发：多页模式（F9）」与「热键触发：截屏识别（F8）」、**40 秒后仍持有**且自检补注册 0 行；portable zip entries=64 / userdata=0 / VC=10、exe 1.1.0；APK versionCode 1019/2019/4019 + AUDIT PASS；源码包 376 条目 / 19.2 MB（含 MiSans 19.1 MB） |
| M45 | **独立的 QuizSyncAI Server v1.0.0**（纯 Dart CLI，主项目零改动）：四步引导 + 中文紧凑输出、数据落 exe 同目录、两个热键动作（默认 F8/F9）、后台运行真脱离控制台 + 再次打开即呼出命令行窗口、`--status`/`--stop`/`--hidden`；**修掉「转后台后热键悄悄失效」**（实测长期存活的 isolate 28 秒换手 327 次 → 热键线程改成「一次 await 都不做」的同步循环 + 共享内存命令 + 每 2 秒自检）；`使用说明.txt`；最后单独发 GitHub Release（zip 只含程序与说明）并把 `server/` 源码补进远端 main、标签重指到该提交 | ✅ Server：`dart analyze` 0 issue、`dart test` 86 项全绿；发布物复核（包内条目/大小一致、无数据文件、exe 内无 Key/用户名路径/局域网 IP）并把资产下载回来比 sha256；从 codeload 拉回的源码 56 项 blob 与推送提交 **56/56 完全一致**，干净目录里 `pub get → analyze → test` 全绿 |
| M44 | 版本 **1.1.3**（Windows 为主，共 6 条）：① 赞助页精简（删掉「不方便…」之后的话、去掉破折号、两张收款码**等高**）② 每日调用上限新增**「不设上限」**（存 0，`QuotaGuard` 仍记用量但不拦）③ **悬浮球默认关闭**（老库 `ball_enabled=1` 一次性迁移）④ 默认模式的答案改成**标绿契约色**（真绿色）⑤ **手机端识别时 Windows 端静默不弹出**（只在窗口本来就是前台时才切界面）+ 修「悬浮窗不同步手机任务状态、不跳新界面」（新增 `RemoteTaskSignal` 信号 → 悬浮窗显示「手机正在识别…」并在完成时跳到新结果）⑥ 设置页说明文字里的 `**重点**` 渲染成**真加粗**（新增 `settingsMarkdownSpans` / `SettingsRichText`，11 个分类全扫一遍断言界面上不再出现字面星号） | ✅ 四包 analyze 0 issue、core 195 / ui 56 / android 83 / desktop 214 全绿；发布版探针：窗口类里**没有** `QuizSyncFloatingBall`（球默认关）、库里自动补上 `ball_enabled_migrated=1` / `float_window_mode_migrated=1`、默认模式仍生效（可点区域 7 个）、答案笔画回读 `20,147,67`（绿通道超出 max(R,B) 80 = 真绿色） |
| M43 | 版本 **1.1.2**（只动 Windows）：① **极简模式改成悬浮窗默认显示的模式**（原来的默认排版改名「详细解析模式」，老库里的 `float_window_minimal=0` 走**一次性迁移**）② 底部「复制本题答案」改成**「复制识别内容」**并挪到三个按钮的**最后一个**（一点就把本次识别的完整内容——题干/全部选项/答案/解析/材料——以纯文本放进剪贴板）③ 修「极简模式答案题号等颜色和背景色高度接近」：题号/答案/次要文字统一走 `ensureContrast` 保证与底色对比度 ≥ 4.5:1，且**选「纯净白」「紫罗兰」时同时切深色模式**④ 设置新增最后一项**「赞助」**（感谢的话 + 微信/支付宝收款码） | ✅ 四包 analyze 0 issue、core 193 / ui 49 / android 83 / desktop 213 全绿；发布版探针：不设任何悬浮窗设置时**默认就是默认模式**（可点区域 7 个 = 含复制按钮）、点第三个按钮 → 日志 `点击 copy-content`、剪贴板 1742 字 = **20 题 / 20 个「答案：」/ 20 个「解析：」**；题号行最强笔画与底色对比度 lilac-light 4.62:1 / lilac-dark 5.43:1 / white-dark 5.25:1 / white-light 4.71:1 |
| M42 | 版本 **1.1.1**（只动 Windows）：**极简模式改成纯文本面板 + 可拖选 + 一个「复制本题答案」**（用户连问三轮）。一题一个 `TextPainter`（题号/题干/选项/答案同一段），没有任何卡片、圆角底、徽标、色块；拖选的高亮**直接在合成像素上混色**（不出图、选区进帧指纹）；这个窗口是 `WS_EX_NOACTIVATE`，拿不到键盘消息（`Ctrl+C` 天生不可用），所以复制选区的入口是**右键**，兜底才是底部那一个按钮 | ✅ 发布版探针（用户真实 20 题会话）：极简面板**内容高 1526 / 图元 60**（正常模式 4659 / 301）、首行有墨 96 = 内容区顶；合成拖选后内容带 9844/28980 像素变化（高亮出来了）；右键 → 系统剪贴板拿到选中的原文；点「复制本题答案」→ 日志 `点击 copy-answer`、剪贴板 = `红楼梦`（第一题答案）；存活 RSS 345 MB。`flutter analyze` 0 issue，新增 20 条用例（选区 9 · 极简面板 3 · 按钮/提示 2 · 合成选区 1 · presenter 3 …） |
| M41 | 版本 **1.1.0**（只动 Windows）：把富文本内容路径**默认关掉**（`FloatWindowPresenter.useRichContent = false`），内容回到 `TextPainter` 直排 + 1024 逻辑像素片高 | 三轮修法（片高按成本给 / 一次渲完全部片 / 指纹去记账字段）都没改变一个事实：只要出图还在推帧链路上，滚动就会撞上 300–700 ms 的渲染。同一份发布版 exe 实测：直排平均整帧 **8–13 ms**、100 帧只出图 6 次；富文本首屏 190–695 ms | ✅ 探针（用户真实 20 题会话，内容高 4659 · 图元 301）：滚 200 格用时 13 s、底部带颜色数 119（不再是一片底色）、首行有墨 96 = 内容区顶、RSS 396 MB 存活 |
| M40d | 版本 **1.0.9**（只动 Windows）：修「滑动还是更卡」的**真正原因** —— 富文本内容指纹里带了 `updatedAt`/`lamport` 这类**记账字段**，而前台每秒一次的轮询会碰到它 → **每秒把整篇内容重渲一遍**（20 题 ≈ 3 片 ≈ 1.2 s，等于一直在渲染）。指纹改成**只看会进画面的字段**（题目 id/题干/选项/答案/解析/把握率/复核标记…），记账字段不再参与 | ✅ analyze 0 issue、float 相关 29 项与全量 189 项全绿 |
| M40c | 版本 **1.0.8**（只动 Windows）：修 1.0.6/1.0.7 的**滚动卡顿** —— 富文本一次出图 300–500 ms，按需出图会让「滚到新片就卡一下」，把片放大又变成首屏冻结 1–2 s。改成 **内容一变就把全部片一次渲完**（片高 2048 逻辑像素），渲完之前画面保持上一帧 → **滚动与悬停永远是纯拷贝**。代价：新结果第一次显示多等一次（每片约 0.4 s） | ✅ 探针：滚动 60 格期间 `出图` 计数不增长（只有外观 + 各片各一次）；analyze 0 issue、float 相关 29 项与全量 189 项全绿（presenter 测试改为注入假「量高/栅格化」） |
| M40b | 版本 **1.0.7**（只动 Windows）：修 M40 引入的**滚动卡顿** —— 富文本渲染一片要重跑一遍 widget 管线（260–660 ms），而片高只有 1024 逻辑像素，于是「每滚十几格重跑一次」。改成**片高按渲染成本给**（富文本路线 8192 逻辑像素，通常整篇只有一片 → 滚动回到纯拷贝；图元直排仍用 1024 提高命中率） | ✅ analyze 0 issue、desktop 189 项全绿；合成器片高改为可配置（`contentChunkHeight`），默认值不变 |
| M40 | 版本 **1.0.6**（只动 Windows）+ **悬浮窗内容改为主界面同源的富文本渲染**：内容区不再用 `TextPainter` 直排，而是把主界面同一套 `QuestionCard` 离屏渲成位图（公式走 KaTeX、化学式切上下标、材料表格画成真表格），仍然**按片出图**（一帧只出可见区 1–2 片 + 1 片预取），滚动/悬停帧还是纯拷贝；高度改为「按指纹量一次 + 缓存」，只量高度时不 `flushPaint` | ✅ desktop **189 项全绿**（新增 `float_window_rich_test` ⑯⑰⑱：量高度/出图有墨/按片栅格化/极简与 DPR 进指纹，以及合成器 ⑮「内容片由富文本渲染器提供 + 内容指纹变了要重出」）；发布版探针（播种公式题会话）：`内容高 957 · 图元 20 · content片=665x1915`，滚到底底部带颜色数 **386**（旧直排路径同位置 ~120），内容区底色不再透出桌面 | 
| M39b | 修 M39 引入的原点回归：切片出图的原点必须带 `bodyRect.topLeft`（内容图元是**窗口坐标**），否则内容整体下移一个表头高、右移一个左边距 —— 用户报「不顶头 / 底部被识别按钮压住 / 左右边距不对等」 | ✅ 探针 A/B：内容区首行有墨的物理行号 **192 → 96**（内容区顶 = 96）；`float_window_compose_test` 新增 `⑭`（把窗口坐标编进像素，同时钉住上下与左右两条）后 14 条全绿 |
| M39 | 版本 **1.0.4**（只动 Windows）+ **悬浮窗内容被截断的真凶**：内容区原来是一张**整图**，而位图高度被 `clamp(1, 8192)` 物理像素卡死 —— 用户真实数据里 20 题的内容高 4659 逻辑像素（DPR2 = 9318 物理像素），滚到底部时最后 563 逻辑像素（约两题）永远看不见、那里是一片纯底色。改成**按 1024 逻辑像素切片出图**（一帧只要可见区那 1–2 片 + 1 片预取），内容再长也画得完；顺带修掉分片拷贝的**行漂移**（目标行距是窗口宽、拷的是内容区宽，连续 memcpy 会切斜，两侧有留白时必须逐行） | ✅ 同一份用户真实 20 题会话做 A/B：旧构建滚到底后内容区底部带 `颜色数=1 · 最常见色占比 100% · 73/73 近似纯色行`，新构建 `颜色数=131 · 占比 41% · 22/73`（剩下的是卡片留白）；合成器状态从 `content=665x8192` 变成 `content片=665x2048×4+665x1126`；首屏出图 571→324 ms、平均整帧 10→11 ms（没有退化）；desktop **184 项全绿**（新增 `float_window_compose_test` ⑫⑬ 两条回归，⑫ 在改之前必红） |
| M38 | 版本 **1.0.3**（只动 Windows）+ **悬浮窗卡顿真凶**：热路径（滚动/悬停，三块都命中缓存）原来 `await window.setFrame(...)` —— 而 `setFrame` 体里没有 await（纯 win32），那次 await 只是在等平台线程被唤醒，实测 **390–670 ms**（有 Dart 定时器时 1–6 ms），整帧 671 ms、~1 fps；改成**同步合成 + 同步贴帧（unawaited + catchError）**。第二条是**「极简 × 锁定」= 4 种外观组合而缓存只留 1 份**导致每点一次重出图（60 次点击 192 张图、RSS 789 MB），改成按块留份数（外观 4 / 内容 2 / 浮层 6）。顺带：M36 丢的圆角用 `renderNodes(cornerRadius:)` + 合成后 `_roundCorners` 角掩码修好（本轮补屏幕实拍取证）、每帧 `ShowWindow` 收成首帧一次、真实剪贴板用例改有上限等待 | ✅ 同一份 exe 的 A/B 取证（贴窗 await 1–6 ms vs 390–670 ms）+ 发布版探针：不开取证时 `200 帧 · 平均整帧 6ms · 帧间隔 77ms · 出图 6 次 / 合成 179 帧`；80 次点击 + 40 格滚轮 + 30 秒空闲全程存活、RSS 峰值 529 MB→361 MB；屏幕实拍证明圆角恢复；四包 analyze 0 issue、desktop **182 项全绿**（新增 3 条合成器回归） |




---





## 6. 全局非目标（写了就不要做）





- 不做公网访问、云同步、账号体系、多用户。


- **不做任何截屏保护（FLAG_SECURE）的绕过**。遇到黑图只提示「该应用禁止截屏」，并把「手动选图 / 系统分享入口」作为该场景的正常通路。


- 不爬题库、不联网搜原题、不做答案比对投票。


- 不做 iOS / macOS / Linux 端。


- 不引入需要付费或需要注册账号才能运行的构建组件。


- M0–M5 不做公式渲染、不做标签、不做收藏、不做多 Android 设备支持（都推到 M6 之后）。





---





## 7. 全局完成定义（DoD）





一个里程碑只有同时满足以下全部条件才算完成：





1. `flutter analyze` 在改动过的包里无 error。


2. 新增的核心逻辑有对应的单测，且 `dart test` 全绿。


3. 该里程碑在 `docs/milestones.md` 里列出的验收命令**逐条跑过**，实际输出摘要写进 `docs/progress.md`。


4. 无法自动验证的部分（Android 真机行为）已写成人工测试清单，附在 `docs/progress.md` 的对应里程碑下。


5. 变更已 `git commit`，提交信息以 `M<n>:` 开头。


