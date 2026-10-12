# 贡献指南（QuizSync AI · Flutter 正线仓库）

> 给 agent 的执行入口是 [`AGENTS.md`](AGENTS.md)（环境事实、平台实测坑、工作守则）；本文件是给人看的摘要：仓库定位、依赖方向、提交规范、版本号来源、发布红线。
>
> **本仓是 Flutter 正线**。原生线在另一个仓：`iop666/QuizSyncAI_Native`。

## 1. 两条线的关系

QuizSync AI 有**两条长期并存、互不影响**的实现线：

| 线 | 仓库 | 定位 | 版本号 |
|---|---|---|---|
| **Flutter（正线，本仓）** | `iop666/QuizSyncAI`（默认分支 `flutter`） | 主推产品线：Flutter/Dart 双端 + 共享核心包，**持续演进** | `x.y.z`，如 `1.2.1` |
| **原生** | `iop666/QuizSyncAI_Native`（默认分支 `native`） | 并行实现线：Windows .NET（WinUI 3）+ Android Compose，逐步追平 | `x.y.z-native`，如 `1.2.1-native` |

- 两仓**各自独立**：独立历史、独立版本号、独立发布、独立构建链。互不引用、互不阻塞。
- 版本号约定：原生线在版本号后加 **`-native`** 后缀；两边功能对等时号也齐。
- 两线共享**四份契约**（`SPEC.md` / `protocol.md` / `data-model.md` / `ai-contract.md`）：本仓各有一份，改动须与原生线保持一致。

## 2. 依赖方向

```
QuizSyncAI（本仓）──► 协议规范        规范 + JSON Schema + 一致性向量（纸面与数据）
                      正本在原生仓 `iop666/QuizSyncAI_Native` 的 `protocol/`
```

- 协议结构**只有一份**：定义在原生仓的 `protocol/`（`iop666/QuizSyncAI_Native`）。本仓库不复制 schema 再改一份。
- 安卓端与 Windows 端**不互相引用**：Windows 代码不进安卓，安卓代码不进 Windows。
- `server/` 是本线的独立 Dart CLI 服务端（纯 Dart，全局热键截屏 → AI → 手机），**继续维护**，主项目零改动。

## 3. 分支

| 分支 | 用途 |
|---|---|
| `flutter` | **默认分支，正线主线**：Flutter 线全部源码，持续演进 |
| `feat/*`、`chore/*` | 特性与杂务 |

## 4. 提交规范

- 非里程碑提交：`<域>: <做什么>`，域取 `docs` / `android` / `desktop` / `core` / `ui` / `server` / `tools` / `chore`。
- 中文提交信息。提交前必须跑通对应包的 `analyze` 与测试。

## 5. 版本号唯一来源

| 位置 | 说明 |
|---|---|
| `apps/desktop/pubspec.yaml` | 桌面端版本，如 `1.2.1+35` |
| `apps/android/pubspec.yaml` | 安卓端版本，如 `1.2.1+24` |
| `windows/runner/Runner.rc` | Windows 可执行文件版本（手改点） |
| `kAppVersion` | 界面显示版本（手改点） |

`apps/desktop/test/version_consistency_test.dart` 会断言上述几处一致 —— **改版本只改 pubspec + 这几个手改点**，不要再去脚本里找。`tools/*.ps1` 的 `-Version` 留空时从 pubspec 读，`installer.iss` 由打包脚本用 `/DAppVersion=` 传入。

## 6. 发布红线

1. 交付物**不得包含 `userdata`**（运行期数据）：打包前强制删除并复核，zip 内再查一次。
2. 交付物**不得出现内部里程碑字样与出包序号**；界面不显示构建号。
3. Windows 便携包必须随包带上 VC 运行库 **10 个 DLL**（排除 `\onecore\` 目录），否则干净机器上双击即缺 DLL。
4. Android 交付物必须通过 `tools/audit_android.ps1` 的 60 项审计（包名 / 版本 / 权限白名单 / 备份策略 / 明文开关 / 签名 / 包内红线）。
5. `tools/*.ps1` 与 `tools/installer.iss` 必须存成 **UTF-8 with BOM**。
6. 公开仓库（`iop666/QuizSyncAI`）**只接受裁剪导出**：禁止直推内部全历史分支；`flutter` 禁强推/删除。
7. 局域网内**不做 HTTPS**、不引入账号体系 / 云服务 / SaaS / 公网访问。
