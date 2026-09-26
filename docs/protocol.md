# 局域网协议契约

Windows 是服务端，Android 是客户端。两端实现必须与本文件一致；`packages/quizsync_core` 里的模型类是这个契约的代码化载体，两端共用。

---

## 1. 传输层

| 项 | 规定 |
|---|---|
| 协议 | HTTP/1.1 + WebSocket（同一端口，`/ws` 路径升级） |
| 服务端 | 仅 Windows。Dart `shelf` + `shelf_router` + `shelf_web_socket`，绑定 `0.0.0.0` |
| 端口 | 默认 **8765**；被占用则依次尝试 8766–8770，实际端口写入配对二维码与 `/api/v1/info` |
| 明文 | 局域网明文 HTTP。Android 需在 `network_security_config.xml` 放行 `cleartextTrafficPermitted` |
| 编码 | 请求与响应均为 `application/json; charset=utf-8`，图片上传用 `multipart/form-data` |
| 时间 | 所有时间戳为 UTC 毫秒（int64），字段名统一 `*_at` |
| 前缀 | 所有 HTTP 接口以 `/api/v1/` 开头 |
| 版本协商 | 客户端在每个请求带上 `X-QS-Client-Version`；服务端响应带 `X-QS-Server-Version`。主版本不一致时服务端返回 426 并在 body 里给出双方版本 |

---

## 2. 配对

配对是唯一不需要 token 的接口，因此必须有有效期与限速。

### 2.1 服务端准备

Windows 端生成：
- `server_device_id`：UUID v4，首次启动时生成后持久化。
- `pairing_code`：6 位数字，**有效期 5 分钟**；过期后 UI 上可一键刷新。
- 二维码内容（UTF-8 文本）：

```
quizsync://pair?host=192.168.1.23&port=8765&code=482913&sid=<server_device_id>&v=1
```

二维码用 `qr_flutter` 渲染。Android 用 `mobile_scanner` 扫描，也支持手动输入 `host`、`port`、`code`。

### 2.2 配对请求

```
POST /api/v1/pair
Content-Type: application/json

{
  "code": "482913",
  "device_id": "<Android 端 UUID>",
  "device_name": "Pixel 7",
  "platform": "android",
  "app_version": "1.0.0"
}
```

成功 `200`：

```json
{
  "token": "<64 位 hex>",
  "server_device_id": "<UUID>",
  "server_name": "DESKTOP-ABC",
  "protocol_version": 1
}
```

失败：

| 状态码 | code | 含义 |
|---|---|---|
| 400 | `invalid_request` | 字段缺失或格式错误 |
| 401 | `invalid_code` | 配对码错误 |
| 401 | `code_expired` | 配对码过期（响应带 `retry_after_seconds`） |
| 429 | `rate_limited` | 尝试过于频繁或已锁定（响应带 `retry_after_seconds`） |
| 409 | `already_paired` | 同 device_id 已配对，直接返回已有 token 的**新**签发（视为重新配对，旧 token 作废） |

限速规则：每分钟最多 5 次尝试；累计 10 次失败锁定 60 秒。

### 2.3 鉴权

除 `/api/v1/pair` 外，所有 HTTP 请求与 WS 握手都必须带：

```
Authorization: Bearer <token>
```

- Windows 端只保存 token 的 **SHA-256 哈希**（`devices.token_hash`）。
- Android 端用 Keystore 加密保存 token。
- token 校验失败 → `401 {"code":"unauthorized"}`。被吊销 → `401 {"code":"revoked"}`（Android 收到后清除本地 token 并提示重新配对）。

---

