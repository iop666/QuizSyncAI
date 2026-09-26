import 'dart:io';

import 'package:quizsync_server/src/config.dart';
import 'package:test/test.dart';

/// 数据目录解析与老数据迁移（1.0.0 优化第 1 条）。
///
/// 注意：这里**替换掉** exe 目录与老数据目录的提供者，绝不碰真实的程序目录或
/// 用户 `%APPDATA%` 里的真数据。
void main() {
  late Directory temp;
  late Directory fakeExeDir;
  late Directory fakeLegacy;
  late String Function() savedExeProvider;
  late Directory Function() savedLegacyProvider;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('quizsync-paths');
    fakeExeDir = Directory('${temp.path}${Platform.pathSeparator}app')..createSync();
    fakeLegacy = Directory('${temp.path}${Platform.pathSeparator}legacy');
    savedExeProvider = ConfigPaths.executableDirProvider;
    savedLegacyProvider = ConfigPaths.legacyDirProvider;
    ConfigPaths.executableDirProvider = () => fakeExeDir.path;
    ConfigPaths.legacyDirProvider = () => fakeLegacy;
  });

  tearDown(() {
    ConfigPaths.executableDirProvider = savedExeProvider;
    ConfigPaths.legacyDirProvider = savedLegacyProvider;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('默认数据目录 = exe 同目录下的应用同名目录', () {
    final paths = ConfigPaths.resolve();
    expect(paths.dir.path,
        '${fakeExeDir.path}${Platform.pathSeparator}${ConfigPaths.dataDirName}');
    expect(paths.fallbackToAppData, isFalse);
    expect(paths.dir.existsSync(), isTrue);
    // 配置/状态/日志/运行文件都落在这里。
    expect(paths.configFile.parent.path, paths.dir.path);
    expect(paths.stateFile.parent.path, paths.dir.path);
    expect(paths.logFile.parent.path, paths.dir.path);
    expect(paths.runtimeFile.parent.path, paths.dir.path);
    expect(paths.imageDir.parent.path, paths.dir.path);
  });

  test('显式 --config 优先（传目录或 config.json 都认）', () {
    final byDir = ConfigPaths.resolve(override: temp.path);
    expect(byDir.dir.path, temp.path);
    final byFile = ConfigPaths.resolve(
        override: '${temp.path}${Platform.pathSeparator}config.json');
    expect(byFile.dir.path, temp.path);
  });

  test('老数据（%APPDATA%\\QuizSyncAI\\Server）会自动搬到新目录', () async {
    fakeLegacy.createSync(recursive: true);
    File('${fakeLegacy.path}${Platform.pathSeparator}config.json')
        .writeAsStringSync('{"api_key":"old"}');
    File('${fakeLegacy.path}${Platform.pathSeparator}state.json')
        .writeAsStringSync('{"device_id":"old-device"}');
    final images = Directory('${fakeLegacy.path}${Platform.pathSeparator}images')
      ..createSync();
    File('${images.path}${Platform.pathSeparator}abc.jpg').writeAsBytesSync([1, 2, 3]);

    final paths = ConfigPaths.resolve();
    await paths.migrateLegacyIfNeeded();

    expect(paths.configFile.existsSync(), isTrue);
    expect(paths.configFile.readAsStringSync(), contains('old'));
    expect(paths.stateFile.readAsStringSync(), contains('old-device'));
    expect(File('${paths.imageDir.path}${Platform.pathSeparator}abc.jpg').existsSync(),
        isTrue);
    // 老目录不删（用户自己决定要不要清理）。
    expect(fakeLegacy.existsSync(), isTrue);
  });

  test('新目录已经有数据时不搬（不覆盖用户正在用的数据）', () async {
    fakeLegacy.createSync(recursive: true);
    File('${fakeLegacy.path}${Platform.pathSeparator}config.json')
        .writeAsStringSync('{"api_key":"old"}');

    final paths = ConfigPaths.resolve();
    await paths.ensure();
    await paths.save(ServerConfig(apiKey: 'new'));
    await paths.migrateLegacyIfNeeded();

    expect(paths.configFile.readAsStringSync(), contains('new'));
    expect(paths.configFile.readAsStringSync(), isNot(contains('old')));
  });

  test('没有老数据时迁移是空操作', () async {
    final paths = ConfigPaths.resolve();
    await paths.migrateLegacyIfNeeded();
    expect(paths.configFile.existsSync(), isFalse);
  });
}
