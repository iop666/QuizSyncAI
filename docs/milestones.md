# 里程碑与验收



**执行规则**：严格按顺序做，一个里程碑验收通过并提交后再开下一个。每个里程碑完成后在 `docs/progress.md` 追加记录（做了什么、验收命令的真实输出摘要、遗留问题），提交信息以 `M<n>:` 开头。



开工前先读 `AGENTS.md` 第 0 节的无人值守守则。



---



## 进度看板



> agent 每完成一个里程碑就把状态改成 ✅ 并填上提交号。



| 里程碑 | 状态 | 提交 | 完成日期 | 备注 |

|---|---|---|---|---|

| M0 脚手架与构建基线 | ✅ | 321d0a7 | 2026-09-16 | APK 三个 ABI 共 44MB，无 maven.google.com 访问 |

| M1 共享核心与数据库 | ✅ | 3a28bfc | 2026-09-16 | 63 个单测全绿；含 LWW/tombstone/user_edited/离线队列 |

| M2 AI 接入与解析 | ✅ | 64b5d3a | 2026-09-16 | 110 个单测全绿；ai-contract §7 六类测试齐备 |

| M3 Windows 单机闭环 | ✅ | acd381b | 2026-09-16 | 14 个 widget/管线测试全绿；Windows release 可构建 |

| M4 网络层与配对 | ✅ | ef23a2f | 2026-09-16 | 回环 9 步全过（含吊销 401 revoked）；双端构建通过 |

| M5 Android 采集 | ✅ | f99dfe0 | 2026-09-16 | 编译+逻辑单测过；真机行为未验证（manual-test-android.md） |

| M6 同步与增强 | ✅ | 2949c5a | 2026-09-16 | core 128 测试全绿；7 类同步测试齐备；双端构建过 |

| M7 打包与交付 | ✅ | （本提交） | 2026-09-16 | build_all 全绿；zip 14.5MB；APK 24.1–30.2MB；README 补全 |

| M8 需求第 2 轮（合集 / 多页 / 界面与导航重做） | ✅ | f145cfc | 2026-09-19 | 13 项需求全部落地；contracts 先行更新；core 166 测试全绿；两端构建过 |

| M9 Windows 设置页重构（左导航 + 7 个分类页） | ✅ | 44a8171 | 2026-09-19 | 四包 analyze 无 issue；core 166 / ui 4 / desktop 51 / android 37 全绿；最小窗口不溢出；安装包重打 |

| M10 用户反馈轮（15 项） | ✅ | f7953e1 | 2026-09-19 | MiSans + 字重/界面缩放；热键模块重写；图标字体不裁剪；托盘图标；主机本地识别也广播状态；安卓端 9 项 |

| M11 用户反馈轮 2（16 项） | ✅ | cb6763b | 2026-09-19 | 图标圆角/关于页应用图标与字体许可；导出弹「另存为」+数据目录随软件；设置白底模块且无切换动效；缩放改下拉并自动调窗口；DeepSeek 默认值 + 进页面自动刷配对码；硬上限 6；双端静默互显；AI 不确定标黄；阅读材料折叠 + 主观题结构化；多页排序与材料页 |

| M12 用户反馈轮 3（12 项） | ✅ | d9cc034 | 2026-09-19 | 托盘图标圆角；**导出全部失败真凶**（`FNERR_INVALIDFILENAME`）；标题带底色与模块间距；连接设备去双层背景；热键页暂停热键；**热键串键根因**（线程级注册泄漏）；「恢复默认热键」；序号移到题号徽标外；缩放跟住内容边界；安卓长提示与答案换行；**Windows 悬浮球**（原生分层窗口三态）；MiSans 链接 |

| M13 用户反馈轮 4（1 项：安卓状态栏跟随主题） | ✅ | 4f9c7c7 | 2026-09-19 | **状态栏第 3 次修，这次拿到了机制性证据**：反编译引擎产物确认 Android 15（API 35）起 `PlatformPlugin` 直接跳过 `setStatusBarColor`，M10/M11 两轮在此类机器上注定无效；改为 ① App 自绘状态栏底色条带 ② 自家 Kotlin 桥设图标明暗并在获焦/回前台重贴 ③ 启动窗口系统栏改透明；安卓构建号 3→4 |

| M14 用户反馈轮 5（8 项） | ✅ | 21148e4 | 2026-09-19 | **缩放「那片黑」第 2 次修**（根因是紧约束把虚拟画布夹回窗口尺寸，改用 `OverflowBox`）；设置 ⓘ 改成真能弹出说明；**剪贴板监听真凶 `BI_BITFIELDS`**（旧解析只认 `BI_RGB`，静默返回 null）；悬浮球默认打开 + 渲染缓存（实测 RSS 216→175 MB）；**双端静默互显回归**（本机截屏误触发「窗口带到前台」钩子 + 手机漏掉断线期间的推送）；手机上传图片与本机截图合并目录 + 安卓固定留 20 张并去掉缓存选项；主界面标题前显示应用图标；安卓构建号 4→5 |

| M15 用户反馈轮 6（4 项） | ✅ | （本提交） | 2026-09-19 | **悬浮球四项设置全都调不动**（Riverpod：直接 `listen` `ChangeNotifierProvider` 时 `prev == next`，签名比较永远相等 → 改走 `select`）；**手机上传的图在 Windows 没有缩略图**（上传处理器写完文件后又查库，`local_path` 永远是 null → 改用刚落盘的路径 + 显式 `setImageLocalPath`，客户端再加约定路径兜底）；**悬浮球识别后主窗口自己跳出**（`hideWindowWhile` 恢复用了 `SW_SHOW` + 无条件 `SetForegroundWindow` → 改 `SW_SHOWNOACTIVATE`，只有原本就在前台才还焦点）；**安卓当前任务页不刷新** → 加 1 秒轮询兜底（WS 推送仍保留） |



---



## M0 · 脚手架与构建基线



**目标**：两端能空跑构建成功，Android 的依赖下载不被网络卡死。这一步不写业务代码。



**任务**

1. 创建 monorepo 结构（见 `AGENTS.md` 第 3 节）：

   - `flutter create --template=package --project-name quizsync_core packages/quizsync_core`

   - `flutter create --platforms=windows --project-name quizsync_desktop apps/desktop`

   - `flutter create --platforms=android --project-name quizsync_android apps/android`

2. 两端 `pubspec.yaml` 用 path 依赖引入 `quizsync_core`。

3. **Android 配置阿里云镜像**（`apps/android/android/settings.gradle.kts`，写法见 `AGENTS.md` 第 1 节）。这是本步最关键的一件事。

4. Android `android/app/src/main/AndroidManifest.xml`：`minSdk 26`、`targetSdk 34`、`compileSdk 36`；添加 `INTERNET`、`SYSTEM_ALERT_WINDOW`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PROJECTION`、`POST_NOTIFICATIONS`、`ACCESSIBILITY_SERVICE` 权限声明。

5. 添加 `android/app/src/main/res/xml/network_security_config.xml` 放行局域网明文 HTTP，并在 manifest 引用。

6. 根目录 `.gitignore`（Flutter 产物、`build/`、`.dart_tool/`、`*.keystore`、`key.properties`、`*.jks`、IDE 目录）。

7. 写 `tools/build_all.ps1`：依次执行三包的 `pub get`、`analyze`、core 的 `test`、两端构建，任一失败即非零退出。

8. 写 `README.md` 的骨架（安装与构建步骤，内容可在 M7 补全）。



**验收命令（逐条跑，把输出贴进 `docs/progress.md`）**



```bash

FLUTTER=/d/Windows/Apps/flutter/flutter/bin/flutter

DART=/d/Windows/Apps/flutter/flutter/bin/dart

(cd packages/quizsync_core && $FLUTTER pub get && $FLUTTER analyze)

(cd apps/desktop && $FLUTTER pub get && $FLUTTER analyze)

(cd apps/android && $FLUTTER pub get && $FLUTTER analyze)

(cd apps/desktop && $FLUTTER build windows --release)

(cd apps/android && $FLUTTER build apk --split-per-abi --release)

```



**DoD**：五条命令全部退出码 0；Windows 产物与 APK 文件实际存在；若 Gradle 首次下载耗时很长属正常，但**不得出现访问 `maven.google.com` 的请求**（出现即说明镜像没配对）。



**无法自动验证**：APK 在真机上的安装与启动。



---



## M1 · 共享核心与数据库



**目标**：协议模型、数据库 schema、同步原语全部就位并单测覆盖。这一步完全不碰 UI 与网络。



**任务**

1. 模型类（`quizsync_core/lib/model/`）：`Session`、`Question`、`Option`、`AnswerValue`、`ImageMeta`、`TaskState`、`DeviceInfo`、`SyncOp`、`PairRequest`、`PairResponse` 等。JSON 序列化**手写** `toJson` / `fromJson`，并在 `fromJson` 里实现 `ai-contract.md` 第 3 节的字段规范化表（缺字段补默认值、非法值剔除 + warning）。

2. `AnswerValue` 提供纯函数 `Set<String> matchedOptionLabels(List<Option> options)`，即标绿的判定核心（单选/多选/判断都靠它），非法 label 自动剔除。

3. drift schema（`quizsync_core/lib/db/`）：`data-model.md` 第 1 节的全部表、索引、FTS5 虚拟表；`schemaVersion = 1`；`MigrationStrategy` 骨架就位。

4. 同步原语（`quizsync_core/lib/sync/`）：

   - `LamportClock`：本地递增、收到对端后 `max+1`。

   - `SyncOpWriter`：每次 upsert / delete 恰好生成 1 条 op，`fields_json` 只含变更字段。

   - `LwwApplier`：按 `data-model.md` 2.2 的伪码实现字段级 LWW + `field_clocks_json` 维护。

   - `user_edited` 保护逻辑（2.3）。

   - tombstone 查询过滤（含 FTS join 排除）。

5. 单测覆盖 `data-model.md` 第 4 节的第 1–5、7 项（第 6 项快照折叠放到 M6）。



**验收命令**



```bash

(cd packages/quizsync_core && $DART analyze && $DART test --reporter expanded)

```



**DoD**：`dart test` 全绿；`sync_ops` 生成、Lamport、字段级 LWW、`user_edited`、tombstone 各有独立测试名可查；`migration_test.dart` 存在且通过。



---



## M2 · AI 接入与解析



**目标**：从「一张 JPEG 字节」到「结构化的题目列表 + 标绿结论」这条链路完全正确且可离线测试。



**任务**

1. `QuizAiProvider` 抽象 + `AiConfig`（见 `ai-contract.md` 第 1 节）。

2. 三个真实实现：`openai-compatible`（默认）、`anthropic`、`gemini`。请求构造按各自 API 形态；只做「发请求取文本」，不在这里做 JSON 解析。

3. `FakeAiProvider`：从 fixture 文件读固定响应，供单测与回环测试用。**单测绝不允许发真实网络请求。**

4. prompt 常量与 `promptVersion`（对 prompt 文本做哈希）；把 `ai-contract.md` 第 2 节的 prompt 逐字写进代码。

5. `ResponseParser`：按 `ai-contract.md` 第 3 节的 5 步容错逐级降级；全失败时返回失败结果并保留原文。

6. `RetryPolicy`：超时 90s 默认值、可重试/不可重试错误分类、指数退避 1s / 3s、JSON 解析失败的额外重试。

7. `AnalysisCache`：`image_hash + prompt_version + model` 命中且 < 30 天则回放，不调用 provider。

8. `QuotaGuard`：每日上限（默认 200，不含缓存命中）+ `ai_usage` 记录。

9. 标绿映射：`Question → HighlightResult`（哪些 option label 标绿 / 答案文本标绿 / 是否需要复核徽标），规则见 `ai-contract.md` 第 5、6 节。



**验收命令**



```bash

(cd packages/quizsync_core && $DART test test/ai --reporter expanded)

(cd packages/quizsync_core && $DART test)

```



**DoD**：`ai-contract.md` 第 7 节的 6 类测试全部存在且通过，其中标绿映射必须覆盖单选、多选、判断、填空、主观、答案与选项不匹配、answer 为空共 7 个用例；重试用例能断言「超时→超时→成功 = 调用 3 次」与「401 = 调用 1 次」；缓存用例能断言第二次不再触发 provider。



---



## M3 · Windows 单机闭环（核心价值里程碑）



**目标**：在这台电脑上，按一个热键截屏 → 出题目与答案 → 正确答案标绿 → 存进历史 → 能翻上一条下一条。**做完这一步产品就已经可用。**



**任务**



采集层

1. `ScreenCaptureService`（`win32` GDI BitBlt）：截取鼠标所在显示器的全屏；截图前隐藏主窗口与托盘气泡；Per-Monitor DPI V2 下坐标正确。

2. 图片处理：转 JPEG、长边 ≤ 1600、质量 80，计算 `sha256`。

3. 全局热键（默认 `Ctrl+Alt+Q`，可改）+ 托盘菜单（`tray_manager`、`hotkey_manager`）。

4. 剪贴板监听（默认开）：检测到新图片自动分析，注意去重（同一张图不要反复触发）。

5. 拖入文件 / `Ctrl+V` 粘贴。



分析与存储

6. 串联 M1 + M2：入库 → 建任务 → 调 AI → 解析 → 写题目 → 生成 sync_ops（此时还没有对端，但 op 照常写）。

7. 失败路径按 `SPEC.md` 第 8 节实现（超时/401/429/非法 JSON/无题目）。



UI

8. 主窗口：左侧会话列表（时间倒序、缩略图、题目数、状态图标），右侧题目卡片纵向滚动。

9. 题目卡片：题干、选项列表、标绿（配色与 ✓ 图标严格按 `SPEC.md` 4.3）、解析、置信度徽标、题号、来源与时间。

10. 导航：`← 上一次` / `下一次 →` / `回到本次`，语义严格按 `SPEC.md` 第 5 节（会话之间跳转；同会话多题在同一页滚动）。

11. 外观：字号 12–32（默认 16，`Ctrl+滚轮` 可调）、主题三态（跟随系统/浅/深），均持久化。

12. 设置页：provider、API Key（只回显尾 4 位）、模型、base_url、超时、每日上限、当前用量、端口、是否保存图片。

13. 首次启动的隐私告知弹窗（图片会上传第三方 AI 服务），确认后才允许第一次分析。

14. 常驻免责声明「答案由 AI 生成，仅供参考」。



**验收命令**



```bash

(cd apps/desktop && $FLUTTER analyze)

(cd apps/desktop && $FLUTTER test)              # widget test

(cd apps/desktop && $FLUTTER build windows --release)

```



**必须有的 widget 测试**（没有设备也能跑，是这一步的主要验证手段）

1. 给一个含 4 个选项、正确答案为 `B` 的会话渲染题目卡片 → 断言 `B` 行的 `TextStyle.color` 等于 `#FF16A34A`（浅色主题），且 `A/C/D` 行不是；断言 `B` 行存在 ✓ 图标。

2. 深色主题下同一题 → 断言颜色为 `#FF4ADE80`，且背景为 `#FF14351F`。

3. 多选（`B`,`D`）→ 断言两行都标绿。

4. 判断题（`对`）→ 断言只有「对」标绿。

5. 填空题（`answer.text` 非空、无选项）→ 断言答案文本以绿色显示。

6. `confidence = 0.4` → 断言出现「建议复核」徽标。

7. 造 3 个会话 → 断言「上一次 / 下一次 / 回到本次」的跳转结果符合 `SPEC.md` 第 5 节。

8. 字号调到 24 → 断言题干 `TextStyle.fontSize == 24`（并断言重启后仍为 24，即持久化生效）。

9. 一个会话含 5 道题 → 断言 5 张卡片都在同一滚动视图内。



**DoD**：上述 widget 测试全部通过；`flutter build windows --release` 成功；程序能常驻托盘。



**无法自动验证**：真实 AI 调用（需要用户提供 API Key —— 请把这一条写进 `docs/progress.md` 的人工步骤，并保证注入 `FakeAiProvider` 时全链路可跑）；真实屏幕截图的像素正确性（可做「截到的图尺寸等于屏幕尺寸」的冒烟断言）。



---



## M4 · 网络层与配对



**目标**：Windows 起服务，Android 能配对、上传、拿到结果。Android 这一步先用**相册选图**作为输入源，绕开截屏这个高风险项。



**任务**

1. Windows 端 `shelf` 服务端：`protocol.md` 第 3 节的全部端点 + `/ws` 升级 + Bearer 鉴权 + 配对码有效期与限速。

2. 配对 UI：二维码（`qr_flutter`）+ 6 位配对码显示与刷新；已配对设备列表 + 吊销。

3. 服务端任务队列：串行执行分析（默认并发 1，避免打爆 AI 限流），任务状态机 `queued → analyzing → done/failed`。

4. 共享包里的 `ApiClient`（`dio`）与 `SyncSocket`（`web_socket_channel`），含握手鉴权、心跳、指数退避重连、断线后补状态。

5. Android 端基础 UI：配对页（`mobile_scanner` 扫码 + 手动输入 `host:port` + 配对码）、相册选图上传、历史列表、结果页（复用 M3 的题目卡片组件）。

6. 服务端固定端口 8765，占用时探测 8766–8770。



**验收命令**



```bash

(cd packages/quizsync_core && $DART test test/integration/loopback_test.dart --reporter expanded)

(cd apps/android && $FLUTTER analyze && $FLUTTER build apk --split-per-abi --release)

(cd apps/desktop && $FLUTTER build windows --release)

```



**DoD**：`protocol.md` 第 6 节的回环验证 9 个步骤全部通过（含「吊销后返回 401 revoked」）；APK 构建成功。



**无法自动验证**：真机与 PC 的局域网实际连通（需要用户的两台设备）。



---



## M5 · Android 采集（最高风险，无法自动验证）



**目标**：悬浮球单击即截屏上传。这一步的产物**只能保证编译通过 + Dart 侧逻辑单测**，真机行为必须由人工验证。



**任务**

1. 悬浮球：Kotlin 原生 `View` + `WindowManager` `TYPE_APPLICATION_OVERLAY`；可拖动、吸附边缘、长按展开菜单（截屏/历史/设置/隐藏）；8dp 阈值区分点击与拖动。

2. 截屏主路径：前台服务（`foregroundServiceType="mediaProjection"`）常驻复用单个 `MediaProjection` + `VirtualDisplay` + `ImageReader`；注册 `MediaProjection.Callback` 处理 `onStop`；会话失效时清状态并引导重新授权。

3. 截屏前隐藏悬浮球 → 等待约 250ms → 取帧 → 恢复悬浮球。

4. 备选路径：`AccessibilityService.takeScreenshot()`（API 30+），在设置里可切换；不可用时回落主路径。

5. 权限引导页：通知、悬浮窗、电池优化白名单，逐项说明缺权限会导致什么不可用，并给跳转按钮。

6. MethodChannel 接口（保持极薄，只有两个方向）：

   - `captureScreen() -> Uint8List`（JPEG 字节）

   - `setBallVisible(bool)`、`isCaptureAvailable() -> {main, accessibility}`

7. Dart 侧把 MethodChannel 包在 `CaptureSource` 接口后面，提供 `FakeCaptureSource`，使上传链路能在本机单测。

8. 结果回传：前台直接跳结果页；后台发通知（标题为「第 N 题 · 答案 X」），点击进结果页。

9. 降级通路：取帧全黑或失败 → 提示「该应用禁止截屏」+「从相册选图」。**不实现任何绕过。**



**验收命令**



```bash

(cd apps/android && $FLUTTER analyze)

(cd apps/android && $FLUTTER test)

(cd apps/android && $FLUTTER build apk --split-per-abi --release)

"/d/Windows/Apps/Android/Sdk/build-tools/36.0.0/aapt2.exe" dump badging apps/android/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | head -20

```



**DoD**

1. 上述命令全部成功；`aapt2 dump badging` 的输出里能看到 `FOREGROUND_SERVICE_MEDIA_PROJECTION` 等权限与正确的 `minSdkVersion`/`targetSdkVersion`。

2. Dart 侧上传链路单测通过（用 `FakeCaptureSource`）。

3. **必须产出 `docs/manual-test-android.md`**：逐步的人工测试清单，每步含「操作 → 预期结果 → 失败时看什么日志」，至少覆盖：首次授权只弹一次、单击截屏不弹窗、悬浮球不出现在截图里、拖动不误触发截屏、长按菜单、后台被杀后恢复、锁屏后会话失效与重新授权、FLAG_SECURE 应用返回黑图的提示、相册选图降级通路、通知点击进结果页、备选无障碍路径。

4. 在 `docs/progress.md` 里明确写明「本里程碑的真机行为未经验证，需人工执行 manual-test-android.md」。



**无法自动验证**：本机没有 Android 设备也没有模拟器，MediaProjection、悬浮球、前台服务、通知的**全部运行时行为**都无法验证。不要试图为此安装模拟器（见 `AGENTS.md` 守则 6）。



---



## M6 · 同步、离线与增强



**目标**：两端数据最终一致；补齐搜索、导出、备份与公式渲染。



**任务**

1. 同步引擎：水位线推拉、`ack` 处理、分页拉取（每页 500）、断线重连后先拉后推。

2. 快照折叠（`data-model.md` 2.6）+ 新设备 bootstrap（`GET /sync/snapshot`）。

3. Tombstone GC（30 天 + 全部对端已确认）。

4. 离线队列（`data-model.md` 2.8）：上限 20 条，Windows 上线后按序补跑并通知。

5. 图片后台补传（最近约 200 张，一次最多 5 张）+ 本地文件清理策略。

6. 搜索：Windows 用 FTS5 查题干与解析（必须排除软删除）；Android 用 LIKE 兜底。

7. 导出：单条会话或全部历史导出为 Markdown / JSON。

8. 备份与恢复：Windows 端一键备份数据库 + 图片目录为 zip，支持从备份恢复。

9. 公式渲染：引入 `flutter_math_fork`，把 `$...$` / `$$...$$` 渲染为公式；渲染失败时回退为等宽字体原样显示（必须保留回退，不能白屏）。

10. 日志：可导出的日志文件（含请求 id），日志中不得出现 API Key 与 token。



**验收命令**



```bash

(cd packages/quizsync_core && $DART test --reporter expanded)

(cd apps/desktop && $FLUTTER test && $FLUTTER build windows --release)

(cd apps/android && $FLUTTER build apk --split-per-abi --release)

```



**DoD**：`data-model.md` 第 4 节的 7 类测试全部存在且通过，其中必须包含 `data-model.md` 2.9 表格里全部 6 个冲突场景的用例；快照折叠测试要断言折叠后行数下降且增量拉取仍能拿到最新状态；备份→恢复→数据一致的往返测试通过。



---



## M7 · 打包与交付



**目标**：产出可交付物与给人看的文档。



**任务**

1. Windows 便携版：`flutter build windows --release` 产物打包为 zip（含必要 DLL）。若机器上存在 `ISCC.exe` 则额外生成 Inno Setup 安装包，否则跳过并记录（不要安装软件）。

2. Android：生成 keystore（若不存在）、配置 `key.properties`（加入 `.gitignore`）、`--split-per-abi` 出三个 APK；把 keystore 备份路径与口令保管说明写进 README（**不要把口令写进仓库**）。

3. 体积核对：Windows zip ≤ 60MB，单 ABI APK ≤ 40MB；超出则在 `docs/progress.md` 记录实际值并分析原因。

4. `README.md` 补全：安装、首次配置（填 API Key）、两端配对步骤（含截图说明位置）、常见故障排查（防火墙、配对失败、AI 报错、截屏黑图、悬浮球不显示、电池优化）。

5. `docs/manual-test-android.md` 复核完整性。

6. `tools/build_all.ps1` 复核可用。



**验收命令**



```bash

powershell -File tools/build_all.ps1

ls -lh apps/desktop/build/windows/x64/runner/Release/

ls -lh apps/android/build/app/outputs/flutter-apk/

```



**DoD**：`build_all.ps1` 一次跑通；记录两个产物的实际体积；README 里的配对步骤与实际 UI 一致（逐条核对，不要凭记忆写）。



---



## M8 · 需求第 2 轮（合集 / 多页 / 界面与导航重做）



