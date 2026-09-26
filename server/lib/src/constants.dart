/// Server 的固定常量。
///
/// 这些都是**协议常量**，与主项目 `packages/quizsync_core/lib/util/keys.dart`
/// 里同名常量逐字一致（Server 只复制需要的几个，不去依赖那个包）。
library;

/// 产品名（CLI 标题、配对二维码、关于信息都用它）。
const String kServerProductName = 'QuizSyncAI Server';

/// 独立版本线：功能冻结在 1.0.x，不跟随主项目。
///
/// - `1.0.0`：M45 发布的功能冻结版（截图 → AI → 手机）。
/// - `1.0.1`：M47 的**补丁版** —— 不新增任何能力，只把主项目那轮代码审查里
///   同样适用于 Server 的四条加固搬过来（上传边读边限长、上传限流 30 次/分、
///   snapshot 分页、任务忙时回 429 而不是假排队），另加 op 归属校验、
///   426 版本协商、`already_paired` 409 与 README 的明文 Key 说明。
///   按 README 的约定「要改就发 Server v2」—— 那是说**功能**；这里是同一冻结
///   功能线上的缺陷修复，所以只顶补丁位（v2 留给将来真的要加功能的时候）。
const String kServerVersion = '1.0.1';

/// 协议版本（protocol.md；Android 端只认这个）。
const int kProtocolVersion = 1;

/// 默认端口与探测范围（被占用则依次尝试 8766–8770）。
const int kDefaultPort = 8765;
const int kPortRange = 6;

/// 一次识别最多几页（protocol.md 3.3 的硬上限，kHardMaxPagesPerTask）。
const int kHardMaxPagesPerTask = 6;

/// 单张图片上限（protocol.md 3.2）。
const int kMaxImageBytes = 2 * 1024 * 1024;

/// 未配置占位符：`GET /api/v1/info` 的 ai_configured。
const String kNoCollectionMessage = '请先在电脑上选择任务合集';

/// 服务器自己用的合集名。
///
/// 安卓端的历史记录按合集分组，且**主机必须有一个当前合集**它才允许发起识别
/// （protocol.md 3.1：`active_collection_id` 为 null 时安卓端不得发起识别）。
/// Server 只有「截图 → AI」一条流水线，用不着多合集，所以固定一个合集，
/// 让 Android 看到的状态与连着 Desktop 时完全一样。
///
/// 名字取 **Server**：Server 识别出来的记录在手机历史里一眼就能认出来，
/// 不会和 Desktop 建的合集混在一起。
const String kDefaultCollectionName = 'Server';

/// 1.0.0 早期用过的合集名（升级时自动改名成上面那个）。
const String kLegacyCollectionName = '默认合集';
