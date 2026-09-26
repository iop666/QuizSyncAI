import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';

import 'package:quizsync_android/services/live_updates.dart';
import 'package:quizsync_android/state/app_state.dart';

import 'support.dart';

/// WS 事件 → 本地库 + 自动刷新通知（用户需求 7）。
class _RecordingSink implements LiveUpdateSink {
  final List<String> events = [];
  ServerInfo? info;
  String? collectionId;
  String? collectionName;
  List<Map<String, dynamic>> taskUpdates = [];
  String? resultSessionId;
  bool resultSelfInitiated = false;
  String? failedMessage;
  int dataChangedCount = 0;
  bool revoked = false;

  @override
  void collectionChanged(String? collectionId, String? collectionName) {
    events.add('collection');
    this.collectionId = collectionId;
    this.collectionName = collectionName;
  }

  @override
  void serverInfo(ServerInfo info) {
    events.add('info');
    this.info = info;
  }

  @override
  void taskUpdate({
    required String taskId,
    required TaskState status,
    String? sessionId,
    int imageCount = 0,
  }) {
    events.add('task_update');
    taskUpdates.add({
      'task_id': taskId,
      'status': status.wire,
      'session_id': sessionId,
      'image_count': imageCount,
    });
  }

  @override
  void taskResult({
    required String sessionId,
    required int questionCount,
    bool selfInitiated = false,
  }) {
    events.add('task_result');
    resultSessionId = sessionId;
    resultSelfInitiated = selfInitiated;
  }

  @override
  void taskFailed({required String taskId, String? message}) {
    events.add('task_failed');
    failedMessage = message;
  }

  @override
  void offline(String message) => events.add('offline');

  @override
  void dataChanged() {
    events.add('data_changed');
    dataChangedCount++;
  }

  @override
  void deviceRevoked() {
    revoked = true;
    events.add('revoked');
  }
}