**目标**：落实用户在 2026-09-19 一次性提出的 13 项需求，两端同步，契约（`SPEC.md` / `protocol.md` / `data-model.md` / `ai-contract.md`）先行更新。



| # | 用户需求 | 落点 |

|---|---|---|

| 1 | 安卓结果页「上一次识别 / 下一次识别」，一次识别的题目同页显示完成 | `apps/android/lib/ui/result_page.dart`、`SPEC.md` 3.3 |

| 2 | 题目不全 → 整卡黄框；只有答案不识别；选项不全 → AI 推断并注明猜测 | `Question.incomplete/answerGuessed`、`QuestionCard`、`ai-contract.md` 4.2 |

| 3 | 答案区显示识别到的题号，前面是排序序号 | `Question.displayTitle`（`3. 第 12 题`） |

| 4 | 多页识别：追加页热键 + 截止热键，默认上限 6 页，到上限自动上传 | `session_images`、`CaptureCoordinator.appendPage/finishMultiPage`、`SPEC.md` 2.2.1 |

| 5 | 本地图片缓存上限默认 60 张，可设为不设限 | `kImageCacheLimitKey`、`pruneImageFiles`、两端设置页 |

| 6 | 安卓底部三标签（当前任务 / 历史记录 / 设置），默认当前任务，未开始显示「已连接电脑，但未开始任务」 | `apps/android/lib/ui/home_page.dart` |

| 7 | 主机开始识别后安卓自动加载新记录；未完成显示「N 张图片识别中」，完成后刷新并可重新生成 | `LiveUpdates`、`POST /sessions/{id}/reanalyze` |

| 8 | Windows 首次必须新建合集、每次打开都要选择；识别都落在选中合集里；安卓历史按合集分组 | `collections` 表、`CollectionGate`、安卓 `history_page.dart` |

| 9 | 两端可一键导出合集（易读文件，按识别顺序排序） | `Exporter.collectionToMarkdown/Json` |

| 10 | 设置页只保留主题三态，去掉配色选择 | `AppSettings.theme`、两端设置页 |

| 11 | 安卓识别模块总开关（默认关）+ 二级设置页；悬浮球 单击=单图、长按=多页追加、多页中短按=结束并作为最后一页 | `FloatingBallManager.kt`、`MultiPageCapture`、`SPEC.md` 3.1 |

| 12 | 安卓发起识别前必须有主机选中的合集 | `/info`、WS hello、`409 no_active_collection` |

| 13 | 历史记录可删除（两端，软删除 + 同步） | `CoreRepository.deleteSession`、两端历史列表 |



**验收命令**



```bash

(cd packages/quizsync_core && dart analyze && dart test)          # 含 v1→v2 迁移、多页/合集/不全题目

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)

(cd apps/android           && flutter analyze && flutter test)

(cd apps/desktop && flutter build windows --release)

(cd apps/android && flutter build apk --split-per-abi --release)  # 同时验证 Kotlin 编译

powershell -File tools/package_windows.ps1

```



**DoD**：13 项全部落地且两端行为一致；四包 analyze 无 issue、测试全绿；`docs/DECISIONS.md` 记录本轮全部实施期决策；`docs/progress.md` 写出实际验收输出；两个产物可构建、体积不超限。



---



## M9 · Windows 设置页重构（左导航 + 7 个分类页）



**目标**：把设置页从「一条很长、所有设置混在一起的纵向页面」重做成「左侧导航 + 右侧分类内容」的 Windows 桌面设置中心。**只改信息架构、布局、视觉层级与交互，不改任何设置项的功能、落库键位与数据模型。**



| # | 要求 | 落点 |

|---|---|---|

| 1 | 左侧固定导航（232px，窄窗口收成 60px 图标栏）+ 右侧独立滚动；一次只显示一个分类 | `apps/desktop/lib/ui/settings_page.dart` |

| 2 | 七个分类：显示设置 / API 配置 / 连接设备 / 识别设置 / 热键设置 / 数据管理 / 关于 | `apps/desktop/lib/ui/settings/{display,api,device,recognition,hotkey,data,about}_settings_page.dart` |

| 3 | 统一基础组件：`SettingsSection` / `SettingsGroup` / `SettingsRow` / `SettingsField` / `SettingsTile` / `SettingsSidebarItem` / `SettingsKeycap(s)` / `SettingsSwitch` / `SettingsStatusDot` / `SettingsProgressBar` / `SettingsNote` | `packages/quizsync_ui/lib/src/settings_components.dart` |

| 4 | 间距只用 8 的倍数；分组用「标题 + Divider」而不是满屏大卡片；只有连接状态、配对扫码区用浅色卡片 | 同上（`SettingsGap` / `SettingsMetrics`） |

| 5 | 90% 中性灰白 + 10% 品牌绿（绿只用于选中项 / 开关 ON / 主按钮 / 滑块当前值 / 成功-已连接） | 同上（`SettingsType` / `settingsSidebarColor`） |

| 6 | 连接设备页要有明确「当前连接状态」，数据来自服务端真实 WS 连接数 | `QuizSyncServer.connectedCount` / `connectedDeviceIds`、`device_settings_page.dart` |

| 7 | 热键用键帽显示，「编辑」弹窗录入并给出「可能被其他程序占用」提示 | `hotkey_settings_page.dart`（`HotKeyRecorder` 只在弹窗挂载） |

| 8 | 关于页只展示真实信息（应用名 / 版本 / 技术栈 / 开源许可），不虚构 GitHub 与「检查更新」 | `about_settings_page.dart`、`state/app_info.dart` |

| 9 | 切分类就地淡入切换（140ms，尊重系统「减少动画」），不重开窗口 | `settings_page.dart`（`AnimatedSwitcher`） |

| 10 | 最小窗口 860×520 下七个分类都不溢出 | `settings_shell_test.dart` 断言 |



**验收命令**



```bash

(cd packages/quizsync_core && dart analyze && dart test)          # 含 connectedCount 回环断言

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)    # 含 settings_shell_test

(cd apps/android           && flutter analyze && flutter test)

powershell -File tools/build_all.ps1                              # 四包 analyze+test、两端构建、zip 与安装包

```



**DoD**：设置页从「一条长页」变成分类设置中心；`docs/SPEC.md` 2.3 按新结构改写；原有设置项一条都没丢（`settings_shell_test` 的功能清单逐项断言）；四包 analyze 无 issue、测试全绿；`docs/DECISIONS.md` 记录本轮实施期决策；`docs/progress.md` 写出实际验收输出；Windows 便携版与 Inno Setup 安装包重打。



---



## M10 · 用户反馈轮（15 项）



**目标**：落实用户一次性提出的 15 条反馈（Windows 11 项 + 安卓 9 项，其中 2 项跨端）。仍然只改界面/交互与既有模块的内部实现，**不改数据模型与协议语义**（唯一新增的协议字段是 `task_update.image_count`，向后兼容）。



| # | 用户反馈 | 落点 |

|---|---|---|

| 1 | Windows 端字体换 MiSans，题目显示可调字重与字号 | `assets/fonts/MiSans-VF.ttf`、`QuizSyncTheme.build(fontFamily:)`、`QuestionCard.fontWeight`、`question_font_weight` |

| 2 | 主机开始识别后手机端要能自动加载、显示「N 张图片识别中」、完成后显示 | `QuizSyncServer.notifyLocalSession`、`task_update.image_count`、`AnalysisWorkflow.onSessionStarted/onSessionFinished` |

| 3 | 安卓「当前任务」页只当 Windows 的结果显示器，不显示识别模块相关提示 | `apps/android/lib/ui/current_task_page.dart` |

| 4 | Windows 应用内大量图标丢失/显示异常 | 构建加 `--no-tree-shake-icons`（裁剪后图标字体只剩 4.5KB） |

| 5 | 设置页选项要有模块归属，长背景信息可读性差 | `SettingsGroup` 模块标题带 + `SettingsRow/Field.info` ⓘ |

| 6 | Windows 热键设置与调用不正常 → 重写模块与设置页 | `services/hotkeys.dart`（物理键→VK）、`hotkeyStatusProvider`、`hotkey_settings_page.dart` |

| 7 | 两端系统栏/标题栏要跟着主题变（原来一直是黑色） | `windowManager.setBrightness`、安卓 `AnnotatedRegion` + edge-to-edge |

| 8 | Windows 状态栏（托盘）图标缺失，用 `icon/Statusbar.png`，区别于应用图标 | `assets/statusbar.ico`、`tool/make_icons.dart`、运行时落盘后传绝对路径 |

| 9 | Windows 界面缩放 50%–300% | `ui_scale`、`app.dart` 的 `UiScale`（虚拟画布 + dpr 同步） |

| 10 | 安卓一题多页的介绍要写清长按/松手/短按顺序 | 安卓设置页与手势说明文案 |

| 11 | 安卓识别模块设置里的国产 ROM 介绍过时，不点名系统 | 权限/后台说明文案改为通用说法 |

| 12 | 安卓首次打开不自动开扫码，点「使用」后再要权限 | `apps/android/lib/ui/pairing_page.dart` |

| 13 | Windows 关于页的图标不显示 | 改用图片资源 `assets/logo.png` |

| 14 | 安卓悬浮球默认显示在右侧 | `FloatingBallManager.kt` 初始位置与吸附方向 |

| 15 | 两端识别都在后台静默执行，不弹界面 | 安卓去掉跳页/前台唤起；Windows 侧手机任务本来就不抢前台（已写进 SPEC 2.1） |



**验收命令**



```bash

(cd packages/quizsync_core && dart analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)   # 含热键/显示设置新用例

(cd apps/android           && flutter analyze && flutter test)

powershell -File tools/build_all.ps1                             # 含 --no-tree-shake-icons 与打包

```



**DoD**：15 项全部落地；四包 analyze 无 issue、测试全绿；图标字体完整（构建产物里 1,645,184 字节）且 MiSans 随包；托盘图标经 `LoadImage` 实测可加载；`docs/SPEC.md` / `protocol.md` / `DECISIONS.md` / `progress.md` 同步；两端口径一致。



---



## M11 · 用户反馈轮 2（16 项）



**目标**：落实用户第二轮 16 条反馈。这一轮**动了数据模型与 AI 契约**（唯一一次）：

`questions.material`（schemaVersion 2 → 3）与 AI 输出的 `material` 字段 —— 因为「阅读材料默认折叠」

必须是结构化字段，不能靠端侧猜文本；同时把多页硬上限从 12 收紧到 6。协议字段本身没有变化。



| # | 用户反馈 | 落点 |

|---|---|---|

| 1 | Windows 任务栏图标不是圆角 | `tool/make_icons.dart` 生成时用 alpha 遮罩烘焙圆角（半径 22%，3×3 超采样）→ `app_icon.ico` |

| 2 | 导出默认在软件目录下，点击导出时让用户选位置；安卓删掉分享按钮 | 桌面 `nativePickSavePath`（win32 `GetSaveFileNameW`）+ 可注入 `savePathChooser`；`history_page.dart` 删除两个导出入口 |

| 3 | 删掉设置切换动效；设置内容要加白色底模块 | `SettingsGroup` 改为卡片色底圆角容器；`_SettingsContent` 去掉 `AnimatedSwitcher` |

| 4 | 关于页图标错了，是应用图标不是状态栏图标 | 新增 `assets/app_icon.png`（由 `icon/QuizSync_AI.png` 生成），删除 `assets/logo.png` |

| 5 | 多页暂存只有激活时才显示 | `home_page.dart` 暂存条改为 `stagedCount > 0` 才渲染；托盘 tooltip 带页数 |

| 6 | 关于页声明使用的字体与协议 | 关于页「字体与许可」模块（MiSans + 官方 FAQ + Material Icons） |

| 7 | 缩放只提供下拉档位，不提供进度条，选后自动更新窗口边界 | `kUiScalePresets`（11 档）+ `applyUiScaleToWindow` |

| 8 | API 页默认填 DeepSeek 的模型名与 baseUrl；点连接设备页自动刷新配对码与二维码 | `AiUiSettings.defaultModel/defaultBaseUrl`；`DeviceSettingsPage.initState` → `refreshPairingCode()` |

| 9 | 多页硬上限就是 6 张，不是 12 | `kHardMaxPagesPerTask = 6`（契约 + 三处 UI + 安卓单测同步） |

| 10 | 数据放应用所在目录，按钮打开资源管理器 | `resolveDataDir()`（`<exe>/data`，不可写/有旧库时兜底）+ 数据管理页「打开目录」 |

| 11 | 双端切换深浅色后状态栏不跟着变 | Windows 标题栏：自己调 DWM（`services/window_theme.dart`；`window_manager.setBrightness` 在系统浅色时恒为 no-op，是插件 bug）。安卓：系统栏显式配色 + 平台通道强制重发（绕开 Flutter 的样式缓存） |

| 12 | 双端静默互显：本机静默、对端显示识别界面与结果 | Windows：`_toast(reveal:)` + `onTaskUpdateHook`/`remoteTaskSession`；安卓：`ActiveTask.shownSessionId/autoOpenResult`、`next-task-banner`、前台门控自动进结果页 |

| 13 | AI 不确定的选中选项不用绿色，用黄色 | `HighlightColors.text/background(uncertain:)` + `QuestionCard` 用 `needsReview`；✓ → `help_outline` |

| 14 | 多页热键调用失败、设置无法保存；只有材料的页识别不了；页序可能乱 | 三个槽位指纹触发重注册（`hotkeySettingsSignature`）；prompt 增加「自行排序」与「材料页不丢弃」；`material` 字段 |

| 15 | 阅读类材料默认折叠可展开；主观题结构化 | `Question.material/hasMaterial/hasStructuredAnswer` + `QuestionCard` 折叠面板与分行答案 + prompt 分点要求 |

| 16 | 安卓当前任务页不重复显示连接；粘贴配对链接独立成方式二 | `current_task_page.dart` 去掉重复连接行；`pairing_page.dart` 拆成方式一/二/三 |



**验收命令**



```bash

(cd packages/quizsync_core && dart analyze && dart test)          # 含 material 往返/同步、迁移 v3、阅读材料解析

(cd packages/quizsync_ui   && flutter analyze && flutter test)    # 含标黄、材料折叠、主观题分行

(cd apps/desktop           && flutter analyze && flutter test)    # 含数据目录、热键指纹、暂存条、导出另存为

(cd apps/android           && flutter analyze && flutter test)    # 含下一轮悬浮窗、自动进结果页、配对三模块

powershell -File tools/build_all.ps1

```



**DoD**：16 项全部落地；四包 analyze 无 issue、测试全绿；AI 契约 prompt 与 `prompt.dart` 逐字一致；

`material` 列有 v2→v3 迁移与往返测试；图标为圆角且关于页用应用图标；双端「本机静默 / 对端显示」方向正确；

`docs/SPEC.md` / `ai-contract.md` / `protocol.md` / `data-model.md` / `DECISIONS.md` / `progress.md` / `README.md` 同步。



---



## M12 · 用户反馈轮 3（12 项）



**目标**：落实用户第三轮 12 条反馈。这一轮的四个 bug **全部是「上一轮以为改好了、其实没改到根因」**，

所以每条都先用可复现的证据定位再改：



1. **导出全部失败**：不是对话框弹不出来 —— 给发布版加临时探针、打印 `CommDlgExtendedError`，

   拿到 `0x3002`（`FNERR_INVALIDFILENAME`），确认是预填路径混用了正反斜杠（`Directory('$root/exports')` 留下 `/`），

   而旧代码把「返回 0」一律当成「用户取消」，于是既没弹窗也没提示。

2. **热键串键**（单张键进了多页模式 / 添加页面键直接识别 / 改了键不生效）：`RegisterHotKey(NULL,id,…)` 绑在

   **线程**上，旧实现「每槽位一个 isolate、id 固定为 1、靠 isolate 退出隐式释放」在 Dart 线程池复用下会留下

   旧注册；新 isolate 落到同一线程 → 注册失败（回退到别的键）而旧键照常生效，它的 `WM_HOTKEY` 被该线程上

   另一个槽位的轮询泵读走。改为**单 isolate + 槽位固定 id + 显式 `UnregisterHotKey`**。

3. **界面缩放不跟内容**：真跑一遍发现 `ui_scale=0.5` 时窗口被最小尺寸 860×520 卡住（日志与

   `GetWindowRect` 对照），修成「最小尺寸随比例放开 + 启动按已保存缩放摆窗口 + 最大化先还原」。

4. **托盘图标不是圆角**：源图 `icon/Statusbar.png` 是白底不透明，M11 只给应用图标做了圆角。



新功能只有一项：**Windows 悬浮球**（用户反馈 11），用原生分层窗口实现，三态图由源图去白底 + 圆形化生成。



| # | 用户反馈 | 落点 |

|---|---|---|

| 1 | Windows 状态栏图标不是圆角，要按 `icon/Statusbar.png` 重画 | `make_icons.dart` 对 `statusbar.ico` 套与应用图标同一套 22% 圆角遮罩；回归测试直接解码 ICO 帧断言角上 alpha=0 |

| 2 | 所有导出全部失败，不弹系统「另存为」 | `normalizeForDialog()` 归一化路径（真凶是 `FNERR_INVALIDFILENAME`）；错误码非 0 时抛 `StateError` 并在界面报错；`CommDlgExtendedError` 写日志；新增 `save_dialog_path_test.dart` |

| 3 | 模块标题带还是透明背景；连接设备每个模块有两个背景 | `settingsGroupHeaderColor()`（主色薄涂）；`device_settings_page.dart` 去掉 `_statusCard`/`_pairingCard` 自己的卡片 |

| 4 | 设置每个选项模块之间距离太远 | `SettingsSection` 模块间 32→16、标题段后 32→20、页面纵向 40→28 |

| 5 | 设置热键时也会触发截屏 | `hotkeysSuspendedProvider`：进热键页暂停全部全局热键，离开恢复（恢复放在微任务里，避开 unmount 期改 provider） |

| 6 | 单张热键进多页模式 / 添加页面热键直接识别 / 改键不生效 | `hotkey_service.dart` 重写为单 isolate + 固定 id（capture=1/append=2/finish=3）+ 每次注册前 `UnregisterHotKey` + 退出前显式注销 |

| 7 | 双端序号要放到识别题号的外面前面 | `QuestionCard` 新增 `question-seq`（序号在徽标外），徽标只放 `questionNoLabel`；`Question.displayTitle` 不变（导出/安卓结果行仍用它） |

| 8 | 缩放后边框不跟随内容，留下一大片黑块 | `applyUiScaleToWindow(newScale, previousScale:)`（unmaximize + 最小尺寸按比例 + 请求/实际尺寸写日志）+ `applyStoredUiScaleToWindow` + 设置页内容居中 |

| 9 | 安卓解析下的提示不换行、当前任务答案溢出 | `QuestionCard._warnings` 改为换行提示块（`HighlightColors.warnText`）；安卓 `_answerLine` 答案改 `Expanded` + `softWrap` |

| 10 | 「重新注册全部热键」连点会触发 bug，改成恢复默认 | 「恢复默认热键」按钮（三个自定义键一次清空，无自定义键时置灰）；根因（线程级注册泄漏）同时在 6 里修掉 |

| 11 | 为 Windows 加悬浮球（三态图、去白底圆形化、开关/大小/透明度/描边） | `services/floating_ball.dart`（原生分层窗口 + `UpdateLayeredWindow` + WndProc 手势）；三态 PNG 由 `make_icons.dart` 去白底 + 圆形遮罩生成；新增设置分类「悬浮球设置」与六个 `ball_*` 设置键 |

| 12 | MiSans 许可链接末尾不要多打 `/` | 关于页 `misansFaqUrl = 'https://hyperos.mi.com/font/faq'`（pubspec 注释同步） |



**验收命令**



```bash

(cd packages/quizsync_core && dart analyze && dart test)          # 含 AppLogger 落盘

(cd packages/quizsync_ui   && flutter analyze && flutter test)    # 含序号在徽标外、提示换行

(cd apps/desktop           && flutter analyze && flutter test)    # 含另存为路径归一化、热键页暂停、悬浮球资源、托盘圆角

(cd apps/android           && flutter analyze && flutter test)    # 含当前任务答案换行

powershell -File tools/build_all.ps1

```



**本机实测证据**（无法自动验证的部分也留了机器可查的痕迹）



- 另存为：发布版 exe + 临时探针，日志出现 `另存为选中`/`FNERR_INVALIDFILENAME`；修完窗口枚举看到

  `#32770 | 导出全部历史（Markdown）`，路径为 `…\userdata\exports`。

- 悬浮球：`GetWindowRect` 显示 `QuizSyncFloatingBall` 64×64 贴右边缘；模拟拖动后窗口位移且日志写

  「悬浮球移动到 (3072,856)」；`PrintWindow` 回读球面得到主色 `(29,134,253)`（蓝）。

  期间实测修掉一个真 bug：`_createWindow` 预置 `_bitmapSize` 会让 `_ensureBitmap` 被跳过 → 窗口建出来但

  **什么都没画**（只在真跑一次才暴露）。

- 缩放：`ui_scale=0.5` 时窗口由 860×520（被最小尺寸卡住）变为 590×380。



**DoD**：12 项全部落地；四包 analyze 无 issue、测试全绿（core 170 / ui 12 / desktop 108 / android 57）；

两项新资源（三态悬浮球 PNG）已进 `pubspec.yaml` 并有断言；热键与另存为两条根因都写进 `DECISIONS.md`；

`docs/SPEC.md` / `DECISIONS.md` / `progress.md` / `README.md` / `AGENTS.md` 同步。



---



## M13 · 用户反馈轮 4（1 项：安卓状态栏跟随主题）



**目标**：修掉「安卓端状态栏（时间 / 通知 / 电量）不跟着浅色深色变」这一条 —— 它**已经被修过两次**

（M10 反馈 7、M11 反馈 11），用户第三次反馈「依旧不会变」。所以本轮先拿证据，再动代码：



**证据（反编译本项目实际使用的引擎产物）**



```bash

javap -p -c -cp <flutter>/bin/cache/artifacts/engine/android-arm64-release/flutter.jar \

      io.flutter.plugin.platform.PlatformPlugin

# → setSystemChromeSystemUIOverlayStyle():

#     statusBarColor != null

#     Build.VERSION.SDK_INT >= 35  →  if_icmpge 跳过

#     window.setStatusBarColor(color)        ← 只在 API 34 及以下执行

#   图标明暗那一支没有版本限制：

#     WindowInsetsControllerCompat.setAppearanceLightStatusBars(...)

```



结论：**Android 15（API 35）及以上，Flutter 引擎根本不设状态栏底色**，只设图标明暗；

平台 15 起也规定状态栏区域显示的就是应用自己画的内容。于是：

- M10 的「透明底 + 图标明暗」→ 底色一直是启动窗口主题的默认值（黑色）；

- M11 的「显式给颜色」→ 那个颜色**下发得到平台，但引擎不会用它**。



这解释了为什么两轮都「改完还是没变」，也说明必须在**应用侧**解决，而不是继续调下发参数。



**改动（三层，缺一层就会在部分机器上失效）**



| # | 做法 | 落点 |

|---|---|---|

| 1 | **底色由 App 自己画**：顶部安全区（`MediaQuery.padding.top`）画一条与应用顶栏同色的条带，`IgnorePointer` 不吞触摸；没有顶部 inset 时不画 | `apps/android/lib/ui/system_ui.dart` → `ThemedSystemUi.statusStripKey` |

| 2 | **图标明暗走自家 Kotlin 桥**：`WindowInsetsControllerCompat.isAppearanceLightStatusBars/isAppearanceLightNavigationBars`；API < 35 时顺带设 `window.statusBarColor/navigationBarColor` 与 `isStatusBarContrastEnforced=false`；样式缓存在原生侧，`onResume` / 获焦时**重贴**（Android 会重置这些窗口标志，引擎 `enableEdgeToEdge()` 就把 visibility 清成 0） | `systemui/SystemUiBridge.kt` + `MainActivity.kt` + `services/system_ui_channel.dart` |

