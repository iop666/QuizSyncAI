// 诊断脚本：逐个试注册 F1–F12，报告哪些键在本机可用（哪些已被别的程序占用）。
//
// 用途：默认热键要挑本机没被占用的键（用户实测 F7 被占用）。
// 每行的 err 是 Win32 错误码：1409 = ERROR_HOTKEY_ALREADY_REGISTERED（已被占用）。
//
// 运行：dart run tool/hotkey_selfcheck.dart
import 'dart:ffi';

void main() {
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final registerHotKey = user32.lookupFunction<
      Int32 Function(IntPtr, Int32, Uint32, Uint32),
      int Function(int, int, int, int)>('RegisterHotKey');
  final unregisterHotKey = user32.lookupFunction<
      Int32 Function(IntPtr, Int32),
      int Function(int, int)>('UnregisterHotKey');
  final setLastError =
      kernel32.lookupFunction<Void Function(Uint32), void Function(int)>(
          'SetLastError');
  final getLastError =
      kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  final free = <String>[];
  final taken = <String>[];

  // 一次只试一个：注册成功就立刻注销，不影响后面的判断。
  for (var i = 1; i <= 12; i++) {
    final vk = 0x70 + i - 1;
    setLastError(0);
    final ok = registerHotKey(0, 1, 0, vk) != 0;
    final err = ok ? 0 : getLastError();
    print('F$i (vk=0x${vk.toRadixString(16)}) -> ${ok ? '可用' : '不可用 err=$err'}');
    if (ok) {
      free.add('F$i');
      setLastError(0);
      unregisterHotKey(0, 1);
    } else {
      taken.add('F$i');
    }
  }
  print('');
  print('本机可用：${free.join(' ')}');
  print('被占用：${taken.join(' ')}');
}
