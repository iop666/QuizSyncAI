import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/services/float_window.dart';
import 'package:quizsync_desktop/services/float_window_content.dart';
import 'package:quizsync_desktop/services/float_window_compose.dart';
import 'package:quizsync_desktop/services/float_window_presenter.dart';
import 'package:quizsync_desktop/services/float_window_view.dart';
import 'package:quizsync_desktop/services/remote_task.dart';
import 'package:quizsync_desktop/state/capture_coordinator.dart';

/// 悬浮窗 presenter（M32 / M33）的回归：数据映射、翻记录、极简模式、
/// 按钮落到设置与窗口上、外观与配色。
///
/// 窗口与内容渲染都用假实现：presenter 只依赖那几个动作，
/// 单测不需要真的建 Win32 分层窗口，也不需要真的排版题目卡片。
class _FakeWindow implements FloatWindowSurface {
  final List<String> calls = [];
  final List<Map<String, Rect>> hits = [];
  final List<Rect> dragRects = [];
  int frames = 0;
  int lastW = 0;
  int lastH = 0;
  bool visible = false;
  bool locked = false;
  bool topmost = true;
  double x = 0;
  double y = 0;
  double devicePixelRatio = 1;

  /// 最近一次推帧的整窗透明度（M36：由原生层 `SourceConstantAlpha` 施加）。
  double opacity = 1;

  @override
  Future<void> show() async {
    visible = true;
    calls.add('show');
  }

  @override
  void hide() {
    visible = false;
    calls.add('hide');
  }

  @override
  void setLocked(bool value) {
    locked = value;
    calls.add('locked=$value');
  }

  @override
  void setTopmost(bool value) {
    topmost = value;
    calls.add('topmost=$value');
  }

  @override
  void setDevicePixelRatio(double devicePixelRatio) {
    this.devicePixelRatio = devicePixelRatio;
    calls.add('dpr=$devicePixelRatio');
  }

  @override
  void setPosition(double logicalX, double logicalY) {
    x = logicalX;
    y = logicalY;
    calls.add('pos=${logicalX.round()},${logicalY.round()}');
  }

  @override
  Future<void> setFrame({
    required Uint8List pixels,
    required int pixelWidth,
    required int pixelHeight,
    required double devicePixelRatio,
    double opacity = 1,
    required Map<String, Rect> hits,
    required Rect dragRect,
    Rect bodyRect = Rect.zero,
    bool textSelectable = false,
  }) async {
    frames++;
    lastW = pixelWidth;
    lastH = pixelHeight;
    this.hits.add(hits);
    dragRects.add(dragRect);
    bodyRects.add(bodyRect);
    selectable.add(textSelectable);
  }

  /// M42：内容区矩形与「是否可拖选」也要传给原生层。
  final List<Rect> bodyRects = [];
  final List<bool> selectable = [];
}

/// 假出图：按请求的尺寸产出一块**全透明**位图（不碰引擎）。
Future<Uint8List> fakePiece(
  List<FloatNode> nodes, {
  required double width,
  required double height,
  required double devicePixelRatio,
  Offset origin = Offset.zero,
  int backgroundArgb = 0,
  double cornerRadius = 0,
  double opacity = 1,
}) async =>
    Uint8List((width * devicePixelRatio).round().clamp(1, 8192) *
        (height * devicePixelRatio).round().clamp(1, 8192) *
        4);