| 3 | **启动窗口别再定死颜色**：`LaunchTheme`/`NormalTheme` 的系统栏改透明，只声明 `windowLightStatusBar`（浅色 true / 深色 false）；`app/build.gradle.kts` 显式声明 `androidx.core:core:1.13.1` | `res/values/styles.xml`、`res/values-night/styles.xml` |



**验收命令**



```bash

(cd apps/android && flutter analyze && flutter test)              # 含自绘条带与自家桥 payload

(cd apps/android && flutter build apk --split-per-abi --release)  # 必须过 Kotlin 编译（新桥）

```

其余三包本轮未改代码，验收沿用 M12 的结论（core 170 / ui 12 / desktop 108 全绿）。



**本机实测证据**



- 反编译输出见上（`javap` 结果，`SDK_INT >= 35` 跳过那一支）。

- 安卓单测 60 项全绿（新增 3 项）：浅色主题条带颜色 = `0xFFFFFFFF`、只盖 `Rect(0,0,800,24)`；

  深色主题条带颜色不同；顶部 inset 为 0 时不画；自家桥两次 payload 的 `dark` 与两种颜色都不同。

- `flutter build apk --split-per-abi --release` 成功 → 三个 APK（Kotlin 新桥编译通过）。



**未验证（需人工）**：真机上状态栏的实际观感与「回前台 / 录屏授权后不被系统重置」——

清单见 `docs/manual-test-android.md` 第 25 项；必须装 **构建 4**（构建 2/3 在这一条上注定无效）。



**DoD**：安卓包 analyze 无 issue、测试全绿（60）；根因与三层方案写进 `DECISIONS.md` 与 `SPEC.md` 3.1.2；

`progress.md` / `milestones.md` / `manual-test-android.md` / `AGENTS.md` 同步；构建号 +1 并重新出包。



---



## M14 · 用户反馈轮 5（8 项）



**目标**：落实第五轮 8 条反馈。两条是「老 bug 又说没修好」（缩放的黑块、双端静默互显），

照旧先拿证据再改；三条是有明确机制性根因的（剪贴板、悬浮球内存、ⓘ 死图标）。



**逐条与落点**



| # | 用户反馈 | 根因 / 做法 |

|---|---|---|

| 1 | 缩放 50% 时界面只剩一半、留一片黑 | **不是窗口尺寸**（M12 改的是那个）：根节点给的是**紧约束**，`Transform.scale(child: SizedBox(虚拟尺寸))` 里那个 SizedBox 被夹回窗口尺寸 → 界面按窗口尺寸布局再缩小一半，只画左上角，其余没有任何 widget 覆盖（引擎清屏色）。修法：虚拟画布套 `OverflowBox`。新增 `ui_scale_test`（断言铺满子块缩放后的全局矩形 == 窗口） |

| 2 | API 配置里名称后的 ⓘ 毫无作用 | 原来是一个 14px 裸 `Icon` 套 Tooltip：点击无反应、悬停命中区只有 14px；某些调用方传空文案却照样渲染。改成 28×28 `IconButton` + Tooltip + 点击弹 `AlertDialog` 看全文，空文案不渲染。新增 4 条测试 |

| 3 | 剪贴板监听毫无作用 | **实测根因**：现代剪贴板的 `CF_DIB` 是 `BI_BITFIELDS`（本机 .NET 放图实测 `comp=3`、`GlobalSize` 正好 = 头 40 + 掩码 12 + 行字节×高），旧解析只认 `BI_RGB` → 每步都成功、最后静默 null。改为 CF_DIB→CF_DIBV5、按掩码取色、按 DIB 头算字节数，并修 `_readI32` 未做符号扩展。新增 6 条测试（含真实系统剪贴板） |

| 4 | 悬浮球打开不显示、内存飙升；默认打开 | 内部实测球能渲染（`PrintWindow` 回读有像素）；内存是真问题：固定素材每次切状态都重新解码 + 缩放 + 逐像素预乘，300 次切换 RSS 163.5 → 216.6 MB。加渲染缓存后 159.2 → 175.0 MB 并停住。另把默认改成打开 |

| 5 | 配对成功后跳到「当前任务」 | 切标签只在 `PairingPage._pair` 成功那一处（扫码/粘贴/手输三条路都汇合于此），并补上「从主页推入时收起配对页」的 pop（否则用户仍停在配对页） |

| 6 | Windows 识别后 Windows 弹窗、安卓毫无反应 | 两个独立缺陷：① `notifyLocalSession` 走了 `notifyTaskUpdate`，会触发桌面端「手机任务 → 窗口带到前台」的钩子 → 本机按热键主窗口自己跳出来；② 手机漏掉断线/中途连接期间的 `task_update`/`task_result` → 「一点反应没有，也不同步」。修法：本机截屏只广播不触发钩子 + 记住进行中的本机任务并在 WS 握手后补发；安卓订阅 `connectionState`，重连成功即补齐状态与数据 |

| 7 | 安卓图片要与 Windows 同一位置；安卓固定留 20 张、去掉缓存选项 | 手机上传图片改写到与 Windows 本机截图同一个 `images` 目录（原来各一个）；安卓本地固定 `kAndroidLocalImageLimit = 20`，删掉识别设置里的「图片缓存上限」整块 UI（共享字段保留给 Windows） |

| 8 | 主界面 QuizSync 前面显示软件图标 | 顶栏 logo 换成 `assets/app_icon.png`（与关于页同一份资源，26×26 圆角裁剪），三处 logo 从此一致 |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && flutter test)    # 含双端回环：本机截屏不触发钩子 + 中途连上补发状态

(cd packages/quizsync_ui   && flutter analyze && flutter test)    # 含 ⓘ 的行为与「空文案不渲染」

(cd apps/desktop           && flutter analyze && flutter test)    # 含缩放铺满、真实剪贴板 DIB、悬浮球缓存

(cd apps/android           && flutter analyze && flutter test)    # 含配对后切标签、固定 20 张、WS 重连补齐

(cd apps/desktop && flutter build windows --release)              # 交付物

(cd apps/android && flutter build apk --split-per-abi --release)  # 交付物

```



**本机实测证据**（照旧：能跑的 bug 都先跑出证据再改）



- 剪贴板：`Clipboard.SetImage` 放真图 → 枚举剪贴板打印每个格式的 `GlobalSize`/`GlobalLock`/DIB 头；

  修前 `readClipboardImageNow()` 返回 **null**，修后返回 **120×80**；真实剪贴板用例进测试套件。

- 缩放：`ui_scale_test` 在 900×600 窗口里断言「子块缩放后的全局矩形 == 900×600」——修之前是 450×300（就是那片黑）。

- 悬浮球：进程内探针反复切状态 300 次，改前 RSS `163.5 → 216.6 MB` 且仍在涨，改后 `159.2 → 175.0 MB` 停住；

  GDI/USER 句柄全程 2/3，`dispose` 后归 0/1（无句柄泄漏）。

- 双端互显：core 侧真服务端 + 真 WS 客户端 4 条用例（含「本机截屏不得触发钩子」「中途连上要补发」「已结束不补发」）。



**DoD**：四包 analyze 无 issue、测试全绿（core 174 / ui 19 / desktop 119 / android 62）；

两端 release 构建通过；根因与取舍写进 `DECISIONS.md`；`SPEC.md` / `progress.md` / `README.md` / `AGENTS.md` /

`manual-test-android.md` 同步；安卓构建号 4→5。



---



## M15 · 用户反馈轮 6（4 项）



**目标**：第四轮反馈里的 4 条。三条是上一轮改动**没生效/只改了一半**，一条是用户明确点名要的兜底机制。



| # | 用户反馈 | 根因 / 做法 |

|---|---|---|

| 1 | 悬浮球显示了，但大小 / 透明度调不动、描边开不了、开关无用（一直开着） | **不在悬浮球实现里**：`settingsProvider` 是 `ChangeNotifierProvider`，它的值就是 controller 实例本身 —— 直接 `listen` 整个 provider 时 `prev` 与 `next` 是同一个对象（读到的都是刚更新过的 `app`），「前后签名相等」恒成立，`_applyBallSettings()` 一次都没执行。改用 `select((s) => ballSignature(s.app))`；**热键指纹监听是同一个坑，一并改掉**。`settings_listener_test.dart` 把这个语义钉住 |

| 2 | 安卓传的图没进 Windows 截图目录、主界面也没有缩略图 | 目录那半 M14 已合并；缩略图这半是真 bug：`_handleImageUpload` **先写文件、后又查了一次库**，而写文件不建 `images` 行 → `localPath` 恒为 null（主界面缩略图 / 结果页 / 「重新分析」都靠这一列）。改用 `imageStore.pathFor(hash)`，路径变化时显式 `setImageLocalPath`（`upsertImage` 的改动判定不含本地专属列，只改这一列会走「无变化直接返回」的短路）；客户端再加「`local_path` 空/文件不在 → 回落 `<数据目录>/images/<hash>.jpg`」 |

| 3 | 悬浮球识别后 Windows 界面还是会跳出来 | `ScreenCaptureService.hideWindowWhile` 恢复时用 `ShowWindow(SW_SHOW)`（本身就会激活窗口）**加无条件 `SetForegroundWindow`** → 每识别一次都把主窗口抢到前台。热键路径看不出来只是因为人本来就在本程序里。改为 `SW_SHOWNOACTIVATE`，且只有「藏之前本来就是前台窗口」时才还焦点 |

| 4 | 安卓「当前任务」页不刷新，要求「一直刷新，比如 1 秒获取一次状态」 | WS 推送在用户那台机器上不可靠（安卓→Windows 的上传走 HTTP 一直正常）。按用户要求加**轮询兜底**：配对且在前台时每 1 秒问一次主机状态，与 WS 并存、复用同一套 `LiveUpdateSink` 语义（识别中 → 自动进结果页 → 悬浮横幅），状态没变不触碰界面 |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && flutter test)    # 含上传路径 local_path、轮询端点

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)    # 含设置监听语义、缩略图回落

(cd apps/android           && flutter analyze && flutter test)    # 含轮询器生命周期与语义

(cd apps/desktop && flutter build windows --release)

(cd apps/android && flutter build apk --split-per-abi --release)

```



**本机实测证据**



- 悬浮球设置（发布版 exe）：库里写 `ball_size=96 / ball_opacity=0.5 / ball_stroke=1 / width=6` 后启动，

  悬浮球窗口从默认 112px 变成 **192px**（日志 `ball: 悬浮球显示于 (3008,704) 192px 状态=待识别`，

  窗口枚举同为 96×96 —— 枚举进程 DPI-unaware，值 = 物理/2）；写 `ball_enabled=0` 后窗口列表里**没有** `QuizSyncFloatingBall`。

- 缩略图链路：core 侧真服务端 + 真 HTTP 上传 3 条（落盘且在目录里 / 重复上传不抹掉路径 / 老记录重传补路径）。

- 设置监听语义：`settings_listener_test.dart` 断言「直接监听时 `identical(prev, next)` 且 `prev.app` 已是新值」，

  以及修好后四次改动（大小/透明度/描边/开关）各触发一次。

- 截屏恢复窗口的**抢焦点**这一条只做了代码级修正（`SW_SHOW` 会激活窗口是 Windows 既有语义），

  没有自动化验证手段：要在真机上让「别的应用在前台」再点悬浮球才能观察到，已写进人工清单第 27 项。



**DoD**：四包 analyze 无 issue、测试全绿；两端 release 构建通过；三条根因写进 `DECISIONS.md` 与 `AGENTS.md` 环境事实；

`SPEC.md` / `progress.md` / `README.md` / `manual-test-android.md` 同步；安卓构建号 5→6。



---



## M16 · 用户反馈轮 7（3 项）



**目标**：第五轮反馈里的 3 条 —— 悬浮球描边的**方向与配色**、悬浮球**左键手势**的语义，以及「停在结果页时看不见电脑进度」。



| # | 用户反馈 | 根因 / 做法 |

|---|---|---|

| 1 | 悬浮球描边要**向外**（不是向内），颜色**加深** | 旧实现把环带以「画布边缘半径」为中心往**里**画：环带压在球体上，而且颜色就取状态主色 —— 球素材本身就是「主色圆 + 白色内芯」，同色环画在球上等于看不出描边。改为向外：画布边长 = 球 + 两侧 `描边宽 × DPI`，环带整圈落在球体之外；颜色取状态主色每通道 ×0.72（`#1D86FC`→`#1560B5` / `#1EB945`→`#168532` / `#FBD705`→`#B59B04`）。几何与配色抽到纯函数模块 `services/ball_paint.dart`（不依赖 Flutter/win32，可纯单测）。顺手修掉 `applyAppearance` 只在「圆整后尺寸变了」才置脏标记的漏画（只改**描边透明度**时窗口一像素不变） |

| 2 | 左键点击不变、**左键长按改为右键**（进入多页），结束多页仍是左键单击 | 长按原来靠 `SetTimer` + `WM_TIMER` —— 消息队列里**优先级最低**、只在没有别的消息时才生成的消息：用户按住不放时松手产生的 `WM_LBUTTONUP` 会先被处理，`_endDrag` 顺手 `KillTimer`，一次长按被判成单击；而且长按与右键本来就是两条独立分支。改为**松手时按按住时长结算**（`BallGestureTracker`：<500ms 单击 / ≥500ms 长按 / >8px 拖动，拖动优先），长按与右键走同一个 `onLongPress`；单击 / 左键长按 / 右键各补一条 `ball` 日志 |

| 3 | 已经进入识别结果后，Windows 识别时安卓端不显示；要在结果上显示「正在识别 / 完成识别」并跳新页面 | 「当前任务」页的悬浮横幅被结果页压在 `IndexedStack` 下面，用户停在结果页时什么都看不到。结果页自己加一条浮层（共用 `NextRoundBanner` + `Stack/Positioned` 浮在结果内容之上），判定用新加的 `ActiveTask.hostInitiated`：**本机识别的回声不算**（用户需求 3 的静默）、**正在看的那次自己的重新生成不算**。跳页仍然只有一个出口 —— 一直挂着的「当前任务」页消费 `autoOpenResult` 后 push，结果页只显示「识别完成，正在打开新结果…」 |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)    # 含描边几何/配色、手势判定

(cd apps/android           && flutter analyze && flutter test)    # 含结果页浮层与真实结构跳页

(cd apps/desktop && flutter build windows --release)

(cd apps/android && flutter build apk --split-per-abi --release)

powershell -File tools/package_windows.ps1

```



**本机实测证据**



- 描边方向与配色（发布版 exe + `PrintWindow` 回读真实窗口像素，探针脚本见 `DECISIONS.md`）：

  - 旧实现：窗口 112px，中线 x=0..6 = `#1D86FC`（球自己的主色，环带压在球上）、球外没有像素；

  - 新实现：窗口 **136px**（112 球 + 2×12 描边），中线 x=0..11 = **`#1560B5`**（加深后的描边，整圈在球外），x=12 起才是球自己的 `#1D86FC`；

  - 切到多页模式后同一位置变成 `#168532`（加深后的绿）、识别中变成 `#B59B04`（加深后的黄）—— 三个状态的**向外 + 加深**都在真窗口上量到了。

- 手势语义（同一发布版 exe，鼠标移到球心后 `PostMessage` 合成手势）：

  - 日志出现 `ball: 悬浮球：左键长按 → 追加一页（多页模式）`（按住 700ms）、`ball: 悬浮球：单击`、`ball: 悬浮球：右键 → 追加一页（多页模式）`；

  - 状态时间线：长按/右键后球变成多页绿（`#168532` 外圈），长按之后的那次**单击把多页收尾**（球回到蓝）；

  - **静默**：先把主窗口 `WM_CLOSE` 收进托盘（`IsWindowVisible=False`，前台是别的程序），再发右键追加页 → 球变绿而主窗口**依旧隐藏**、前台窗口也没变（若走 `_reveal()` 会立刻可见，同一探针里「收尾时缺 API Key」那条就把它带了回来，说明这个检查是有效的）。

- 手势判定与描边几何的纯单测：`ball_gesture_test`（4 条）、`ball_paint_test`（4 条）。

- 安卓结果页浮层：`result_page_test` 5 条（识别中浮层 / 本机识别静默 / 完成后文案 / 自己重新生成不弹 / **真实结构**＝当前任务页在下面 + 结果页在上面时，完成后新结果页被推上来且只推一个）。

- **没有验证的**：真机上「电脑正在识别」浮层的观感、以及用户那台机器上 WS/轮询的到达时机 —— 已写进人工清单第 28 项（构建 7）。



**DoD**：四包 analyze 无 issue、测试全绿；两端 release 构建通过（便携包 + 按 ABI 拆分的 APK）；

`DECISIONS.md` / `SPEC.md` / `AGENTS.md` 环境事实 / `progress.md` / `manual-test-android.md` 同步；安卓构建号 6→7。



---



## M17 · 用户反馈轮 8（6 项）



**目标**：第六轮反馈里的 6 条 —— 悬浮球的默认外观与描边几何、中文应用名、关于页补项目地址、安卓前台轮询再次漏刷新、Windows 删除合集要同步到安卓、API Key 页给出申请入口。



| # | 用户反馈 | 做法 |

|---|---|---|

| 1 | 悬浮球默认大小 40、透明度 70%、描边默认开·宽 4·不透明 25%；描边渲染在球**下方**、并向内多渲染 2 填掉「球不是标准圆」的缝 | 默认值全部改成常量（`kDefaultBallSize=40` / `kDefaultBallOpacity=0.7` / `kDefaultBallStroke=true` / `kDefaultBallStrokeWidth=4` / `kDefaultBallStrokeOpacity=0.25`），布尔项走「键不存在 → 常量默认值」的写法（M14 踩过的坑）；`composeBallFrame` 增加 `insetPx`：环带内缘 = 球半径 − 2 逻辑像素，**先画环带、再把球按 alpha 盖在上面**（球体不被染色，只有球边缘透明处才透出内重叠 = 填缝） |

| 2 | 加中文名「AI 双端搜题」，默认显示中文名，安卓应用名也要中文 | `kAppName = 'AI 双端搜题'`（两端），新增 `kAppNameEn = 'QuizSync AI'`：窗口标题 / 单实例提示 / 托盘提示 / `findAppWindow` 查找用的标题 / MaterialApp title / 关于页 / 安卓 AppBar / **AndroidManifest `android:label`** / **exe 的 FileDescription·ProductName** / 安装包 AppName·默认目录·快捷方式 全部改中文；`main.cpp` 里的预标题保留 ASCII（MSVC 源码编码不确定，真正的标题由 window_manager 启动时设置） |

| 3 | 双端关于页标明 GitHub 地址，版本号统一 1.0.0 | 新增 `kGitHubUrl`；桌面关于页加「项目」模块（GitHub 仓库 + 打开按钮），安卓关于页加可点复制的地址行（不引入 url_launcher）；版本两端都是 `1.0.0`，构建号桌面 1→2、安卓 7→8（构建号只是「装的是哪一版」的标识） |

| 4 | Windows 识别时安卓「当前任务」又是不能刷新（要求只要前台就一秒一刷新） | 轮询器新增 `uiSignature`：除了「主机指纹变没变」，还比**界面当前展示的任务签名**；界面停在别的任务上就补发一次（上次通知丢了 / 被后台吞了），界面为空（用户点过「忽略」）不补发。另外把 `done` 的「本地库已有同版本就跳过」换成「界面已显示才跳过」—— 主机**同图复用**会复用 `session_id`，本地早有记录但界面还停在上一轮，旧逻辑会把结果静默丢掉 |

| 5 | Windows 新建合集界面要能删合集（带确认），删完安卓同步也要跟着删 | 删除入口与二次确认 M8 起就在「新建/选择任务合集」页（软删除 + 同步 op），真正缺的是**安卓的触发时机**：`/tasks/active` 新增 `ops_lamport`（主机本地 ops 水位），轮询发现水位涨了就做一次 `pullFromPeer`（只拉不推，不 drain 队列）；WS 的 `ops` 消息也走同一条路径。core 侧新增「主机删合集 → 客户端 pull-only 之后本地也没了」的集成测试 |

| 6 | API Key 页面下面写上推荐 `https://platform.deepseek.com/api_keys` | API 配置页的 API Key 项下面加一行推荐（地址 + 「去申请 Key」按钮 + ⓘ 说明），走已有的 `openExternal` |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)

(cd apps/android           && flutter analyze && flutter test)

(cd apps/desktop && flutter build windows --release)

(cd apps/android && flutter build apk --split-per-abi --release)

powershell -File tools/package_windows.ps1

```



**DoD**：四包 analyze 无 issue、测试全绿；两端 release 构建通过；exe 属性里的显示名与版本用 `(Get-Item exe).VersionInfo` 复核；

`DECISIONS.md` / `SPEC.md` / `AGENTS.md` / `progress.md` / `manual-test-android.md` 同步；安卓构建号 7→8，桌面构建号 1→2。



---



## M18 · 用户反馈轮 9（4 项）



**目标**：第七轮反馈里的 4 条 —— 版本就是 1.0.0 正式版（界面不再写构建号）、安卓端能选中删除合集、

安卓结果页上的「电脑正在识别中」浮层要画在最上层且 85% 不透明、安卓端要能同步 Windows 的分类

（并且**改掉** M17 第 5 条：Windows 删合集不再让安卓跟着删）。



| # | 用户反馈 | 做法 |

|---|---|---|

| 1 | 「关于不要写构建 8，这就是 1.0.0 正式版，前面全是预览版」 | 两端关于页的版本行去掉「（构建 N）」：桌面 `Windows 桌面版 · v1.0.0`、安卓 `局域网搜题工具 · v1.0.0`；删掉 `kAppBuildNumber` 常量与 `Runner.rc` 里指向它的注释。出包序号只留在 `pubspec.yaml` 的 `1.0.0+N`（安卓 `+8`→`+9`、桌面 `+2`→`+3`），它的唯一作用是把 `versionCode` 顶上去、保证新包能覆盖安装 |

| 2 | 「安卓端可以选中删除合集」 | 历史页的合集分组支持**长按选中**：进入多选模式后顶部出现一条操作栏（已选 N 个合集 · 取消 · 删除），多选模式下单击 = 切换选中；「未分类」不是合集、不可选。删除走二次确认（按钮带 key），**不级联删记录**（记录回到「未分类」，与 Windows 端语义一致）；本机删除照常生成 op 同步给主机 |

| 3 | 「安卓端已经进入识别结果页面后，windows 端识别时安卓端的悬浮窗提示渲染在识别结果题目下。修改为渲染到最上层，同时调整这个的不透明度为 85%」 | 结果页 `Stack` 的孩子顺序调过来：浮层从**第一个**孩子改成**最后一个**（`Stack` 里后画的在上层，原来被 `Positioned.fill` 的内容盖住）；`NextRoundBanner` 新增 `opacity`（默认 1），结果页传 `kResultBannerOpacity = 0.85`，且只作用在**卡片底色**上（`color.withValues(alpha:)`）而不是整窗 `Opacity` —— 压在题目上时文字与图标仍完全不透明才读得清 |

| 4 | 「安卓端现在识别不到无法同步 windows 端的分类，想办法完成同步」＋「修改上次的第 5 条：windows 端删除后安卓端不再同步跟着删除」 | ① `GET /api/v1/tasks/active` 新增 `collections`（主机**当前活跃合集列表**），`ActiveTaskView.collections` 解析；`HostStatusPoller` 新增 `onHostCollections`，**第一次观测就回调**、之后只在列表指纹（id:name:updatedAt）变化时回调，写库失败会把指纹撤回以便下一轮重试。② 宿主调 `AndroidSync.mirrorHostCollections` → `CoreRepository.mirrorCollections`：**只增改、不删**、本机已删的合集绝不复活、不产生 sync op。③ 语义反转：`CoreRepository(applyRemoteCollectionDeletes: false)`（安卓端）—— 远端「删除合集」的 op 照常入库 + observe 时钟（拉取游标不卡），但不回写 `deleted_at`，手机本地的分组保留；桌面/单测默认 `true`，core 契约不变 |



**为什么第 4 条的旧做法会漏**：合集原来只有一条落地通道 —— ops 拉取，而拉取由 `opsLamport`

水位这种**间接信号**触发（第一次只建基线、水位不涨就不拉、失败后不自愈）。任一环节出问题，

手机本地就永远没有那一行合集，主机识别的记录于是在手机历史里全被算进「未分类」。

新做法直接把「主机现在有哪些合集」这份**想要的结果**放进每秒一次的探测里，差什么补什么。



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)

(cd apps/android           && flutter analyze && flutter test)

(cd apps/desktop && flutter build windows --release --no-tree-shake-icons)

(cd apps/android && flutter build apk --split-per-abi --release --no-tree-shake-icons)

powershell -File tools/build_all.ps1   # 上面全部步骤 + 打包成 dist\ 交付物，末行 ALL GREEN

```



