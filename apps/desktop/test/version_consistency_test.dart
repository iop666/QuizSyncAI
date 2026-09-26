import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_desktop/state/app_info.dart';

/// M47：版本号原来散在 pubspec / Runner.rc / `kAppVersion` / 三个打包脚本 /
/// installer.iss 里各写一份 —— 曾经就因为两处硬编码 `1.0.0` 漏改，被迫双端
/// 重新出包。这里把「同一个来源」钉住：以后改版本只改 pubspec 就够了。
void main() {
  String? versionOf(String pubspec) =>
      RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
          .firstMatch(File(pubspec).readAsStringSync())
          ?.group(1);

  test('桌面端：pubspec ↔ kAppVersion ↔ Runner.rc 三处一致', () {
    final v = versionOf('pubspec.yaml');
    expect(v, isNotNull, reason: 'apps/desktop/pubspec.yaml 必须有 version');
    expect(kAppVersion, v,
        reason: 'lib/state/app_info.dart 的 kAppVersion 要与 pubspec 同源');

    final rc = File('windows/runner/Runner.rc').readAsStringSync();
    expect(rc, contains('#define VERSION_AS_STRING "$v"'),
        reason: 'Runner.rc 的 VERSION_AS_STRING 要跟着改');
    expect(rc, contains('#define VERSION_AS_NUMBER ${v!.split('.').join(',')},0'),
        reason: 'Runner.rc 的 VERSION_AS_NUMBER 要跟着改');
  });

  test('安卓端：pubspec ↔ app_info ↔ 桌面端版本号完全一致（双端统一）', () {
    final androidPubspec = versionOf('../../apps/android/pubspec.yaml');
    expect(androidPubspec, isNotNull);
    expect(androidPubspec, kAppVersion, reason: '双端版本号必须统一');

    final androidInfo =
        File('../../apps/android/lib/state/app_info.dart').readAsStringSync();
    expect(androidInfo, contains("kAppVersion = '$androidPubspec'"),
        reason: '安卓端 app_info.dart 也要跟着改');
  });

  test('打包 / 审计脚本不再各写一份版本号（留空即从 pubspec 读）', () {
    for (final script in [
      '../../tools/package_windows.ps1',
      '../../tools/package_android.ps1',
      '../../tools/audit_android.ps1',
    ]) {
      final text = File(script).readAsStringSync();
      expect(RegExp(r'\$Version\s*=\s*"[0-9]').hasMatch(text), isFalse,
          reason: '$script 里仍有写死的版本号默认值');
      expect(text, contains('pubspec.yaml'),
          reason: '$script 应当从 pubspec 读版本号');
    }
    // installer.iss 的版本由打包脚本用 /DAppVersion 传进来。
    final iss = File('../../tools/installer.iss').readAsStringSync();
    expect(iss, contains('#ifndef AppVersion'), reason: '要能接受外部传入的版本号');
  });
}
