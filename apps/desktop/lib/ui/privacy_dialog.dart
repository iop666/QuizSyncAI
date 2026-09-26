import 'package:flutter/material.dart';

/// 首次启动隐私告知（SPEC §10）：
/// 图片会上传到用户自己配置的第三方 AI 服务，确认后才允许第一次分析。
class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('隐私告知'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('使用本工具搜题时，截图会被上传到你在设置中配置的第三方 AI 服务进行分析。'),
          SizedBox(height: 12),
          Text('· API Key 只保存在本机（Windows DPAPI 加密），不会同步到手机端'),
          Text('· 屏幕截图中可能包含个人信息，请注意截取内容'),
          Text('· 可在设置中关闭「保存图片文件」，只保留文本结果'),
          SizedBox(height: 12),
          Text('答案由 AI 生成，仅供参考。'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暂不使用'),
        ),
        FilledButton(
          key: const ValueKey('privacy-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('我已知晓，开始使用'),
        ),
      ],
    );
  }
}
