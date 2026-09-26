import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

void main() {
  group('协议 JSON 往返（protocol.md 的模型载体）', () {
    test('Question toJson/fromJson 逐字段往返', () {
      final q = Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: 2,
        questionNo: '(3)',
        stem: '下列说法正确的是',
        type: QuestionType.multi,
        options: const [Option(label: 'A', text: '甲'), Option(label: 'B', text: '乙')],
        choice: const ['A', 'B'],
        answerText: null,
        analysis: '因为 AB',
        confidence: 0.87,
        needReview: false,
        answerInImage: true,
        warnings: const ['w1'],
        answerEdited: true,
        analysisEdited: false,
        createdAt: 111,
        updatedAt: 222,
        updatedBy: 'dev-x',
        lamport: 9,
        deletedAt: null,
      );
      final back = Question.fromJson(q.toJson());
      expect(back.questionId, 'q1');
      expect(back.ordinal, 2);
      expect(back.questionNo, '(3)');
      expect(back.stem, '下列说法正确的是');
      expect(back.type, QuestionType.multi);
      expect(back.options.length, 2);
      expect(back.options.first.label, 'A');
      expect(back.choice, ['A', 'B']);
      expect(back.analysis, '因为 AB');
      expect(back.confidence, 0.87);
      expect(back.answerInImage, isTrue);
      expect(back.warnings, ['w1']);
      expect(back.answerEdited, isTrue);
      expect(back.createdAt, 111);
      expect(back.lamport, 9);
    });

    test('Session toJson/fromJson 往返', () {
      final s = Session(
        sessionId: 's1',
        taskId: 't1',
        imageHash: 'h1',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        aiProvider: 'openai-compatible',
        aiModel: 'gpt-4o-mini',
        promptVersion: 'v1',
        cached: true,
        questionCount: 4,
        latencyMs: 3500,
        createdAt: 1,
        updatedAt: 2,
        updatedBy: 'dev-a',
        lamport: 3,
      );
      final back = Session.fromJson(s.toJson());
      expect(back.taskId, 't1');
      expect(back.status, TaskState.done);
      expect(back.cached, isTrue);
      expect(back.questionCount, 4);
      expect(back.latencyMs, 3500);
      expect(back.promptVersion, 'v1');
    });

    test('SyncOp toJson/fromJson 往返（WS 推送载荷）', () {
      final op = SyncOp(
        opId: 'op-1',
        deviceId: 'dev-a',
        lamport: 42,
        entity: SyncEntity.question,
        entityId: 'q1',
        opType: SyncOpType.upsert,
        fields: {'stem': '新题干', 'confidence': 0.9},
        createdAt: 12345,
      );
      final back = SyncOp.fromJson(op.toJson());
      expect(back.opId, 'op-1');
      expect(back.lamport, 42);
      expect(back.entity, SyncEntity.question);
      expect(back.opType, SyncOpType.upsert);
      expect(back.fields['stem'], '新题干');
    });

    test('PairRequest / PairResponse / ServerInfo / ApiError', () {
      const req = PairRequest(
        code: '482913',
        deviceId: 'd-1',
        deviceName: 'Pixel 7',
        platform: 'android',
        appVersion: '1.0.0',
      );
      final reqBack = PairRequest.fromJson(req.toJson());
      expect(reqBack.code, '482913');
      expect(reqBack.isValid, isTrue);
      expect(PairRequest.fromJson({'code': ''}).isValid, isFalse);

      const resp = PairResponse(
        token: 'tok',
        serverDeviceId: 'sid',
        serverName: 'DESKTOP-ABC',
        protocolVersion: 1,
      );
      final respBack = PairResponse.fromJson(resp.toJson());
      expect(respBack.serverName, 'DESKTOP-ABC');

      const info = ServerInfo(
        deviceId: 'sid',
        deviceName: 'DESKTOP-ABC',
        platform: 'windows',
        protocolVersion: 1,
        appVersion: '1.0.0',
        aiConfigured: true,
        capabilities: ['analyze', 'sync'],
      );
      final infoBack = ServerInfo.fromJson(info.toJson());
      expect(infoBack.capabilities, ['analyze', 'sync']);

      const err = ApiError(code: 'invalid_code', message: '配对码错误');
      final errBack = ApiError.fromJson(err.toJson());
      expect(errBack.code, 'invalid_code');
    });

    test('生成器：配对码 6 位数字，token 64 位 hex', () {
      final code = generatePairingCode();
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(generatePairingCode() != code, isTrue, reason: '随机性');

      final token = generateTokenHex();
      expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('newUuidV4 形态', () {
      final id = newUuidV4();
      expect(id, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });
}
