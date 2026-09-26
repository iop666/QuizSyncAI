import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart'
    show Option, Question, QuestionType;
import 'package:quizsync_desktop/services/float_window_compose.dart';
import 'package:quizsync_desktop/services/float_window_content.dart';
import 'package:quizsync_desktop/services/float_window_view.dart';

/// 分块缓存 + 合成（M36）的回归。
///
/// 这轮把「每帧都出图」改成「内容/外观变化才出图，其余纯内存合成」。
/// 这里用**假出图器**（不碰 `toImage`）钉住三件事：
/// ① 只有真正变化的那一块才重出图；② 滚动/悬停是零出图（compositeOnly）；
/// ③ 合成的**像素摆放**对（内容区按滚动量整行拷贝、浮层按 alpha 叠加）。
void main() {
  const w = 342.0;
  const h = 760.0;
  final palette = FloatWindowPalette.of(dark: false, paletteId: 'white');

  /// 假出图器：把「请求的矩形」编码进像素，方便断言合成结果。
  /// - 每个像素 = 0xFF000000 | (源行号 & 0xFF)，行号 = 该位图里的 y（物理像素）。
  /// - 这样合成后只要看某一行像素的低字节就知道它来自内容图的哪一行。
  Future<Uint8List> fakePiece(
    List<FloatNode> nodes, {
    required double width,
    required double height,
    required double devicePixelRatio,
    Offset origin = Offset.zero,
    int backgroundArgb = 0,
    double cornerRadius = 0,
    double opacity = 1,
  }) async {
    final pw = (width * devicePixelRatio).round().clamp(1, 8192);
    final ph = (height * devicePixelRatio).round().clamp(1, 8192);
    final out = Uint8List(pw * ph * 4);
    for (var y = 0; y < ph; y++) {
      final word = 0xFF000000 | (y & 0xFF);
      for (var x = 0; x < pw; x++) {
        final i = (y * pw + x) * 4;
        out[i] = word & 0xFF; // B
        out[i + 1] = (word >> 8) & 0xFF; // G
        out[i + 2] = (word >> 16) & 0xFF; // R
        out[i + 3] = (word >> 24) & 0xFF; // A
      }
    }
    return out;
  }

  Question q({String id = 'q1', String stem = '题目：下列说法的化学式正确的是？'}) =>
      Question(
        questionId: id,
        sessionId: 's1',
        ordinal: 0,
        questionNo: '12',
        stem: stem,
        type: QuestionType.single,
        options: const [Option(label: 'A', text: '甲'), Option(label: 'B', text: '乙')],
        choice: const ['A'],
        confidence: 0.85,
        createdAt: 1,
        updatedAt: 1,
        updatedBy: 'windows-local',
      );

  /// 造一帧：内容 + 可选悬停提示。
  FloatFrame frameWith({
    required List<Question> questions,
    String? hoveredId,
    bool busy = false,
    double contentHeightOverride = 0,
  }) {
    final content = questions.isEmpty
        ? const FloatContent([], 0)
        : layoutQuestionContent(questions,
            width: w - 20, fontSize: 13, palette: palette);
    final first = layoutFloatWindow(
      FloatWindowModel(palette: palette, total: 1, index: 0, createdAt: 1),
      width: w,
      height: h,
    );
    final bodyW = first.bodyRect.width;
    final content2 = questions.isEmpty
        ? const FloatContent([], 0)
        : layoutQuestionContent(questions,
            width: bodyW, fontSize: 13, palette: palette);
    return layoutFloatWindow(
      FloatWindowModel(
        palette: palette,
        total: 1,
        index: 0,
        createdAt: 1,
        busy: busy,
        busyText: '识别进行中…',
        hoveredId: hoveredId,
        content: content.nodes,
        contentHeight: contentHeightOverride > 0
            ? contentHeightOverride
            : content2.height,
      ),
      width: w,
      height: h,
    );
  }

  testWidgets('① 第一次合成出齐三块；同样的一帧再来一次零出图', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    final frame = frameWith(questions: [q()], hoveredId: FloatAction.regenerate);

    final first = await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 2, scrollPx: 0);
    expect(first.chromeRendered, isTrue);
    expect(first.contentRendered, isTrue);
    expect(first.overlayRendered, isTrue, reason: '悬停提示是浮层，单独出图');
    expect(first.compositeOnly, isFalse);
    expect(c.pieceRenders, 3);

    final second = await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 2, scrollPx: 0);
    expect(second.compositeOnly, isTrue, reason: '一模一样的一帧不该再出图');
    expect(c.pieceRenders, 3, reason: '出图次数不该增加');
    expect(identical(second.pixels, first.pixels), isTrue,
        reason: '直接复用上一帧像素');
  });

  testWidgets('② 滚动：零出图，但内容区像素按滚动量整行平移', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    final frame = frameWith(questions: [q()]);
    final a = await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    // 合成器复用内部缓冲（省掉每帧 4 MB 分配），所以要比较两帧就得自己拷一份。
    final aPixels = Uint8List.fromList(a.pixels);
    final before = c.pieceRenders;
    final b = await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 1, scrollPx: 25);
    expect(b.compositeOnly, isTrue, reason: '滚动只需要重新合成，不该出图');
    expect(c.pieceRenders, before);

    // 内容区第 0 行在 scrollPx=25 时应当显示内容图的第 25 行。
    final bodyY = frame.bodyRect.top.round();
    int rowWord(Uint8List px, int y) {
      final i = (y * a.pixelWidth + frame.bodyRect.left.round() + 4) * 4;
      return px[i + 3] << 24 | px[i + 2] << 16 | px[i + 1] << 8 | px[i];
    }

    expect(rowWord(aPixels, bodyY) & 0xFF, 0);
    expect(rowWord(b.pixels, bodyY) & 0xFF, 25,
        reason: '滚 25 像素后，内容区顶部应显示内容图的第 25 行');
    // 顶部第一栏不随内容滚动（两边都是外观图层，值相同）。
    expect(rowWord(aPixels, 2), rowWord(b.pixels, 2));
  });

  testWidgets('③ 悬停：只重出浮层那一小块，外观与内容都不动', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    final plain = frameWith(questions: [q()]);
    final hovered = frameWith(questions: [q()], hoveredId: FloatAction.regenerate);
    await c.compose(
        frame: plain, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    final renders = c.pieceRenders;
    final r = await c.compose(
        frame: hovered, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    expect(r.overlayRendered, isTrue);
    expect(r.chromeRendered, isFalse, reason: '外观没变不该重出图');
    expect(r.contentRendered, isFalse, reason: '内容没变不该重出图');
    expect(c.pieceRenders, renders + 1, reason: '只多出一次浮层图');
  });

  testWidgets('④ 内容变了才重出内容图（外观与浮层不动）', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    await c.compose(
        frame: frameWith(questions: [q()]),
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0);
    final renders = c.pieceRenders;
    final r = await c.compose(
        frame: frameWith(questions: [q(stem: '换了一道完全不同的题目内容')]),
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0);
    expect(r.contentRendered, isTrue);
    expect(r.chromeRendered, isFalse);
    expect(c.pieceRenders, renders + 1);
  });

  testWidgets('⑤ 浮层按 alpha 叠加（预乘 source-over），且不影响别处', (tester) async {
    // 自定义假出图器：浮层整块用 50% 红（预乘后 B=0,G=0,R=128,A=128）。
    Future<Uint8List> fake(List<FloatNode> nodes,
        {required double width,
        required double height,
        required double devicePixelRatio,
        Offset origin = Offset.zero,
        int backgroundArgb = 0,
        double cornerRadius = 0,
        double opacity = 1}) async {
      final pw = (width * devicePixelRatio).round().clamp(1, 8192);
      final ph = (height * devicePixelRatio).round().clamp(1, 8192);
      final out = Uint8List(pw * ph * 4);
      final overlay = nodes.isNotEmpty && nodes.every((n) => n.overlay);
      for (var i = 0; i < out.length; i += 4) {
        if (overlay) {
          out[i] = 0;
          out[i + 1] = 0;
          out[i + 2] = 128;
          out[i + 3] = 128;
        } else {
          out[i] = 40;
          out[i + 1] = 60;
          out[i + 2] = 80;
          out[i + 3] = 255;
        }
      }
      return out;
    }

    final c = FloatFrameComposer(renderPiece: fake);
    addTearDown(c.dispose);
    final frame = frameWith(questions: [q()], hoveredId: FloatAction.regenerate);
    final r = await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    // 浮层的矩形（外扩 2）内应是「50% 红叠在底色上」；外面应是底色。
    final overlay = frame.nodes.where((n) => n.overlay).toList();
    final rect = overlay
        .map((n) => n.rect)
        .reduce((a, b) => a.expandToInclude(b));
    final cx = rect.center.dx.round();
    final cy = rect.center.dy.round();
    final i = (cy * r.pixelWidth + cx) * 4;
    // 预乘 source-over：dst = src + dst × (255 − srcA) / 255，且四通道都要算。
    expect(r.pixels[i], 19, reason: 'B：0 + 40×127/255');
    expect(r.pixels[i + 1], 29, reason: 'G：0 + 60×127/255');
    expect(r.pixels[i + 2], 167, reason: 'R：128 + 80×127/255');
    expect(r.pixels[i + 3], 255, reason: 'A：128 + 255×127/255');
    // 远离浮层的地方还是底色。
    final j = ((frame.bodyRect.top + 4).round() * r.pixelWidth + 4) * 4;
    expect(r.pixels[j + 3], 255);
    expect(r.pixels[j], 40);
  });

  testWidgets('⑥ 尺寸/配色变了会重出外观图（缓存失效）', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    await c.compose(
        frame: frameWith(questions: [q()]),
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0);
    final renders = c.pieceRenders;
    final dark = FloatWindowPalette.of(dark: true, paletteId: 'white');
    final r = await c.compose(
        frame: frameWith(questions: [q()]),
        palette: dark,
        devicePixelRatio: 1,
        scrollPx: 0);
    expect(r.chromeRendered, isTrue, reason: '换明暗/配色要重出外观图');
    expect(r.contentRendered, isTrue, reason: '卡片配色也变了，内容图一起重出');
    expect(c.pieceRenders, greaterThan(renders));
  });

  testWidgets('⑦ 行数/像素尺寸自检：合成结果尺寸 = 逻辑尺寸 × DPR', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    for (final dpr in [1.0, 1.5, 2.0]) {
      final r = await c.compose(
          frame: frameWith(questions: [q()]),
          palette: palette,
          devicePixelRatio: dpr,
          scrollPx: 0);
      expect(r.pixelWidth, (w * dpr).round());
      expect(r.pixelHeight, (h * dpr).round());
      expect(r.pixels.length, r.pixelWidth * r.pixelHeight * 4);
      // 预乘不变式抽查。
      for (var i = 0; i < r.pixels.length; i += 4 * 211) {
        expect(r.pixels[i], lessThanOrEqualTo(r.pixels[i + 3]));
      }
    }
    expect(math.max(1, 2), 2);
  });

  testWidgets('⑧ 真渲染器端到端：合成结果里能看到卡片与命中项底色（标绿 / 标黄都认）', (tester) async {
    // 前面的用例用假出图器钉住「什么时候出图、像素怎么摆」；这一条走**真**的
    // `renderNodes`（含 `Picture.toImage`），确认分块合成之后窗口里真的还有卡片和
    // 命中项底色 —— 契约要求把握足够时标绿（#DCFCE7）、需复核时标黄（#FEF3C7）。
    Future<int> countColor(Question question, (int, int, int) target) async {
      final base = layoutFloatWindow(
        FloatWindowModel(palette: palette, total: 1, index: 0, createdAt: 1),
        width: w,
        height: h,
      );
      final content = layoutQuestionContent([question],
          width: base.bodyRect.width, fontSize: 13, palette: palette);
      final frame = layoutFloatWindow(
        FloatWindowModel(
          palette: palette,
          total: 1,
          index: 0,
          createdAt: 1,
          content: content.nodes,
          contentHeight: content.height,
        ),
        width: w,
        height: h,
      );
      final c = FloatFrameComposer();
      addTearDown(c.dispose);
      final r = (await tester.runAsync(() => c.compose(
            frame: frame,
            palette: palette,
            devicePixelRatio: 1,
            scrollPx: 0,
          )))!;
      var hits = 0;
      for (var i = 0; i < r.pixels.length; i += 4) {
        // BGRA
        final b = r.pixels[i];
        final g = r.pixels[i + 1];
        final rr = r.pixels[i + 2];
        if ((rr - target.$1).abs() <= 6 &&
            (g - target.$2).abs() <= 6 &&
            (b - target.$3).abs() <= 6) {
          hits++;
        }
      }
      return hits;
    }

    // 有把握（无需复核）→ 标绿。
    expect(await countColor(q(), (220, 252, 231)), greaterThan(200),
        reason: '命中项的浅绿底必须出现在合成结果里');
    // 需复核 → 按契约改用标黄。
    expect(
        await countColor(q(id: 'q2').copyWith(needReview: true), (254, 243, 199)),
        greaterThan(200),
        reason: '需复核时应当标黄');
  });

  testWidgets('⑨ M38：来回切两套内容（极简/正常）之后不再重出图', (tester) async {
    // 用户报「频繁点上面按钮就崩溃 / 卡」：极简与锁定是**来回切**的按钮，
    // 合成器只留一个内容槽位时两个指纹互相顶掉 —— 实测每点一次重出整张内容图
    // （665×8192 ≈ 22 MB），30 轮点击出了 192 张图、RSS 冲到 789 MB。
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    final normal = frameWith(questions: [q(stem: '正常模式：整段题干与解析')]);
    final minimal = frameWith(questions: [q(stem: '极简模式：只留题干')]);

    await c.compose(
        frame: normal, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    final afterNormal = c.pieceRenders;
    await c.compose(
        frame: minimal, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    final afterMinimal = c.pieceRenders;
    expect(afterNormal, 2, reason: '第一套：外观 + 内容各出一次');
    expect(afterMinimal, 3, reason: '第二套只需要再出一次内容');

    for (var i = 0; i < 6; i++) {
      final f = i.isEven ? normal : minimal;
      final fast = c.composeFast(
          frame: f, palette: palette, devicePixelRatio: 1, scrollPx: 0);
      expect(fast, isNotNull,
          reason: '第 ${i + 1} 次来回切应当命中缓存（这正是 M38 修的东西）');
      await c.compose(
          frame: f, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    }
    expect(c.pieceRenders, afterMinimal, reason: '来回切不该再出图');
  });

  testWidgets('⑩ M39：内容改成切片后，三套内容各自只占 1 片时都留在缓存里', (tester) async {
    // M38 时内容块只留两份（够「极简 ↔ 正常」来回翻）；M39 改成按片缓存（8 片，
    // 1024 逻辑像素一片），于是短内容的三套变体都能同时留着 —— 这条把新语义钉住。
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    FloatFrame variant(String stem) => frameWith(questions: [q(stem: stem)]);
    final a = variant('第一套');
    final b = variant('第二套');
    final third = variant('第三套');

    for (final f in [a, b, third]) {
      await c.compose(
          frame: f, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    }
    for (final f in [a, b, third]) {
      expect(
          c.composeFast(
              frame: f, palette: palette, devicePixelRatio: 1, scrollPx: 0),
          isNotNull,
          reason: '短内容各占 1 片，三套都该还在缓存里');
    }
  });

  testWidgets('⑫ M39：内容比 8192 物理像素还高时，滚到底部仍然看得到内容（不截断）', (tester) async {
    // 用户报「悬浮窗在默认模式下显示不全被截断」：真实数据里 20 题的识别结果内容高
    // 4659 逻辑像素，DPR2 = 9318 物理像素，而一块位图的高度被 clamp 到 8192 ——
    // 滚到底部时最后 563 逻辑像素永远看不见、底下是一片底色。切片之后不再有上限。
    // 这条用例用假出图器（把「源行号」编码进像素）钉住：滚到底部时最后一行必须是
    // **内容**，不是底色。
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    const contentH = 6000.0; // DPR2 → 12000 物理像素（旧实现会被截到 8192）
    final frame =
        frameWith(questions: [q()], contentHeightOverride: contentH);
    final bodyHLogical = frame.bodyRect.height;
    final scroll = contentH - bodyHLogical; // 滚到底

    final r = await c.compose(
        frame: frame,
        palette: palette,
        devicePixelRatio: 2,
        scrollPx: scroll);

    // 注意：滚到底时最后一**物理**行正好越过内容末尾（内容是 12000 行，
    // 可见区是 [10666, 12001)），所以取倒数第二行 —— 它必须是内容的最后一行。
    final lastRow = (frame.bodyRect.top * 2).round() +
        (bodyHLogical * 2).round() -
        2;
    int rowByte(int y) {
      // 注意：内容区起点是**物理**像素（bodyRect.left × DPR），别按逻辑像素取，
      // 否则会差一像素读到外观块（外观块的假像素也写着它自己的行号）。
      final x = (frame.bodyRect.left * 2).round() + 4;
      final i = (y * r.pixelWidth + x) * 4;
      return r.pixels[i]; // 假出图器把源行号写在 B 通道
    }

    final got = rowByte(lastRow);
    expect(got, isNot(equals(palette.background & 0xFF)),
        reason: '底部那一行必须是内容像素，不能是底色（M39 修的截断就是这个）');
    // 期望值 = 该片内的行号：片高 1024 逻辑 = 2048 物理，最后一行的绝对行号 11999。
    expect(got, ((contentH * 2).round() - 1) % 2048 % 256,
        reason: '最后一行应当来自最后一片的最后一行');

    // 一帧只需要可见区那 1–2 片（外加一片预取），不该把整篇内容都出图。
    expect(c.pieceRenders, lessThanOrEqualTo(4),
        reason: '首帧只该出外观 + 可见区切片（+1 片预取），不是整篇内容');

    // 往回滚一点点（还在同一片里）不该再出图。
    final before = c.pieceRenders;
    await c.compose(
        frame: frame,
        palette: palette,
        devicePixelRatio: 2,
        scrollPx: scroll - 40);
    expect(c.pieceRenders, before, reason: '同一片内滚动是纯拷贝帧');
  });

  testWidgets('⑬ M39：跨片滚动时只多出「跨进去的那一片」', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    const contentH = 6000.0;
    final frame =
        frameWith(questions: [q()], contentHeightOverride: contentH);
    // 从顶部（片 0）往下滚两片，每次只看可见区要用的片有没有准备好。
    await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 2, scrollPx: 0);
    final first = c.pieceRenders;
    expect(first, lessThanOrEqualTo(3));

    // 滚到第 3 片（逻辑 2560 → 物理 5120，片号 5120/2048 = 2）附近。
    final r = await c.compose(
        frame: frame,
        palette: palette,
        devicePixelRatio: 2,
        scrollPx: 2560);
    expect(r.compositeOnly, isFalse, reason: '跨到新片需要出图');
    expect(c.pieceRenders - first, lessThanOrEqualTo(3),
        reason: '多数片在滚动路上已经被预取，这次最多补一两片');
    // 滚回去：片还在缓存里 → 纯合成。
    final r2 = await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 2, scrollPx: 0);
    expect(r2.compositeOnly, isTrue, reason: '滚回已缓存的片不该再出图');
  });


  testWidgets('⑭ M39 修复：切片必须按**窗口坐标**出图（内容顶头、左右边距对称、底部不丢）', (tester) async {
    // 真凶：`layoutFloatWindow` 已经把内容图元平移到了 `bodyRect.topLeft`
    // （`n.intoBody(delta)`），所以第 i 片的原点必须是
    // `(bodyRect.left, bodyRect.top + i×片高)`。写成 `(0, i×片高)` 会让内容整体
    // 下移一个表头高、右移一个左边距 —— 用户看到的就是「不顶头 / 底部被识别按钮
    // 压住 / 左右边距不对等」。这条用例的出图器把**原点**编进像素：
    //   B 通道 = 绝对行号（原点 y + 位图行号），G 通道 = 绝对列号（原点 x + 列号）。
    // 于是「某个目的像素显示的是哪一行/哪一列」可以直接断言。
    Future<Uint8List> absolutePiece(
      List<FloatNode> nodes, {
      required double width,
      required double height,
      required double devicePixelRatio,
      Offset origin = Offset.zero,
      int backgroundArgb = 0,
      double cornerRadius = 0,
      double opacity = 1,
    }) async {
      final pw = (width * devicePixelRatio).round().clamp(1, 8192);
      final ph = (height * devicePixelRatio).round().clamp(1, 8192);
      final ox = (origin.dx * devicePixelRatio).round();
      final oy = (origin.dy * devicePixelRatio).round();
      final out = Uint8List(pw * ph * 4);
      for (var y = 0; y < ph; y++) {
        for (var x = 0; x < pw; x++) {
          final i = (y * pw + x) * 4;
          out[i] = (oy + y) & 0xFF; // B = 绝对行
          out[i + 1] = (ox + x) & 0xFF; // G = 绝对列
          out[i + 2] = 0;
          out[i + 3] = 255;
        }
      }
      return out;
    }

    final c = FloatFrameComposer(renderPiece: absolutePiece);
    addTearDown(c.dispose);
    final frame = frameWith(questions: [q()], contentHeightOverride: 4000);
    final r = await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 1, scrollPx: 0);

    final bodyY = frame.bodyRect.top.round();
    final bodyX = frame.bodyRect.left.round();
    int at(int x, int y) => (y * r.pixelWidth + x) * 4;
    // 内容区左上角那个像素，应当正是**窗口坐标**下的 (bodyX, bodyY)：
    // 漏掉 bodyRect 的原点会分别差 (-bodyX, -bodyY)（表现就是偏右下、边距不等）。
    expect(r.pixels[at(bodyX, bodyY)], bodyY,
        reason: '内容必须顶头（B 通道 = 绝对行号，应等于 bodyRect.top）');
    expect(r.pixels[at(bodyX, bodyY) + 1], bodyX,
        reason: '内容左边界必须正好落在 bodyRect.left（左右边距才对称）');

    // 滚到底：最后一行内容必须是内容，而不是底色（底部不能被识别按钮吃掉）。
    final bodyHLogical = frame.bodyRect.height;
    final scroll = 4000 - bodyHLogical;
    final r2 = await c.compose(
        frame: frame,
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: scroll);
    final lastContentRow = (bodyY + (bodyHLogical).round() - 2);
    expect(r2.pixels[at(bodyX + 4, lastContentRow)],
        isNot(equals(palette.background & 0xFF)),
        reason: '滚到底时倒数第二行必须是内容像素');
  });

  testWidgets('⑮ M40：内容片由富文本渲染器提供，且内容指纹变了会重出图', (tester) async {
    final tiles = <String>[];
    final c = FloatFrameComposer(
      renderPiece: fakePiece,
      renderContentTile: ({
        required double width,
        required double tileTop,
        required double tileHeight,
        required double devicePixelRatio,
        required int backgroundArgb,
        double opacity = 1,
      }) async {
        tiles.add('top=$tileTop h=$tileHeight');
        return Uint8List(
            (width * devicePixelRatio).round() *
                (tileHeight * devicePixelRatio).round() *
                4);
      },
    );
    addTearDown(c.dispose);
    final frame = frameWith(questions: [q()], contentHeightOverride: 3000);
    await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    expect(tiles, isNotEmpty, reason: '内容片必须由富文本渲染器出图');
    expect(tiles.first, startsWith('top=0.0'), reason: '可见区从第 0 片开始');

    // 同一帧 + 同一内容指纹 → 纯合成，不再出图。
    final before = tiles.length;
    await c.compose(
        frame: frame, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    expect(tiles.length, before, reason: '内容没变不该重出片');

    // 内容指纹变了（题目换了，但高度一样）→ 必须重出内容片。
    await c.compose(
        frame: frame,
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0,
        contentSignature: 12345);
    expect(tiles.length, greaterThan(before),
        reason: '高度一样但内容不同时，靠 contentSignature 区分');
  });
  testWidgets('⑪ M38：照真实路径翻「极简 ↔ 正常」（内容与图标都变）不该每次重出图', (tester) async {
    // ⑨/⑩ 只换了题干文字；这条照**真实**路径来：极简模式走 `abstractQuestion`
    // 裁过的题目，外观块还会因图标/按钮态变化而变 —— 用来钉住用户在按钮上
    // 来回点时不该出现「每点一次重出整张 22 MB 内容图」。出图块用尺寸记账，
    // 哪一块在重出图一眼能看出来。
    final rendered = <String>[];
    Future<Uint8List> recording(
      List<FloatNode> nodes, {
      required double width,
      required double height,
      required double devicePixelRatio,
      Offset origin = Offset.zero,
      int backgroundArgb = 0,
      double cornerRadius = 0,
      double opacity = 1,
    }) {
      rendered.add('${width.round()}x${height.round()}');
      return fakePiece(nodes,
          width: width,
          height: height,
          devicePixelRatio: devicePixelRatio,
          origin: origin,
          backgroundArgb: backgroundArgb,
          cornerRadius: cornerRadius,
          opacity: opacity);
    }

    final c = FloatFrameComposer(renderPiece: recording);
    addTearDown(c.dispose);
    FloatFrame variant({required bool minimal}) {
      final questions = [q()];
      final shown =
          minimal ? questions.map(abstractQuestion).toList() : questions;
      final base = layoutFloatWindow(
        FloatWindowModel(
            palette: palette, total: 1, index: 0, createdAt: 1, minimal: minimal),
        width: w,
        height: h,
      );
      final content = layoutQuestionContent(shown,
          width: base.bodyRect.width, fontSize: 13, palette: palette);
      return layoutFloatWindow(
        FloatWindowModel(
          palette: palette,
          total: 1,
          index: 0,
          createdAt: 1,
          minimal: minimal,
          content: content.nodes,
          contentHeight: content.height,
        ),
        width: w,
        height: h,
      );
    }

    final normal = variant(minimal: false);
    final mini = variant(minimal: true);
    await c.compose(
        frame: normal, palette: palette, devicePixelRatio: 1, scrollPx: 0);
    await c.compose(
        frame: mini, palette: palette, devicePixelRatio: 1, scrollPx: 0);

    rendered.clear();
    for (var i = 0; i < 8; i++) {
      final f = i.isEven ? normal : mini;
      await c.compose(
          frame: f, palette: palette, devicePixelRatio: 1, scrollPx: 0);
      final fast = c.composeFast(
          frame: f, palette: palette, devicePixelRatio: 1, scrollPx: 0);
      expect(fast, isNotNull, reason: '第 ${i + 1} 次来回切应当命中缓存');
    }
    expect(rendered, isEmpty, reason: '来回切不该重出图，实际出了：$rendered');
  });

  testWidgets('⑯ M42：选区高亮直接调进合成像素（零出图），选区变了要重合成', (tester) async {
    final c = FloatFrameComposer(renderPiece: fakePiece);
    addTearDown(c.dispose);
    final frame = frameWith(questions: [q()]);
    const accent = 0xFF0F9D58;
    const sel = <Rect>[Rect.fromLTWH(20, 120, 100, 14)];

    final plain = await c.compose(
        frame: frame,
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0);
    final pw = plain.pixelWidth;
    final rendersBefore = c.pieceRenders;
    // ⚠ 合成器复用输出缓冲：要比像素必须先拷一份。
    final before = Uint8List.fromList(plain.pixels);

    int at(int x, int y) => (y * pw + x) * 4;
    final fast = c.composeFast(
        frame: frame,
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0,
        selectionRects: sel,
        selectionArgb: accent);
    expect(fast, isNotNull, reason: '选区只是调像素，不该因此需要出图');
    expect(c.pieceRenders, rendersBefore, reason: '画选区绝不能出图');

    // 选中区域混进了主色（绿色通道明显抬起），区域外一个像素都不许动。
    expect(fast!.pixels[at(30, 125) + 1], greaterThan(30),
        reason: '选区内的像素要混上主色');
    expect(fast.pixels[at(30, 125) + 1], isNot(before[at(30, 125) + 1]));
    for (final p in [
      [30, 100],
      [200, 125],
      [30, 200],
    ]) {
      expect(fast.pixels[at(p[0], p[1]) + 1], before[at(p[0], p[1]) + 1],
          reason: '选区外的像素（${p[0]},${p[1]}）不该被改');
    }

    // 同一选区再来一次：帧指纹相同 → 直接复用（连合成都省）。
    final again = c.composeFast(
        frame: frame,
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0,
        selectionRects: sel,
        selectionArgb: accent);
    expect(identical(again!.pixels, fast.pixels), isTrue,
        reason: '选区没变时应当直接复用上一帧像素');

    // 选区挪一下 → 必须重合成（否则拖选时画面不动）。
    final moved = c.composeFast(
        frame: frame,
        palette: palette,
        devicePixelRatio: 1,
        scrollPx: 0,
        selectionRects: const <Rect>[Rect.fromLTWH(20, 160, 100, 14)],
        selectionArgb: accent);
    expect(moved, isNotNull);
    expect(moved!.pixels[at(30, 125) + 1], before[at(30, 125) + 1],
        reason: '选区挪走后原处必须还原成没有选区的样子');
    expect(moved.pixels[at(30, 165) + 1], greaterThan(30),
        reason: '新选区位置要混上主色');
  });
}
