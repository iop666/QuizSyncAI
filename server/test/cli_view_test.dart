import 'package:quizsync_server/src/constants.dart';
import 'package:quizsync_server/src/qr_terminal.dart';
import 'package:quizsync_server/src/status_panel.dart';
import 'package:test/test.dart';

void main() {
  group('CLI 状态块（中文、紧凑、不刷屏）', () {
    final view = StatusView(
      running: true,
      ip: '192.168.1.100',
      port: 8765,
      pairingCode: '582931',
      providerLabel: 'DeepSeek / OpenAI 兼容',
      model: 'deepseek-flash',
      aiConfigured: true,
      captureLabel: 'F8 · 备用 Alt+Shift+Q',
      multipageLabel: 'F9 · 备用 Alt+Shift+W',
      dataDir: r'D:\srv\data',
    );

    test('包含需求要求的信息（都是中文标注）', () {
      final text = renderStatusLines(view).join('\n');
      expect(text, contains('$kServerProductName v$kServerVersion'));
      expect(text, contains('服务器'));
      expect(text, contains('运行中'));
      expect(text, contains('192.168.1.100:8765'));
      expect(text, contains('手机'));
      expect(text, contains('等待配对'));
      expect(text, contains('配对码 582931'));
      expect(text, contains('AI'));
      expect(text, contains('已配置'));
      expect(text, contains('deepseek-flash'));
      expect(text, contains('截屏识别'));
      expect(text, contains('F8 · 备用 Alt+Shift+Q'));
      expect(text, contains('多页模式'));
      expect(text, contains('F9 · 备用 Alt+Shift+W'));
      expect(text, contains(r'D:\srv\data'));
    });

    test('没配 AI / 没连手机时如实反映', () {
      final text = renderStatusLines(StatusView(
        running: true,
        ip: '10.0.0.2',
        port: 8766,
        pairingCode: '111111',
        providerLabel: 'DeepSeek / OpenAI 兼容',
        model: 'deepseek-flash',
        aiConfigured: false,
        captureLabel: 'F8(未生效)',
        multipageLabel: 'F9(未生效)',
      )).join('\n');
      expect(text, contains('未配置'));
      expect(text, contains('等待配对'));
      expect(text, contains('未生效'));
    });

    test('手机连上后状态行跟着变', () {
      final text = renderStatusLines(StatusView(
        running: true,
        ip: '10.0.0.2',
        port: 8765,
        pairingCode: '111111',
        connectedDevices: const ['Android 手机'],
        providerLabel: 'DeepSeek / OpenAI 兼容',
        model: 'deepseek-flash',
        aiConfigured: true,
        captureLabel: 'F8 · 备用 Alt+Shift+Q',
        multipageLabel: 'F9 · 备用 Alt+Shift+W',
      )).join('\n');
      expect(text, contains('已连接'));
      expect(text, contains('Android 手机'));
      expect(text, isNot(contains('等待配对')));
    });

    test('多页模式下多显示一行「已抓 N/6 张」', () {
      final text = renderStatusLines(StatusView(
        running: true,
        ip: '10.0.0.2',
        port: 8765,
        pairingCode: '111111',
        providerLabel: 'DeepSeek / OpenAI 兼容',
        model: 'deepseek-flash',
        aiConfigured: true,
        captureLabel: 'F8',
        multipageLabel: 'F9',
        pendingPages: 3,
      )).join('\n');
      expect(text, contains('已抓 3/6 张'));
      expect(text, contains('按识别键立即上传识别'));
    });

    test('不在多页模式时不显示多页那行', () {
      expect(renderStatusLines(view).join('\n'), isNot(contains('已抓')));
    });
  });

  group('配对二维码', () {
    test('内容是 protocol.md 2.1 的 quizsync://pair 链接', () {
      final payload = pairQrPayload(
        host: '192.168.1.23',
        port: 8765,
        code: '482913',
        serverDeviceId: 'abc-123',
      );
      expect(payload,
          'quizsync://pair?host=192.168.1.23&port=8765&code=482913&sid=abc-123&v=1');
    });

    test('渲染出的半块字符行是方形且深浅都有', () {
      final lines = renderQrLines(
        pairQrPayload(
          host: '192.168.1.23',
          port: 8765,
          code: '482913',
          serverDeviceId: 'abc-123',
        ),
      );
      expect(lines.length, greaterThan(10));
      final widths = lines.map((l) => '\u2580'.allMatches(l).length).toSet();
      expect(widths.length, 1);
      expect(lines.first, contains('\x1b['));
      expect(lines.every((l) => l.endsWith('\x1b[0m')), isTrue);
      expect(lines.join(), contains('\x1b[30;40m'));
    });

    test('useAnsi=false 时退化成块字符，宽度按两个字符算', () {
      final lines =
          renderQrLines('quizsync://pair?host=x&port=1&code=1&sid=y&v=1', useAnsi: false);
      expect(lines.first.contains('\x1b'), isFalse);
      final widths = lines.map((l) => l.length).toSet();
      expect(widths.length, 1);
    });
  });
}