void main() {
  late QuizSyncDb db;
  late CoreRepository repo;
  late SettingsController settings;
  late _FakeWindow window;
  late FloatWindowPresenter presenter;

  /// M42：复制出去的内容（注入的写剪贴板记录）。
  late List<String> clipboard;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = QuizSyncDb(NativeDatabase.memory());
    repo = CoreRepository(db: db, deviceId: 'windows-local');
    await repo.init();
    settings = SettingsController(MemoryKeyValueStore());
    await settings.load();
    window = _FakeWindow();
    clipboard = [];
    presenter = FloatWindowPresenter(
      window: window,
      repo: repo,
      coordinator: CaptureCoordinator(
        refOf: () => throw StateError('本测试不触发采集'),
        contextOf: () => throw StateError('本测试不触发采集'),
        imageDir: 'unused',
      ),
      settings: () => settings.app,
      saveSettings: settings.updateApp,
      appIsDark: () => false,
      devicePixelRatioOf: () => 1,
      screenLogicalSizeOf: () => const Size(1600, 1000),
      // M42：写剪贴板注入成记录调用（真剪贴板在 flutter_test 里要平台通道）。
      writeClipboard: (text) async => clipboard.add(text),
      // M36：presenter 走分块合成器；`toImage` 在 flutter_test 的假异步环境里
      // 不会完成，所以这里塞一个**只产出空白位图**的假出图器 —— 用例关心的是
      // 「排了什么、合成有没有出图、尺寸多少、点了谁」，像素本身由
      // float_window_compose_test / float_window_view_test 覆盖。
      composer: FloatFrameComposer(renderPiece: fakePiece),
      // M40：内容高度来自富文本离屏管线、片位图由它栅格化 —— 真跑要 `toImage`，
      // 在 flutter_test 的假异步环境里不会完成，所以这里注入假实现。
      measureRichContent: (spec) async =>
          spec.questions.isEmpty ? 60 : spec.questions.length * 220.0,
      rasterRichContent: (spec,
              {required double tileTop,
              required double tileHeight,
              required double devicePixelRatio,
              required int backgroundArgb,
              double opacity = 1}) async =>
          Uint8List(((spec.width * devicePixelRatio).round().clamp(1, 8192)) *
              ((tileHeight * devicePixelRatio).round().clamp(1, 8192)) *
              4),
    );
  });

  tearDown(() async {
    // M42：「已复制」提示挂了一个 1.4 秒的计时器，用例结束必须让它停掉，
    // 否则 flutter_test 会报「A Timer is still pending」。
    presenter.dispose();
    await db.close();
  });

  Future<Session> addSession(String id, int createdAt,
      {List<Question> questions = const []}) async {
    await repo.upsertSession(Session(
      sessionId: id,
      imageHash: 'h-$id',
      sourceDevice: 'windows-local',
      status: TaskState.done,
      questionCount: questions.length,
      createdAt: createdAt,
      updatedAt: createdAt,
      updatedBy: 'windows-local',
    ));
    for (var i = 0; i < questions.length; i++) {
      await repo.upsertQuestion(questions[i].copyWith(sessionId: id));
    }
    await repo.setSessionImages(id, ['h-$id', 'h-$id-2']);
    return (await repo.getSession(id))!;
  }

  Question q({
    required String id,
    int ordinal = 0,
    String stem = '下列说法正确的是？',
    List<Option> options = const [],
    List<String> choice = const [],
    String? text,
    String analysis = '解析：因为甲是对的。',
    String? questionNo = '12',
  }) =>
      Question(
        questionId: id,
        sessionId: 's',
        ordinal: ordinal,
        questionNo: questionNo,
        stem: stem,
        type: options.isEmpty ? QuestionType.subjective : QuestionType.single,
        options: options,
        choice: choice,
        answerText: text,
        analysis: analysis,
        createdAt: nowMs(),
        updatedAt: nowMs(),
        updatedBy: 'windows-local',
      );

  testWidgets('① 打开后按「最新一次」显示：序号/时间/内容都在', (tester) async {
    final older = await addSession('s-old', 1000,
        questions: [q(id: 'q1', text: '答案甲')]);
    final newer = await addSession('s-new', 2000,
        questions: [
          q(
            id: 'q2',
            options: const [
              Option(label: 'A', text: '甲'),
              Option(label: 'B', text: '乙'),
            ],
            choice: const ['A'],
          ),
        ]);
    presenter.setSessions([newer, older]);
    await presenter.show();

    expect(window.visible, isTrue);
    // DPR 必须**在定位之前**告诉窗口（否则原生按 1:1 摆位置，200% 缩放下偏到左边）。
    expect(window.devicePixelRatio, 1);
    expect(window.calls.indexOf('dpr=1.0'),
        lessThan(window.calls.indexWhere((c) => c.startsWith('pos='))),
        reason: 'setDevicePixelRatio 必须先于 setPosition');
    // 默认位置：屏幕右侧、不贴边。
    expect(window.x + settings.app.floatWindowWidthLogical,
        closeTo(1600 - kFloatWindowDefaultMarginX, 1));
    // 一帧真的推给窗口了，且像素尺寸 = 逻辑尺寸 × DPR。
    expect(window.frames, greaterThan(0));
    expect(window.lastW, settings.app.floatWindowWidthLogical.round());

    final m = presenter.buildModel();
    expect(m.index, 0, reason: '默认看最新一次');
    expect(m.total, 2);
    expect(m.humanIndex, 2, reason: '最新一次是「第 2/2 次识别」');
    expect(m.createdAt, 2000);
    // M36：内容同步排版 + 分块缓存合成；尺寸、透明度与命中区都推给了窗口。
    expect(presenter.contentHeight, greaterThan(60), reason: '内容真的排出来了');
    expect(window.lastW, greaterThan(0));
    // M38：透明度由合成器乘进像素（每块一次），不交给 DWM。
    expect(presenter.buildModel().palette.background, isNonZero);
    // 拖拽区 = 顶部第一栏。
    expect(window.dragRects.last.height, lessThan(window.lastH.toDouble()));
    expect(window.dragRects.last.top, 0);
  });

  testWidgets('② 默认外观是竖屏 9:20，且只能三选一（第 1/15 条）', (tester) async {
    final s = await addSession('s-1', 1000);
    presenter.setSessions([s]);
    await presenter.show();

    expect(settings.app.floatWindowAspect, 'portrait', reason: '默认竖屏 9:20');
    expect(settings.app.floatWindowHeightLogical,
        greaterThan(settings.app.floatWindowWidthLogical));
    // 像素尺寸跟着外观走：高 = 宽 / (9/20)。
    expect(window.lastW,
        settings.app.floatWindowWidthLogical.round());
    expect(window.lastH, settings.app.floatWindowHeightLogical.round());

    // 换外观 → 窗口尺寸跟着变（不做任何拉伸）。
    await settings.updateApp(settings.app.copyWith(floatWindowAspect: 'landscape'));
    await presenter.applySettings();
    expect(settings.app.floatWindowHeightLogical,
        lessThan(settings.app.floatWindowWidthLogical));
    expect(window.lastH, settings.app.floatWindowHeightLogical.round());
    expect(window.lastW, settings.app.floatWindowWidthLogical.round());
  });

  testWidgets('③ 默认配色是浅色系（第 9 条）', (tester) async {
    final s = await addSession('s-1', 1000);
    presenter.setSessions([s]);
    await presenter.show();
    expect(settings.app.floatWindowPalette, 'white');
    await settings.updateApp(settings.app.copyWith(floatWindowPalette: 'sky'));
    await presenter.applySettings();
    expect(settings.app.floatWindowPalette, 'sky');
    // 未知 id 会被归一化回默认。
    await settings.updateApp(settings.app.copyWith(floatWindowPalette: 'nope'));
    expect(settings.app.floatWindowPalette, 'white');
  });

  testWidgets('④ 默认模式（极简）：只看题目答案（M43 第 1 条）', (tester) async {
    final s = await addSession('s-1', 1000, questions: [
      q(
        id: 'q1',
        options: const [
          Option(label: 'A', text: '甲'),
          Option(label: 'B', text: '乙'),
          Option(label: 'C', text: '丙'),
        ],
        choice: const ['B'],
      ),
    ]);
    presenter.setSessions([s]);
    await presenter.show();

    // M43 第 1 条：极简模式**就是**悬浮窗默认显示的模式（不需要先点按钮）。
    expect(presenter.buildModel().minimal, isTrue);
    expect(settings.app.floatWindowMinimal, isTrue);
    // 点一下切到「详细解析模式」。
    await presenter.handleAction(FloatAction.toggleMinimal);
    expect(settings.app.floatWindowMinimal, isFalse, reason: '按钮要落库');
    expect(presenter.buildModel().minimal, isFalse);
    // 裁剪逻辑本身在 float_window_content_test ④ 里逐条钉住。
    final view = abstractQuestion((await repo.questionsOfSession('s-1')).single);
    expect(view.options.map((o) => o.label).toList(), ['B']);
    expect(view.analysis, isEmpty);
  });

  testWidgets('⑤ 上一次 / 下一次翻记录', (tester) async {
    final s1 = await addSession('s-1', 1000, questions: [q(id: 'qa', text: '早')]);
    final s2 = await addSession('s-2', 2000, questions: [q(id: 'qb', text: '晚')]);
    presenter.setSessions([s2, s1]);
    await presenter.show();

    await presenter.handleAction(FloatAction.prev);
    expect(presenter.buildModel().index, 1);
    expect(presenter.currentSessionId, 's-1');
    await presenter.handleAction(FloatAction.prev);
    expect(presenter.buildModel().index, 1, reason: '已经最早了，不再往前');
    await presenter.handleAction(FloatAction.next);
    expect(presenter.currentSessionId, 's-2');
    await presenter.handleAction(FloatAction.next);
    expect(presenter.buildModel().index, 0, reason: '已经最新了，不再往后');
  });

  testWidgets('⑥ 极简与锁定按钮落到设置和窗口上（字号按钮已删，第 7 条）', (tester) async {
    final s = await addSession('s-1', 1000);
    presenter.setSessions([s]);
    await presenter.show();

    // 字号统一在设置页里调：顶部不再有这两个按钮。
    final ids = window.hits.last.keys.toSet();
    expect(ids, isNot(contains('font-up')));
    expect(ids, isNot(contains('font-down')));
    expect(ids, contains(FloatAction.toggleMinimal));
    expect(ids, contains(FloatAction.toggleLock));

    await presenter.handleAction('font-up');
    expect(settings.app.floatWindowFontScale, 1.0, reason: '未知 id 不该改设置');

    await presenter.handleAction(FloatAction.toggleLock);
    expect(settings.app.floatWindowLocked, isTrue);
    await presenter.applySettings();
    expect(window.locked, isTrue, reason: '锁定要真的作用到原生窗口');
  });

  testWidgets('⑦ 归位：窗口真的回到默认位置', (tester) async {
    final s = await addSession('s-1', 1000);
    presenter.setSessions([s]);
    await presenter.show();

    await settings.updateApp(settings.app.copyWith(
        floatWindowX: 12, floatWindowY: 34));
    await presenter.resetPosition();
    expect(settings.app.floatWindowX,
        closeTo(1600 - settings.app.floatWindowWidthLogical - 24, 1));
    // 设置页的「恢复默认位置」只改设置值；外壳的设置监听会走 applySettings，
    // 这条路径也必须真的把窗口摆回去。
    await settings.updateApp(settings.app.copyWith(
        floatWindowX: kFloatWindowNoPosition,
        floatWindowY: kFloatWindowNoPosition));
    await presenter.applySettings();
    expect(window.x, closeTo(1600 - settings.app.floatWindowWidthLogical - 24, 1));
  });

  testWidgets('⑧ 滚轮：滚动量受内容高度限制', (tester) async {
    final s = await addSession('s-1', 1000, questions: [
      for (var i = 0; i < 12; i++) q(id: 'q$i', ordinal: i, stem: '第 $i 题' * 20),
    ]);
    presenter.setSessions([s]);
    await presenter.show();

    // M34：内容高度是**真的排出来的**（文本排版），不再靠注入的假高度。
    expect(presenter.contentHeight, greaterThan(1000));
    await presenter.scrollBy(-3);
    expect(presenter.buildModel().scrollPx, 0, reason: '已经在顶部，向上滚不动');
    await presenter.scrollBy(3);
    final scrolled = presenter.buildModel().scrollPx;
    expect(scrolled, greaterThan(0));
    for (var i = 0; i < 60; i++) {
      await presenter.scrollBy(3);
    }
    expect(presenter.buildModel().scrollPx, greaterThanOrEqualTo(scrolled));
  });

  testWidgets('⑨ 拖动结束把位置写进设置', (tester) async {
    final s = await addSession('s-1', 1000);
    presenter.setSessions([s]);
    await presenter.show();
    await presenter.onMoveEnd(321, 123);
    expect(settings.app.floatWindowX, 321);
    expect(settings.app.floatWindowY, 123);
  });

  testWidgets('⑩ 会话列表刷新时保留用户正在看的那一次', (tester) async {
    final s1 = await addSession('s-1', 1000, questions: [q(id: 'qa', text: '早')]);
    final s2 = await addSession('s-2', 2000, questions: [q(id: 'qb', text: '晚')]);
    presenter.setSessions([s2, s1]);
    await presenter.show();
    await presenter.handleAction(FloatAction.prev);
    expect(presenter.currentSessionId, 's-1');

    presenter.setSessions([
      (await repo.getSession('s-2'))!,
      (await repo.getSession('s-1'))!,
    ]);
    await tester.pump();
    expect(presenter.currentSessionId, 's-1', reason: '刷新列表不该把用户拽回最新');

    presenter.setSessions([(await repo.getSession('s-2'))!]);
    await tester.pump();
    expect(presenter.currentSessionId, 's-2');
  });

  testWidgets('⑪ 没有识别记录时给出空状态而不是崩溃', (tester) async {
    presenter.setSessions(const []);
    await presenter.show();
    final m = presenter.buildModel();
    expect(m.total, 0);
    expect(m.emptyText, contains('还没有识别记录'));
    expect(window.frames, greaterThan(0));
  });

  testWidgets('⑫ M43：默认模式下的拖选与「复制识别内容」', (tester) async {
    final s = await addSession('s-1', 1000, questions: [
      q(
        id: 'qa',
        choice: const ['B'],
        options: const [
          Option(label: 'A', text: '甲'),
          Option(label: 'B', text: '乙'),
        ],
      ),
      q(id: 'qb', ordinal: 1, text: '四十二'),
    ]);
    presenter.setSessions([s]);
    await presenter.show();

    // M43 第 1 条：**极简（默认模式）就是默认显示的模式**，不用点任何按钮。
    expect(settings.app.floatWindowMinimal, isTrue, reason: '默认就是默认模式');
    expect(presenter.buildModel().minimal, isTrue);

    // 内容区要告诉原生层「这里可以拖选」，否则原生根本不接管按下。
    expect(window.selectable.last, isTrue, reason: '默认模式必须允许拖选');
    expect(window.bodyRects.last.height, greaterThan(0));

    // 拖选：从内容区顶部往下拖，选中开头那一段。
    final body = window.bodyRects.last;
    presenter.onSelectBegin(body.left + 8, body.top + 6);
    presenter.onSelectUpdate(body.left + 120, body.top + 40);
    await tester.pump(const Duration(milliseconds: 10));
    await presenter.copySelected();
    expect(clipboard, hasLength(1));
    expect(clipboard.single, isNotEmpty);
    expect(clipboard.single.contains('第 1 题'), isTrue,
        reason: '从内容区顶部拖选应当选中第一题的题号行');

    // 「复制识别内容」：一点就把**这一次识别的全部内容**复制走（M43 第 2 条）。
    clipboard.clear();
    await presenter.handleAction(FloatAction.copyContent);
    expect(clipboard, hasLength(1));
    final text = clipboard.single;
    expect(text, contains('第 1 题'));
    expect(text, contains('A. 甲'), reason: '完整内容要含全部选项（不只是命中的那个）');
    expect(text, contains('B. 乙'));
    expect(text, contains('答案：B'));
    expect(text, contains('第 2 题'));
    expect(text, contains('答案：四十二'));
    expect(text, contains('解析：因为甲是对的。'), reason: '解析也要在复制内容里');
    expect(presenter.buildModel().tipText, isNotNull, reason: '要给一条「已复制」提示');
    // 让 1.4 秒的提示计时器走完（fake async 里 pump 一下就好）。
    await tester.pump(const Duration(seconds: 2));
    expect(presenter.buildModel().tipText, isNull, reason: '提示应当自己消失');
  });

  testWidgets('⑭ M42：切到详细解析模式后不再允许拖选（选区也清掉）', (tester) async {
    final s = await addSession('s-1', 1000, questions: [q(id: 'qa', text: '甲')]);
    presenter.setSessions([s]);
    await presenter.show();
    // 默认就是默认模式（极简）：拖一段选中。
    final body = window.bodyRects.last;
    presenter.onSelectBegin(body.left + 8, body.top + 6);
    presenter.onSelectUpdate(body.left + 100, body.top + 30);
    await tester.pump(const Duration(milliseconds: 10));
    await presenter.copySelected();
    expect(clipboard, hasLength(1));

    // 切到详细解析模式。
    await presenter.handleAction(FloatAction.toggleMinimal);
    expect(settings.app.floatWindowMinimal, isFalse);
    expect(window.selectable.last, isFalse, reason: '详细解析模式不拖选');
    clipboard.clear();
    await presenter.copySelected();
    expect(clipboard, isEmpty, reason: '切走之后必须把选区清掉');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('⑮ M44：手机端搜题时悬浮窗同步状态并跳到新结果', (tester) async {
    final s1 = await addSession('s-1', 1000, questions: [q(id: 'qa', text: '旧的')]);
    presenter.setSessions([s1]);
    await presenter.show();
    expect(presenter.currentSessionId, 's-1');

    // 手机开始识别：悬浮窗要显示「手机正在识别…」浮层（以前完全不知道）。
    presenter.onRemoteTask(const RemoteTaskSignal('analyzing', 's-remote'));
    expect(presenter.buildModel().busy, isTrue, reason: '手机识别中要亮出提示');
    expect(presenter.buildModel().busyText, contains('手机'));

    // 识别完成：既要把浮层收掉，也要在会话到位后跳到**新结果**。
    presenter.onRemoteTask(const RemoteTaskSignal('done', 's-remote'));
    expect(presenter.buildModel().busy, isFalse);
    final s2 = await addSession('s-2', 2000, questions: [q(id: 'qb', text: '新的')]);
    // 用户原本停在 s-1，但手机刚搜完 → 必须跳到最新的那次。
    presenter.setSessions([s2, s1]);
    await tester.pump();
    expect(presenter.currentSessionId, 's-2',
        reason: '手机识别结束后悬浮窗要跳到新界面（用户报的 bug）');

    // 之后再刷新列表（与手机无关）仍然尊重用户当前看的那一次。
    presenter.setSessions([s2, s1]);
    await tester.pump();
    expect(presenter.currentSessionId, 's-2');
  });

  testWidgets('⑯ M44：本机识别中（coordinator busy）文案不是「手机正在识别」',
      (tester) async {
    final s = await addSession('s-1', 1000, questions: [q(id: 'qa', text: '甲')]);
    presenter.setSessions([s]);
    await presenter.show();
    // 手机端任务与本机互不干扰：手机结束了，本机仍然是 idle。
    presenter.onRemoteTask(const RemoteTaskSignal('done', 's-remote'));
    expect(presenter.buildModel().busy, isFalse);
  });
}