void main() {
  late QuizSyncDb db;
  late AndroidAppState app;
  late _RecordingSink sink;
  late LiveUpdates updates;

  setUp(() async {
    db = QuizSyncDb(NativeDatabase.memory());
    app = await makeTestApp(db);
    sink = _RecordingSink();
    updates = LiveUpdates(app: app, sink: sink);
  });

  tearDown(() async => db.close());

  test('task_result：会话 + 题目 + 页序落本地库，并通知宿主刷新', () async {
    await updates.handle({
      'type': 'task_result',
      'task_id': 't1',
      'session': {
        'session_id': 's1',
        'collection_id': 'c1',
        'image_hash': 'h1',
        'source_device': 'android-local',
        'status': 'done',
        'question_count': 1,
        'created_at': 1000,
        'updated_at': 1000,
        'updated_by': 'server-1',
        'image_hashes': ['h1', 'h2'],
        'questions': [
          {
            'question_id': 'q1',
            'session_id': 's1',
            'ordinal': 0,
            'question_no': '12',
            'stem': '识别出来的题干',
            'type': 'blank',
            'answer_text': '答案',
            'created_at': 1000,
            'updated_at': 1000,
            'updated_by': 'server-1',
          }
        ],
      },
    });

    // 本地库真的有：历史可离线查看。
    final session = await app.repo.getSession('s1');
    expect(session, isNotNull);
    expect(session!.collectionId, 'c1');
    final questions = await app.repo.questionsOfSession('s1');
    expect(questions.single.displayTitle, '1. 第 12 题');
    expect(await app.repo.imageHashesOf('s1'), ['h1', 'h2']);

    // 宿主被通知刷新（用户需求 7：不靠手动下拉）。
    expect(sink.resultSessionId, 's1');
    expect(sink.events, contains('task_result'));
    // 这条会话的 source_device 就是本机 → 是本机自己发起的识别，全程静默。
    expect(sink.resultSelfInitiated, isTrue,
        reason: '本机发起的识别不能因为主机回广播就自动跳结果页（用户需求 3）');
  });

  test('M47：手机改过答案后，主机重分析推回的结果不覆盖用户手改', () async {
    // 主机第一次的结果。
    await updates.handle({
      'type': 'task_result',
      'task_id': 't1',
      'session': {
        'session_id': 's2',
        'image_hash': 'h1',
        'source_device': 'server-1',
        'status': 'done',
        'question_count': 1,
        'created_at': 1000,
        'updated_at': 1000,
        'updated_by': 'server-1',
        'questions': [
          {
            'question_id': 'q2',
            'session_id': 's2',
            'ordinal': 0,
            'stem': '题干',
            'type': 'blank',
            'answer_text': 'AI 答案',
            'analysis': 'AI 解析',
            'created_at': 1000,
            'updated_at': 1000,
            'updated_by': 'server-1',
          }
        ],
      },
    });

    // 用户在手机上改了答案（`answer_edited = 1`）。
    await app.repo.updateUserAnswer('q2', const AnswerValue(text: '我改的答案'));
    expect((await app.repo.getQuestion('q2'))!.answerEdited, isTrue);

    // 主机重新识别，推回一份新的 AI 结果（没带上用户的手改）。
    await updates.handle({
      'type': 'task_result',
      'task_id': 't2',
      'session': {
        'session_id': 's2',
        'image_hash': 'h1',
        'source_device': 'server-1',
        'status': 'done',
        'question_count': 1,
        'created_at': 1000,
        'updated_at': 2000,
        'updated_by': 'server-1',
        'questions': [
          {
            'question_id': 'q2',
            'session_id': 's2',
            'ordinal': 0,
            'stem': '题干',
            'type': 'blank',
            'answer_text': 'AI 新答案',
            'analysis': 'AI 新解析',
            'created_at': 1000,
            'updated_at': 2000,
            'updated_by': 'server-1',
          }
        ],
      },
    });

    final after = (await app.repo.getQuestion('q2'))!;
    expect(after.answerText, '我改的答案',
        reason: '用户手改的答案不得被 AI 新结果覆盖（data-model.md 2.3）');
    expect(after.answerEdited, isTrue);
    expect(after.analysis, 'AI 新解析', reason: '没被手改的字段照常更新');
  });

  test('task_result：主机发起的会话标记为非本机（可以自动进入结果页）', () async {    await updates.handle({
      'type': 'task_result',
      'task_id': 't-host',
      'session': {
        'session_id': 's-host',
        'image_hash': 'h1',
        'source_device': 'server-1',
        'status': 'done',
        'question_count': 0,
        'created_at': 1000,
        'updated_at': 1000,
        'updated_by': 'server-1',
      },
    });

    expect(sink.resultSessionId, 's-host');
    expect(sink.resultSelfInitiated, isFalse,
        reason: '主机发的 task_result 才是「进入结果页」的信号（用户需求 3）');
  });

  test('task_update：未完成时把页数报给宿主（N 张图片识别中…）', () async {
    // 主机起的任务：本地已有这张会话的页序。
    await addSession(app, 's1');
    await app.repo.setSessionImages('s1', ['h1', 'h2', 'h3']);

    await updates.handle({
      'type': 'task_update',
      'task_id': 't1',
      'status': 'analyzing',
      'session_id': 's1',
    });

    expect(sink.taskUpdates.single['status'], 'analyzing');
    expect(sink.taskUpdates.single['image_count'], 3);
  });

  test('task_update：优先用主机广播的 image_count（本地还没有这条会话）', () async {
    // 主机本地截屏起的任务：session_id 在手机本地库里还不存在。
    expect(await app.repo.getSession('s-host'), isNull);

    await updates.handle({
      'type': 'task_update',
      'task_id': 't-host',
      'status': 'analyzing',
      'session_id': 's-host',
      'image_count': 5,
    });

    expect(sink.taskUpdates.single['image_count'], 5,
        reason: '页数用主机广播的 image_count；查本地库只会得到 0');
    expect(sink.taskUpdates.single['session_id'], 's-host',
        reason: '本地库里没有这条会话，也要把状态交给宿主');
    expect(sink.taskUpdates.single['status'], 'analyzing');
    expect(sink.events, contains('task_update'));
  });

  test('task_update：image_count 为 0 或缺失时退回本地库页数', () async {
    await addSession(app, 's1');
    await app.repo.setSessionImages('s1', ['h1', 'h2']);

    await updates.handle({
      'type': 'task_update',
      'task_id': 't1',
      'status': 'analyzing',
      'session_id': 's1',
      'image_count': 0,
    });
    expect(sink.taskUpdates.last['image_count'], 2);

    await updates.handle({
      'type': 'task_update',
      'task_id': 't1',
      'status': 'done',
      'session_id': 's1',
    });
    expect(sink.taskUpdates.last['image_count'], 2);
  });

  test('hello / collection_changed：主机当前合集变化要立刻反映到界面', () async {
    await updates.handle({
      'type': 'hello',
      'server_device_id': 'server-1',
      'protocol_version': 1,
      'active_collection_id': 'c9',
      'active_collection_name': '期末复习',
    });
    expect(sink.collectionId, 'c9');
    expect(sink.collectionName, '期末复习');
    expect(sink.info?.deviceId, 'server-1');

    await updates.handle({
      'type': 'collection_changed',
      'collection_id': null,
      'collection_name': null,
    });
    expect(sink.collectionId, isNull);
  });

  test('ops / task_failed / device_revoked 各自的通知', () async {
    await updates.handle({'type': 'ops'});
    expect(sink.dataChangedCount, 1);

    await updates.handle({'type': 'task_failed', 'task_id': 't1', 'message': 'AI 超时'});
    expect(sink.failedMessage, 'AI 超时');

    // 吊销要清掉配对信息，否则界面还会以为自己在配对状态。
    await app.savePairing(const PairingInfo(
      host: 'h', port: 1, token: 't', serverDeviceId: 's', serverName: 'n'));
    await updates.handle({'type': 'device_revoked', 'device_id': 'android-local'});
    expect(sink.revoked, isTrue);
    expect(await app.loadPairing(), isNull);
  });

  test('hostErrorMessage：409 no_active_collection 用统一文案', () {
    expect(
      hostErrorMessage(
          const ApiClientException(409, 'no_active_collection', '先选合集')),
      '请先在电脑上选择任务合集',
    );
    expect(isNoActiveCollection(
        const ApiClientException(409, 'no_active_collection', 'x')), isTrue);
    expect(
        isNoActiveCollection(
            const ApiClientException(500, 'internal', 'boom')),
        isFalse);
  });
}