## 3. HTTP 接口

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/v1/info` | 设备信息与能力协商（无需鉴权，便于 Android 探测服务是否在线） |
| POST | `/api/v1/pair` | 配对 |
| POST | `/api/v1/images` | 上传图片（multipart），返回 `image_hash` |
| GET | `/api/v1/images/{hash}` | 按需下载图片字节（后台补传用） |
| POST | `/api/v1/tasks` | 创建分析任务（支持多页 + 合集归属） |
| GET | `/api/v1/tasks/{task_id}` | 查询任务状态与结果 |
| POST | `/api/v1/tasks/{task_id}/retry` | 重试失败任务 |
| POST | `/api/v1/sessions/{session_id}/reanalyze` | 「重新生成」：按既有页序重跑一次（用户需求 7） |
| GET | `/api/v1/collections` | 合集列表 + 当前选中项（用户需求 8） |
| POST | `/api/v1/collections/{id}/select` | 切换主机当前合集（用户需求 12） |
| POST | `/api/v1/sync/ops` | 推送本地操作日志 |
| GET | `/api/v1/sync/ops?since_lamport=&from_device=` | 拉取对端操作日志 |
| GET | `/api/v1/sync/snapshot` | 新设备 bootstrap 快照 |
| GET | `/api/v1/devices` | 已配对设备列表（仅 Windows 端设置页用） |
| DELETE | `/api/v1/devices/{device_id}` | 吊销设备 |

### 3.1 `GET /api/v1/info`

```json
{
  "device_id": "<UUID>", "device_name": "DESKTOP-ABC", "platform": "windows",
  "protocol_version": 1, "app_version": "1.0.0",
  "ai_configured": true,
  "active_collection_id": "<UUID 或 null>",
  "active_collection_name": "期末复习",
  "capabilities": ["analyze", "sync", "image_fetch", "collections", "multipage"]
}
```

`ai_configured` 为 false 时 Android 应提示「主机尚未配置 AI」，而不是让任务静默失败。
`active_collection_id` 为 null 时 Android **不得**发起识别，应提示「请先在电脑上选择任务合集」（用户需求 12）。

### 3.2 `POST /api/v1/images`

`multipart/form-data`，字段名 `file`，内容为 JPEG 字节。

```json
{ "image_hash": "<sha256 hex>", "size": 214333, "mime": "image/jpeg",
  "width": 1600, "height": 900, "existed": false }
```

- `image_hash` 对**压缩后**的字节计算，服务端按 hash 去重。
- 服务端限制单文件 ≤ 2MB，超出返回 `413 {"code":"payload_too_large"}`。
- 客户端限流：每分钟 30 次，超出返回 429。

### 3.3 `POST /api/v1/tasks`

```json
{
  "task_id": "<客户端生成的 UUID v4>",
  "image_hash": "<sha256>",
  "image_hashes": ["<第 1 页 sha256>", "<第 2 页 sha256>"],
  "source_device": "<发起端 device_id>",
  "collection_id": "<合集 UUID，可省略则用主机当前选中的合集>",
  "created_at": 1757980000000,
  "force_reanalyze": false
}
```

响应 `202`：

```json
{ "status": "queued", "session_id": "<服务端分配>", "question_count": null }
```

- `task_id` **由发起端生成**，服务端以它做幂等：重复提交同一个 `task_id` 直接返回既有状态，不重复分析。
- `image_hashes` 是**多页页序**（用户需求 4），1..6 张（服务端硬上限 `kHardMaxPagesPerTask` = **6**，`too_many_pages`；用户反馈 9 把原来的 12 收紧到 6）。省略时退回单页 `image_hash`；每张都必须已经 `POST /images` 上传过。
- **合集必填**（用户需求 8/12）：`collection_id` 与主机当前选中的合集都为空，或指向不存在的合集 → `409 no_active_collection`。Android 收到该码应提示「请先在电脑上选择任务合集」。
- 若 `image_hash` 已有 `done` 会话、**页序完全一致**、且 `force_reanalyze == false` → 立即返回 `{"status":"done",...,"cached":true}`。
- `status` 取值：`queued` | `analyzing` | `done` | `failed` | `cancelled`。

### 3.3.1 `POST /api/v1/sessions/{session_id}/reanalyze`

用户需求 7 的「重新生成」。服务端按该会话的 `session_images` 页序起一个**新任务**（`force_reanalyze = true`，不复用缓存），响应与 3.3 一致（`202`）。

### 3.3.2 `GET /api/v1/collections` / `POST /api/v1/collections/{id}/select`

```json
{ "collections": [ { "collection_id": "...", "name": "期末复习", "created_at": 0 } ],
  "active_collection_id": "..." }