**DoD**：四包 analyze 无 issue、测试全绿（core 192 / ui 21 / desktop 132 / android 83）；两端 release

构建通过且产物重新打包；`DECISIONS.md` / `protocol.md` / `AGENTS.md` / `progress.md` /

`manual-test-android.md` 同步；安卓 `versionCode` 1008→**1009**（出包序号 8→9，界面上不显示）。



---



## M19 · 用户反馈轮 10（3 项）



**目标**：第八轮反馈里的 3 条 —— 主界面右上角药丸改报**配对状态**（不再是「服务 · N 台」）、

Windows 端**随时都能删合集**（不只是启动时的合集选择页）、安卓**识别模块写明「可能识别时间过长，不建议开启」**。



| # | 用户反馈 | 做法 |

|---|---|---|

| 1 | 「Windows 端主页面右上角服务：0 台修改为显示如『已配对设备：安卓设备』、『未配对』」 | 顶栏药丸改由 `_pairedDevicesProvider`（`listDevices()` 过滤 `isRevoked`）驱动，文案走纯函数 `serverPillLabel` / `pairedDeviceLabels`：有设备 → `已配对设备：安卓设备`（多设备以 `、` 连接、按标签去重；**安卓端按平台统一写「安卓设备」**，非安卓设备写自己的名字），无设备 → `未配对`，服务未起来 → 仍是 `服务未启动`（故障优先）。端口与设备清单退到 tooltip。原来的「服务 8765 · 0 台」写的是**此刻连接数**，手机配对过但没开着 App 时永远是「0 台」 |

| 2 | 「windows 端提供合集删除功能」 | 「切换任务合集」弹窗（顶栏药丸 / 托盘 / 设置页三处入口共用）每行加垃圾桶（`picker-delete-<id>`）：先读该合集的记录数 → 二次确认（写明「下有 N 条识别记录；删除合集不会删掉这些记录」，`picker-delete-confirm`）→ `CollectionController.delete`（软删除 + 同步 op；删掉的正是当前选中的合集时退回未选中）→ SnackBar。删除**代码** M8 起就有，但只在 `activeCollectionId == null` 时的选择页出现，进了主界面就再找不到入口 |

| 3 | 「安卓识别模块加入说明：受限于网络延迟与 api 端相应，可能识别时间过长，不建议开启」 | 新增常量 `kRecognitionSlowNote` 与组件 `RecognitionSlowNote`（黄色警示条，key `recognition-slow-note`），挂在**设置首页「识别模块」开关下方**与**「识别模块设置」二级页顶部**（同一组件，文案不会各自漂移）。只是知情提示：不拦人、不改默认值 |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)

(cd apps/android           && flutter analyze && flutter test)

powershell -File tools/build_all.ps1   # 上面全部步骤 + 打包成 dist\ 交付物，末行 ALL GREEN

```



**DoD**：四包 analyze 无 issue、测试全绿（core 192 / ui 21 / desktop 136 / android 83）；

`tools/build_all.ps1` 跑到 `ALL GREEN` 并重新打包（APK × 3 + 便携版 zip + 安装包）；

`DECISIONS.md` / `SPEC.md` / `AGENTS.md` / `progress.md` / `manual-test-android.md` 同步；

出包序号只动 `pubspec.yaml`（安卓 `1.0.0+9`、桌面 `1.0.0+3`），界面文案仍是 `1.0.0`。



---



## M20 · 用户反馈轮 11（2 项）



**目标**：第九轮反馈里的 2 条 —— Windows 主界面右上角的**配对状态一直显示「未配对」**（不重启就不更新）、

**物理公式整段显示成源码**（双端）。



| # | 用户反馈 | 做法 |

|---|---|---|

| 1 | 「windows 主页面右上角『配对状态』不更新，一直显示未配对」 | M19 的药丸只在**挂载时查一次库**且没有任何失效时机 → 「App 先开着、手机后来才扫码配对」这条最平常的路径永远停在 `未配对`，吊销设备也不回落。新增 `CoreRepository.watchDevices({includeRevoked = false})`（`devices` 表的 drift 流，与既有 `watchSessions` / `watchCollections` 同一写法），桌面 `_pairedDevicesProvider` 由 `FutureProvider` 改为 `StreamProvider`，配对与吊销谁写库谁就让它变。**先复现再改**：新用例在改之前是红的 |

| 2 | 「之前优化好的显示公式，怎么现在不显示了，双端都是？？？」（补充：「是物理公式」） | 真凶是**定界符**：prompt 要求 `$…$`，但模型对物理题吐 LaTeX 原生的 `\(…\)`。用真实库取证 —— 数学题存 `$f(x)=x^2-2a\ln x$`（37 处 `$…$`，一直正常），物理题存 `\(m_A = 1\,\mathrm{kg}\)`、`\(E_p=\frac{16}{3}\,\mathrm{J}\)`（10 处 `\(…\)`，**一处 `$` 都没有**）。`MathText` 只认 `$`，于是定界符连同公式被当普通文字画出来；两端共用 `QuestionCard` → 同一个 `MathText`，所以两端一起坏。改为认四种定界符（`$$…$$` / `\[…\]` 独立，`$…$` / `\(…\)` 行内），**`$` 路径与旧实现逐字相同** |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)

(cd apps/android           && flutter analyze && flutter test)

powershell -File tools/build_all.ps1   # 上面全部步骤 + 打包成 dist\ 交付物，末行 ALL GREEN

```



**DoD**：四包 analyze 无 issue、测试全绿（core 193 / ui 25 / desktop 137 / android 83）；

`tools/build_all.ps1` 跑到 `ALL GREEN` 并重新打包（APK × 3 + 便携版 zip + 安装包）；

`DECISIONS.md` / `SPEC.md` / `AGENTS.md` / `progress.md` / `manual-test-android.md` 同步；

出包序号只动 `pubspec.yaml`（安卓 `1.0.0+11`、桌面 `1.0.0+5`），界面文案仍是 `1.0.0`。



---



## M21 · 用户反馈轮 12（2 项）



**目标**：第十轮反馈里的 2 条 —— **展开材料时题目/解析/答案的公式（含化学成分小标）与表格显示不清晰**、

**删掉顶栏那枚「未配对 / 已配对设备：…」药丸**。



| # | 用户反馈 | 做法 |

|---|---|---|

| 1 | 「双端展开材料时、题目、解析、答案的公式（包括化学成分的小标等）、表格等优化下显示。我在 …\测试数据 有测试数据，还有其他类数学运算的显示不清晰」+ 补充「我说的表格不是竖线，是有的材料里给表格了，但是他直接一行显示了」 | `MathText` 重写成**内容块**渲染器（双端共用）：① **化学式小标** —— `ZnCO3`/`Fe2O3`/`H2O2`/`Fe2+` 这类裸写法按元素符号切分，数字下沉成下标、电荷上浮成上标（元素符号白名单 + 「至少一个数字或电荷」双条件，挡住 `pH`/`MPa`/`2026`）；② **表格** —— 材料里的空格对齐块与 Markdown 竖线表都画成真 `Table`（带边框、可横向滚动）；③ **公式分块** —— `$$…$$` 与 `\[…\]` 独占一行，超过当前宽度可容纳字符数（`宽度/11`，钳 24–96）的行内公式也搬成块级；④ 行内公式改用 `MathStyle.text`；⑤ `⇌` 借 KaTeX 字形（随包 MiSans 缺这个字）。取证见 `docs/progress.md`：裸化学式 36 处、空格对齐表 4 题、行内公式 308 条（最长 84 字符）、`⇌` 10 次 |

| 2 | 「删除掉『未配对』和已配对那个药丸显示」 | 删掉 `home_page.dart` 顶栏的 `_ServerPill` 整条链路（含 M19 的 `serverPillLabel` / `pairedDeviceLabels`、M20 的 `_pairedDevicesProvider`）。配对状态改由「设置 → 连接设备」独家承担（服务端口、连接状态、已配对设备与吊销都在那里）。`CoreRepository.watchDevices()` 保留为通用库变更流。随功能一并删除其 8 条断言（5 条纯函数 + 2 条 tooltip widget + 1 条「运行中配对就地更新」）与空状态里那句 `服务未启动` 断言，理由写进 `DECISIONS.md` |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)

(cd apps/android           && flutter analyze && flutter test)

powershell -File tools/build_all.ps1   # 上面全部步骤 + 打包成 dist\ 交付物，末行 ALL GREEN

```



**DoD**：四包 analyze 无 issue、测试全绿（core 193 / ui 40 / desktop 133 / android 83）；

`tools/build_all.ps1` 跑到 `ALL GREEN` 并重新打包（APK × 3 + 便携版 zip + 安装包）；

`DECISIONS.md` / `SPEC.md` / `AGENTS.md` / `progress.md` / `manual-test-android.md` 同步；

出包序号只动 `pubspec.yaml`（安卓 `1.0.0+12`、桌面 `1.0.0+6`），界面文案仍是 `1.0.0`。



---



## M22 · 用户反馈轮 13（1 项）



**目标**：第十一轮反馈 —— **化学式里电子的负号 `e⁻` 显示成了普通 `-`**，而且**同一行里的减号不能被跟着上标**。



| # | 用户反馈 | 做法 |

|---|---|---|

| 1 | 「化学的 `Cu²⁺ + 2e⁻` 的 `⁻` 显示为 `-`」+「一定要注意如 `2H₂O - 4e⁻` 就有 `-` 和 `⁻`」 | 数据核对：用户的导出里 `e-`（ASCII 连字符）出现 **28 次**，而 `e⁻`(U+207B) / `e−`(U+2212) 都是 **0 次** —— AI 写的就是普通连字符，所以要在渲染时把它上标。`_chemRe` 增加 `e[+\u2212-]` 这条电子写法（小写 `e`，系数 `2` 保持正文大小），并把结尾后顾断言从 `(?![A-Za-z])` **收紧成 `(?![\dA-Za-z])`**：电荷符号后面不会紧跟数字，于是 `2H2O-4e-`（不留空格）里 `H2O` 后面那个 `-` 判成减号而不是电荷。`isChemicalFormula` 放行小写 `e`。回归 4 条：`Cu2+ + 2e-`、`2H2O - 4e- = O2 + 4H+`、无空格 `2H2O-4e-=O2+4H+`、以及 `e-mail`/`1e-5` 不许误伤 |



**验收命令**



```bash

(cd packages/quizsync_core && flutter analyze && dart test)

(cd packages/quizsync_ui   && flutter analyze && flutter test)

(cd apps/desktop           && flutter analyze && flutter test)

(cd apps/android           && flutter analyze && flutter test)

powershell -File tools/build_all.ps1   # 上面全部步骤 + 打包成 dist\ 交付物，末行 ALL GREEN

```



**DoD**：四包 analyze 无 issue、测试全绿（core 193 / ui 44 / desktop 133 / android 83）；

`tools/build_all.ps1` 跑到 `ALL GREEN` 并重新打包（APK × 3 + 便携版 zip + 安装包）；

`DECISIONS.md` / `SPEC.md` / `AGENTS.md` / `progress.md` / `manual-test-android.md` 同步；

出包序号只动 `pubspec.yaml`（安卓 `1.0.0+13`、桌面 `1.0.0+7`），界面文案仍是 `1.0.0`。



---



## M23 · 优化轮 1：静态基线收口



**目标**：执行 `docs/optimization-plan.md`（对用户原「Flutter Windows + Android 代码优化与检查执行计划」

审阅后的修订版）第 1 项 —— 补齐静态检查并修掉它抓出来的东西，**不改运行时行为**。



| # | 内容 | 做法 |

|---|---|---|

| 1 | 基线 | `git tag baseline-m22 9b4764d` 作为回滚点 |

| 2 | core 补 lint | `packages/quizsync_core` 补 `flutter_lints: ^6.0.0` + `include: package:flutter_lints/flutter.yaml`（此前四个包里只有它一条规则都没有）；两个 app 包加 `unreachable_from_main` |

| 3 | 修 14 条 | 13 条等价改写；**1 条是真 bug**：`sync_engine_test.dart:158` 的 `o.entity == 'snapshot'`（枚举与 `String` 比较恒为 false，豁免分支从不生效）改成 `SyncEntity.snapshot` |

| 4 | 删死代码 | `unreachable_from_main` 第一次跑就报出 `apps/desktop/tool/make_icons.dart` 的 `debugCornerTransparent`（全仓库无调用点），删除 |



**验收命令**



```bash

(cd packages/quizsync_core && dart analyze && dart test)

(cd packages/quizsync_ui   && dart analyze && flutter test)

(cd apps/desktop           && dart analyze && flutter test)

(cd apps/android           && dart analyze && flutter test)

```



（本里程碑只有 Dart 层改动，不涉及构建/打包输入，因此门禁是四包 analyze + 四包 test。）



**DoD**：四包 analyze 无 issue；测试数**不许减少**（core 193 / ui 44 / desktop 133 / android 83，与 M22 持平）；

「`unused_element` / `unused_field` / `unused_local_variable` 不是 lint 名」这一实测结论已记入 `DECISIONS.md`；

本机 flaky（真剪贴板用例）已按「基线 2/2 绿 vs 改动后 3/3 绿」对照取证并记录。



---



## M24 · 优化轮 2：安卓交付物安全审计



**目标**：把安卓交付物的安全审计**本地化、可重复**，并落地用户对四项安全问题的拍板。



| # | 内容 | 做法与代价 |

|---|---|---|

| 1 | 数据不出本机 | `android:allowBackup="false"` **+** 新增 `res/xml/data_extraction_rules.xml`（cloud-backup 与 device-transfer 两个域的全部 domain 都 exclude）。只写 `allowBackup` 关不掉 Android 12+ 的换机直传（D2D）。代价：换机不再自动恢复 |

| 2 | token 换存储 | `FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))`（AndroidX Security）。代价：旧值读不出来 → 需要重新配对一次 |

| 3 | 包名正式化 | `applicationId` → `com.quizsync.android`（`namespace` 与 Kotlin 包路径**保持不动**）。代价：**不能覆盖安装**，已装用户必须先卸载旧版 |

| 4 | 审计工具 | 新增 `tools/audit_android.ps1`（`aapt2` + `apksigner`，只读、零第三方依赖）并挂进 `tools/build_all.ps1`（失败即非 0、不打印 ALL GREEN）。否决了原方案的 `flutterguard_cli`（要注册账号 + 把 APK 上传第三方 SaaS）与 `flutter_build_guard --fix`（会关掉 `usesCleartextTraffic`，直接打断局域网功能） |



**验收命令**



```bash

(cd apps/android && flutter analyze && flutter test)

(cd apps/android && flutter build apk --split-per-abi --release --no-tree-shake-icons)

powershell -File tools/package_android.ps1

powershell -File tools/audit_android.ps1      # 三个 ABI 共 60 项检查，PASS

```



**DoD**：审计脚本对三个 ABI 的 APK 全部 `AUDIT PASS`（包名 / versionCode 分段 / 应用名 / SDK 档位 /

权限白名单 / `allowBackup=false` / `dataExtractionRules` / 明文开关 / 签名 / 包内红线），

且**负向运行会红**（错版本号、不存在的 APK 各测一次，均 exit 1）；

`SPEC.md` §10、`README.md` 安装节、`manual-test-android.md` 第 35 项同步；出包序号统一在 M27 递增。



---



## M25 · 优化轮 3：内存与泄漏



**目标**：定位并处理四个包里的内存泄漏点，并把「内存有没有变坏」变成可重复的测量。



| # | 内容 | 做法 |

|---|---|---|

| 1 | 静态审计 | 摊开全部 **14 处** disposable（比原计划估的 10 处多 4 处），逐条核对 `cancel()` / `dispose()` / 端口关闭 / 连接关闭路径 |

| 2 | 审计结论 | **14 处全部有释放，没有需要修的泄漏**；唯一「不对称」的是服务端 `channel.stream.listen`（未保存订阅），逐条核对三条断开路径都会 `sink.close()` → stream 结束 → 不可达，按**不改**记录 |

| 3 | 泄漏网 | 不用 `LeakTesting`（它追的是 Disposable 对象，**不管 `Timer`**），改用 `flutter_test` 自带的「挂起计时器」强制检查；并做**负向对照**（临时漏一个 `Timer.periodic`，确认真的红后删除）证明这张网有效 |

| 4 | 测量工具 | 新增 `tools/probe_memory.ps1`：真实 release exe 的 RSS / 私有内存 / 句柄 / GDI / USER 采样；**绝不碰正在运行的实例**（发现即 ABORT），在临时工作副本里跑（不污染 build 目录、不碰交付红线） |



**验收命令**



```bash

(cd packages/quizsync_core && dart analyze && dart test)

(cd packages/quizsync_ui   && dart analyze && flutter test)

(cd apps/desktop           && dart analyze && flutter test)

(cd apps/android           && dart analyze && flutter test)

powershell -File tools/probe_memory.ps1     # 空闲稳态 RSS（口径固定，可前后对比）

```



**DoD**：审计表覆盖全部 disposable 点位；负向对照证据写进 `progress.md`；稳态 RSS 基线记录在案

（**277 MB、漂移 -1 MB、句柄/GDI/USER 平稳**）；测试数不许减少；原计划「进出 50 次回到基线 ±10%」

这一条**未做**，替代口径与原因写清楚（进程外没有 UI 驱动接口）。



---



## M26 · 优化轮 4：Windows 兼容性与部署风险



**目标**：让交付物在**没装过开发工具**的 Windows 上也能直接跑，并把「崩溃了怎么查」写成流程。



| # | 内容 | 做法 |

|---|---|---|

| 1 | 随包 VC 运行库（用户拍板） | `tools/package_windows.ps1` 打包前把 `VC\Redist\MSVC\<ver>\x64\Microsoft.VC*.CRT` 整目录（10 个 DLL / 1.9 MB）复制进 Release 目录，逐一复核存在性；zip 内再核一次；缺目录或复制失败 `exit 1` |

| 2 | 为什么是 10 个不是 3 个 | 按微软的 **app-local 部署单位**带整目录：多出的 7 个压缩后约 0.7 MB，换「以后依赖升级引入新的 stdlib 分片也不会再缺 DLL」 |

| 3 | 踩到的坑 | 第一版选中了 `\onecore\x64\` 的**精简版** CRT（与桌面版同名但不同文件：`msvcp140.dll` 631808 vs 643512 字节）；加 `-notmatch '\\onecore\\'` 后逐文件哈希复核一致 |

| 4 | 取证流程 | `docs/DEV.md` 新增「Windows 崩溃 / 起不来的取证流程」：事件查看器 faulting module 分层对照表 → 先分 Debug/Release → **先排本项目自己的原生坑** → HID 触摸屏 issue 是最后一步怀疑对象 → 别在 build 目录里跑 exe 后打包 |



**验收命令**



```bash

powershell -File tools\package_windows.ps1

# 复核：zip 内 10 个 DLL 齐全、userdata=0、Release 目录与 desktop 版源目录哈希一致

```



**DoD**：zip `entries=64`（原 54 + 10）、`userdata` 条目 = 0、10 个 DLL 与 desktop 版源目录

逐文件哈希一致；安装包由 ISCC 重新编译并逐个压缩了这 10 个 DLL；`README.md` 环境要求与

`docs/DEV.md` 同步。



---



## M27 · 优化轮收口：交付复核



**目标**：出包序号 +1、跑一次完整的 `tools/build_all.ps1`（含 M24 挂进去的审计）、逐项复核交付物。



**验收命令**



```bash

powershell -File tools/build_all.ps1        # 末行 ALL GREEN

# 另外逐项复核下面的产物清单

```



**DoD**：四包 analyze 0 issue、四包测试全绿（193 / 44 / 133 / 83，不许减少）；

`audit_android.ps1` 60 项 `AUDIT PASS`；三个 APK 的 `versionCode = 1014 / 2014 / 4014`、

包名 `com.quizsync.android`、`versionName 1.0.0`；`quizsync_desktop.exe` 版本属性仍是 `1.0.0`；

便携版 zip `entries=64`、`userdata=0`、随包 10 个 VC 运行库、`data\app.so` 与 Release 逐字节相同；

安装包重新编译；`DECISIONS.md` / `progress.md` / `milestones.md` / `AGENTS.md` / `DEV.md` /

`README.md` / `manual-test-android.md` 同步。



---



## M29 · 回退 M28 + 热键失效的真凶



**目标**：按用户要求回退代码清理，并把「热键失效」查到根因（不是猜、不是靠回退碰运气）。



| # | 内容 | 做法与结论 |

|---|---|---|

| 1 | 回退 | `git revert d6df7d1`（保留历史）；`git diff a7aeb4d -- packages apps tools` 为空 = 与清理前逐字一致；出包序号顶到桌面 `+10` / 安卓 `+16` 重打产物 |

| 2 | 证据一 | `git diff 9b4764d d6df7d1 -- apps/desktop/lib apps/desktop/windows` **为空** —— 桌面端运行时源码从 M22 到 M28 一行未动 |

| 3 | 证据二 | A/B 对照：带随包 10 个 CRT DLL 与删掉它们，两次启动的 `hotkey` 日志**逐行一致** → 随包 CRT 与热键无关 |

| 4 | 证据三 | 独立探针（全新进程直接 `RegisterHotKey`）：**`Ctrl+Alt+Q` 被占用**，`X/A/S/G/W` 空闲；应用日志显示它已**自动回退到 `Ctrl+Alt+X`** 并报告「默认热键已生效」 |

| 5 | 结论 | 热键链路正常，用户按的默认键 `Ctrl+Alt+Q` 被同机其他常驻程序占着 → 按 `Ctrl+Alt+X` 即可；「设置 → 热键设置」也显示真实状态。**回退与本次故障无关，但按用户要求已执行** |



**验收命令**



```bash

git diff --stat a7aeb4d -- packages apps tools   # 空

powershell -File tools/build_all.ps1             # ALL GREEN

```



**DoD**：源码与清理前一致；四包 analyze 0 issue、测试 193 / 44 / 133 / 83；出包序号 16 的产物逐项复核

（`versionCode 1016 / 2016 / 4016`、audit 60 项 PASS、zip 64 条目 / 0 userdata / 10 个 VC DLL）；

热键根因与诊断方法写进 `DECISIONS.md` / `progress.md`；交付物放入用户惯例目录

`D:\DeepseekHarness\QuizSync_AI-issue\1.0.0\{安装包,源码}`。



---



## M30 · 热键"失效"真凶：暂停逻辑与改键互相打架



**目标**：按用户「不信你试试」的要求，在用户**正在运行的实例**上复现并定位「热键按了没反应」，然后修掉。



| # | 内容 | 结论 |

|---|---|---|

| 1 | 对照实验 | 全新进程实测：`Ctrl+Alt+Q` 被占用，`Ctrl+Alt+X/G/A/S/W` 都能注册**并收到 WM_HOTKEY** → 注入手段可靠 |

| 2 | 用真代码复现 | 用应用真实的 `HotkeyService` 注册 `Ctrl+Alt+W` / `Alt+W` 并注入 → 回调都触发 → 注册与 isolate 消息泵本身没问题 |

| 3 | 在用户实例上复现 | 注入它日志里刚注册成功的 `Ctrl+Alt+X` → **毫无反应**；而全新进程注册同一个键**却成功** → 它当时**没持有**这个键 |

| 4 | 锁定唯一路径 | 全仓库 `unregister()` 三个调用点中，只有 `main.dart:499`（进热键设置页即暂停）是**静默**注销 |

| 5 | 修复 | ① 暂停期间**真的不注册**（`registerAllHotkeys(paused:)`）；② 暂停/恢复写日志；③ 识别**失败**时把窗口带回来；④ 设置页提示写明「在这里按键不会有任何反应」 |



**验收命令**



```bash

