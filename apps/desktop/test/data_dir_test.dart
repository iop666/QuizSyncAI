import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:quizsync_desktop/main.dart'
    show resolveDataDir, kPortableDataDirName;

/// 用户反馈 10：应用产生的数据默认放在**应用所在目录**下，
/// 只在「应用目录不可写」或「有旧版本数据」时才退到系统数据目录。
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('qs-datadir-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('默认落在 <exe 目录>/userdata 下，并且目录真的建出来了', () async {
    final exe = Directory('${tmp.path}/app')..createSync(recursive: true);
    final dir = await resolveDataDir(
      exeDir: exe.path,
      legacyDir: '${tmp.path}/legacy',
    );
    expect(dir, '${exe.path}${Platform.pathSeparator}$kPortableDataDirName');
    expect(Directory(dir).existsSync(), isTrue);
  });

  test('数据目录不叫 data（那是 Flutter 引擎载荷目录，混用会把 app.so 删掉）', () {
    expect(kPortableDataDirName, isNot('data'));
  });

  test('旧版本的库存在时，先把旧数据搬进应用目录再照常用它（升级不丢历史）', () async {
    final exe = Directory('${tmp.path}/app2')..createSync(recursive: true);
    final legacy = Directory('${tmp.path}/legacy2')..createSync(recursive: true);
    File('${legacy.path}${Platform.pathSeparator}quizsync.db')
        .writeAsStringSync('sqlite');
    final images =
        Directory('${legacy.path}${Platform.pathSeparator}images')
          ..createSync(recursive: true);
    File('${images.path}${Platform.pathSeparator}abc.jpg')
        .writeAsStringSync('jpeg');

    final dir = await resolveDataDir(exeDir: exe.path, legacyDir: legacy.path);
    final portable =
        '${exe.path}${Platform.pathSeparator}$kPortableDataDirName';
    expect(dir, portable, reason: '搬完就用应用目录，而不是继续用旧目录');
    expect(
        File('$portable${Platform.pathSeparator}quizsync.db').readAsStringSync(),
        'sqlite',
        reason: '库必须搬过来');
    expect(
        File('$portable${Platform.pathSeparator}images'
                '${Platform.pathSeparator}abc.jpg')
            .existsSync(),
        isTrue,
        reason: '图片一起搬');
    expect(Directory(legacy.path).existsSync(), isTrue,
        reason: '旧目录只是复制、不删除，留个后路');
  });

  test('新目录已经有库时不再回退到旧目录（用户已经迁移过来了）', () async {
    final exe = Directory('${tmp.path}/app3')..createSync(recursive: true);
    final portable =
        Directory('${exe.path}${Platform.pathSeparator}$kPortableDataDirName')
          ..createSync(recursive: true);
    File('${portable.path}${Platform.pathSeparator}quizsync.db')
        .writeAsStringSync('sqlite');
    final legacy = Directory('${tmp.path}/legacy3')..createSync(recursive: true);
    File('${legacy.path}${Platform.pathSeparator}quizsync.db')
        .writeAsStringSync('sqlite');

    final dir = await resolveDataDir(exeDir: exe.path, legacyDir: legacy.path);
    expect(dir, portable.path);
  });

  test('旧目录没有库（新用户）时直接用应用目录，不做无谓的搬迁', () async {
    final exe = Directory('${tmp.path}/app5')..createSync(recursive: true);
    final legacy = Directory('${tmp.path}/legacy5')..createSync(recursive: true);
    File('${legacy.path}${Platform.pathSeparator}secure.bin')
        .writeAsStringSync('x');

    final dir = await resolveDataDir(exeDir: exe.path, legacyDir: legacy.path);
    expect(dir, '${exe.path}${Platform.pathSeparator}$kPortableDataDirName');
    expect(File('${legacy.path}${Platform.pathSeparator}secure.bin').existsSync(),
        isTrue);
  });

  test('搬迁失败（新目录建不出来）时退回旧目录，绝不丢数据', () async {
    final exe = Directory('${tmp.path}/app6')..createSync(recursive: true);
    final legacy = Directory('${tmp.path}/legacy6')..createSync(recursive: true);
    File('${legacy.path}${Platform.pathSeparator}quizsync.db')
        .writeAsStringSync('sqlite');
    // 用一个同名**文件**占住 `userdata`，搬迁时 target.create() 必然失败。
    File('${exe.path}${Platform.pathSeparator}$kPortableDataDirName')
        .writeAsStringSync('occupied');

    final dir = await resolveDataDir(exeDir: exe.path, legacyDir: legacy.path);
    expect(dir, legacy.path, reason: '搬不过去就继续用旧的，宁可位置不理想也不能丢数据');
  });

  test('应用目录不可写时退回系统数据目录（安装到 Program Files 的情形）', () async {
    // 用一个「父路径是文件」的非法目录名模拟不可写。
    final blocker = File('${tmp.path}/blocked')..writeAsStringSync('x');
    final legacy = Directory('${tmp.path}/legacy4')..createSync(recursive: true);
    final dir = await resolveDataDir(
      exeDir: '${blocker.path}/nope',
      legacyDir: legacy.path,
    );
    expect(dir, legacy.path, reason: '不能因为写不进去就让整个应用起不来');
  });
}
