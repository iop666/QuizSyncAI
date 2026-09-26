import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_core/quizsync_core.dart'
    show
        kBallEnabledKey,
        kBallEnabledMigratedKey,
        kDefaultBallOpacity,
        kDefaultBallSize,
        kDefaultBallStroke,
        kDefaultBallStrokeOpacity,
        kDefaultBallStrokeWidth,
        kFloatWindowMinimalKey,
        kFloatWindowModeMigratedKey;
import 'package:quizsync_ui/quizsync_ui.dart';

/// 设置的**默认值**必须真的生效（M14 第 4 条实测踩到）。
///
/// `AppSettings.fromMap` 里布尔项曾写成 `map[key] == '1'`：键不存在（全新安装、
/// 用户从没动过这个开关）时它是 **false**，把构造函数里的默认值整个绕过去。
/// 后果：用户要求「默认打开悬浮球」，代码里默认值改成 true 也没用 ——
/// 真机上悬浮球一直不出现，日志里连一条 `ball` 都没有。
void main() {
  group('默认值', () {
    test('M44：悬浮球默认**关闭**（用户要求）', () {
      expect(const AppSettings().ballEnabled, isFalse);
      expect(AppSettings.fromMap(const <String, String>{}).ballEnabled, isFalse,
          reason: '键不存在时回落到默认值（关闭），而不是被 == 判成别的');
    });

    test('M44：老库里的 ball_enabled=1 会被**一次性**迁移到关闭', () async {
      final store = MemoryKeyValueStore();
      await store.write(kBallEnabledKey, '1');
      final c = SettingsController(store);
      await c.load();
      expect(c.app.ballEnabled, isFalse, reason: '迁移后悬浮球默认不显示');
      expect(await store.read(kBallEnabledKey), '0', reason: '迁移要落库');
      expect(await store.read(kBallEnabledMigratedKey), '1');

      // 只迁移一次：用户之后自己打开悬浮球，再启动必须尊重他的选择。
      await c.updateApp(c.app.copyWith(ballEnabled: true));
      final again = SettingsController(store);
      await again.load();
      expect(again.app.ballEnabled, isTrue,
          reason: '迁移标记已经写过，不能再把用户的选择顶掉');
    });

    test('用户显式关掉后仍然是关的（默认值不能反过来覆盖用户选择）', () {
      const off = AppSettings(ballEnabled: false);
      expect(AppSettings.fromMap(off.toMap()).ballEnabled, isFalse);
      const on = AppSettings(ballEnabled: true);
      expect(AppSettings.fromMap(on.toMap()).ballEnabled, isTrue);
    });

    // M17 第 1 条：球 40 / 70% / 描边开·宽 4·不透明 25%。
    test('M17 默认值：40 / 70% / 描边开·宽 4·不透明 25%', () {
      const s = AppSettings();
      expect(s.ballSize, 40);
      expect(s.ballOpacity, 0.7);
      expect(s.ballStroke, isTrue);
      expect(s.ballStrokeWidth, 4);
      expect(s.ballStrokeOpacity, 0.25);

      // 键不存在（全新安装）时每一项都要回落到常量默认值。
      final fresh = AppSettings.fromMap(const <String, String>{});
      expect(fresh.ballSize, kDefaultBallSize);
      expect(fresh.ballOpacity, kDefaultBallOpacity);
      expect(fresh.ballStroke, kDefaultBallStroke, reason: '描边默认打开');
      expect(fresh.ballStrokeWidth, kDefaultBallStrokeWidth);
      expect(fresh.ballStrokeOpacity, kDefaultBallStrokeOpacity);
    });

    test('描边关掉后仍然是关的（和开关同一个坑）', () {
      const off = AppSettings(ballStroke: false);
      expect(AppSettings.fromMap(off.toMap()).ballStroke, isFalse);
      const on = AppSettings(ballStroke: true);
      expect(AppSettings.fromMap(on.toMap()).ballStroke, isTrue);
    });

    test('往返一致：toMap → fromMap 不改变任何字段', () {
      const settings = AppSettings(
        ballEnabled: true,
        ballStroke: true,
        ballSize: 72,
        ballOpacity: 0.6,
        ballStrokeWidth: 5,
        ballStrokeOpacity: 0.4,
        uiScale: 1.5,
        clipboardWatch: false,
      );
      final back = AppSettings.fromMap(settings.toMap());
      expect(back.ballEnabled, isTrue);
      expect(back.ballStroke, isTrue);
      expect(back.ballSize, 72);
      expect(back.ballOpacity, 0.6);
      expect(back.ballStrokeWidth, 5);
      expect(back.ballStrokeOpacity, 0.4);
      expect(back.uiScale, 1.5);
      expect(back.clipboardWatch, isFalse);
    });

    test('M43：悬浮窗默认显示模式 = 默认模式（极简）', () {
      expect(const AppSettings().floatWindowMinimal, isTrue);
      expect(AppSettings.fromMap(const <String, String>{}).floatWindowMinimal,
          isTrue,
          reason: '全新安装：键不存在时回落到新的默认值（默认模式）');
    });

    test('M43：老库里的 float_window_minimal=0 会被**一次性**迁移到默认模式', () async {
      final store = MemoryKeyValueStore();
      // 老库的样子：出厂值曾是 0，所以库里就存着 0（用户从没手动选过）。
      await store.write(kFloatWindowMinimalKey, '0');
      final c = SettingsController(store);
      await c.load();
      expect(c.app.floatWindowMinimal, isTrue, reason: '迁移后应当进入默认模式');
      expect(await store.read(kFloatWindowMinimalKey), '1', reason: '迁移要落库');
      expect(await store.read(kFloatWindowModeMigratedKey), '1');

      // 迁移只做一次：用户之后自己切到「详细解析模式」，再启动必须尊重他的选择。
      await c.updateApp(c.app.copyWith(floatWindowMinimal: false));
      final again = SettingsController(store);
      await again.load();
      expect(again.app.floatWindowMinimal, isFalse,
          reason: '迁移标记已经写过，不能再把用户的选择顶掉');
    });
  });
}
