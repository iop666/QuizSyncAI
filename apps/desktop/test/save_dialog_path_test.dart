import 'package:flutter_test/flutter_test.dart';
import 'package:quizsync_desktop/services/shell_open.dart';

/// 用户反馈 2（M12）：「所有导出全部失败，Windows 端不会弹出系统另存为」。
///
/// 实测真凶不是对话框本身（它有弹出来），而是**预填路径混用了正反斜杠**：
/// `Directory('$root/exports')` / `'$root/logs'` 会留下正斜杠，
/// `GetSaveFileNameW` 因此以 `CommDlgExtendedError = 0x3002`
/// （FNERR_INVALIDFILENAME）立刻返回 0。旧代码把「返回 0」一律当成
/// 「用户取消」，于是既没有对话框、也没有任何提示。
void main() {
  group('另存为路径归一化（用户反馈 2 的回归）', () {
    test('正斜杠全部换成反斜杠', () {
      expect(normalizeForDialog(r'D:\app\userdata/exports'),
          r'D:\app\userdata\exports');
      expect(normalizeForDialog('D:/app/userdata/exports'),
          r'D:\app\userdata\exports');
      expect(normalizeForDialog(r'D:\a\b/c/d'), r'D:\a\b\c\d');
    });

    test('结尾多余的分隔符去掉（但盘符根保留）', () {
      expect(normalizeForDialog(r'D:\app\exports\'), r'D:\app\exports');
      expect(normalizeForDialog('D:/app/exports/'), r'D:\app\exports');
      expect(normalizeForDialog(r'C:\'), r'C:\');
    });

    test('只有反斜杠的路径原样返回（幂等）', () {
      const p = r'D:\app\userdata\exports';
      expect(normalizeForDialog(p), p);
      expect(normalizeForDialog(normalizeForDialog(p)), p);
    });

    test('数据目录拼接出来的默认目录归一化后不含正斜杠', () {
      // 这三个导出入口真实拼出来的形态：Directory('$root/exports') 之类。
      for (final raw in [
        r'D:\proj\rel\userdata/exports',
        r'C:\Users\me\AppData\Roaming\quizsync/logs',
        r'\\server\share\userdata/exports',
      ]) {
        expect(normalizeForDialog(raw), isNot(contains('/')),
            reason: '$raw 归一化后仍带正斜杠');
      }
    });
  });

  group('CommDlgExtendedError 错误码文案', () {
    test('0 = 用户取消，不当作错误', () {
      expect(commDlgErrorMessage(0), '用户取消');
    });

    test('0x3002 = FNERR_INVALIDFILENAME（本轮真凶）', () {
      expect(commDlgErrorMessage(0x3002), contains('FNERR_INVALIDFILENAME'));
    });

    test('未知错误码给出十六进制，便于查', () {
      expect(commDlgErrorMessage(0x1234), contains('0x1234'));
    });
  });
}