(cd apps/desktop && dart analyze && flutter test)   # 134 项（新增「暂停期间不得注册」1 条）

powershell -File tools/build_all.ps1                # ALL GREEN

```



**DoD**：四包 analyze 0 issue、测试 193 / 44 / **134** / 83；出包序号 **17**（桌面 `+11`）产物逐项复核；

`DECISIONS.md` / `progress.md` / `DEV.md` 故障排查表同步；给用户的两步验证写清楚。



---



## M31 · 热键抑制重写：只有「停在本页」才不触发，别处一律生效



**目标**：按用户要求（「重写为现在只有在点进自定义热键页面时不会触发，其他均可以」）把 M30 的

「进热键设置页 → 注销全部热键 / 离开 → 重新注册」整条重写成**触发时判断**，并修掉同一路径上

「截屏把自己的窗口拍进去」的标题 bug。



| # | 内容 | 结论 |

|---|---|---|

| 1 | 当场取证 | 出包序号 17 的实例日志：`01:46:04` 三个键注册成功 → `01:48:01`「热键设置页打开：已暂停全部全局热键（离开自动恢复）」→ **此后再无「关闭：正在恢复」** = 页面没被卸载，标志一直是 true |

| 2 | 重写抑制 | 热键**永远注册着**；`gatedTrigger` 在**触发那一刻**问 `blocked()`，`_hotkeyBlocked()` = 热键设置页挂载 **且** 本窗口是前台窗口；删掉 `paused` / 暂停时的 `unregister()` / `previous` 状态保留 |

| 3 | 同路径 bug | `hideWindowWhile` 用 M17 之前的英文标题找窗口 → `FindWindow` 返回 0 → **主窗口从未被藏**（探针：`FindWindowW(NULL,"QuizSync AI")=0`、`FindWindowW(NULL,"AI 双端搜题")=主窗口句柄）；改为只认 `kAppName` |

| 4 | 日志与文案 | 被忽略的触发写一行「热键设置页正在前台：忽略本次「…」触发（离开本页即恢复）」；设置页顶部提示改为「停在本页时按键不会有任何反应；离开本页、或切到别的程序，热键立刻恢复」 |

| 5 | 回归 | 新增 3 条（闸门直通 / 忽略并报原因 / **抑制期间键照旧注册着**），替换 M30 的「暂停期间不得注册」1 条 → desktop 134 → **136** |



**验收命令**



```bash

(cd apps/desktop && flutter analyze && flutter test)   # 136 项（触发闸门 3 条）

powershell -File tools/build_all.ps1                    # ALL GREEN

```



**DoD**：四包 analyze 0 issue、测试 193 / 44 / **136** / 83；出包序号 **18**（桌面 `+12`）产物逐项复核；

`SPEC.md` §10 / `README.md` / `DEV.md`（故障排查 + 原生坑清单）/ `DECISIONS.md` / `progress.md` 同步。




### M32 · 用户反馈轮 14（Windows 悬浮窗 + 连接设备开关 + 打包/版本）

用户 2026-09-21 的 6 条要求（全部只动 Windows 端；安卓端本轮一行不改）：

1. **Windows 悬浮窗**（12 条细则）：置顶 / 拖动与锁定 / 透明度与显示比例无极调节 /
   窗内字号与重新识别 / 默认 20:9 与拉伸边界（关掉时锁比例、可一键重置）/
   默认右侧不贴边、无标题栏（解锁时任意处可拖）、归位 / 顶部第一模块（识别序号与
   时间上下两行 + 共？题？张图片 + 右侧七个按钮）/ 正常与极简模式 / 底部两个识别按钮
   （默认与多页；多页时变成结束、继续添加（到上限不可点）、取消）/ 识别中最上层提示
   与取消、结束跳最新 / 明暗模式默认跟随软件 / **默认关闭且记住状态**。
2. Windows 安装包**安装目录改英文**（`QuizSyncAI`）。
3. 「连接设备」加开关，**默认关闭**，打开时才获取网络权限授权；关闭时下方功能均不可用。
4. 系统托盘右键菜单加**悬浮球开关**与**悬浮窗开关**。
5. 应用设置**第一项改为「使用说明」**，其余顺序后延。
6. Windows 版本号升到 **1.0.1**。

**关键实现**：悬浮窗 = Dart 离屏渲染一帧预乘 BGRA（`services/float_window_view.dart`
纯函数布局 + `renderFloatWindow`）+ 原生分层窗口贴图（`services/float_window.dart`），
**不开第二个 Flutter 引擎**；图层列表同时是可点区域（`FloatFrame.hitRegions`）。
`services/float_window_presenter.dart` 负责「取数据 → 布局 → 渲染 → 推给窗口」并派发
窗内十个按钮动作。

**DoD**：四包 analyze 0 issue、测试 core 193 / ui 44 / **desktop 156** / android 83；
出包序号 **19**（桌面 `1.0.1+13`）；`SPEC.md` §2.7/§2.8、`README.md`、`DEV.md`、
`DECISIONS.md`、`progress.md` 同步。

---


### M33 · 用户反馈轮 15（Windows 悬浮窗第二轮：15 条）

用户 2026-09-22 的 15 条要求（全部只动 Windows）：

1. 悬浮窗**默认显示比例改成 9:20（竖屏）**。
2. 托盘右键菜单的两个浮层开关**文字随状态变**（显示 xxx / 隐藏 xxx）。
3. 顶部按钮改**图标**（无文字），悬停出提示；顺序：上一条 · 下一条 · 重新识别 · 字号− · 字号＋ · 极简 · 锁定。
4. **只有顶部第一栏能拖**窗口。
5. **删掉**「识别进行中两个按钮不可操作、但可点取消识别」这条设定。
6. 答案显示模块要做到**与主界面一样的模块区分**。
7. 极简模式下已经标明的答案（选择/多选/判断）**不再另起一行写「答案：X」**。
8. 题号后面**不再带 `1.`** 这种序号。
9. 加更多**配色**，默认浅色系。
10. 识别进行中的提示贴在**答案显示区下部**。
11. 公式等格式**与主界面一致**（M32 是纯文本，不正常）。
12. 极简模式 = **只看题目答案模式**。
13. 答案模块要在题号后面跟上**题型与 AI 把握率**。
14. 首次识别的提示挪到**保存 API Key 之后**。
15. 默认透明度 **90%**；**删掉边界拉伸**，只在（标准）9:20、（加长）9:30、（横向）20:9 之间选。

**关键实现**：悬浮窗内容不再自己画，改为把**主界面同一个 `QuestionCard`** 离屏渲染成位图
（`services/float_window_content.dart`，`PipelineOwner + RenderView + RenderRepaintBoundary`），
公式/化学式/表格/模块区分/题型/把握率**天然与主界面一致**。

**DoD**：四包 analyze 0 issue、测试 core 193 / ui 44 / **desktop 163** / android 83；
出包序号 **20**（桌面 `1.0.1+14`）；`SPEC.md` §2.5、`README.md`、`DEV.md`、
`DECISIONS.md`、`progress.md` 同步。

---

---



### M34 · 用户反馈轮 16（Windows 悬浮窗第三轮：8 条）



用户口径（原文摘要）：① 隐私告知只在首次保存 API Key 时提示；② 悬浮窗左上删除「共几题 / 几张图片」；③ 右上角上一条与下一条位置互换；④ 下方「识别一张 / 多页识别」优化为 macOS Dock 栏那样；⑤ 设置里不要出现构建过程描述（如 m35）；⑥ 纯净白配色套用了薄荷绿，改回来；⑦ 删除窗内字号调整按钮，保留设置里的；⑧ 离屏渲染整张卡片导致悬浮窗异常卡顿，改成文本为主但要有明显题目轮廓。



执行中用户追加/撤回：④ 做完后被撤回（「还是不用 dock 栏了，太奇怪」），并追加两条口径——「按钮不要太大，适度即可」与「下方按钮文字和边框异常」→ 最终形态 = 适度尺寸的整条按钮 + 文字垂直居中。



#### 逐条落点



| # | 落点 | 关键文件 |

|---|---|---|

| 1 | 隐私告知挪到「首次保存 API Key」：确认才写 Key，点「暂不使用」不写入并提示；删掉 `_guardPrivacy` 与 6 处调用、`ensurePrivacyAcknowledged` | `ui/settings/api_settings_page.dart`、`state/capture_coordinator.dart`、`ui/home_page.dart` |

| 2 | 标题栏删「共 X 题 / Y 张图片」，连带删掉模型字段与那次多余的图片查询 | `services/float_window_view.dart`、`services/float_window_presenter.dart` |

| 3 | 上一条 / 下一条位置互换（列表首位 = 最右） | `services/float_window_view.dart` |

| 4 | 底部按钮先做成 Dock 式悬停放大 → 用户否掉 → 改回**适度尺寸整条按钮**（23 逻辑像素高、圆角 `AppRadius.control`、无悬停效果） | `services/float_window_view.dart`、`services/float_window_presenter.dart` |

| 5 | 设置页删掉全部 `Mxx`/`第 N 条`/`用户反馈 N` 文案（悬浮窗设置页 4 处 + 数据管理 1 处） | `ui/settings/*` |

| 6 | 纯净白种子 `0xFF16A34A` → `0xFF64748B`（中性），标题栏三通道差从 18 降到 5 | `packages/quizsync_core/lib/util/keys.dart` |

| 7 | 删掉窗内 `A−`/`A＋` 与 `FloatAction.fontDown/fontUp`，字号只留设置页 | `services/float_window_view.dart`、`services/float_window_presenter.dart` |

| 8 | 内容区删掉离屏出图管线，改 `TextPainter` 直排 + 缓存排版 + 明显题目轮廓；渲染改 `rawRgba` 预乘 | `services/float_window_content.dart`、`services/float_window_view.dart` |



#### 验收命令与结果



```bash

# 1) 静态检查（仓库根，覆盖四个包）

flutter analyze                       # No issues found! (13.5s)



# 2) 单测

cd packages/quizsync_core && dart test      # 193 项全绿

cd packages/quizsync_ui   && flutter test   # 47 项全绿

cd apps/desktop           && flutter test   # 170 项全绿（M33b 为 163）

cd apps/android           && flutter test   # 83 项全绿



# 3) 构建与打包

cd apps/desktop && flutter build windows --release --no-tree-shake-icons

powershell -File tools/package_windows.ps1  # zip 30.6 MB + 安装包 26.3 MB

```



#### 无法自动验证



- 悬浮窗按钮的**手感与观感**只能用户上手确认（本轮用户已经看过一版并据此反馈）；探针/逐像素复核只能钉住几何、颜色与命中。

- 滚轮滚动的顺滑度、悬停提示的出现时机需真机体感。

- 真实 AI 识别链路（点「识别一张」→ 真调 AI）仍需 API Key + 已选合集，探针里没配。

- 安卓端本轮一行未改（仍 `1.0.0+18`）。

- `apps/desktop` 出包序号 **22**（`1.0.1+16`），产品版本仍是 1.0.1。



---

### M35 · 悬浮窗崩溃真凶（显式释放引擎文本对象）+ 一次被带偏的诊断复盘



用户口径：卡顿仍在；切「极简 / 正常」崩；用一段时间崩；「点击上面按钮来回点就崩溃」。



#### 结论



- **真凶**：内容重建时对每个 `TextPainter` 调 `dispose()`（释放原生 `ui.Paragraph`）。去掉后，两条必崩路径（200 格滚轮 + 90 秒空闲；反复点极简/锁定 + 100 格滚轮 + 60 秒空闲）**全部稳定存活**。

- **修法**：①`FloatContent.dispose()` 空实现（交给 GC）；②内容缓存从 1 份改 2 份（正常/极简各留一份，来回切换不重建）；③`questionsSignature` 按 id 排序后拼接（顺序抖动不再触发重建）。

- **回退**：期间做过的「原生 GDI 绘制」重构（完全不经引擎出图）崩溃未修好、观感更差，整段回退，留档 `git stash`。



#### 验收



```bash

flutter analyze                    # No issues found!

cd apps/desktop && flutter test    # float_window_* 32 项全绿

flutter build windows --release --no-tree-shake-icons

powershell -File tools/package_windows.ps1

```



探针（发布版 + 用户真实库，临时副本）：反复点顶栏按钮 + 100 格滚轮 + 60 秒空闲存活；200 格滚轮 + 90 秒空闲存活；回读像素颜色数 248 / 浅绿底 31943 / 标题栏 235,237,240。



#### 未完成（下一轮）



- 卡顿仍在：每帧 ~40 ms（引擎出图 + 4 MB 读回）。下一轮做「chrome/content/提示位图缓存 + Dart 侧 memcpy 合成」，目标每帧 ~6 ms。

- 安卓端本轮未改（仍 `1.0.0+18`）；`apps/desktop` 出包序号 **23**（`1.0.1+17`）。



---

### M36 · 版本 1.0.2 + 悬浮窗卡顿优化（分块缓存 + CPU 合成）



用户口径：「接下来版本号是 1.0.2，开始优化悬浮窗卡顿问题」。



#### 落点



1. **版本 1.0.2**（只动 Windows）：`pubspec` `1.0.2+18`、`Runner.rc` `1,0,2,0`、`app_info.dart`、`installer.iss`、`package_windows.ps1`、`README.md` 同步；安卓仍 `1.0.0+18`。

2. **分块缓存 + CPU 合成**（`float_window_compose.dart`）：chrome / content / overlay 三块各自只在变化时出图，其余每帧纯内存拷贝；整窗透明度改由原生 `SourceConstantAlpha` 施加。

3. **四项配套优化**：整数哈希指纹、输出缓冲复用、内容拷贝连续快路、慢帧分段计时常驻。



#### 验收



```bash

flutter analyze                     # No issues found!

cd apps/desktop && flutter test --no-pub   # 179 项全绿（compose 8 条）

flutter build windows --release --no-tree-shake-icons --no-pub

powershell -File tools/package_windows.ps1  # setup/portable 1.0.2

```



探针（发布版 + 用户真实库）：200 格滚轮 + 悬停 + 空闲 90 秒全程存活；内存 480 → 305 → 315 MB（优化前 574 → 690 → 崩）；出图 14 次（滚动帧一次没出）；帧耗时 合成 5 ms / 首屏 1 ms / 贴窗 2 ms（优化前每次推帧 40–52 ms）。



#### 未完成



- 合成帧仍有 chrome 4 MB + 内容约 3 MB 的拷贝（AOT 约 2–3 ms），没做脏矩形增量更新。

- 观感（滚动顺滑度、悬停时机）需用户上手确认。



---

### M38 · 版本 1.0.3 + 悬浮窗卡顿真凶（热路径那一次 `await`）+ 点按钮重出图的分配风暴

用户口径（本轮三条，原话）：「滚动卡的不能用，悬浮窗圆角还没了」「流畅了但频繁点上面按钮崩溃了」
「这次还是卡，但是这次之前你打开那次不卡」。

**结论先写**：M36 的卡顿不是「渲染慢」，是**热路径上的一次 `await` 把帧率钉在 ~1 fps**，
外加「极简 × 锁定」来回点时的**位图重出风暴**。两条都用同一份 exe 做了 A/B 取证。

#### 1. 真凶一：从窗口过程进来的微任务要等平台线程下一次唤醒（1 fps 的来源）

`FloatWindowPresenter._push` 的热路径原来是 `await window.setFrame(...)`。`setFrame` 的实现体
里**没有任何 await**（纯 win32：写 DIB + `UpdateLayeredWindow`），可那次 `await` 实测要等
**390–670 ms** —— 悬浮窗的滚轮/悬停回调是从**窗口过程**（原生回调）里进到 Dart 的，此时排下的
微任务要等平台线程下一次唤醒才会被跑到，而平台线程只在「有 Dart 定时器到期」或「来了新窗口消息」
时才醒。

**A/B 取证（同一份 exe，只切环境变量）**：

| 运行 | 贴窗 await | 平均整帧 | 帧间隔 |
|---|---|---|---|
| 取证开（里面有个 200 ms 看门狗定时器） | 1–6 ms | 7–8 ms | 98–140 ms（300 帧） |
| `QUIZSYNC_FW_DWMALPHA=1`（透明度交回 DWM = M36 做法） | 3 ms | 7–8 ms | 98–140 ms（300 帧） |
| **取证全关（= 用户真实条件）** | **390–670 ms** | **671 ms** | ~1 fps |

顺带把 M36 的猜想否掉：**整窗透明度交给 `SourceConstantAlpha` 不是卡的原因**（两条路分段耗时一样）。

**修法**：热路径（三块都命中缓存）**一次 await 都不做** —— `composeFast` 同步合成、
`_blit` 同步贴帧（`unawaited`，失败在回调里写日志）。`setFrame` 本来就是同步画完的，
`await` 只买到一次微任务。

#### 2. 真凶二：「极简 × 锁定」= 4 种外观组合，缓存只留 1 份（点按钮重出图的来源）

M36 的合成器**每种块只留一个槽位**。而顶部按钮是**来回切**的，两个指纹互相顶掉 → 实测
30 轮点击（60 次）出了 **192 张图**、RSS 冲到 **789 MB**、单帧 0.3–1.3 s。用户报的「频繁点上面
按钮崩溃」正是这条分配风暴（一张内容图 665×8192 ≈ **22 MB**，每点一次重出一张）。

**修法**（`float_window_compose.dart` 的 `_PieceCache`）：每种块留**多份**，容量按「用户能同时翻的
状态组合数」给 —— 外观块 4（极简 × 锁定）、内容块 2（22 MB 一张，只有正常/极简两套）、浮层块 6。

#### 3. 圆角

M36 丢掉的圆角在**本轮**修好：出图时按 `renderNodes(cornerRadius:)` 裁剪、合成后再补一次`_roundCorners` 角掩码；
本轮补了取证（`20260922-probe-fw-corner.ps1`）：屏幕实拍窗口左上角 0–5 px 露出桌面（透明）、
8 px 起进入窗口底色 —— 与 12 逻辑像素圆角在 DPR2 下的弧线边界（≈7 px）吻合。

#### 4. 顺手收掉

- `setFrame` 里「每帧 `ShowWindow`」收成**首帧一次**（窗口早就可见了）。
- 剪贴板那条真实系统剪贴板用例改成**有上限等待**（并行跑重测试文件时 40 ms 轮询会被挤晚，
  原来会假红；断言不变）。

#### 验收（发布版 exe + 用户真实数据库副本 + 合成鼠标/滚轮消息）

- **滚动**（30 格滚轮 + 悬停，不开任何取证）：`推帧汇总：200 帧 · 平均整帧 6ms（合成 5ms） ·
  平均帧间隔 77ms · 出图 6 次 / 合成 179 帧` —— 而修前同一条件下每帧 390–670 ms（~1 fps）。
- **点按钮**（80 次点击：极简 × 锁定）：`出图 160→164 次`（修前同样是 192 次/60 次点击）、
  RSS 峰值 529 MB 后回到 361 MB、45 秒空闲平稳、全程存活。
  ⚠️ 外观块 4 份容量是这一轮补上的第二个修法，M38 打包前还要用探针复核一次（见 `progress.md`）。
- **圆角**：如上，屏幕实拍取证。
- 四包 analyze 0 issue；desktop **182 项全绿**（新增 `float_window_compose_test` ⑨⑩⑪ 三条回归）。

#### 未决

- 公式/化学式/表格在悬浮窗里仍按 `TextPainter` 直排（M34 起的老代价），用户本轮明确不接受，
  放进下一轮（要恢复「与主界面同源」的渲染，同时靠分块缓存保证滚动/悬停帧不出图）。


### M39 · 版本 1.0.4 + 悬浮窗内容被截断的真凶（整图 8192 上限 → 按片出图）

用户口径：「windows悬浮窗在默认模式下显示不全被截断」（附两张截图；本机模型读不了图，所以改用
**用户自己的日志 + 算术**取证，再用探针 A/B 复核）。

#### 真凶：一块位图的高度有硬上限，而内容可以很长

`renderNodes` 与合成器都把位图高度写成 `clamp(1, 8192)` **物理像素**。用户真实数据里「20 题」那次
识别的内容高 **4659 逻辑像素**，DPR2 就是 **9318 物理像素** → 整块出图被截到 8192，滚到底部时最后
**563 逻辑像素（约两题）**永远画不出来，那一段由合成器铺底色（`_finish` 里「源行超出位图 → 铺底色」）。

**A/B 取证**（同一份用户真实 20 题会话，探针 `20260922-probe-fw-m39.ps1`）：

| | 旧 1.0.3（整图） | 新 M39（切片） |
|---|---|---|
| 合成器状态 | `content=665x8192`（截断） | `content片=665x2048 ×4 + 665x1126` |
| 滚到底后内容区底部带 | `颜色数=1 · 最常见色占比 100% · 73/73 行近似纯色` | `颜色数=131 · 占比 41% · 22/73`（其余是卡片留白） |
| 首屏出图 / 平均整帧 | 571–628 ms / 10 ms | 324–373 ms / 11 ms |

#### 修法

1. **内容按 1024 逻辑像素切片出图**（`kFloatContentTileHeight`）：一帧只需可见区覆盖的 1–2 片，
   外加一片预取；缓存 8 片，内存按片封顶。顺带好处：单帧要出的像素更少 → 首屏出图 571→324 ms。
2. **修掉分片拷贝的行漂移**：目标行距是窗口宽 `pw`、被拷宽度是内容区宽 `bodyW`，当成一整块连续内存
   `setRange` 会每行漂移 `pw − bodyW` 像素（内容被切斜）；两侧有留白时必须逐行，只有内容区铺满窗口
   剩余整宽时才走连续快路。这个 bug 是被新回归 `⑫`（「滚到底后最后一行必须是内容，不能是底色」）抓出来的。

#### 验收

- `float_window_compose_test` 13 条全绿（新增 `⑫` 长内容不截断——改前必红、`⑬` 跨片滚动只多出跨进去的
  那一片）；desktop 全量 **184 项全绿**、analyze 0 issue。
- 探针 A/B 数据见上表；平均整帧 10→11 ms、帧间隔 111→105 ms（性能没有退化），RSS 346→392 MB
  （切片缓存上限带来的一次性代价，换来「内容再长也画得完」）。

### M39b · 版本 1.0.5 + 修 M39 引入的原点回归（内容偏右下、底部被压住）

用户口径：「内容区域不会顶头显示了…划到最底部时显示不全，可能图片藏在了识别按钮下。且内容显示模块左右边距不对等」。

**真凶**：`layoutFloatWindow` 会把内容图元**平移到内容区左上角**（`n.intoBody(Offset(bodyRect.left, bodyRect.top))`），
而 `renderNodes` 会按 `origin` 反向平移画布 —— M39 切片时把原点写成 `Offset(0, 片顶)`，漏掉了 `bodyRect.topLeft`，
于是内容整体**下移 48 逻辑像素、右移 4.8 逻辑像素**：顶部出现一条空带、滚到底时最后一段被底部按钮压住、
左右边距一边多一边少。

**A/B 取证**（用户真实 20 题会话，探针 `20260922-probe-fw-m39b.ps1`）：

```text
旧 1.0.4：内容区首行有墨 = 192 物理行（内容区顶 = 96）→ 低了 96 物理像素 = 48 逻辑像素
修复后 ：内容区首行有墨 =  96 物理行                     → 正好顶头
平均整帧 14 → 11 ms、帧间隔 105 → 106 ms（性能没退化）
```

**回归**：`float_window_compose_test` 新增 `⑭` —— 出图器把**原点**编进像素（B 通道 = 绝对行、G 通道 = 绝对列），
断言「内容区左上角那个像素显示的正是窗口坐标 `(bodyRect.left, bodyRect.top)`」，上下与左右一次钉住；
漏掉原点的写法在这条用例上必红。共 14 条全绿。

### M40 · 版本 1.0.6 + 悬浮窗内容改为主界面同源的富文本渲染（公式/化学式/表格）

用户口径（连报两轮）：「悬浮窗题目，答案与解析的数学公式等其他形式渲染依旧不对」。

