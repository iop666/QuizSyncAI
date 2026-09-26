# QuizSyncAI Server

**截图 → AI → 手机** 专用 Windows 后台服务。功能冻结版 **v1.0.1**（v1.0.0 之后的补丁版：不加功能，只补四条与主项目对齐的加固，见下）。

- 它**不是** Windows Desktop 的一个模式，Desktop 也**不会**因为多了它而改任何东西；
- 它**不依赖** Flutter / Desktop UI / 悬浮球 / 托盘 / 设置页 / Desktop 状态管理；
- 它自己拥有：配置、HTTP + WebSocket 服务端、手机配对、截图、全局热键、AI 调用、
  识别流程、结果同步；
- Android 端**不需要任何修改**：Server 实现的就是 Desktop 那套协议，手机分不出
  自己连的是哪一个。

---

## 1. 它能做什么（只做这四件事）

1. **手机配对**（扫终端里的二维码，或手动输入 IP + 端口 + 6 位配对码）
2. **AI API 配置**（Provider / Base URL / API Key / Model，首次启动四步引导）
3. **两个全局热键**（一个动作一条键）
4. **截图 → AI → 通过既有 WebSocket 协议把结果推给 Android**

两个热键：

```text
截屏识别  F8
    不在多页模式：截一张屏 → 立刻识别 → 结果推到手机
    已在多页模式：结束多页，把已抓的图一起上传识别

多页模式  F9
    第一次按：进入多页模式并抓第 1 张（一题跨屏时用）
    继续按  ：继续追加下一张
    抓满 6 张：自动上传识别（不用再按）
```

Server 识别出来的记录统一归到一个叫 **Server** 的合集里（协议要求主机必须有当前
合集，否则安卓端不允许发起识别、历史也会全落进「未分类」）。手机历史里一眼就能认出
哪条是 Server 识别的，不会和电脑端建的合集混在一起。

没有别的东西：没有 Web 管理页、没有托盘、没有悬浮球、没有账号、没有云、没有数据库、
没有自动更新、没有统计页。

```
Windows 全局热键 ──► 截屏（GDI BitBlt）──► JPEG ──► AI（现有 provider）──►
会话 + 题目 ──► WS task_update / task_result（+ GET /api/v1/tasks/active 轮询兜底）──► Android
```

---

## 2. 运行

```text
QuizSyncAI_Server.exe                 # 双击或命令行启动（前台：能看到状态与二维码）
QuizSyncAI_Server.exe --hidden        # 转后台：本进程**脱离控制台**，窗口消失、关终端也不影响它
QuizSyncAI_Server.exe --background    # 纯后台：另起一个完全没有控制台的自己，本次启动立刻返回
QuizSyncAI_Server.exe --console       # 不起新服务，直接连上正在运行的那个实例，给它当命令行窗口
QuizSyncAI_Server.exe --status        # 看看现在有没有实例在跑、在哪个端口、是第几次启动
QuizSyncAI_Server.exe --stop          # 让正在运行的那个实例优雅退出
QuizSyncAI_Server.exe --api-key sk-xx # 首次启动也可以直接用参数给 Key
QuizSyncAI_Server.exe --help          # 全部参数
使用说明.txt                          # exe 旁边那份简明说明（编译时一起生成）
```

⚠️ `--hidden` / `--background` / `--console` / `--stop` / `--status` 是**启动参数**
（在命令行或快捷方式里加），**不是启动后在窗口里敲的命令**。在窗口里敲它们会提示正确用法。

**窗口消失以后怎么再看到命令行**：`hidden` 走的是 `FreeConsole()`，进程**真脱离控制台**
（不是把窗口藏起来）——窗口没了、关掉终端也不影响它。想再看命令行，**再打开一次
`QuizSyncAI_Server.exe`** 就行：它发现已经有实例在跑，就不再起第二个服务，而是直接给
那个实例当命令行窗口（屏幕上写明「后台实例正在运行（PID …）· 端口 …」，你敲的
`status` / `qr` / `hotkey` / `stop` 都送到那个进程上执行）。要开机自启就用 `--background`。

首次启动（还没有配置文件）会走 **4 步引导**，一步一屏、每步都能用数字选：

