import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import 'package:quizsync_desktop/state/app_scope.dart';

/// M15 第 1 条：**悬浮球的大小 / 透明度 / 描边 / 开关全都调不动**。
///
/// 根因不在悬浮球实现里，而在**监听的写法**：`settingsProvider` 是
/// `ChangeNotifierProvider`，它的值就是 `SettingsController` 实例本身。
/// 直接 `ref.listenManual(settingsProvider, (prev, next) { 比较 prev.app 与 next.app })`
/// 时，`prev` 与 `next` 是**同一个对象**，两边读到的都是刚刚更新过的 `app`
/// —— 于是「前后签名相等」永远成立，`_applyBallSettings()` 一次都没被调用。
///
/// 修法是用 `select` 把指纹取出来，`prev/next` 才是真正的旧值 / 新值。
/// 下面第一条测试把这个坑钉住（直接监听时 prev 就是新值），第二条断言
/// 修好之后的写法在「只改悬浮球字段」时确实会触发回调。
void main() {
  Future<ProviderContainer> containerWith(
    SettingsController controller,
  ) async {
    await controller.load();
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => controller),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('根因：直接监听 settingsProvider 时 prev/next 是同一个实例，比较永远相等', () async {
    final controller = SettingsController(MemoryKeyValueStore());
    final container = await containerWith(controller);

    SettingsController? seenPrev;
    SettingsController? seenNext;
    var fired = 0;
    container.listen<SettingsController>(settingsProvider, (prev, next) {
      fired++;
      seenPrev = prev;
      seenNext = next;
    });

    await controller.updateApp(controller.app.copyWith(ballSize: 80));

    expect(fired, 1, reason: '通知会来');
    expect(identical(seenPrev, seenNext), isTrue,
        reason: '但 prev 与 next 是同一个 controller —— 这就是坑');
    expect(seenPrev!.app.ballSize, 80,
        reason: '而且 prev 读到的已经是**新值**，用 prev.app 与 next.app 比较必然相等');
  });

  test('修好之后：只改悬浮球字段也会触发监听，指纹真的变了', () async {
    final controller = SettingsController(MemoryKeyValueStore());
    final container = await containerWith(controller);

    final signatures = <String>[];
    container.listen<String>(
      settingsProvider.select((s) => ballSignature(s.app)),
      (prev, next) => signatures.add(next),
    );

    final before = ballSignature(controller.app);
    await controller.updateApp(controller.app.copyWith(ballSize: 88));
    final afterSize = ballSignature(controller.app);
    await controller.updateApp(controller.app.copyWith(ballOpacity: 0.5));
    final afterOpacity = ballSignature(controller.app);
    // M17 第 1 条起描边**默认打开**，所以这里改的是「关掉它」（改 true 不会
    // 改变签名，也就测不出监听了）。
    await controller.updateApp(controller.app.copyWith(ballStroke: false));
    final afterStroke = ballSignature(controller.app);
    // M44 第 3 条起悬浮球**默认关闭**，所以这里改的是「打开它」（改 false 不会
    // 改变签名，也就测不出监听了）。
    await controller.updateApp(controller.app.copyWith(ballEnabled: true));
    final afterEnabled = ballSignature(controller.app);

    expect(afterSize, isNot(before));
    expect(afterOpacity, isNot(afterSize));
    expect(afterStroke, isNot(afterOpacity));
    expect(afterEnabled, isNot(afterStroke));
    expect(signatures.length, 4, reason: '四次改动都要通知到（含开关）');
  });

  test('热键指纹同理：改任意一个槽位都要能触发重新注册', () async {
    final controller = SettingsController(MemoryKeyValueStore());
    final container = await containerWith(controller);

    var fired = 0;
    container.listen<String>(
      settingsProvider.select((s) => hotkeySettingsSignature(s.app)),
      (prev, next) => fired++,
    );

    await controller.updateApp(
        controller.app.copyWith(multipageHotkeyJson: '{"keyId":65}'));
    expect(fired, 1, reason: '改「多页模式」热键也必须触发（用户反馈 14 的那个场景）');
  });
}
