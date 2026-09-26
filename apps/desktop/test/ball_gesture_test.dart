import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_desktop/services/floating_ball.dart';

/// M16 第 2 条：**左键长按 = 右键**（进入多页），左键单击不变（多页中 = 收尾）。
///
/// 判定改成「松手时按按住时长结算」：不再依赖 `SetTimer` / `WM_TIMER`
/// （队列里优先级最低的消息，用户按住不放时松手消息会先到，一次长按会被判成
/// 单击 —— 表现就是「长按不灵、跟右键不一样」）。
void main() {
  test('短按 = 单击；按住 ≥500ms = 长按；两者分别只发生一次', () {
    final g = BallGestureTracker();
    g.press(x: 100, y: 100, nowMs: 1000);
    expect(g.release(1000 + 499), BallGesture.tap);

    g.press(x: 100, y: 100, nowMs: 2000);
    expect(g.release(2000 + 500), BallGesture.longPress,
        reason: '整 500ms 就算长按（与设置在设置页里的 500ms 一致）');

    g.press(x: 100, y: 100, nowMs: 3000);
    expect(g.release(3000 + 5000), BallGesture.longPress);
  });

  test('拖过 8px 就是拖动：即使按住很久也不再算长按', () {
    final g = BallGestureTracker();
    g.press(x: 100, y: 100, nowMs: 0);
    g.moveTo(108, 103);
    expect(g.moved, isFalse, reason: '阈值内的小抖动不算拖动');
    g.moveTo(111, 100);
    expect(g.moved, isTrue, reason: '相对按下点位移超过 8px');
    expect(g.release(5000), BallGesture.drag, reason: '拖动优先于长按');
  });

  test('没有按下过时松手不会吞掉事件（兜底成单击）', () {
    expect(BallGestureTracker().release(1), BallGesture.tap);
  });

  test('松手后状态复位：连续两次手势互不影响', () {
    final g = BallGestureTracker();
    g.press(x: 10, y: 10, nowMs: 0);
    g.moveTo(50, 10);
    expect(g.release(10), BallGesture.drag);
    g.press(x: 10, y: 10, nowMs: 20);
    expect(g.moved, isFalse, reason: '上一次的 moved 不能带到下一次');
    expect(g.release(20), BallGesture.tap);
  });
}