```text
第 1 步 / 共 4 步 — Provider：接口协议，三选一（交互输入时直接打 1 / 2 / 3 也行）
   1 = openai-compatible  DeepSeek、OpenAI、通义千问(DashScope 兼容)、智谱、Kimi …
   2 = anthropic         Anthropic 官方 Claude 接口
   3 = gemini            Google Gemini 官方接口
   第 1 步·选择 Provider（1/2/3） [1]:
第 2 步 / 共 4 步 — Base URL：服务地址（默认使用 DeepSeek，也可选择 OpenAI 或其他）
   1 = DeepSeek  https://api.deepseek.com     2 = OpenAI  https://api.openai.com/v1
   第 2 步·选择服务地址（1/2 或直接粘地址） [1]:
第 3 步 / 共 4 步 — API Key：服务商后台申请的密钥，形如 sk-xxxxxxxx（只存在这台电脑上）
   如 DeepSeek 申请入口：https://platform.deepseek.com/api_keys
   第 3 步·粘贴或输入 API Key（sk-...） [必填]:
第 4 步 / 共 4 步 — 输入模型名，必须是能看图的多模态模型，默认为 deepseek-flash
   1 = deepseek-flash（默认）  2 = gpt-4o-mini  3 = qwen-vl-max  4 = glm-4v-plus
   第 4 步·选择模型（1/2/3/4 或直接输入模型名） [1]:
```

填错会当场提示重输（不会静默把值丢掉）；没有可交互控制台时（例如用脚本跑），
四步说明也会整体打印一遍，再用 `--api-key` 或直接编辑 `config.json` 配置。

配置与数据写进

```text
<exe 所在目录>\QuizSyncAI_Server\config.json   ← 配置（AI 四项 + 三个热键 + 端口）
<exe 所在目录>\QuizSyncAI_Server\state.json    ← 状态（设备 / 会话 / 题目 / 合集）
<exe 所在目录>\QuizSyncAI_Server\images\*.jpg  ← 截图原图（手机可按 hash 取回）
<exe 所在目录>\QuizSyncAI_Server\server.log    ← 日志（**始终**写：控制台没了以后只剩它）
<exe 所在目录>\QuizSyncAI_Server\runtime.json  ← 运行信息（pid/端口/停机令牌，退出即删）
```

也就是说：**程序在哪，数据就在哪**（拷走整个文件夹就带走了配对与历史）。exe 目录
不可写（装在 `Program Files` 之类）时才退回 `%APPDATA%`，并在日志里写明用了哪个。
早期版本把数据放在 `%APPDATA%\QuizSyncAI\Server`，升级时会**自动搬一次**到新目录
（老目录保留不删）；用 `--config <目录>` 指定别的位置时不会去搬老数据。

> ⚠️ **API Key 在这个产品里是明文存在 `config.json` 里的**（不是 DPAPI 加密）。
> 这是它与桌面端「AI 双端搜题」的差别 —— 桌面端按 SPEC §10 走 DPAPI（`secure.bin`），
> 而 Server 是一个功能冻结的独立命令行产品，`config.json` 跟着程序目录走。
> `runtime.json` 里的停机令牌（`x-qs-control`）只对**回环地址**生效，局域网打不进来；
> 但只要有本机文件读权限就能拿到 Key —— 介意的话请把程序放在只有自己能读的目录下。

之后每次启动直接读配置，不再询问。

启动后是**中文、紧凑**的一屏（不再是原来那种大英文方块）：