**做法**：内容区不再用 `TextPainter` 直排，而是把**主界面同一套 `QuestionCard`** 离屏渲成位图
（`PipelineOwner + RenderView + RenderRepaintBoundary`，M33 那套管线），于是公式（KaTeX）、化学式上下标、
材料里的表格与主界面天然一致；同时**沿用 M39 的切片**——一帧只出可见区覆盖的 1–2 片（+1 片预取），
所以不会再回到 M33「每帧跑一遍 widget 管线」的卡顿。内容高度改为「按指纹量一次 + 缓存」，且
**只量高度时不做 `flushPaint`/`toImage`**。

**踩到的两个坑**（都已修 + 有回归）：

1. 内容区底色**必须由渲染器铺满**：分层窗口里透明像素会直接露出桌面（探针读回是黑的、肉眼是洞）。
   现在把 `parts.cardBackground` 透传给渲染器，铺满整片。
2. 内容区**没有图元了**，合成器的内容键不能只靠图元指纹 —— 否则「高度一样但内容不同」会命中错缓存。
   新增 `contentSignature`（题目指纹 + 宽度/字号/配色/明暗）拼进内容键。

**验收**：

```text
flutter analyze（desktop）: No issues found!
flutter test --no-pub --concurrency=1: 189 项全绿
  · float_window_rich_test ⑯ 量高度 + 出图有墨（公式题） ⑰ 按片栅格化（两片像素不同） ⑱ 极简/DPR 进指纹
  · float_window_compose_test ⑮ 内容片由富文本渲染器提供、内容指纹变了要重出
发布版探针（播种「公式题 + 化学方程式 + 表格」会话）:
  内容高 957 · 图元 20（旧直排路径同会话是 301 图元）· content片=665x1915
  滚到底底部带 颜色数=386（旧直排路径同位置 ~120）→ 真的把公式/表格画出来了
  内容区底色 220,221,222（不再透出桌面）
```

---

### M40b · 版本 1.0.7 + 修 M40 的滚动卡顿（片高按渲染成本给）

用户口径：「默认模式滑动卡的不行」。

**真凶**：M40 把内容换成离屏 widget 渲染后，**一片要重跑一遍完整 widget 管线**（探针实测 260–660 ms），
而片高还是图元直排时代的 1024 逻辑像素 —— 用户每滚十几格就跨一次片、每跨一次卡半秒。

**修法**：片高按渲染成本给。`FloatFrameComposer` 新增 `contentChunkHeight`（默认仍是 1024，图元直排照旧），
富文本路线给 **8192 逻辑像素**：通常整篇内容只有一片，出图只在「新结果 / 切极简 / 改外观」时发生一次，
滚动与悬停帧回到纯内存拷贝。

---

---

### M40c / M40d · 版本 1.0.8 / 1.0.9（只写了代码，未出包，并入 M41）

- **M40c（1.0.8）**：修 1.0.6/1.0.7 的滚动卡顿 —— 富文本一次出图 300–500 ms，按需出图会「滚到新片卡一下」，
  把片放大又变成首屏冻结 1–2 s。改成「内容一变就把全部片一次渲完」（片高 2048 逻辑像素），渲完之前画面保持
  上一帧。用户实测口径仍是「依旧卡的不行」。
- **M40d（1.0.9）**：内容指纹里带了 `updatedAt`/`lamport` 这类**记账字段**，而前台每秒一次的轮询会碰到它
  → 每秒把整篇内容重渲一遍（20 题 ≈ 3 片 ≈ 1.2 s）。指纹改成只看会进画面的字段。
  这两轮都没能改变用户的观感，原因见 M41。

### M41 · 版本 1.1.0 + 内容渲染切回直排（富文本默认关）

用户第三条口径：「滑动还是更卡」、「依旧卡的不行」。

**结论**：M40b / M40c / M40d 三轮修法都建立在同一个前提上 —— **帧必须等出图**。只要富文本渲染还在推帧
链路上，滚动就一定会撞上它：离屏 widget 管线**一片 300–700 ms**。同一台机器、同一份发布版 exe 的 A/B：

| 内容路径 | 平均整帧 | 出图次数 | 观感 |
|---|---|---|---|
| `TextPainter` 直排（M34/M39b） | **6–11 ms** | 179 帧里 6 次 | 顺滑 |
| 离屏 widget 富文本（M40–M40d） | 首屏 190–695 ms，片栅格化 90–500 ms | 滚动时持续增长 | 卡 |

**做法**：把富文本内容路径**默认关掉**（`FloatWindowPresenter.useRichContent = false`），内容回到
`TextPainter` 直排，合成器回到 1024 逻辑像素片高。富文本那条路（`float_window_rich.dart` + 合成器的
`renderContentTile`）原样留着，等「帧永不等出图」的做法做扎实了再开。

**代价（写明白）**：公式按 LaTeX 源码显示、化学式没有上下标、表格退化。这一轮先换顺滑。

### M42 · 版本 1.1.1 + 极简模式改纯文本可选中面板（+ 一个「复制本题答案」）

用户口径（连问三轮）：「希望极简模式可以变成可选中字符的形式，便于我的选中与复制」、
「做文本形式、可选中」、「怎么极简模式还没改出来」。兜底方案由用户拍板：**只给一个「复制本题答案」按钮**
（明确否掉了「复制本题」「复制全部」）。

**做法**

1. **极简面板重写**（`layoutMinimalTextContent`）：一题一个 `TextPainter`（题号 / 题型·把握率 / 题干 / 选项 /
   答案行合成一个 `TextSpan` 树），**不画任何卡片、圆角底、徽标、色块**，只在题与题之间留一条 1 像素细线。
   一题一个段落是拖选的前提：跨行/跨题选区的字符下标才不会在段间错位。
2. **拖选**（`float_window_selection.dart`，纯函数 + 9 条单测）：选区两个点存在**内容坐标系**里（滚动时选区
   跟着内容走），按读序把「起点所在段 → 终点所在段」拼起来；高亮矩形用 `TextPainter.getBoxesForSelection`
   自己算（和真实字形一致），可复制文本用 `getPositionForOffset` 取下标后切片。
3. **高亮怎么画**：**直接调合成好的像素**（`FloatFrameComposer.selectionRects` → `_paintSelection`）。
   不出图、不新建缓冲 —— 拖选时每一帧选区都在变，出一次图要 `toImage` + 读回几十万像素（几十毫秒），
   拖起来必然一格一格；而高亮就是若干轴对齐矩形，混一遍色只要零点几毫秒。选区也进**帧指纹**，
   否则帧复用会「拖了但画面不动」。
4. **两处入口**：这个窗口是 `WS_EX_NOACTIVATE`（不抢焦点），**拿不到键盘消息** → `Ctrl+C` 天生不可用，
   所以「复制所选」挂在**内容区右键**上；底部在极简模式下多一个「复制本题答案」（取**可见区顶部**那道题，
   一屏多题时语义唯一）。

**实测（发布版探针 `20260922-probe-fw-m42.ps1`）**

```text
极简首屏：首行有墨=96（内容区顶=96）· 内容高 1526 · 图元 60（正常模式 4659 / 301）
合成拖选（LBUTTONDOWN → MOUSEMOVE → LBUTTONUP）后内容带变化像素 = 9844/28980
右键 → 系统剪贴板 = 第 1 题  填空题 · 把握 99% / 中国四大名著中… / 答案：红楼梦 / 第 2 题 …
点底部「复制本题答案」→ 日志「点击 copy-answer」· 剪贴板 = 红楼梦
=== 存活、RSS 345 MB ===
```

**踩坑（探针抓到，值得记）**：`main.dart` 里把 `onSelectBegin: _floatPresenter.onSelectBegin`
直接写成方法引用，会在**这一句**就求值 `_floatPresenter`，而它要到下一句才赋值 → 启动时
`LateInitializationError`、悬浮窗根本建不出来（发布版探针首轮「NOT FOUND」，日志里只有这一条）。
回调一律包一层 lambda。

### M43 · 版本 1.1.2 + 默认模式改极简 / 复制识别内容 / 对比度 / 赞助

用户四条口径：

1. **「将 windows 悬浮窗极简模式设置为悬浮窗默认显示的模式，也就是改为默认模式，将原来的默认模式改为
   详细解析模式。」**
2. **「将极简模式的复制本题答案按钮移动到三个的最后一个，并且修改功能为复制识别内容，点击直接复制本次
   识别的内容。」**
3. **「在悬浮窗设置默认白色和紫色时，同时调整为深色模式，极简模式答案题号等颜色和背景色高度接近，不明显。」**
4. **「windows 端设置关于后添加最后一项赞助，选择后将显示微信和支付宝的赞助二维码（图片在
   `…\QuizSync_AI-issue\其他` 里），上面写点感谢的话语。」**

**做法**

1. 默认显示模式：`kDefaultFloatWindowMinimal` 改成 `true`；用户可见的名字改成
   「默认模式（只看题目与答案）」与「详细解析模式（选项全列 + 解析 + 材料）」。
   **老库里存着 `float_window_minimal=0`**（那时候出厂值就是 0，绝大多数人从没手动选过），
   只改常量默认值救不了他们 → `SettingsController.load()` 做**一次性迁移**（标记键
   `float_window_mode_migrated`），迁移后用户自己的切换一律以库里的值为准。
2. 复制：`FloatAction.copyAnswer` → `copyContent`，Dock 里排在「识别一张 / 多页识别」**之后**；
   `recognitionTextOf()` 把**完整**识别内容排成纯文本（题干、全部选项、答案、解析、阅读材料；
   与屏幕上那份被极简裁剪过的视图**故意不同**，因为用户要的是能粘到别处的结果）。
3. 对比度：新增纯函数 `relativeLuminance` / `contrastRatio` / `ensureContrast`（WCAG 2.1，
   不够就往白/黑方向逐档调和到 ≥ 4.5:1）。面板里的题号、答案、题型/把握率、空答案提示
   **每一种颜色**都过一遍它；配色表里「纯净白」「紫罗兰」在悬浮窗设置里被选中时，
   **同时把明暗模式切到深色**（`kFloatWindowDarkPalettes`）。
4. 赞助：设置导航最后一项 `sponsor`，页面是感谢的话 + 微信/支付宝两张收款码
   （用户原图，用主色确认过归属：微信绿 `#00C060`、支付宝蓝 `#0060E0`），
   只展示、不跳转、不追踪；图片按 2× 解码（`cacheWidth: 488`），不整张进内存。

**验收**（`20260923-probe-fw-m43b.ps1`，用户真实 20 题会话）

```text
位图 342x760 → 缩放系数 k=1.0
首行有墨=54（内容区顶=48）· 底色=220,221,222
点第三个按钮 → 剪贴板长度=1742 · 「第 N 题」20 处 · 「答案：」20 处 · 「解析：」20 处
  开头 = [第 1 题  填空题 · 把握 99% · 卷面题号 1 / 中国四大名著中，曹雪芹创作的是《____》。
          / 答案：红楼梦 / 解析：曹雪芹是《红楼梦》的作者，该书为中国四大名著之一。 / 第 2 题 …]
app.log  悬浮窗首帧：… · 可点区域 7 个 · 拖拽区 342×43
app.log  点击 copy-content
题号行最强笔 vs 底色：lilac-light 4.62:1 · lilac-dark 5.43:1 · white-dark 5.25:1 · white-light 4.71:1
```

**探针踩到的坑**：本机 PowerShell 子进程会**继承父进程的 DPI 感知**，同一个探针脚本这次拿到的位图是
逻辑像素（342×760）、上次是物理像素（684×1520）—— 写死 `bodyTop=96` 直接把「点第三个按钮」点成了
「多页识别」。改成按 `k = 位图宽 / 342` 缩放所有坐标后稳定。

### M44 · 版本 1.1.3 + 赞助页精简 / 不设上限 / 悬浮球默认关 / 答案绿色 / 手机任务静默同步 / 说明文字加粗

用户六条口径（原文）：

1. 「赞助页面不方便后面的话全删掉。破折号不要。下面两张图片调整为等高。」
2. 「每日调用上限添加一个不设上限。」
3. 「悬浮球默认也关闭。」
4. 「悬浮窗默认模式的答案颜色改成绿色吧。」
5. 「在手机端进行识别时，windows 端应用修改为静默不弹出。优化：同时 windows 端悬浮窗显示时，若在手机端
   搜题，悬浮窗不会同步状态与跳转新界面的 bug。」
6. 「设置中部分说明文字还存在 **，优化下显示效果。」

**做法**

1. 赞助页：感谢文案只剩一句「可以请作者喝一杯咖啡，金额随意，一分钱也是心意。」（删掉后面那句、去掉破折号）；
   两张收款码改成**固定高度 300**（原图宽高比不同），按 2× 解码。
2. `QuotaGuard.dailyLimit <= 0` = **不设上限**（新增 `unlimited` getter，`canCall` 直接放行），设置页下拉新增
   「不设上限」（存 0），「今日用量」文案与进度条跟着改。
3. `kDefaultBallEnabled` 改成 `false`（core 与 ui 两处常量都要改，它们是同一个名字的两份声明），
   并在 `SettingsController.load()` 里加**一次性迁移**（`ball_enabled_migrated`）——老库里是 1 的话摆到关。
4. 答案色 = `HighlightColors` 的**标绿契约色**（浅色 `#16A34A` / 深色 `#4ADE80`），不再按 4.5:1 自动压暗
   （那样浅色下几乎看不出绿）；`answerStrong` 的门槛降到 2.9:1（= 主界面在白卡片上的水平）。
5. 手机任务：新增 `services/remote_task.dart` 的 `RemoteTaskSignal` + 全局 `remoteTaskState`；
   服务端 `onTaskUpdateHook` 写它，外壳转发给悬浮窗 → 手机在搜题时悬浮窗显示「手机正在识别…」、
   完成时跳到最新结果；`_onRemoteTaskStarted` **不再 show/focus 主窗口**（只有窗口本来就是前台才切界面）。
6. 设置页说明文字统一走 `SettingsRichText`：成对的 `**…**` → 真加粗（`FontWeight.w600`），
   落单的星号与 `****`（掩码）原样保留；`SettingsSection`/`SettingsGroup`/`SettingsRow`/`SettingsField`/
   `SettingsNote`/ⓘ 对话框六处都换掉。

**验收**（`20260923-probe-fw-m44.ps1`，用户真实库）

```text
迁移前：ball_enabled=0（用户本来就关着）、float_window_minimal=0、无迁移标记
① 窗口类： QuizSyncFloatWindow, FLUTTER_RUNNER_WIN32_WINDOW, MSCTFIME UI, IME
① 悬浮球窗口 = 不存在 ✓（默认关闭）
迁移后：ball_enabled_migrated=1、float_window_mode_migrated=1、float_window_minimal=1
② 偏绿像素 = 6943 · 最绿的一笔 = 20,147,67（绿通道超出 max(R,B) 80）
悬浮窗首帧：… · 可点区域 7 个（默认模式生效，含「复制识别内容」）
```

**单测**：四包 analyze 0 issue；core 195（新增「不设上限」2 条）/ ui 56（新增加粗渲染 6 条 + 悬浮球默认关与
迁移 2 条）/ android 83 / desktop 214（新增手机任务同步 2 条、每日上限 UI 1 条、11 个分类无字面星号 1 条、
收款码等高与文案 1 条）。

### M45 · 新增独立产品 QuizSyncAI Server v1.0.0（Windows CLI 后台服务，功能冻结）

**需求原文要点**：基于当前仓库创建一个**全新、独立**的 Windows CLI 应用
`QuizSyncAI_Server.exe`。**不是** Desktop 的一个运行模式（明确禁止给 Desktop 加 `--server`）；
只允许四个功能（手机配对 / AI API 配置 / 三个全局截图热键 / 截图→AI→Android 结果同步）；
与 Desktop 完全独立（不依赖 Flutter、UI、悬浮球、托盘、设置页、Desktop 状态管理）；
Android 端**无需任何修改**（实现现有配对与结果协议）；功能冻结在 v1.0.0，以后要改就发 v2。
要求先分析仓库、再基于现有实现提取最小必要代码。

**先做的分析（定位）**

| 关注点 | 位置 |
|---|---|
| 配对协议 | `packages/quizsync_core/lib/model/pair_messages.dart` + `docs/protocol.md` §2（6 位码、5 分钟 TTL、`quizsync://pair?...` 二维码、Bearer token 存 sha256） |
| HTTP 服务端 | `packages/quizsync_core/lib/server/quizsync_server.dart`（shelf + shelf_router，protocol.md 全端点） |
| WebSocket | 同上 `_handleWs` / `_onWsConnected` / `_emitTaskUpdate`（hello / ping / task_update / task_result / task_failed / device_revoked） |
| 三个热键 | `apps/desktop/lib/services/hotkeys.dart`（纯逻辑）+ `hotkey_service.dart`（isolate + `RegisterHotKey` + `PeekMessageW` 泵） |
| 截图 | `apps/desktop/lib/services/screen_capture.dart`（GDI BitBlt，鼠标所在显示器，Per-Monitor DPI V2） |
| AI 请求 | `packages/quizsync_core/lib/ai/`（prompt 全文 / 三家 provider / 容错解析 / 重试策略） |
| 结果协议 | 会话 + 题目 JSON（`model/session.dart` / `question.dart`）+ `/api/v1/tasks/active` 轮询兜底 |

**做法**

1. 新建 `server/`（Dart 包 `quizsync_server`），**逐文件复制**所需的最小核心子集到
   `lib/src/core/{model,ai,util}`（保留原有相对导入，未改写）→ Server 与主项目
   **没有运行时依赖**，主项目以后怎么改都不会影响冻结版的 Server。
2. 自己实现：JSON 状态存储（`state.json` + `images/`，**不用数据库**）、识别流水线、
   HTTP+WS 服务端（协议与 Desktop 逐端点一致）、配置、纯文本 CLI、终端二维码。
3. 三个全局热键默认 **F6（截图并识别）/ F10（追加一页）/ F11（结束多页并提交）**——
   用户报 F7 被占用；实测本机 F2/F8/F9 会被「妙享桌面 / 截图工具」吃掉（能注册、按键不触发）。
   注册失败按需求给固定两行英文提示 + 一句可操作建议，面板显示 `(FAILED)`。
   （这三个默认值在 M45b 里按用户口径改成了 Ctrl+Q / Ctrl+Shift+A / Ctrl+Shift+S。）
4. 终端里用 `▀` + ANSI 黑白画配对二维码（Server 没有 GUI，扫码是 Android 现有能力），
   并额外打印一行可复制的 `quizsync://pair?...` 链接（Android 支持从剪贴板粘贴）。
5. `Ctrl+C` / `quit`：停 HTTP → 关 WS → 注销热键 → 保存状态 → 退出（不留残进程）。

**验收**

```text
dart analyze                → No issues found!
dart test                   → 49 项全绿（真 HTTP + 真 WebSocket + 假 AI 回环）
dart compile exe            → build\QuizSyncAI_Server.exe（8.2 MB，单文件、无需 DLL）

端到端探针（真 exe + 真全局热键 + 假 AI，35/35 通过）：
  ✓ 面板 + 6 位配对码 + 终端二维码（payload 与 protocol.md 2.1 逐字一致）
  ✓ F6 真实热键触发 → 真截屏（170 KB JPEG）→ AI → done，题目结构/合集/source_device 全对
  ✓ 截图原图可按 hash 下载（真 JPEG 头）· 同图再提交直接命中缓存且不再调 AI
  ✓ 手机提交 3 页任务：202 queued → 一次 AI 调用 → 3 页会话推给手机
  ✓ CLI 改热键 → 面板变 Ctrl+Alt+F9 → 该热键真的能触发；重复键被拒；非法键给可读原因；reset 生效
  ✓ quit 后进程正常退出，config.json / state.json 落盘正确
```

**独立性与兼容性**：`git status` 显示除新增 `server/` 外**主项目零改动**；
四包 analyze 0 issue、core 195 / ui 56 / android 83 / desktop 215 全绿（行为未变）。

### M45b · Server 1.0.0 六条优化

用户六条口径（原文）：

1. 「数据默认保存应用同名目录下。」
2. 「首次运行：请配置 AI 时详细标明区分示例。」
3. 「单张截屏默认案件修改为 ctrl+q，append 为 Ctrl+Shift+A，finish 为 Ctrl+Shift+S。」
4. 「连接手机后会弹出多次：{面板}，看看什么原因。」
5. 「有没有什么能让服务关闭命令窗口也能运行的办法。」
6. 「Server 识别的全放到 Server 合集。」

**做法**

1. **数据目录**：默认改成 `<exe 所在目录>\QuizSyncAI_Server\`（配置 / 状态 / 图片 /
   日志 / 运行文件都在这里），exe 目录不可写才退回 `%APPDATA%`，并在日志里写明实际用了
   哪个；启动时把 1.0.0 早期写在 `%APPDATA%\QuizSyncAI\Server` 的数据**自动搬一次**
   （老目录保留不删）。`--config` 属于明确指定，不参与搬迁。
2. **首次配置**：改成「带例子」的说明书 —— Provider 三种取值各是什么、**DeepSeek 属于
   第 1 种**（最易填错）、四家服务的 Base URL 与多模态模型名实例、API Key 不是登录密码
   并给出申请入口；交互问答支持直接打 `1/2/3`。说明文字**无条件打印**（没有可交互
   控制台时也给完整指引）。
3. **默认热键**改为 `Ctrl+Q` / `Ctrl+Shift+A` / `Ctrl+Shift+S`；老配置里等于某个历史默认值
   （F6/F7/F8、F6/F10/F11、F6/Ctrl+F6/Shift+F6）的槽位**自动迁移**到新默认，用户自己改过的
   一律不动。
4. **面板刷屏**：根因是「手机连上 / 断开」被通知了**两次**（`onDeviceConnected` 与
   `onStateChanged` 各让 CLI 重画一次），断线重连时同样内容还会反复印。修法：服务端只通知
   一次 + CLI 端**内容去重**（指纹没变就不重印，`status` 命令强制重印）。
5. **后台运行**：新增 `--hidden`（收好自己的控制台窗口、日志同时写 `<数据>\server.log`；
   从终端启动时不动用户的终端窗口；一台手机都没配对过时保持可见以便扫码）与 `--stop`
   （读 `runtime.json` 里的端口 + 一次性控制令牌，向**本机回环地址**发
   `POST /api/v1/shutdown`，等价于 `quit` / `Ctrl+C`）。
6. **Server 合集**：固定合集名从「默认合集」改成 **Server**（老状态文件自动改名）。

**验收**（`20260923-quizsync-server-opt.py`，真 exe + 真热键 + 假 AI，**27/27 通过**）

```text
① 数据目录 = <exe 目录>\QuizSyncAI_Server（config/state/runtime 全在内，日志写明路径）
② 首次运行打印三档 Provider + 各家 Base URL/模型示例 + 「不是登录密码」
③ 面板与配置文件都是 Ctrl+Q / Ctrl+Shift+A / Ctrl+Shift+S；Ctrl+Q 真按键能触发截图识别
④ 配对只印一次面板；连续三次连断也不刷屏；连上后显示 CONNECTED
⑤ --hidden 起服务 + 写 server.log + 写 runtime.json；--stop 成功、进程真的退出、
   运行文件被清掉、日志进 server.log；没有实例时给可读错误
