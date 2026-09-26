import '../db/repository.dart';
import '../model/question.dart';
import '../model/task_state.dart';
import '../util/ids.dart';

/// 缓存命中条目。
class CachedAnalysis {
  final String sessionId;
  final List<Question> questions;
  final int createdAt;

  const CachedAnalysis({
    required this.sessionId,
    required this.questions,
    required this.createdAt,
  });
}

/// 缓存（`ai-contract.md` 第 4 节）：
/// key = `image_hash` + `prompt_version` + `model`；命中且距今 < 30 天 → 回放。
///
/// 存储复用 sessions 表（同 hash + 同 prompt_version + 同模型、status=done、
/// 未删除的最近会话即缓存条目），不新增表、不改 schemaVersion。
class AnalysisCache {
  final CoreRepository repo;
  final Duration ttl;
  final int Function() now;

  AnalysisCache(this.repo, {this.ttl = const Duration(days: 30), int Function()? now})
      : now = now ?? nowMs;

  Future<CachedAnalysis?> lookup({
    required String imageHash,
    required String promptVersion,
    required String model,
  }) async {
    if (model.isEmpty) return null;
    final threshold = now() - ttl.inMilliseconds;
    final sessions = await repo.listSessions(limit: 500);
    for (final s in sessions) {
      if (s.imageHash != imageHash) continue;
      if (s.status != TaskState.done) continue;
      if (s.promptVersion != promptVersion) continue;
      if (s.aiModel != model) continue;
      if (s.createdAt < threshold) continue;
      final questions = await repo.questionsOfSession(s.sessionId);
      if (questions.isEmpty) continue;
      return CachedAnalysis(
        sessionId: s.sessionId,
        questions: questions,
        createdAt: s.createdAt,
      );
    }
    return null;
  }
}