```text
QuizSyncAI Server v1.0.1
──────────────────────────────────────────────
  服务器  运行中    192.168.1.100:8765
  手机    等待配对  配对码 582931
  AI      已配置    DeepSeek / OpenAI 兼容 · deepseek-flash
  热键    截屏识别  F8
          多页模式  F9
  运行    第 3 次启动 · 首次 09-23 19:02 · 上次 09-23 20:15
  数据    <数据目录>\QuizSyncAI_Server

用手机「扫码配对」扫下面这个二维码：
（二维码）
扫不出来就手动输入：192.168.1.100 : 8765  配对码 582931

怎么用：
  1) 手机配对：用手机 App 里的「扫码配对」扫下面的二维码；扫不出来就手动输入地址与配对码。
     地址 192.168.1.100:8765   配对码 582931
  2) 截屏识别：按 F8 → 截取鼠标所在那块屏幕 → 自动识别 → 结果直接推到手机。
  3) 多页识别：按 F9 进入多页模式并抓第 1 张，继续按追加，攒满 6 张会自动上传；
     没满时按 F8 立即结束并上传。
  4) 更多命令：help 全部命令 · status 看状态 · qr 看二维码 · pair 刷新配对码 · hotkey 改热键 ·
     ai 看配置 · devices 已配对手机 · quit 退出。
  5) 后台运行：这里输入 hidden → 窗口消失、服务继续跑（关掉终端也不影响它）；
     想再看命令行就再打开一次本程序，停止服务请输入 stop。
命令提示符已就绪（help 看命令，Ctrl+C 或 quit 退出）。
>
```

启动时会有一行**启动标识**：`[启动] 第 3 次启动 · 首次 09-23 19:02 · 上次 09-23 20:15`，
状态块里也有同样的「运行」一行，并且写进 `state.json` 的 `stats`。
另开一个命令行执行 `QuizSyncAI_Server.exe --status` 可以随时查：
在不在跑、跑在哪个端口（PID 多少）、总共启动过几次。

如果这台机器上**已经有一个实例在跑**，再次启动**不会起第二个服务**：它会直接给那个
实例当命令行窗口（见下面「后台运行与找回命令行」）。

状态块只在**内容变了**的时候才印（配对成功、手机连上/断开、改热键…）：断线重连来来回回
也不会刷出一堆一模一样的方块；热键注册的 Win32 原文只在**失败**时才打。

下面还会打印**终端二维码**（用 `▀` + ANSI 黑白渲染，手机扫码即可），以及一行可以
复制发给手机的 `quizsync://pair?...` 配对链接。

### 命令（启动后直接输入）

| 命令 | 作用 |
|---|---|
| `help` | 命令列表 |
| `status` | 重显状态 |
| `qr` / `pair` | 重显二维码 / 刷新配对码再显示 |
| `hidden` | 转后台运行：**脱离控制台**，窗口彻底消失，关掉终端也不影响它 |
| `hotkey capture <组合键>` | 改「截屏识别」热键 |
| `hotkey multipage <组合键>` | 改「多页模式」热键 |
| `hotkeys reset` | 两个热键恢复默认 |
| `devices` | 已配对手机 |
| `ai` | 当前 AI 配置 |
| `set-api-key` / `set-model` / `set-base-url` / `set-provider` | 改 AI 配置 |
| `stop` | 停止服务（等价于 `--stop`） |
| `quit` | 退出（前台时停服务；作为后台实例的命令行窗口时只关窗口） |

`Ctrl+C` 与 `quit` 同效：停 HTTP、关 WebSocket、注销全局热键、保存状态、进程退出。

### 后台运行与找回命令行

`hidden`（或启动参数 `--hidden`）做的是 **`FreeConsole()`**，不是"把窗口藏起来"：
进程从此不属于任何控制台，窗口**真的没了**，关掉任何终端都不影响它。代价是 stdin
也没了 —— 所以脱离之后进程只由 `stop` / `--stop` 结束，日志固定写在 `server.log`
（日志从这一版起**始终**写文件，不再只有后台模式才写）。

想再看到命令行：**再打开一次 `QuizSyncAI_Server.exe`**。它读数据目录里的 `runtime.json`
确认已有实例在跑，于是**不起第二个服务**，直接当那个实例的前端窗口：

```text
QuizSyncAI Server v1.0.1
──────────────────────────────────────────────
  后台实例正在运行（PID 31752） · 端口 8821
  这里就是它的命令行：你敲的命令会送到那个进程上执行。
  关闭本窗口不影响它；要停它请敲 stop（或执行 --stop）。
  输入 help 看全部命令，quit 退出本窗口。
```

窗口里的 `status` / `qr` / `hotkeys reset` / `ai` / `set-*` 都由**那个正在跑的实例**
执行（走只认回环 + 控制令牌的 `POST /api/v1/console`，局域网里的手机与别的机器一律
403），输出原样回到这个窗口；`quit` 只关这个窗口，`stop` 才停服务。

