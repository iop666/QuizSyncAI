import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// _cryptProtectUiForbidden（win32 包未导出，本地定义）。
const _cryptProtectUiForbidden = 0x1;

/// Windows 安全存储：DPAPI（CryptProtectData，当前用户作用域）加密整个
/// 键值表后落盘。等价于 flutter_secure_storage 在 Windows 上的 DPAPI 行为；
/// 因该插件的 C++ 实现需要 ATL 头而本机 VS 生成工具未含 ATL 组件
/// （守则禁止安装），改为 win32 直连。密钥绝不进明文 SQLite / 日志。
class WindowsSecureStore {
  final File _file;

  WindowsSecureStore(String path) : _file = File(path);

  Future<void> _ensureDir() async {
    await _file.parent.create(recursive: true);
  }

  Future<Map<String, String>> _readAll() async {
    if (!await _file.exists()) return {};
    try {
      final plain = _unprotect(Uint8List.fromList(await _file.readAsBytes()));
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is Map<String, dynamic>) {
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {
      // 损坏或换了用户上下文：按空表处理。
    }
    return {};
  }

  Future<void> _writeAll(Map<String, String> map) async {
    await _ensureDir();
    final blob = _protect(utf8.encode(jsonEncode(map)));
    await _file.writeAsBytes(blob, flush: true);
  }

  Future<String?> read(String key) async => (await _readAll())[key];

  Future<void> write(String key, String value) async {
    final map = await _readAll();
    map[key] = value;
    await _writeAll(map);
  }

  Future<void> delete(String key) async {
    final map = await _readAll();
    map.remove(key);
    await _writeAll(map);
  }

  // ---- DPAPI ----

  Uint8List _protect(List<int> data) {
    return using((arena) {
      final inBlob = arena<CRYPT_INTEGER_BLOB>()
        ..ref.cbData = data.length
        ..ref.pbData = arena<Uint8>(data.length);
      final src = inBlob.ref.pbData.cast<Uint8>().asTypedList(data.length);
      src.setAll(0, data);

      final outBlob = arena<CRYPT_INTEGER_BLOB>();
      final ok = CryptProtectData(inBlob, nullptr, nullptr, nullptr, nullptr,
          _cryptProtectUiForbidden, outBlob);
      if (ok == 0) {
        throw StateError('CryptProtectData failed: ${GetLastError()}');
      }
      final out =
          Uint8List.fromList(outBlob.ref.pbData.cast<Uint8>().asTypedList(outBlob.ref.cbData));
      // M47：还给系统**之前**先清零（顺序不能反：LocalFree 之后这块内存已经不归我们）。
      outBlob.ref.pbData
          .cast<Uint8>()
          .asTypedList(outBlob.ref.cbData)
          .fillRange(0, outBlob.ref.cbData, 0);
      LocalFree(outBlob.ref.pbData);
      // arena 里那份明文副本也清掉。
      src.fillRange(0, data.length, 0);
      return out;
    });
  }

  Uint8List _unprotect(Uint8List data) {
    return using((arena) {
      final inBlob = arena<CRYPT_INTEGER_BLOB>()
        ..ref.cbData = data.length
        ..ref.pbData = arena<Uint8>(data.length);
      inBlob.ref.pbData.cast<Uint8>().asTypedList(data.length).setAll(0, data);

      final outBlob = arena<CRYPT_INTEGER_BLOB>();
      final ok = CryptUnprotectData(inBlob, nullptr, nullptr, nullptr,
          nullptr, _cryptProtectUiForbidden, outBlob);
      if (ok == 0) {
        throw StateError('CryptUnprotectData failed: ${GetLastError()}');
      }
      final out =
          Uint8List.fromList(outBlob.ref.pbData.cast<Uint8>().asTypedList(outBlob.ref.cbData));
      // M47：把明文缓冲清干净再还给系统（同机其他进程本来就能解 secure.bin，
      // 这里只是不给「顺手扫进程内存」留窗口）。
      outBlob.ref.pbData
          .cast<Uint8>()
          .asTypedList(outBlob.ref.cbData)
          .fillRange(0, outBlob.ref.cbData, 0);
      LocalFree(outBlob.ref.pbData);
      return out;
    });
  }
}
