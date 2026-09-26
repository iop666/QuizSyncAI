/// QuizSync AI 共享核心。
///
/// 两端（Windows / Android）共用：协议模型、drift schema、
/// 同步引擎（Lamport + 字段级 LWW）、AI 客户端与解析。
library;

// ---- 模型（协议与 AI 契约的代码化载体）----
export 'model/answer_value.dart';
export 'model/collection.dart';
export 'model/device_info.dart';
export 'model/image_meta.dart';
export 'model/option.dart';
export 'model/pair_messages.dart';
export 'model/question.dart';
export 'model/question_type.dart';
export 'model/session.dart';
export 'model/session_image.dart';
export 'model/sync_op.dart';
export 'model/task_state.dart';

// ---- 工具 ----
export 'util/hash.dart';
export 'util/ids.dart';
export 'util/keys.dart';
export 'util/app_logger.dart';
export 'util/backup.dart';
export 'util/exporter.dart';
export 'util/image_proc.dart';

// ---- 同步原语 ----
export 'sync/field_clocks.dart';
export 'sync/lamport_clock.dart';
export 'sync/lww_applier.dart';
export 'sync/sync_engine.dart';
export 'sync/sync_op_writer.dart';

// ---- AI 客户端与解析（M2）----
export 'ai/analysis_cache.dart';
export 'ai/analysis_engine.dart';
export 'ai/fake_provider.dart';
export 'ai/highlight.dart';
export 'ai/prompt.dart';
export 'ai/provider.dart';
export 'ai/providers.dart';
export 'ai/quota_guard.dart';
export 'ai/response_parser.dart';
export 'ai/retry_policy.dart';

// ---- 数据库 ----
export 'db/database.dart';
export 'db/mappers.dart';
export 'db/offline_queue.dart';
export 'db/open.dart';
export 'db/repository.dart';
export 'db/tables.dart';

// ---- 局域网服务端与客户端（M4）----
export 'server/image_store.dart';
export 'server/task_executor.dart';
export 'server/quizsync_server.dart';
export 'client/api_client.dart';
export 'client/sync_socket.dart';