⑥ /info 与 /collections 都报 Server；截图会话的 collection_id 指向它
```

核心链路回归（`20260923-quizsync-server-e2e.py`）：**35/35 通过**。

**单测**：`dart analyze` 0 issue；`dart test` **59 项**（新增停机接口 2 条、数据目录与
老数据搬迁 5 条、默认值迁移 1 条、老配置热键迁移 1 条、运行文件断言 1 条）。

### M45c · Server 1.0.0 第三轮优化（四步引导 / 输出中文紧凑 / 两个热键动作 / 后台门禁 / 说明书 txt）

用户七条口径（原文摘要）：

1. 首次配置改成**四步、一步一介绍**，每步显示各自的说明，支持直接输入或打数字选择。
2. 「首次配对手机弹出的信息太多」（启动时一整屏 + 二维码 + 刷新时又整屏）→ 优化显示。
3. 「已连接后也是太多了」→ 优化显示。
4. 全部完成后要有提示（热键、更多命令等），**一定要有中文提示**。
5. **热键全面修改**：只有两个动作，默认截屏识别 F8 / 备用 Alt+Shift+Q，进入多页并截第一张
   F9 / 备用 Alt+Shift+W；多页攒满 6 张自动上传，未满时按 F8 结束多页并上传；
   「热键目前不可用，修改这个 bug」。
6. 「关掉命令窗口也能跑」需要**完成设定并配对手机后可跑**。
7. exe 生成时同目录生成一个 txt，简要说明启动命令、配置设置、使用指南。

**做法**

1. **四步引导**：`_firstRunSetup` 改成一步一屏（打印本步说明 → 等输入 → 打印「→ 已选择」
   → 下一步）。每步都支持数字：Provider `1/2/3`、Base URL `1/2`（DeepSeek/OpenAI）或直接
   粘地址、API Key 必填（空则提示重输并给出申请入口）、Model `1..4` 或自填。填错当场提示
   重输，不静默丢值；没有可交互控制台时整体打印一遍四步说明。
2. **输出改成中文紧凑**：状态块从 30 行英文方框压成 6–8 行中文（服务器/手机/AI/热键/多页/数据），
   只印一次标题（原来 run() 的横幅 + 状态块各印一次标题）；热键注册的 Win32 原文只在**失败**
   时才打；配对码过期刷新只印一行 + 新二维码，不再重印整块；状态块按**内容指纹去重**。
3. **事件提示**：手机配对/连接/断开/吊销、识别结果推送、停机请求等日志标签与正文全部中文
   （`[手机] 已连接：…` / `[同步] 识别结果已推送给手机`）。
4. **启动提示块**：`怎么用：` 五条中文说明（配对方法 + 地址/配对码、截屏识别、多页识别、
   更多命令、后台运行与停止）。
5. **热键改成两个动作 + 备用键**：`HotkeySlot{capture, multipage}`，四个槽位
   `capture / capture-fallback / multipage / multipage-fallback` 各占一个注册 id，
   **四条同时注册**（不是失败才回退）；`CaptureFlow` 重写：
   - `onCapture`：不在多页 → 单张识别；在多页 → 结束多页并上传已抓的全部图片；
   - `onMultipage`：抓一张入列，达到 6 张自动上传，否则打印 `多页模式 N/6 张`。
   老配置（三个动作那套）自动迁移到新方案，用户自定义过的截屏键保留为新的备用键。
   「热键不可用」的直接修法就是**主键与备用键同时注册**：本机有些键会被别的程序的键盘钩子
   吃掉（注册成功但收不到 WM_HOTKEY），两条一起才稳。
6. **后台门禁**：`--hidden` 只在 `AI 已配置 && 至少配对过一台手机` 时才收窗口；条件不满足
   时保持可见并说明缺什么（否则用户没法扫码配对 / 改配置）。停止仍走 `--stop`。
7. **使用说明.txt**：新增 `tool/make_guide.dart`，编译后运行即在 exe 同目录生成
   《使用说明.txt》（UTF-8 BOM，记事本不乱码），内容含启动命令、四步配置、配对、热键语义、
   数据位置、常用命令、常见问题。

**验收**（两个专项探针 + 回归探针，全绿）

```text
20260923-quizsync-server-opt2.py（真 exe）→ 22/22
  ✓ 只有一处标题；不再打印热键注册 Win32 原文；状态块中文紧凑且带「备用」说明
  ✓ 启动后有「怎么用：」五条中文提示；配对只多印一次状态块；反复连断不刷屏
  ✓ F8 真的能触发截屏识别；F9 进入多页（攒页不调 AI）；多页中按识别键 = 结束并上传
  ✓ 没配对手机时 --hidden 不转后台并说明原因；已配对时转后台且可被 --stop 停掉
  ✓ exe 同目录有《使用说明.txt》且覆盖启动/配置/热键/数据/FAQ

20260923-quizsync-server-opt.py（上一轮六条）→ 29/29
20260923-quizsync-server-e2e.py（协议与核心链路）→ 35/35
```

**单测**：`dart analyze` 0 issue；`dart test` **71 项**（新增两个热键动作的行为用例
`capture_flow_test.dart` 7 条，重写热键/状态块用例）。

### M45d · Server 1.0.0 第四轮优化（去掉备用键 / 启动标识 / 讲清 --hidden 用法）

用户三条口径（原文）：

1. 「备用热键功能删除，没用。」
2. 「启动一次后就要有一定的标识。」
3. 在窗口里敲 `hidden` / `--hidden` 得到「未知命令」，问「这要怎么用？」

**做法**

1. **删除备用键**：`HotkeySlot` 只留 `capture` / `multipage` 两个动作，配置只剩
   `hotkey_capture`（默认 F8）与 `hotkey_multipage`（默认 F9）；注册 id 固定 1 / 2；
   状态块、help、说明书、`hotkeys reset` 文案全部跟着改。老配置里的
   `hotkey_capture_fallback` / `hotkey_multipage_fallback` 与历史默认值
   （F6/F7/F8/F10/F11、Ctrl+Q 系列、Alt+Shift+Q/W）在升级时**自动换成 F8 + F9**，
   用户自己改过的非默认值原样保留。
2. **启动标识**：`state.json` 新增 `stats{run_count, first_run_at, last_run_at}`，
   每次启动 +1 并落盘；启动时打一行 `[启动] 第 N 次启动 · 首次 … · 上次 …`，
   状态块多一行「运行 第 N 次启动…」；新增 `--status` 启动参数：不启动任何东西，
   只回答「在不在跑（端口 / PID）」「第几次启动（首次 / 上次）」「数据在哪」。
   另外检测到**已有实例在跑**时明确提示，且第二个实例**不接管** `runtime.json`
   （`--stop` / `--status` 仍指向先启动的那个；退出时也只删自己写的那份）。
3. **讲清 `--hidden` 用法**：
   - 窗口里新增 `hidden` 命令：条件满足就把窗口收起来转后台，条件不满足直接说缺什么；
   - 敲 `--hidden` / `--stop` / `--status` 这类**启动参数**时不再回「未知命令」，而是
     逐条讲清它们是启动参数、给出真实用法（并且解释窗口里该敲 `hidden`）；
   - help、启动提示块、`使用说明.txt` 里都写明了「启动参数 vs 窗口内命令」的区别，
     并给出开机自启的快捷方式写法。

**验收**（`20260923-quizsync-server-opt3.py`，真 exe + 真热键 + 假 AI，**23/23 通过**）

```text
✓ 状态块只有两个热键、config.json 只有 hotkey_capture / hotkey_multipage、默认 F8 + F9
✓ 启动打印「第 1 次启动」；状态块有「运行」行；state.json 的 stats.run_count = 1
✓ 窗口里输入 hidden 有明确反馈；输入 --hidden 会说明它是启动参数；--stop 会说明正确用法
✓ hotkeys reset 提示「热键已恢复默认：截屏识别 F8 · 多页模式 F9」
✓ F8 真的能触发截屏识别；F9 进入多页（攒页不调 AI）；多页中按 F8 结束并上传
✓ 第二次启动打印「第 2 次启动」+ 「已经有一个实例在运行」+ 不接管 runtime.json
✓ --status 报告正在运行 / 端口 / 启动次数；第二个实例退出后不影响第一个
✓ --hidden 在已配对后转入后台，且可被 --stop 停掉
```

回归：`20260923-quizsync-server-opt2.py` 22/22、`20260923-quizsync-server-opt.py` 29/29、
`20260923-quizsync-server-e2e.py` 35/35（都已按"两条热键"更新）。

**单测**：`dart analyze` 0 issue；`dart test` **71 项**（热键用例重写：只剩两个动作、
迁移覆盖三种老形态；smoke 断言启动标识与 `stats.run_count`）。

### M45e · Server 1.0.0 第五轮优化（真·后台运行 + 重新呼出命令行界面）

用户两条口径（原文）：

1. 「输入 hidden，没有办法纯后台运行吗，窗口只是最小化，并没有消失，关掉后服务就没了」
2. 「打开 server 输入后台运行命令后直接在后台运行，再次打开 server 后提示后台正在运行，
   也就是重新呼出命令行界面」

**根因**：上一轮的 `hidden` 只调了 `ShowWindow(SW_HIDE)` —— 窗口是"隐藏"不是"消失"，
而且进程**仍然挂在那台控制台上**：从终端启动时藏的是控制台窗口、用户的终端还在，
他一关终端，控制台被销毁，挂在上面的服务一起被杀；双击启动时窗口虽然看不见了，
任务栏/进程列表里它也还是那个控制台程序。

**做法**

1. **真脱离控制台**：`hidden` / `--hidden` 改走 `FreeConsole()`（先 `ShowWindow(SW_HIDE)`
   让双击场景立刻消失，再脱离）。脱离之后进程不属于任何控制台，窗口**真的没了**，
   关掉任何终端都不影响它。日志改由文件承载：输出层新增 `Terminal.consoleWithFile`
   （转后台时 `detachFromConsole()` 摘掉控制台那一路、在没有控制台时直接不写控制台，
   否则 `detached` 起的进程往无效句柄写会抛异步错误把服务带崩）；**日志从这一轮起
   始终同时写 `<数据目录>\server.log`**，不再只有 `--hidden` 才写。
2. **`hidden` 之后不能自己退出**：`FreeConsole` 之后 stdin 也跟着没了，命令循环会
   立刻读到 EOF 然后走收尾分支（= 转后台后马上自杀）。新增 `_detached` 标记，
   脱离之后 `_parkForever()` 挂住不返回，进程只由 `stop` / `--stop` 结束。
3. **重新呼出命令行界面**：服务端新增 **只认回环 + 控制令牌** 的
   `POST /api/v1/console`（与 `POST /api/v1/shutdown` 同一道门槛，令牌只写在
   `runtime.json` 里），由 `ServerApp.handleRemoteCommand` 把命令在**正在跑的那个实例**上
   执行、输出原样回给请求方（执行期间把 `terminal` 临时换成内存缓冲）。
   于是**再打开一次 exe** 就等于重新拿到命令行：它发现已有实例，就不起第二个服务，
   直接当那个实例的前端窗口（`attachToRunningServer`），窗口里 `status` / `qr` /
   `hotkeys reset` / `stop` 都能用。也顺带治好了老问题——以前第二次启动会起第二个
   服务抢下一个端口、两个实例的热键互相顶掉。
4. **两个新的启动参数**（用户"纯后台运行"的原话）：
   - `--background` / `-b`：另起一个**完全没有控制台**的自己（`ProcessStartMode.detached`），
     本次启动立刻返回；启动前用 `backgroundBlockReason()` 先查「AI 已配置 + 配对过手机」，
     缺什么就当场说，不让用户对着一个不出声的后台进程猜。
   - `--console`：明确要求"只给正在跑的实例当命令行窗口"；没有实例时照常启动并说明。
5. **`stop` 命令 = 真的停止服务**（以前只打印一段说明，容易误解）；命令行窗口里敲
   `quit` 只退出这个窗口，不动服务。
6. **顺手修**：`hotkey` 的用法提示还留着上一轮删掉的 `capture-fallback` 槽位名；
   日志文件句柄从"每行开关一次文件"改成**常开 `RandomAccessFile`**（二维码那三四十行
   原本要开关三四十次文件，实测把启动输出拖到状态面板都印完了二维码还没出来）。

**验收**（`20260923-quizsync-server-opt4.py`，真 exe + **真控制台窗口** + 假 AI，**34/34 通过**）

窗口取证办法：用 `CREATE_NEW_CONSOLE` 起子进程（它有真控制台窗口）但 stdin/stdout 仍接
管道（既能给它敲命令，也能读它的输出）；控制台标题默认就是 exe 路径，于是
`FindWindowW(NULL, exe)` 转后台之前拿得到句柄、转后台之后 **= 0**（"隐藏"骗不过这条）。

```text
A 输入 hidden：明说窗口即将消失、服务继续跑；脱离之后进程仍活着
A 控制台窗口真的没了（FindWindow 由非 0 变 0x0）；日志写明已脱离控制台
B 脱离后 HTTP 照常应答；热键 F8 仍能截屏识别并推给手机
C 再次打开 exe：提示「后台实例正在运行（PID …）· 端口 …」，没有起第二个服务、没有新二维码
C 窗口里 status / qr / hotkeys reset 都送到那个实例执行并原样回来
C 关掉这个窗口：后台服务不受影响；窗口里敲 hidden 会说服务本来就在独立后台运行
D 窗口里敲 stop：后台实例真的退出、端口不再应答、日志留下退出记录
E --background：启动器带 PID 报告后自己退出、没有控制台窗口、实例在跑、日志自证无控制台
E 再次打开 exe 连上的是这个纯后台实例；关掉窗口它仍在跑
F --stop 能停掉纯后台实例（无窗口也能停）
G --hidden 启动参数同样真正脱离控制台
H 没有实例时 --console 说明会按常规启动；quit 正常退出
```

回归：`20260923-quizsync-server-opt3.py` **24/24**（首跑）/ 22/23（末轮重跑，唯一失败项是
合成按键被别的软件吃掉那条）、`-opt2.py` **22/22**、`-opt.py` **29/29**、`-e2e.py` **35/35**
（都按"第二次启动 = 命令行窗口""hidden = 真脱离控制台"更新；`-e2e.py` 另把二维码两处断言
从"抢在打印前断言"改成"等它出现"，因为日志改为始终写文件后逐行输出慢了几十毫秒）。
启动输出耗时复核（`20260923-quizsync-server-startup-timing.py`）：
配对码 0.5–1.2s、二维码印完 +0.05s、配对链接 +0.05s、提示符就绪 ≈同刻。

**单测**：`dart analyze` 0 issue；`dart test` **86 项**（新增 `background_console_test.dart`
15 项：转发的回环 + 令牌门槛、错误令牌 / 缺令牌 / 错误请求体 / 未开放命令行 / 实例不在 /
运行文件损坏这六条负路径、`attachToRunningServer` 无实例时返回 null、`--background` 的
启动前检查四种形态、以及两个新启动参数的解析）。

### M45f · Server 1.0.0 第六轮：后台运行后热键会「悄悄死掉」的根因与修复

用户口径（原文）：

> 「用 hidden 进入后台模式后一切正常，但当重新点击应用后提示 <后台实例正在运行（PID …）>，
> 无论是关闭这个命令行还是（按）热键，就都失效了」

**真凶：热键注册落在一条会被 VM 换掉的线程上**

`RegisterHotKey(NULL, id, …)` 把注册挂在**调用它的那条线程**的消息队列上。上一版的注释
写着「所有热键共用一个 isolate ⇒ 线程不再换手」，**实测不成立**：给隔离线程加了
`GetCurrentThreadId()` 诊断后，28 秒里记录到 **327 次线程换手**，而且就在两条池线程
（如 27772 ↔ 30728）之间来回跳 —— Dart 的 isolate 每 `await` 一次，VM 就可能把它调度到
另一条线程上。后果有两种，用户看到的是第一种：

- **注册被回收**：持有注册的那条池线程被 VM 收走时，系统里的注册跟着消失。进程还活着、
  HTTP 照常、状态块里依旧写着「F8」，可按下去谁都不响应，且**没有任何 Win32 通知**。
  老版本没有自愈，于是「热键永久失效」。
- **消息被晾着**：注册还在，但泵跑在另一条线程上 → WM_HOTKEY 投递到旧线程队列，没人取。

**做法**

1. **热键线程改成「永不 await」的同步循环**：`PeekMessageW` + `kernel32.Sleep(15)`，
   一次都不让出执行权，线程号从此钉死，注册永远挂在正在泵的这条线程上。
2. **命令通道换成共享内存轮询**（因为不 await 就收不到 `SendPort`）：主 isolate /
   热键线程共用一块 `calloc<Int64>(8)`，主 isolate 写参数后**最后**写 `seq`，热键线程
   轮询到变化就执行、把错误码写回、**最后**写 `replySeq` 作应答。加「就绪握手」：
   `Isolate.spawn` 只保证 isolate 被创建、不保证入口已跑起来，不等握手就发命令会让第一条
   注册命令永远等不到应答（实测表现为「F8 未生效、F9 正常」）。触发事件仍走 `SendPort`。
3. **2 秒自检兜底**：拿同一个 id 再次 `RegisterHotKey` —— 还持有必然 1409，丢了会成功
   （顺手补回来）并写一行日志。
4. **顺带修掉三个真实缺陷**：
   - 状态块的「上次」显示的是本次启动时间（`noteStartup()` 把 `lastRunAt` 写成「现在」），
     改成记住上一次的时间；
   - **同一份 `server.log` 被两个实例同时写会互相覆盖**（各自句柄的写指针独立）：每次写入
     前把指针挪到文件末尾；
   - **运行文件僵尸**：先启动的实例被硬杀后，`runtime.json` 里的 PID/令牌属于死进程，
     后启动的实例却因为「不接管」规则永远拿不到它 → `--stop` 拿着旧令牌敲新实例得 403。
     现在每 15 秒复查一次，发现记录里的 PID 已经结束就把运行文件收回来。判定存活必须看
     **退出码**（`GetExitCodeProcess`）：进程被杀之后只要还有人持有它的句柄，`OpenProcess`
     照样成功，只看它会把死进程当活的（实测踩到）。
     归属判据也从「ping 文件里的端口，有人应答就算已有实例」改成「记录里的 PID 还活着吗」：
     交付冒烟当场抓到前者会**自己 ping 到自己**（旧文件记的端口恰好就是本次要绑的端口，
     `server.start()` 之后答话的其实是自己）→ 误判「已经有一个实例在运行」→ 永远不写运行
     文件，`--stop` / `--status` 一直指着死进程，这正是用户「停不掉」的另一半原因。

**验收**（`20260924-quizsync-server-opt9.py`，真 exe + 真控制台窗口 + 假 AI）

```text
==== 19/19 PASS ====
① 前台：F8 注册归本实例且能识别
② hidden 之后：注册仍归本实例、F8 仍能识别
③ 重新打开 exe：拿到命令行窗口；打开后注册仍归它、F8 仍能识别；窗口里 status 可用
④ 关掉窗口：注册没丢、F8 仍能识别、后台实例不受影响
⑤ 整段日志没有出现需要自愈的注册丢失，也没有「注册不在热键线程手上」的告警
⑥ 状态块的「上次」是上一次启动时间（种入 09-01 10:20 验过），不是本次
⑦ 第二个实例启动时不抢运行文件；先启动的实例被杀掉后 15 秒内运行文件被收回，
   --stop 因此能停掉它（不再 403），退出后运行文件被清掉
```

线程钉死的证据（`20260924-hotkey-thread-churn.py`，同一台机器同一套流程）：

```text
修复前：换手 327 次 / 28 秒（两条池线程来回跳），自检丢失 0 次（当时恰好没丢）
修复后：换手 0 次，自检「复查正常」52 次（每秒一次，注册一直在手上），F8 连按 3 次全部识别
```

自愈路径单独验过（诊断版每 5 次自检人为丢弃全部注册，`20260924-hotkey-selfheal-verify.py`）：
**丢弃 8 次 → 自动补回 8 次**，且抽查期间键始终归本实例（12/12）、F8 照常识别。

回归：`20260923-quizsync-server-opt3.py` 24/24、`-opt2.py` 22/22、`-opt.py` 29/29、
`-e2e.py` 35/35。

**单测**：`dart analyze` 0 issue；`dart test` **86 项**（热键命令通道换成共享内存之后，
单测里的假注册器不受影响，全部保持绿色）。

### M45g · Server 1.0.0 第七轮：《使用说明.txt》重排 + 关于页带项目地址

用户口径（原文）：

> 「使用说明先写一、首次配置的四个，然后二、配对手机，三、热键，四、数据与配置放在哪，
> 五、常用命令介绍，六、常见问题（将后台运行方式写到这里面）。本程序是功能冻结版
> v1.0.0：只做「截图 → AI → 手机」这一件事这句话不要，改成关于说明带上我的 GitHub 库地址」

**做法**：只改说明书正文（`server/tool/make_guide.dart`），章节按用户顺序重排 ——
一、首次配置（4 步，附改配置的窗口命令）；二、配对手机（补「配对码 5 分钟过期、重新配对」）；
三、热键；四、数据与配置放在哪（补「日志一直写，出错先看它」）；五、常用命令介绍；
六、常见问题（**把整段「后台运行方式」搬进来**：三种转后台方式、窗口没了怎么找回命令行、
关掉窗口会不会停、怎么停止、怎么确认在不在跑，再接原有的热键/网络/识别类问题）；
七、关于（删掉「功能冻结版 v1.0.0 只做一件事」那句，改成名称 + 版本 +
`https://github.com/iop666/QuizSyncAI` + 一句「与桌面端共用协议、手机端不需改动」）。
开头补一句使用顺序引导。

**验收**：`dart run tool\make_guide.dart build` 生成 8,409 字节的 BOM 文本；
`Select-String` 复核「一、…七、」齐全、`功能冻结` 不再出现、GitHub 地址在「七、关于」里；
交付目录里的 `使用说明.txt` 同步且与构建产物哈希一致。本轮 **不动 exe**（仍是最终版
8,811,008 字节），所以不需要重启服务。

### M45h · Server 1.0.0 发布到 GitHub Releases

用户要求「创建只有程序和使用说明的压缩包更新到 https://github.com/iop666/QuizSyncAI/releases，
创建一个单独的 releases，写明简要更新介绍」。

- 压缩包 `QuizSyncAI_Server-1.0.0-win64.zip`（3,793,818 字节，sha256 `ff7aed3e82858936…`）
  内**只有** `QuizSyncAI_Server.exe` 与 `使用说明.txt` 两个文件（根下，解压即得）。
- Release：标签 `server-1.0.0`、标题「QuizSyncAI Server 1.0.0（Windows 单文件版）」、
  `make_latest=false`（主项目那个 release 继续占 `Latest`），页面
  https://github.com/iop666/QuizSyncAI/releases/tag/server-1.0.0 。
- 标题与更新说明走 `gh api --input <utf-8 json>` 落库（不用命令行中文参数，避开 PS 5.1 的
  argv 编码坑）；发布前做了「包内条目/大小一致 + 无数据文件 + exe 内无 Key/用户名路径/
  局域网 IP」自检，发布后又把资产下载回来比对 sha256，全部一致。

### M45i · Server 源码入库 GitHub

用户要求：「将 server 的源码更新上去」。

远端仓库 `iop666/QuizSyncAI` 的 `main` 原本只有两个提交（`001a466 1.0.0 首次发布` →
`4feb50e Update README.md`），是主项目 1.0.0 的快照，**没有 `server/`**；本地仓库则是另一条
独立历史（67 个提交，已到 M45h），而且原来**没有配远端**。

**做法**：本地补上 `origin`（`https://github.com/iop666/QuizSyncAI.git`），在 `origin/main`
之上加**一次提交**，只含 `server/` 56 个文件（10,779 行），提交信息「新增 QuizSyncAI Server
1.0.0 服务端源码（独立 Windows 版，纯 Dart）」，作者沿用远端首个提交的身份。提交用**临时索引**
构造（`GIT_INDEX_FILE` + `git read-tree origin/main` + `git add server/` + `git commit-tree`），
**不动工作区、不动本地 `master`**。标签 `server-1.0.0` 从 `4feb50e` 重指到这个新提交，让 release
页面的「Source code (zip / tar.gz)」也带上服务端源码；主项目标签 `1.0.0` 与那个 `Latest` release
一概不动。**没有**推本地 `master`（它含桌面端 1.1.x 等未发布改动），也**没有**推 `docs/` 下的
内部记录（远端 `docs/` 一直只有四份契约文档）。

**验收**：

- 远端 `refs/heads/main = 05c3abc`，顶层多出 `server/` 目录；`git rev-parse origin/main:server`
  与 `master:server` 同为 `f3068b09…` —— 子树对象同号即逐字节一致。
- 从 codeload 拉下标签 `server-1.0.0` 的源码 zip（19,735,944 字节）：`server/` 共 **56 项**，
  逐项重算 git blob sha1 与推送提交里的 blob **56/56 完全一致**；包内 `server/build/`、
  `.dart_tool/`、`.exe`、`userdata/` 均为 **0 项**。