- `--background` 起的是**完全没有控制台**的进程（`ProcessStartMode.detached`），
  适合放进「启动」文件夹 / 快捷方式做开机自启；启动前会先确认「AI 已配置 + 配对过手机」，
  缺什么当场说（后台进程没有窗口，缺东西时用户什么都看不到）。
- `--stop` 不需要窗口：它读 `runtime.json` 里的端口与一次性令牌，向本机回环地址发一个
  停机请求（等价于 `quit`）。

### 热键（只有两个动作，一个动作一条键）

- 默认 **截屏识别 `F8`**、**多页模式 `F9`**。
- 多页模式：按 `F9` 进入并抓第 1 张，继续按追加，**攒满 6 张自动上传**；没满时按 `F8`
  立即结束多页并上传已抓的所有图片。
- 早期版本留下的默认值（F6/F7/F8、F6/F10/F11、Ctrl+Q/…、以及已删除的备用键
  `Alt+Shift+Q`/`Alt+Shift+W`）在升级时**自动换成 F8 + F9**；用户自己改过的键原样保留。
- 支持 F1–F12、字母数字、方向键/Delete 等常用键，以及 Ctrl / Alt / Shift / Win
  任意组合（如 `Ctrl+Shift+Q`、`Alt+F6`、`Ctrl+Alt+Shift+Win+A`）。
- 两个热键**不能相同**，相同会被拒绝并提示换一个。
- 注册失败**绝不静默**：

  ```text
  [Hotkey] Ctrl+Shift+A registration failed.
  [Hotkey] The hotkey may already be used by another application.
  [Hotkey] Use "hotkey append <combo>" to pick another one.
  [Hotkey] 本机现在空闲的键：F1 F3 F4 F6 F10（已被别的程序占用的不会出现在这里…）
  ```

  面板上该槽位会显示 `Ctrl+Shift+A(未生效)`，一眼就能看出它没生效；最后一行直接
  告诉你本机还有哪些键可用（后端会临时试注册 F1–F12 逐个探测）。

---

## 3. 目录结构与「src / config / tests / build」的对应

```text
server/
├── pubspec.yaml            依赖（与 quizsync_core 的同名依赖同版本）
├── analysis_options.yaml
├── bin/quizsync_server.dart    入口（编译成 QuizSyncAI_Server.exe）
├── lib/
│   ├── quizsync_server_core.dart   ← 从主项目提取的最小核心子集的出口
│   └── src/
│       ├── core/                   ← 提取自 packages/quizsync_core 的代码
│       │   ├── model/              协议模型（question / session / collection / …）
│       │   ├── ai/                 prompt + 三家 provider + 容错解析 + 重试
│       │   └── util/               sha256 / uuid / JPEG 编码
│       ├── config.dart             配置与数据目录（默认 exe 同目录的应用同名目录）
│       ├── console_window.dart     转后台用的控制台处理（判断/脱离自己的控制台）
│       ├── store.dart              状态（state.json + images/，无数据库）
│       ├── engine.dart             识别引擎（prompt → 重试 → 解析）
│       ├── tasks.dart              识别流水线（会话 → AI → 落库 → 广播）
│       ├── server.dart             HTTP + WebSocket 服务端（protocol.md 全端点）
│       ├── hotkeys.dart            热键解析/标签（纯逻辑，可单测）
│       ├── hotkey_service.dart     RegisterHotKey + 消息泵（独立 isolate）
│       ├── capture.dart            GDI BitBlt 截屏（Per-Monitor DPI V2）
│       ├── capture_flow.dart       两个热键动作（识别 / 多页模式）
│       ├── terminal.dart           CLI 输出（UTF-8 + ANSI + 日志文件，转后台只留文件）
│       ├── qr_terminal.dart        终端二维码
│       ├── status_panel.dart       状态块渲染（纯函数，可单测）
│       └── net_info.dart           局域网 IP
├── test/                   单测 + 回环集成测试（真 HTTP + 真 WebSocket + 假 AI）
├── tool/                   诊断脚本与说明书生成（不进 exe，见下）
└── build/                  dart compile exe 与《使用说明.txt》的产物（gitignore）
```