```

`select` 会把 `active_collection_id` 落库并**广播** `collection_changed` 给所有已连接客户端；合集不存在返回 `404 not_found`。

### 3.4 `GET /api/v1/tasks/{task_id}`

```json
{
  "task_id": "...", "status": "done", "session_id": "...",
  "error_code": null, "error_message": null,
  "session": { /* 完整 session + questions，字段见 data-model.md 的模型定义 */ }
}
```

`status == "failed"` 时 `error_code` 取值：`ai_timeout` | `ai_auth` | `ai_rate_limited` | `ai_bad_response` | `ai_quota_exceeded` | `no_question_found` | `internal`。端侧按 `SPEC.md` 第 8 节给出对应文案。

### 3.4.1 `GET /api/v1/tasks/active`（用户反馈 M15 第 4 条）

**只读**：主机「现在正在识别什么」的快照，供安卓端**轮询兜底**（默认 1 秒一次）使用 ——
WS 推送不可靠时，手机靠它也能显示「N 张图片识别中…」并在出结果后自动进结果页。

```json
{
  "status": "analyzing",              // idle | queued | analyzing | done | failed
  "task_id": "...",                   // 本机截屏任务的 task_id 就是 session_id
  "session_id": "...",
  "image_count": 3,
  "updated_at": 1758300000000,        // 毫秒；客户端用它做「有没有变化」的比较
  "message": null,                     // failed 时的原因
  "active_collection_id": "...",       // WS 全断时手机据此把状态行恢复成「已连接 · 合集名」
  "active_collection_name": "...",
  "collections": [                     // M18 第 4 条：主机**当前活跃合集列表**（只增改不删）
    { "collection_id": "...", "name": "期末复习", "created_at": 1, "updated_at": 2,
      "updated_by": "...", "lamport": 7 }
  ],
  "ops_lamport": 812,                  // M17 第 5 条：主机本地 ops 水位（0 = 老版本没上报）
  "session": { /* 可选：仅 status=done 时带，载荷与 WS task_result 的 session 同构 */ }
}
```

- 没有进行中的任务时返回 `{"status": "idle", "active_collection_id": ..., "active_collection_name": ..., "collections": [...], "ops_lamport": N}`。
- `status=done` 时额外带 `session`（含 questions 与 `image_hashes`）——本机截屏任务**不经任务队列**，
  数据库里没有对应的 `tasks` 行，客户端无法用 `GET /api/v1/tasks/{task_id}` 取回结果，所以结果直接挂在这里。
- 该状态是**内存态**：主机重启后回到 `idle`，不补发历史结果（与 WS 只补发「进行中」任务一致）。
- `collections` = 主机**未删除**的合集列表（与 `GET /api/v1/collections` 的条目同构，**M18 第 4 条**）。
  客户端把这份列表**镜像**进本地库（`CoreRepository.mirrorCollections`：只增改、不删，本机已删除的合集
  不会被复活）—— 这是「想要的结果」本身，所以**不依赖** `ops_lamport` 这类间接触发信号：
  用户反馈的「安卓端识别不到 windows 端的分类」（主机新建的合集在手机本地没有那一行，主机识别的
  记录在手机历史里全被算进「未分类」）由此消除。空数组 = 老主机没上报（客户端不动作）。
  纯加法字段，老客户端忽略。
- `ops_lamport` = 主机 `sync_ops` 的最大 lamport（**M17 第 5 条**）。客户端发现它比上次大就做一次
  **只拉不推**的同步（`GET /api/v1/sync/ops` + 本地 LWW 落地），于是 Windows 上「改题目」这类本地改动，
  手机在前台时 **1 秒内**就能跟上。第一次看到只建立基线（不拉），避免每次开 App 白拉一次。
  纯加法字段，老客户端忽略。
- **合集删除的方向性（M18 第 4 条，用户明确要求修改 M17 的第 5 条）**：主机删除合集时
  （合集从 `collections` 里消失、并生成一条 delete op），安卓端**不跟随删除** ——
  `CoreRepository(applyRemoteCollectionDeletes: false)`：那条 op 照常入库、时钟照常 observe
  （拉取游标不会卡），只是不回写 `deleted_at`；手机本地那个分组保留。反方向（手机上主动删合集）
  照常软删除并生成 op 同步给主机。桌面端 `applyRemoteCollectionDeletes` 默认 `true`，两端一致的
  语义不变，因此 `SyncEngine` / `applyRemoteOp` 的契约没有被改。
- 客户端约定：**第一次**探测就拿到 `done/failed` 时只当基线、不触发自动进结果页（否则每次开 App 都会跳进上一轮结果）；
  已投递过的结果不再重复推（M17 第 4 条修正：判定「这条结果**已经在界面上**」而不是「本地库里已有」——
  主机同图复用会复用 `session_id`，按本地库判断会把结果静默丢掉）。
- 客户端约定（M17 第 4 条）：轮询次数多了以后，「主机上报的指纹没变」不等于「界面已经显示对了」；
  界面停在**别的**任务上时要补发一次，界面为空（用户点过「忽略」）则不补发。

### 3.5 错误响应统一格式

```json
{ "code": "invalid_request", "message": "人类可读的说明", "retry_after_seconds": null }
```

HTTP 状态码与 `code` 必须成对出现，客户端以 `code` 为准做分支。

---

## 4. WebSocket

### 4.1 握手

```
GET /ws
Authorization: Bearer <token>
X-QS-Device-Id: <device_id>
X-QS-Client-Version: 1.0.0
```

握手鉴权失败返回 401，客户端退化为轮询 `GET /api/v1/tasks/{task_id}`（轮询间隔 2s，上限 90s）。

### 4.2 服务端 → 客户端

```jsonc
{ "type": "hello",        "server_device_id": "...", "protocol_version": 1,
                          "active_collection_id": "...", "active_collection_name": "期末复习" }
{ "type": "task_update",  "task_id": "...", "status": "analyzing", "session_id": "...", "image_count": 2 }
{ "type": "task_result",  "task_id": "...", "session": { /* 完整会话 + image_hashes/image_count + questions */ } }
{ "type": "task_failed",  "task_id": "...", "error_code": "ai_timeout", "message": "..." }
{ "type": "collection_changed", "collection_id": "...", "collection_name": "期末复习" }  // 用户需求 12
{ "type": "ops",          "ops": [ /* sync_ops 数组 */ ] }
{ "type": "device_revoked","device_id": "..." }   // 收到后清 token 并断开
{ "type": "ping",         "ts": 1757980000000 }
```

`task_result.session` 里额外带 `image_hashes`（页序）与 `image_count`，安卓端据此显示「N 张图片识别中…」（用户需求 7）。

`task_update` 的 `image_count` 是这次识别的页数（用户反馈 2）：**主机自己截屏**（不经 `/tasks` 队列）
也会广播 `task_update` / `task_result`，字段与手机端提交的任务完全一致，`task_id` 就等于 `session_id`。
安卓端必须优先用消息里的 `image_count`，本地库查不到这群图片时（主机起的任务）也能显示「N 张图片识别中…」。
`status=done` 但会话已被删除（同图复用）时服务端只发状态、不发 `task_result`。

### 4.3 客户端 → 服务端

```jsonc
{ "type": "hello", "device_id": "...", "app_version": "1.0.0", "platform": "android" }
{ "type": "ack",   "watermark_lamport": 421, "watermark_device": "<自己已收到的最大 lamport 对应的来源设备>" }
{ "type": "push_ops", "ops": [ /* 本地待推送的 ops */ ] }
{ "type": "pong",  "ts": 1757980000000 }
```

### 4.4 连接管理

- 心跳：服务端每 30s 发 `ping`，客户端 10s 内未回 `pong` 则断开重连。
- 重连：指数退避 1s / 2s / 5s / 10s，上限 30s；恢复后先 `GET /api/v1/sync/ops` 补齐缺口。
- 同 `device_id` 重复连接：新连接踢掉旧连接（服务端行为），避免僵尸连接。
- 客户端在 `queued` 任务期间断开 → 重连后主动 `GET /api/v1/tasks/{task_id}` 补状态，不依赖推送。

---

## 5. 幂等与重试总则

| 场景 | 规则 |
|---|---|
| 所有 GET | 天然幂等，可安全重试 |
| `POST /images` | 按 hash 幂等，重复上传返回 `existed: true` |
| `POST /tasks` | 按 `task_id` 幂等 |
| `POST /sync/ops` | 按 `op_id` 幂等，服务端忽略已存在的 op |
| `POST /pair` | 允许重复，返回新签发的 token 并使旧 token 作废 |
| 网络错误重试 | 仅对 GET 与上述幂等 POST 生效；指数退避 1s / 3s / 10s |
| 禁止重试 | 4xx 中除 408 / 429 外的错误 |

---

## 6. 环形验证（M4 的验收基础）

`packages/quizsync_core/test/integration/loopback_test.dart` 必须在无设备、无网络外联的情况下跑通：

```
1. 启动服务端，监听 127.0.0.1:0（随机端口）
2. 获取 /info → 断言 protocol_version
3. 用配对码 POST /pair → 拿到 token
4. 构造一张 1x1 的假 JPEG → POST /images → 拿到 hash
5. POST /tasks（假 AI provider 返回 fixture）→ 202 queued
6. 等 WS 收到 task_result → 断言题目数量、字段、标绿所需字段齐全
7. 断言两端数据库都生成了对应的 sync_ops
8. GET /sync/ops 增量拉取 → 断言不重复、不丢
9. 吊销设备 → 再请求 → 断言 401 revoked
```

这个测试是「安卓虽不能运行但协议仍然被验证」的关键保障，M4 必须全绿。