- 用 `git archive` 把这 56 个文件取到干净目录，`dart pub get --offline` → `dart analyze` →
  `dart test`：**0 issue / 86 项全绿**（发布出去的源码自洽、可独立构建与测试）。
- 发布红线复扫 `server/` 源码：无 `C:\Users\<用户名>`、无真实 Key（`sk-`）、无 `lnx14`；
  出现的 `192.168.1.100`、`D:\Server\…`、`D:\tmp\cfg` 都是文档/测试里的示例值，
  `https://github.com/iop666/QuizSyncAI` 是有意保留的项目地址。

### M46 · 用户反馈轮（热键收敛成两个 + 悬浮窗公式声明 + 赞助挪位 + 版本 1.1.0 + 源码包）

用户一次性给了 7 条（原话）：

1. 「软件截屏热键改为F8和F9，截屏逻辑和server类似。就是只有两个热键，默认截屏识别为F8。
   进入多页模式并截取第一张为F9，进入多页模式后，若累积到第六张则截取完第六张自动上传识别，
   若未满的情况下，按下默认识别热键也就是F8结束多页模式上传缓存所有图片进行识别。」
2. 「windows悬浮窗设置页面，声明悬浮窗不支持显示公式。」
3. 「删除赞助页及其所有代码图片。在设置关于的最下面加入赞助支持模块，填上我的爱发电地址：
   https://afdian.com/a/iop666。」
4. 「我已删除除了正式版1.0.0外的安装包，修改双端软件版本号为1.1.0。」
5. 「安卓配对页有句过时文案，修改它：手机上写着「Windows 端：设置 → 服务（Android 配对）」，
   而 Windows 那个分现在叫「连接设备」。」
6. 「源码包要带 19MB 的 MiSans 字体：不带就没人能直接构建（pubspec 声明了它）；带就意味着
   字体文件进了公开仓库 —— 按小米 FAQ「可随软件嵌入分发、不得单独再分发」来看随包是允许的.」
7. 「除去正式版软件中一些构建中的介绍等信息。」

**逐条做了什么**

| # | 做法 | 关键点 |
|---|---|---|
| 1 | `HotkeySlot` 三个 → **两个**：`capture`（截屏识别，默认 `F8`）/ `multipage`（多页模式，默认 `F9`）。语义照服务端：截屏识别键在多页模式里＝**结束多页并上传已抓的图**（不再多截一张）；多页模式键第一下进多页抓第一张、继续按追加、**抓满 6 张抓完就自动上传识别**。判定抽成纯函数 `intentOfCaptureHotkey` / `intentOfMultipageHotkey` / `shouldAutoUploadAfterCapture`（可单测）。`hotkeyRejectReason` 给单按 F1–F12 开口子（单按字母/数字仍然要求带修饰键）。托盘、悬浮球、悬浮窗、主界面暂存条、使用说明页、识别设置页的文案一起改 | 悬浮窗上的「多页识别 / 继续添加页」到上限时**不替用户上传**（用户显式点的一次加页），只提示点「结束并上传」——热键路径才自动上传 |
| 1b | `services/hotkey_service.dart` **整条照搬 Server 的线程模型**：后台循环同步 `PeekMessageW` + `Sleep(15)`（一次 `await` 都不做）、命令走共享内存 + 就绪握手、每 2 秒自检「同 id 再注册」（还持有必然 1409）、线程异常/退出自动重建、触发写一行日志 | 这是 M45f 在服务端实测过的坑（isolate 换线程 → 注册静默消失）；桌面端的热键是用户看得见的功能，不能靠「没人报就当没坏」 |
| 2 | 悬浮窗设置页的页面说明 + 「详细解析模式」的 ⓘ 都写明**悬浮窗不排版公式**（公式按 LaTeX 源码显示，要看排版好的请回主窗口） | M41 起就是这个取舍，界面上第一次说清楚 |
| 3 | 删 `sponsor_settings_page.dart`、两张收款码图片与 pubspec 资源项、`SettingsTab.sponsor`；「关于」页最下面新增「赞助支持」组（爱发电 `https://afdian.com/a/iop666`，`openExternal` 打开） | 分类 11 → 10，关于重新是最后一项 |
| 4 | 双端版本统一 **1.1.0**：桌面 `pubspec 1.1.0+30` / `Runner.rc` / `app_info` / `installer.iss` / 三个打包脚本默认版本；安卓 `pubspec 1.1.0+19`（versionCode 1019/2019/4019）；另把两处硬编码的 `appVersion: '1.0.0'`（安卓配对请求、桌面内置服务端）改成随产品版本走 | 出包序号继续往上顶，旧包装不上时能覆盖；配对时双方上报的版本号也要是真的 1.1.0 |
| 5 | 安卓配对页引导改成「Windows 端：设置 → 连接设备 → 显示二维码与 6 位配对码。」，下面那句「服务区」也改成「连接设备」 | 新增 widget 断言：必须出现「设置 → 连接设备」，且旧文案一个字都不许留 |
| 6 | 新增 `tools/package_source.ps1`：产出 `dist\quizsync-source-<版本>.zip`，**带 `apps/desktop/assets/fonts/MiSans-VF.ttf`（20,000,736 字节）**，zip 内无外层目录 | 复核步骤会拒绝「字体缺失 / 字体被截断 / 混进构建产物」的包 |
| 7 | 源码包**不带**内部构建记录（`AGENTS.md`、`docs/{DECISIONS,DEV,milestones,progress,optimization-plan,manual-test-android,agent-kickoff-prompt}.md`，只留 SPEC/protocol/data-model/ai-contract）；界面文案里「源码、构建脚本与每一轮改动的说明」也改掉 | 新增根 `LICENSE`（MIT）；README 里「LICENSE 待补充」同步改掉 |

**验收命令与实际输出**

```text
(core)     flutter analyze → No issues found!          dart test → 00:04 +195: All tests passed!
(ui)       flutter analyze → No issues found!          flutter test → 00:02 +56: All tests passed!
(desktop)  flutter analyze → No issues found!          flutter test → 00:17 +219: All tests passed!
(android)  flutter analyze → No issues found!          flutter test → 00:09 +83: All tests passed!

desktop: flutter build windows --release --no-tree-shake-icons → √ Built quizsync_desktop.exe
android: flutter build apk --split-per-abi --release --no-tree-shake-icons → 3 个 ABI 全部 Built
tools\package_windows.ps1 → portable zip 30.6 MB（entries=64 / userdata=0 / VC DLL=10）
                              + setup 26.4 MB
tools\package_android.ps1 + tools\audit_android.ps1 → 3 个 APK 落到 dist，AUDIT PASS（60 项）
tools\package_source.ps1  → dist\quizsync-source-1.1.0.zip（376 条目 / 19.2 MB，含 MiSans 19.1 MB）

发布版探针（临时副本，绝不碰用户真实 userdata）：
  register[capture]  id=1 vk=119 mods=0 -> F8 OK      register[multipage] id=2 vk=120 mods=0 -> F9 OK
  另一个进程注册 F8 -> 0 (err=1409) / F9 -> 0 (err=1409) / 对照 F1 -> 1 (err=0)
  合成 F9 → 日志「热键触发：多页模式（F9）」；合成 F8 → 日志「热键触发：截屏识别（F8）」
  保持运行 40 秒后再注册 F8/F9 仍然都失败（= App 一直持有）；自检补注册行 0、线程异常行 0
```

**未验证（需人工）**：安卓真机（安装 `quizsync-android-arm64-v8a-1.1.0.apk`，看关于页版本与
配对页那句「设置 → 连接设备」）；Windows 上两个热键在**用户真实环境**里与其他程序是否冲突
（本机实测：启动前 F1–F11 空闲、**F12 被别的程序占着**；F8/F9 都注册成功）。


### M47 · 代码审查修复轮（1 个 P0 数据正确性 + 端侧状态机 + 协议收尾 + 发布包元信息）

**起因**：用户让另一个 AI 做了一轮全库静态审查（P0 数据正确性 / P2 文档与实现不一致 /
P3 端侧运行时缺陷 / 工程与发布质量四个分区）。M47 是**逐条核实之后**按严重度修的那一批 ——
审查报告里错报、夸大、以及"其实是有意设计"的条目一律不动（见 `DECISIONS.md` M47 各行）。

任务与验收：

| # | 内容 | 验收 |
|---|---|---|
| 1 | **A1 迁移补列**：v1→v2 漏了 `tasks.payload_json`；另加"打开时自愈"（已标成 v3 但缺列的老库） | `migration_test` 新增 2 条（v1 升上来能入离线队列 / 已标 v3 的坏库自愈） |
| 2 | **A5 闸门补齐**：「结束多页」原来不查合集与 API Key，且会先清暂存区 | 新增 `staging_gate_test`（3 条：没合集不调 AI 且暂存不丢 / 正常路径不变 / 连按两次只调一次 AI，含**反向对照**） |
| 3 | **B1 重入闸门同步置位**：`_busy` 原来在两个 await 之后才置位；多页入口压根不置位 | 同上第 3 条（把闸门放回旧位置会红） |
| 4 | **B3 取消置顶无效**：`SetWindowPos(..., 0, ...)` 的 `0` 是 `HWND_TOP` | 非置顶时改用 `_hwndNotTopmost` + `SWP_NOZORDER`（Z 序只在 `setTopmost` 里改一次） |
| 5 | **B5 悬浮球缓存键竞态**：`rootBundle.load` 前后各算一次键，旧图会存进新键 | `_render` 先把状态/颜色/键快照成局部变量，并在收尾检测"期间又变了"重出一帧 |
| 6 | **B4 点击阈值**：物理像素写死 6（球 8），150%/200% 缩放下只剩 3–4 逻辑像素 | 常量改**逻辑像素**，按当前 DPR 折算成物理阈值 |
| 7 | **A3 op 归属校验**：`/sync/ops` 与 WS `push_ops` 原来只挡"冒充主机" | 新增 `push_ops_ownership_test`（HTTP + WS 两条通道：冒充别的设备被拒、自己的 op 照常、冒充主机只是跳过） |
| 8 | **C1 上传体积闸门**：预检依赖 `Content-Length`，chunked 时为 null → 整包进内存 | 边收边计数、超限立刻 413；`upload_limits_test` 用**不结束请求体**的用例证明"不等整包收完"（含反向对照） |
| 9 | **C2 上传限流**：SPEC §10 要求 30 次/分，两端都没实现 | 每台设备一个滑窗，超限 429；用例验证"另一台设备不被连坐" |
| 10 | **A2 删除 vs 修改的收敛**：删除输掉时没人回头 → 一端删一端在，永久分叉（违反 `data-model.md` 2.9） | 规则定成「lamport 大者赢、输的一方跟着改」；`delete_edit_convergence_test` 3 条（删除输→删除方复活 / 删除赢→两端都删 / 双删→时间戳收敛），第 1 条含反向对照 |
| 11 | **A4 手机端结果落库**：`LiveUpdates` 逐个 `upsertQuestion` 会盖掉用户手改 | 改走 `applyAnalysisResult`（带 `*_edited` 保护 + 多余题目软删）；`live_updates_test` +1 条（含反向对照） |
| 12 | **B2 热键线程真重建**：`_restoreAfterDeath` 只清 `_starting`，`_ensureThread` 见 `_slot != null` 直接返回 → 「重建」什么都没重建 | 新增 `_respawn()` 真正再 spawn 一个 isolate（复用共享内存与端口） |
| 13 | **B6 安卓到上限自动提交**：只在长按**开始**时判上限 | 加页后立刻判；**改了一条旧用例的期望**（原断言把"要再多按一次"钉住了，理由写进 DECISIONS） |
| 14 | **B7/B8/B9/B10 安卓侧四项**：悬浮球开关不落库（任何设置变更都会把球打开）/ 轮询闩锁按裸 `session_id` 吞掉同会话新结果 / 队满被 `catch (_)` 吞成网络错误 / 剪枝会剪掉离线队列引用的原图 | 球开关落 `kBallEnabledKey` 并在 `_applyRecognitionState` 尊重；闩锁改「会话+结果版本」指纹（+1 条用例）；`QueueFullException` 单独上报；`pruneImageFiles` 新增 `keep`（+1 条 core 用例） |
| 15 | **C3/C4 服务端**：`/sync/snapshot` 一次物化全库（`limit: 1000000`）；任务队列无深度上限 | snapshot 改 `limit`/`offset`/`has_more`；队列满回 429 `queue_full` |
| 16 | **C5/C6 协议**：主版本不一致要回 426（两端都没读这个头）；`already_paired` 应回 409 | 两个服务端都实现（**不带版本头的请求放行**，避免挡住老客户端）；`ApiClient.pair` 把 409 也当成功 |
| 17 | **C7 安全提示与锁定**：SPEC §8 的「陌生设备尝试连接」提示没实现；配对失败计数是纯内存态 | 服务端统计无效 token 尝试 + 设置页「安全提示」模块（可"知道了"清掉）；失败计数/锁定期落库，重启仍生效 |
| 18 | **D 契约清理**：SPEC 里 2 行旧版本号、悬浮球「默认开」、安卓"图片缓存上限"、以及**从未实现的开机自启** | 全部改正；开机自启按用户要求**删功能与条款**，其余三条以代码为准改文档 |
| 19 | **E 发布包元信息**：Gradle wrapper 被 `.gitignore` 忽略却在源码包里（用户 git init 后安卓端构建不了）、两个包 LICENSE 是 `TODO`、`Runner.rc` 还是 `com.example`、`.env` 不在排除集、4 个零引用依赖、剪贴板用例会静默变绿、`raw_response` 无落库覆盖 | wrapper 三个文件进版本库并放行忽略；LICENSE/CHANGELOG/README 换成真实内容；`Runner.rc` 改 `iop666`；`.env*` 进排除集与泄漏闸门；删 4 个依赖；剪贴板用例改成"只跳过真剪贴板往返、解码断言照跑"；补 `raw_response` 用例 |
| 20 | **E7/E8 版本与脚本**：版本号散在 ~10 处；4 个工具脚本硬编码作者机绝对路径 | 三个打包/审计脚本改为**从 pubspec 读**、`installer.iss` 用 `/DAppVersion` 传入（保留兜底默认值）；脚本加 `Get-Command`/环境变量回退；新增 `version_consistency_test`（桌面 pubspec ↔ kAppVersion ↔ Runner.rc、双端一致、脚本里不许再写死版本） |
| 21 | **G 加固**：悬浮窗分块缓存只按条数封顶（3.0× + DPR2 最坏 ~330 MB）；DPAPI 明文缓冲不清零；每改一项设置串行写 32 条键 | 缓存加**字节**上限（48/96/12 MB）；`LocalFree` 前清零（并清掉 arena 里的明文副本）；设置只写变化过的键（`settings_write_test`） |

| 22 | **独立 Server 对齐加固 → 发 v1.0.1**（用户追加要求）：把只进了桌面内置服务端的四条搬到 `server/`（上传边读边限长 / 上传限流 30 次每分 / snapshot 分页 / 任务忙时 429 `queue_full`），`kServerVersion` 顶到 1.0.1，重编 exe + 说明并打包到交付目录 | `server`: analyze 0 issue、**90 项全绿**（+4 条新用例：chunked 超大包不等整包收完就 413、限流按设备算、snapshot 分页不重不漏、忙时 429）；exe `--version` → `QuizSyncAI Server v1.0.1`；交付 zip 内两条目与散装文件 sha256 逐个一致 |

**出包**：序号 +31 / +20（versionCode 1020 / 2020 / 4020），产物复核后交付到
`D:\DeepseekHarness\QuizSync_AI-issue\1.1.0\`。

---

### M48 · 用户实测反馈三条（1.1.0 交付后）

用户装完 1.1.0（M47）立刻实测报的三条：两条安卓侧、一条 Windows 侧。其中第 1 条是 **M47 自己
按审查报告加的功能判据错了**（"我改出来的 bug"），这轮先修它。

| # | 内容 | 验收 |
|---|---|---|
| 1 | **删掉「陌生设备尝试连接」安全提示**（用户原话「一秒一个无效链接尝试的提示，删掉他」）：整块移除服务端计数 + 控制器透出 + 设置页「安全提示」模块；`SPEC.md` §8 同步改成「拒绝，但不再显示提示」 | 根因：手机端前台每秒轮询 `/tasks/active`，未配对 / 换过 token 时这些**合法轮询**被判成无效尝试 → 提示一秒加一条（误报）。`server_hardening_test` 那条断言换成「在线判据」用例；`settings_shell_test` 断言连接设备页只有连接状态、不再有安全提示模块 |
| 2 | **「当前连接状态」不更新**：在线判据改成「WS 连着 **或** 最近 15 秒内有已认证请求」（`activeDeviceCount`），设置页不再只读 WS 连接数 | 新增 `settings_shell_test` 用例：真起服务端 + **真 HTTP 配对与轮询**（测试里临时把 `HttpOverrides.global` 置空才打得了真网络）→ 页面显示「已连接 · 1 台设备在线」；core 侧 `server_hardening_test` 另有一条纯服务端断言（轮询算在线、无效 token 不算） |
| 3 | **关悬浮球要连投屏一起停**：`CaptureBridge.setBallVisible(false)` 里补 `CaptureService.stop()`，前台服务与 `MediaProjection` 随之释放 | Kotlin 改动，本机无设备无法自动化验证；真机验收项写进 `docs/manual-test-android.md` 第 37 项 |

**验收**（四包 analyze + 测试）：

```text
(core)     flutter analyze → No issues found!          dart test    → All tests passed!（212 项）
(ui)       flutter analyze → No issues found!          flutter test → All tests passed!（57 项）
(desktop)  flutter analyze → No issues found!          flutter test → All tests passed!（227 项，+1）
(android)  flutter analyze → No issues found!          flutter test → All tests passed!（85 项）
```

**明确不改**（审查报告里错报或本就有意为之，逐条写进 DECISIONS）：
悬浮球默认关（M44 用户决定，改的是 SPEC）、安卓 `AccessibilityService`（真实存在且不读屏）、
`server/lib/src/core/` 的 20 文件复制（有意冻结）、`/sync/ops` 这条 HTTP 路由（手机端在用）、
`applyRemoteCollectionDeletes=false`（M18 用户决定）。

**验收**（四份 analyze + 五套测试）：

```text
(core)     flutter analyze → No issues found!          dart test    → All tests passed!（212 项，+17）
(ui)       flutter analyze → No issues found!          flutter test → All tests passed!（57 项，+1）
(desktop)  flutter analyze → No issues found!          flutter test → All tests passed!（226 项，+7）
(android)  flutter analyze → No issues found!          flutter test → All tests passed!（85 项，+2）
(server)   dart analyze    → No issues found!          dart test    → All tests passed!（86 项）
```

**出包**（`tools/build_all.ps1` ALL GREEN + `package_source.ps1`，出包序号 +31 / +20）：

```text
dist\quizsync-windows-portable-1.1.0.zip   30.5 MB（entries=61 / userdata=0 / VC DLL=10）
dist\quizsync-windows-setup-1.1.0.exe      26.3 MB（版本号由 package_windows → /DAppVersion 传入）
dist\quizsync-android-{arm64-v8a,armeabi-v7a,x86_64}-1.1.0.apk  29.0 / 25.5 / 31.6 MB
dist\quizsync-source-1.1.0.zip             19.2 MB（383 条目，含 MiSans 19.1 MB）
audit_android.ps1 → AUDIT PASS（60 项；versionCode 1020 / 2020 / 4020）
exe 属性：FileVersion=1.1.0 / CompanyName=iop666 / LegalCopyright=Copyright (C) 2026 iop666
```

**未验证（需人工 / 需真机）**：热键线程死后重建的真实触发（要发布版探针杀线程）、
200% 缩放下的点击阈值、安卓真机上的长按截帧时机与横竖屏（G1/G2 两条本轮**刻意没做**，
它们要动 Kotlin 手势/尺寸逻辑，属于"必须真机验证"的范围，留待用户决定）。

### M49 · 用户实测反馈三条（1.1.0 交付后，第二轮）

用户装完 M48 的包后报的三条：两条安卓侧、一条 Windows 侧。

| # | 内容 | 验收 |
|---|---|---|
| 1 | **安卓多页手势看齐 Windows 端**（用户原话「短按则是提交已经截取的图片，不再添加图片」）：`MultiPageCapture.tapToFinish()` 不再补截一张，只用已抓的页 `_submit()`；「最后一页截屏/上传失败」两条提示随之删除。**抓满上限自动提交并退出多页模式**本来就是 M47 的行为，本轮写进说明与用例 | `multipage_capture_test`：短按后 `capturePage`/`uploadPage` 调用次数**不变**、提交页数 = 长按次数（负向对照：改回补截一页 → 两条红）；`capture_pipeline_test` 的端到端用例从「2 长按 + 1 短按 = 3 页」改成 **2 页**；识别模块设置页的手势说明、`SPEC.md` §3.1、`README.md`、真机清单同步改写 |
| 2 | **过程提示不再排队回放**（用户原话「回到安卓应用后，app内会把app累积的提示一个一个跳出来，直到结束」）：后台不入队（Toast 那一侧负责）、前台只留最新一条、回前台清一次队列；`CaptureBridge.showToast` 也改成新提示 `cancel()` 掉旧提示 | 新增 `apps/android/test/snack_queue_test.dart`（2 条）：连发三条后推进 5 秒屏幕应为空（旧实现会在第 4 秒跳出第二条）、后台 `paused` 期间连发三条→回前台一条都不跳。**负向对照两条都红**（分别死在「看完一条就结束」与「回前台不再跳」上） |
| 3 | **设置里写明「同时只支持连接一台安卓设备」**：连接设备页三个分支各加一条 `SettingsNote`（含换手机先吊销旧设备的顺序），`SPEC.md` §2.3 / `README.md` 同步 | `settings_shell_test`：页面自检里断言该说明存在（开关关着那一支），另有独立用例断言「开关打开、服务未启动」那一支；服务已启动那一支在既有用例里补一条断言 |

**验收**（四包 analyze + 测试）：

```text
(core)     flutter analyze → No issues found!          dart test    → All tests passed!（212 项）
(ui)       flutter analyze → No issues found!          flutter test → All tests passed!（57 项）
(desktop)  flutter analyze → No issues found!          flutter test → All tests passed!（228 项，+1）
(android)  flutter analyze → No issues found!          flutter test → All tests passed!（88 项，+3）
```

**出包**（`tools/build_all.ps1` ALL GREEN + `package_source.ps1`，出包序号 +33 / +22）：
产物清单与 sha256 见 `docs/progress.md` 的 M49 段。

**未验证（需真机）**：①②③ 的安卓侧观感都在 `docs/manual-test-android.md` 第 38 项（短按不多截一张、
抓满自动提交、提示不连锁播放、Toast 不排队、电脑端设置里的那行说明）。





## 收尾：交付前的自检清单

在宣布全部完成前，逐条确认并写入 `docs/progress.md`：



- [ ] `dart test` 在 `quizsync_core` 全绿，且覆盖了 `ai-contract.md` §7 与 `data-model.md` §4 列出的全部测试。

- [ ] 两端 `flutter analyze` 无 error。

- [ ] `tools/build_all.ps1` 一次跑通。

- [ ] 标绿规则在两端实现一致（对照 `SPEC.md` 4.3 逐项核对，包括深色主题的独立色值与 ✓ 图标）。

- [ ] 「上一次 / 下一次 / 回到本次」在两端语义一致（对照 `SPEC.md` 第 5 节）。

- [ ] 无题目框选的默认状态是「关闭」，仅在「未识别到题目」时临时启用。

- [ ] 没有任何 FLAG_SECURE 绕过代码。

- [ ] `docs/DECISIONS.md` 的实施期决策表已记录所有偏离原始文档的选择。

- [ ] AI API Key 与 token 未出现在任何日志、数据库明文字段或提交内容中。

- [ ] 无法自动验证的项目（Android 真机行为、真实 AI 调用）已在 `docs/progress.md` 与 `docs/manual-test-android.md` 中明确列出，且没有谎报为「已验证」。

