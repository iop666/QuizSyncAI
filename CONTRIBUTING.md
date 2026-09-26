# 贡献指南（QuizSyncAI · 产品仓库）

> 给 agent 的执行入口是 [`AGENTS.md`](AGENTS.md)（环境事实、平台实测坑、工作守则）；本文件是给人看的摘要：依赖方向、提交规范、版本号来源、发布红线。

## 1. 依赖方向

```
QuizSyncAI ──► QuizSyncProtocol              规范 + JSON Schema + 一致性向量（纸面与数据）
QuizSyncAI(Windows) ──► QuizSync.Server.Core 内嵌模式的 Host 能力（库）
```

- 协议结构**只在** `QuizSyncProtocol` 定义：本仓库不复制 schema 再改一份。
- 安卓端与 Windows 端**不互相引用**：Windows 代码不进安卓，安卓代码不进 Windows。
- 服务端实现（原 `server/`，Dart 版）在新 Server 上线后删除，能力由 `QuizSyncServer` 承担。旧源码永久保留在 `flutter` 分支与 `v1.1.0-flutter` tag 上。

## 2. 分支

| 分支 | 用途 |
|---|---|
| `main` | 默认分支；**逐模块替换的主线**（Flutter 目录原地不动，新代码进新顶层目录） |
| `flutter` | **已冻结**的 1.x 全量源码（完全锁定：禁更新、禁强推、禁删除） |
| `feat/*`、`chore/*` | 特性与杂务 |

出 1.1.x 补丁时才临时解冻 `flutter`。

## 3. 提交规范

- 里程碑提交：`M<n>: <一句话>`（一个里程碑一次提交，不合并、不拆分）。
- 非里程碑提交：`<域>: <做什么>`，域取 `docs` / `android` / `windows` / `server` / `tools` / `chore`。
- 中文提交信息。提交前必须跑通对应包的 `analyze` 与测试。

## 4. 版本号唯一来源

| 时期 | 唯一来源 |
|---|---|
| Flutter（1.x） | 两个 `pubspec.yaml`（`apps/desktop`、`apps/android`）；`tools/*.ps1` 的 `-Version` 留空时从它读，`installer.iss` 由打包脚本用 `/DAppVersion=` 传入 |
| native（2.0 起） | 三个仓库各自的版本清单（协议 / 客户端 / Server），并保留一致性断言 |

`Runner.rc` 与 `kAppVersion` 仍是手改点，`apps/desktop/test/version_consistency_test.dart` 会断言三处一致 —— **改版本只改 pubspec + 这两处**，不要再去脚本里找。

## 5. 发布红线

1. 交付物**不得包含 `userdata`**（运行期数据）：打包前强制删除并复核，zip 内再查一次。
2. 交付物**不得出现内部里程碑字样与出包序号**；界面不显示构建号。
3. Windows 便携包必须随包带上 VC 运行库 **10 个 DLL**（排除 `\onecore\` 目录），否则干净机器上双击即缺 DLL。
4. Android 交付物必须通过 `tools/audit_android.ps1` 的 60 项审计（包名 / 版本 / 权限白名单 / 备份策略 / 明文开关 / 签名 / 包内红线）。
5. `tools/*.ps1` 与 `tools/installer.iss` 必须存成 **UTF-8 with BOM**。
6. 公开仓库（`iop666/QuizSyncAI`）**只接受裁剪导出**：禁止直推内部全历史分支；`main` 禁强推/删除，`flutter` 完全锁定。
7. 局域网内**不做 HTTPS**、不引入账号体系 / 云服务 / SaaS / 公网访问。