需求文档里的 `src/` = `lib/src/`，`tests/` = `test/`，`build/` = `build/`，
`config/` = 运行时的 `<exe>\QuizSyncAI_Server\`（配置不进源码树）。

---

## 4. 与主项目的关系（功能冻结）

- **提取**：`lib/src/core/**` 是从 `packages/quizsync_core` **逐文件复制**的
  （保留原有相对导入，未改写）。这样 Server 与主项目**没有运行时依赖**，
  `quizsync_core` 以后怎么改都不会改变已冻结的 Server v1。
- **没改主项目**：`apps/desktop`、`apps/android`、`packages/quizsync_core`、
  `packages/quizsync_ui` **一行都没动**，行为与加 Server 之前完全一致。
- **冻结**：v1.0.0 之后**功能**不再跟随主项目；v1.0.1 只补缺陷（见下），将来要真的加功能再发 Server v2。
- **v1.0.1 补了什么**（M47，逐条与 Desktop 版同口径，都没引入新能力）：
  1. **op 归属校验**：`/sync/ops` 与 WS `push_ops` 现在要求 `op.device_id` 等于认证设备，
     否则计 `rejected` 丢弃（原来只挡「冒充主机」）；
  2. **上传边读边限长**：分块传输（chunked）没有 `Content-Length` 时也一超限就回 413，
     不再等整包进内存；
  3. **上传限流**：每台设备每分钟 30 次，超限 429（原来只有 `/pair` 有限速）；
  4. **snapshot 分页**：`limit`（默认 200）+ `offset` + `has_more`，题目只带本页会话；
  5. **任务忙时回 429 `queue_full`**：Server 的任务链路本来就是串行的（`ServerTasks._busy`），
     原来先答应 202、再让那条任务以 `busy` 失败 —— 现在直接告诉手机「稍后重试」；
  6. **426 版本协商**（主版本不一致才拒，不带版本头的请求放行）、**`already_paired` 回 409**
     （body 里照旧给新 token）；
  7. README 里写明 **API Key 是明文存在 `config.json`**（本产品不走 DPAPI，见下）。

---

## 5. 开发与验收

```powershell
cd server
dart pub get
dart analyze          # 0 issue
dart test             # 90 项（含真 HTTP + 真 WebSocket 回环 + 两个热键动作的行为）
dart compile exe bin\quizsync_server.dart -o build\QuizSyncAI_Server.exe
dart run tool\make_guide.dart build      # 生成《使用说明.txt》放在 exe 旁边
```

回环测试覆盖（不需要真手机、不需要真 AI）：

- `/info` 能力协商、配对（错码/正确码/限流）、无 token 一律 401
- WS 握手 `hello` + `task_update` + `task_result`（含页序与题目）
- 手机上传图片 → `POST /tasks` → 结果推送；同图复用命中缓存不再调 AI
- `GET /tasks/active` 的 idle / 进行中 / done 三种载荷
- 合集、ops（恒空 + 幂等 applied）、snapshot、设备吊销（HTTP 401 revoked + WS 通知）
- 本机停机接口（只认回环地址 + 控制令牌，令牌错了 403 且不停机）
- 端口被占用自动探测、`stop()` 后端口释放
- 识别引擎：正常 / 非 JSON 重试 / 无题 / 六种错误码映射
- 热键解析与冲突判定、默认值迁移、状态文案（生效 / 未生效）
- **两个热键动作的行为**（假截屏 + 假 AI）：单张识别、多页攒页不调 AI、
  多页中按识别键上传已抓的图、攒满 6 张自动上传、截图失败只写日志
- 数据目录解析（exe 同目录 / `--config` 优先）与老数据自动搬迁
- 启动标识（第几次启动写进 state.json）、状态块渲染、二维码渲染、配置与状态存取
- **v1.0.1 的四条加固**：分块传输的超大包（不设 Content-Length、且不结束请求体）一超限就回 413、
  上传限流按设备算（第 3 次 429、另一台不受影响）、snapshot 分页（limit/offset/has_more 不重不漏）、
  已有识别在跑时新建任务回 429 `queue_full`

### 诊断脚本（`tool/`，不随包发布）

| 脚本 | 用途 |
|---|---|
| `dart run tool/make_guide.dart build` | 生成 exe 旁边那份《使用说明.txt》 |
| `dart run tool/hotkey_selfcheck.dart` | 逐个试注册 F1–F12，告诉你本机哪些键**没被占用** |
| `dart run tool/hotkey_live_test.dart F8 F9` | 注册后真实按键，打印每一次触发（区分「注册成功」与「真的能触发」） |
| `dart run tool/hotkey_probe.dart` | 反复注销/重注册，检查注册是否稳定（打印 Win32 结果码） |

⚠️ 实测结论：**能注册 ≠ 能触发**。有键盘钩子（输入法、投屏、截图工具）时，某个键可能
注册成功却永远收不到。选键前先跑 `hotkey_live_test.dart`。

### 诊断环境变量（默认全关，排查时临时打开）

| 变量 | 作用 |
|---|---|
| `QS_HOTKEY_DIAG=1` | 热键线程每秒复查一次注册、逐条打时间戳，并把收到的每个 `WM_HOTKEY` 写进日志 |
| `QS_RUNTIME_WATCH_DIAG=1` | 打印运行文件复查（记录里的 PID、是否存活）与接管动作 |

热键线程内部的结论值得单独记一笔：`RegisterHotKey(NULL, …)` 的注册是**线程级**的，而
Dart 的 isolate **每 `await` 一次就可能换到另一条池线程**（实测 28 秒 327 次换手）。
持有注册的那条线程被 VM 回收时，注册会**悄悄消失**（进程还活着、状态块还写着 F8、
按下去没反应，Win32 不给任何通知）。所以这个泵**一次都不 await**（`PeekMessageW` +
`Sleep`），命令走共享内存轮询；另有每 2 秒的注册自检兜底，日志里出现
「自检发现 … 的系统注册已丢失，已自动补回」就说明兜底救回来过一次。

---

## 6. 已知边界

- **后台运行**（`--hidden` / 窗口里的 `hidden`）：**AI 已配置 + 至少配对过一台手机**
  之后才真的转后台（条件不满足时保持窗口可见并说明原因），做法是 `FreeConsole()`
  **真脱离控制台** —— 窗口消失、关掉终端也不影响它（实测：`FindWindowW(NULL, exe)`
  在脱离前拿到句柄、脱离后返回 0）。代价是 stdin/stdout 都没了，所以脱离之后
  日志只写 `server.log`、进程只由 `stop` / `--stop` 结束；`--background` 起的是
  完全没有控制台的进程（适合开机自启），启动前会先检查配置与配对。
- **找回命令行**：再次运行本程序即可 —— 它检测到已有实例就不再起第二个服务，而是
  当那个实例的前端窗口（`POST /api/v1/console`，只认回环 + `runtime.json` 里的令牌）。
  在脱离控制台的进程上从外部"把控制台还给它"是做不到的（`AttachConsole` 只能进程自己调），
  所以"呼出界面"只能做成前端。
- **多开**：正常用不会多开了 —— 第二次启动就是上面那个命令行窗口。真起了第二个实例
  （比如用 `--hidden` 再起一个）时，`runtime.json` 仍指向先启动的那个；先启动的那个
  一旦被杀掉，15 秒内会被后启动的实例收回（否则 `--stop` 会拿着旧令牌去敲新实例得 403）。
- **热键**：注册挂在热键线程上，那条线程**永不 await**（线程号钉死）；另有 2 秒注册自检
  兜底，丢了自己补回来并写日志。所以正常运行时不该再出现「状态里写着 F8、按下去没反应」。
  若仍然没反应，先确认热键没标「(未生效)」，再试别的键（部分输入法/投屏/截图工具会吃掉
  特定按键，注册成功也收不到）。
- 截图取**鼠标所在显示器**的全屏，不隐藏自己的命令行窗口（藏窗口会把控制台变回前台、
  导致之后的合成按键进不来，实测踩过）。命令行里的文字若正好在屏幕上，会被一起发给 AI，
  而 prompt 明确要求 AI 忽略界面元素。
- 一次只跑一条识别链路：识别中再按热键只写一行日志（不排队）。
- 多页最多 6 页（协议硬上限），攒满自动上传；同图命中即复用，不重复花 AI 额度。
- AI 的原始返回、题目结构、错误码与 Desktop 版逐字一致（Android 端文案不用改）。
