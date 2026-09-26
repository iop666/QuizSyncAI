/// QuizSyncAI Server 使用的**最小核心子集**。
///
/// 来源：主项目 `packages/quizsync_core`（协议模型 / AI 客户端 / 图像处理），
/// 逐文件复制而来（保留原有相对导入结构，未作改写），目的是让 Server 与主项目
/// **没有运行时依赖**：`quizsync_core` 将来怎么改都不会影响已冻结的 Server v1。
///
/// 提取范围（只保留 Server 真正用到的部分）：
///   - model/：协议 JSON 的代码化载体（question / session / collection / device /
///     pair_messages / sync_op …）
///   - ai/：prompt、三个 provider 的请求构造与发送、容错解析、重试策略
///   - util/：hash（sha256）、ids（uuid/时间）、image_proc（JPEG 编码）
///
/// 未提取（Server 不需要）：drift schema / repository / 同步引擎 / 悬浮窗 /
/// 设置页 / Flutter 相关的一切。
library;

export 'src/core/ai/fake_provider.dart';
export 'src/core/ai/prompt.dart';
export 'src/core/ai/provider.dart';
export 'src/core/ai/providers.dart';
export 'src/core/ai/response_parser.dart';
export 'src/core/ai/retry_policy.dart';
export 'src/core/model/answer_value.dart';
export 'src/core/model/collection.dart';
export 'src/core/model/device_info.dart';
export 'src/core/model/option.dart';
export 'src/core/model/pair_messages.dart';
export 'src/core/model/question.dart';
export 'src/core/model/question_type.dart';
export 'src/core/model/session.dart';
export 'src/core/model/session_image.dart';
export 'src/core/model/sync_op.dart';
export 'src/core/model/task_state.dart';
export 'src/core/util/hash.dart';
export 'src/core/util/ids.dart';
export 'src/core/util/image_proc.dart';
