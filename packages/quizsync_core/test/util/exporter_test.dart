import 'dart:io';

import 'package:test/test.dart';

import 'package:quizsync_core/quizsync_core.dart';

void main() {
  group('导出（M6 任务 7）', () {
    final session = Session(
      sessionId: 's1',
      imageHash: 'h1',
      sourceDevice: 'dev-a',
      status: TaskState.done,
      createdAt: 1757980000000,
      updatedAt: 1757980000000,
      updatedBy: 'dev-a',
    );
    final questions = [
      Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: 0,
        questionNo: '12',
        stem: '下列说法正确的是',
        type: QuestionType.single,
        options: const [
          Option(label: 'A', text: '甲'),
          Option(label: 'B', text: '乙'),
        ],
        choice: const ['B'],
        analysis: r'因为 $x^2=4$ 所以选 B',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'd',
      ),
      Question(
        questionId: 'q2',
        sessionId: 's1',
        ordinal: 1,
        stem: '计算 1+1',
        type: QuestionType.blank,
        answerText: '2',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'd',
      ),
    ];

    test('Markdown：正确答案加粗 + ✓、填空答案、免责声明', () {
      final md = Exporter.sessionToMarkdown(session, questions);
      expect(md, contains('**✓ B.** 乙'));
      expect(md, contains('**答案：B**'));
      expect(md, contains('**答案：**2'));
      expect(md, contains(r'因为 $x^2=4$ 所以选 B'));
      expect(md, contains('答案由 AI 生成，仅供参考'));
    });

    test('JSON 往返：字段完整', () {
      final json = Exporter.sessionToJson(session, questions);
      expect(json['session_id'], 's1');
      final q0 = (json['questions'] as List).first as Map<String, dynamic>;
      expect(q0['choice_json'], ['B']);
      final back = Question.fromJson(q0);
      expect(back.choice, ['B']);
      expect(back.type, QuestionType.single);
    });

    test('全部历史导出', () {
      final all = Exporter.allToJson([(session, questions), (session, questions)]);
      expect((all['records'] as List).length, 2);
      final md = Exporter.allToMarkdown([(session, questions)]);
      expect(md, contains('# AI 双端搜题（QuizSync AI）历史导出'));
    });
  });

  group('备份与恢复（M6 任务 8）', () {
    test('备份 → 恢复 → 数据一致（往返）', () async {
      final dir =
          await Directory.systemTemp.createTemp('quizsync-backup-');
      final dbPath = '${dir.path}/quizsync.db';
      final imagesDir = '${dir.path}/images';
      await Directory(imagesDir).create(recursive: true);

      // 原库写入数据 + 图片文件。
      final db = openQuizSyncDb(dbPath);
      final repo = CoreRepository(db: db, deviceId: 'dev-a');
      await repo.init();
      await repo.upsertSession(Session(
        sessionId: 's1',
        imageHash: 'h1',
        sourceDevice: 'dev-a',
        status: TaskState.done,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      await repo.upsertQuestion(Question(
        questionId: 'q1',
        sessionId: 's1',
        ordinal: 0,
        stem: '往返测试',
        type: QuestionType.blank,
        answerText: 'ok',
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'dev-a',
      ));
      await File('$imagesDir/h1.jpg').writeAsBytes([1, 2, 3]);
      await db.close();

      final zip = BackupManager.createBackup(dbPath: dbPath, imagesDir: imagesDir);
      expect(zip.isNotEmpty, isTrue);

      // 恢复到新位置。
      final dir2 = await Directory.systemTemp.createTemp('quizsync-restore-');
      await BackupManager.restore(
        zipBytes: zip,
        dbPath: '${dir2.path}/quizsync.db',
        imagesDir: '${dir2.path}/images',
      );

      final db2 = openQuizSyncDb('${dir2.path}/quizsync.db');
      final repo2 = CoreRepository(db: db2, deviceId: 'dev-a');
      final sessions = await repo2.listSessions();
      final questions = await repo2.questionsOfSession('s1');
      expect(sessions.length, 1);
      expect(questions.single.stem, '往返测试');
      expect(questions.single.answerText, 'ok');
      expect(await File('${dir2.path}/images/h1.jpg').readAsBytes(), [1, 2, 3]);
      await db2.close();

      await dir.delete(recursive: true);
      await dir2.delete(recursive: true);
    });
  });

  group('日志（M6 任务 10）', () {
    test('导出；Key 与 token 不落日志', () {
      final log = AppLogger();
      log.info('ai', 'call with sk-abcdef1234567890 key');
      log.info('net', 'Authorization: Bearer abcdefghijk1234567890');
      log.info('pair', '{"token":"0123456789abcdef"}');

      final exported = log.export().join('\n');
      expect(exported, isNot(contains('abcdef1234567890')));
      expect(exported, isNot(contains('abcdefghijk1234567890')));
      expect(exported, isNot(contains('0123456789abcdef')));
      expect(exported, contains('****'));
    });

    test('环形上限', () {
      final log = AppLogger(capacity: 10);
      for (var i = 0; i < 50; i++) {
        log.info('t', 'line $i');
      }
      expect(log.export().length, 10);
      expect(log.export().last, contains('line 49'));
    });
  });
}
