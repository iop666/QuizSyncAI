import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_android/services/android_capture_controller.dart'
    show CaptureResult;
import 'package:quizsync_android/services/multipage_capture.dart';

/// 多页识别手势状态机（用户需求 4/11、M49 对齐 Windows 端）：
/// 长按 = 加一页并立即上传；短按（多页中）= 只提交已抓的页（不再补截一张）；
/// 到上限 = 提示 + 自动提交。
void main() {
  Uint8List page(int i) => Uint8List.fromList([0xff, 0xd8, i, 0xff, 0xd9]);

  late List<String> captured;
  late List<String> submitted;
  late List<(bool, int)> stateChanges;

  MultiPageCapture build({
    int limit = 6,
    bool captureOk = true,
    bool uploadOk = true,
    List<String>? messages,
  }) {
    var counter = 0;
    return MultiPageCapture(
      limitOf: () => limit,
      capturePage: () async {
        if (!captureOk) return null;
        captured.add('page-${counter++}');
        return page(counter);
      },
      uploadPage: (jpeg) async => uploadOk ? 'hash-${jpeg[2]}' : null,
      submitPages: (hashes) async {
        submitted.add(hashes.join(','));
        return CaptureResult.ok('session-1');
      },
      onMessage: messages?.add,
      onStateChanged: (active, pages) => stateChanges.add((active, pages)),
    );
  }

  setUp(() {
    captured = [];
    submitted = [];
    stateChanges = [];
  });

  test('长按逐页累加并立即上传，短按只提交已抓的页（M49：不再补截一张）', () async {
    final multi = build();
    expect(multi.active, isFalse);

    final first = await multi.longPress();
    expect(first.event, MultiPageEvent.pageAdded);
    expect(multi.pageCount, 1);
    expect(multi.active, isTrue, reason: '第一页后进入多页模式');
    expect(stateChanges.last, (true, 1));

    final second = await multi.longPress();
    expect(second.event, MultiPageEvent.pageAdded);
    expect(multi.pageCount, 2);
    expect(submitted, isEmpty, reason: '还没结束，不能提前提交');
    final capturedBeforeFinish = captured.length;

    // 短按 = 结束并识别（只有长按才截新图）。
    final finish = await multi.tapToFinish();
    expect(finish.event, MultiPageEvent.submitted);
    expect(finish.result?.ok, isTrue);
    expect(captured.length, capturedBeforeFinish,
        reason: '收尾的短按不再补截一张（看齐 Windows 端 F8）');
    expect(submitted.single.split(',').length, 2,
        reason: '提交的就是长按抓到的 2 页');
    expect(multi.active, isFalse, reason: '提交后退出多页模式');
    expect(stateChanges.last, (false, 0));
  });

  test('短按收尾后重新长按 = 开新的一轮，页数不串台', () async {
    final multi = build();
    await multi.longPress();
    await multi.tapToFinish();
    expect(submitted.single.split(',').length, 1);

    await multi.longPress();
    expect(multi.pageCount, 1, reason: '新一轮从第 1 页重新数');
    await multi.tapToFinish();
    expect(submitted.length, 2);
    expect(submitted.last.split(',').length, 1, reason: '不带上上一轮的页');
  });

  test('到页数上限：提示并自动提交已收集的页（不用再多按一次）', () async {
    final messages = <String>[];
    final multi = build(limit: 2, messages: messages);

    await multi.longPress();
    final second = await multi.longPress();
    expect(second.event, MultiPageEvent.submitted,
        reason: 'M47：抓满上限就自动提交（SPEC 3.1）');
    expect(submitted.single.split(',').length, 2, reason: '上限页数原样提交');
    expect(messages.any((m) => m.contains('上限')), isTrue, reason: '到上限要提示');
    expect(multi.pageCount, 0);

    // 提交之后重新长按 = 开新的一轮。
    final again = await multi.longPress();
    expect(again.event, MultiPageEvent.pageAdded);
    expect(multi.pageCount, 1);
  });

  test('截屏失败：取消多页模式，不留半截任务', () async {
    final messages = <String>[];
    final multi = build(captureOk: false, messages: messages);
    final r = await multi.longPress();
    expect(r.event, MultiPageEvent.captureFailed);
    expect(multi.active, isFalse);
    expect(submitted, isEmpty);
    expect(messages.any((m) => m.contains('截屏失败')), isTrue);
  });

  test('上传失败：取消多页模式（不允许混着未上传的页提交）', () async {
    final multi = build(uploadOk: false);
    final r = await multi.longPress();
    expect(r.event, MultiPageEvent.uploadFailed);
    expect(multi.active, isFalse);
    expect(submitted, isEmpty);
  });

  test('收尾的短按不碰截屏 / 上传（没有「最后一页」这条失败路径了）', () async {
    var captureCalls = 0;
    var uploadCalls = 0;
    final messages = <String>[];
    final multi = MultiPageCapture(
      limitOf: () => 6,
      capturePage: () async {
        captureCalls++;
        return page(1);
      },
      uploadPage: (jpeg) async {
        uploadCalls++;
        return 'hash-1';
      },
      submitPages: (hashes) async {
        submitted.add(hashes.join(','));
        return CaptureResult.ok('session-1');
      },
      onMessage: messages.add,
    );

    await multi.longPress();
    expect(captureCalls, 1);
    expect(uploadCalls, 1);

    final r = await multi.tapToFinish();
    expect(r.event, MultiPageEvent.submitted);
    expect(submitted.single, 'hash-1');
    expect(captureCalls, 1, reason: '短按不再截新图');
    expect(uploadCalls, 1, reason: '短按不再上传新图');
  });

  test('页数上限被主机硬上限夹住（不会超过 6），到第 6 页自动提交', () async {
    // kHardMaxPagesPerTask 由 12 改成 6（用户反馈：「多页识别硬上限就是 6 张」），
    // 所以用户把设置里的一题多页上限调到 99 时，实际只能用 6 页。
    //
    // M47 改了这里的期望：契约（SPEC 3.1）要求「到达上限时提示『已达上限』并
    // **自动**创建多页任务上传识别」，桌面端热键也是抓满即上传。原实现只在
    // 长按**开始时**判上限，所以要多按一次；本用例原来把这个（错的）行为钉住了，
    // 现在改成「第 6 页加进来就提交」。
    final multi = build(limit: 99);
    for (var i = 0; i < 5; i++) {
      final r = await multi.longPress();
      expect(r.event, MultiPageEvent.pageAdded);
    }
    final sixth = await multi.longPress();
    expect(sixth.event, MultiPageEvent.submitted,
        reason: '加满第 6 页就自动提交，不需要再长按一次');
    expect(submitted.single.split(',').length, 6);
    expect(multi.active, isFalse);
  });
}
