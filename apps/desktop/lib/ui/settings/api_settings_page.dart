import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../services/shell_open.dart';
import '../../state/app_scope.dart';
import '../privacy_dialog.dart';

/// API 配置（M9）：AI 服务、API Key、模型与调用限制。
/// 原来的「AI 服务」整块搬到这里，功能与落库逻辑完全不变。
class ApiSettingsPage extends ConsumerStatefulWidget {
  const ApiSettingsPage({super.key});

  /// DeepSeek 开放平台的 Key 申请页（M17 第 6 条：把推荐地址写在 API Key 下面）。
  static const String deepSeekKeysUrl =
      'https://platform.deepseek.com/api_keys';

  @override
  ConsumerState<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends ConsumerState<ApiSettingsPage> {
  late TextEditingController _modelCtrl;
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _keyCtrl;

  /// Key 的尾 4 位（只回显这 4 位，明文永远不落到界面与数据库）。
  String? _keyTail;
  bool _keyLoaded = false;

  /// Key 输入框默认遮挡；这里是「显示我刚输入的内容」的开关，
  /// 保存成功后输入框即清空，不会长期明文展示。
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    final ai = ref.read(settingsProvider).ai;
    _modelCtrl = TextEditingController(text: ai.model);
    _baseUrlCtrl = TextEditingController(text: ai.baseUrl);
    _keyCtrl = TextEditingController();
    _loadKeyTail();
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKeyTail() async {
    final key = await ref.read(apiKeyReaderProvider)();
    if (!mounted) return;
    setState(() {
      _keyTail =
          (key != null && key.length >= 4) ? key.substring(key.length - 4) : null;
      _keyLoaded = true;
    });
  }

  /// 保存 API Key（点保存按钮或在该输入框内按回车触发）。
  ///
  /// M34 第 1 条：**隐私告知只在「首次保存 API Key」时提示一次**。
  /// 识别流程里不再弹它（那时用户已经在别的应用里，弹窗既打断又容易被忽略）；
  /// 「暂不使用」= 不保存这个 Key，用户看到告知后可以再决定。
  Future<void> _saveKey() async {
    final v = _keyCtrl.text.trim();
    final settings = ref.read(settingsProvider);
    if (v.isNotEmpty && !settings.privacyAcknowledged) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PrivacyDialog(),
      );
      if (!mounted) return;
      if (ok != true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('未确认隐私告知，API Key 没有保存'),
          duration: Duration(seconds: 3),
        ));
        return;
      }
      await settings.acknowledgePrivacy();
    }
    try {
      await ref.read(apiKeyWriterProvider)(v);
      await _loadKeyTail();
      if (!mounted) return;
      setState(() {
        _keyCtrl.clear();
        _revealed = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v.isEmpty ? 'API Key 已清除' : 'API Key 已保存'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  Future<void> _saveAi(AiUiSettings v) async {
    await ref.read(settingsProvider).updateAi(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ai = ref.watch(settingsProvider).ai;
    final usage = ref.watch(usageTodayProvider).value ?? 0;

    return SettingsSection(
      title: 'API 配置',
      description: '默认已按 DeepSeek 填好模型名与地址（deepseek-flash），'
          '通常只要粘一个 API Key 就能用。'
          'API Key 用 Windows DPAPI 加密保存在本机，界面上只回显尾 4 位。',
      children: [
        SettingsGroup(
          title: 'AI 服务',
          icon: Icons.auto_awesome_outlined,
          children: [
            SettingsField(
              title: 'Provider',
              subtitle: 'OpenAI 兼容接口同时覆盖 DashScope / GLM-4V / DeepSeek 等',
              maxWidth: 420,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('settings-provider'),
                initialValue: ai.providerId,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(
                      value: 'openai-compatible',
                      child: Text('OpenAI 兼容（默认）')),
                  DropdownMenuItem(
                      value: 'anthropic', child: Text('Anthropic Claude')),
                  DropdownMenuItem(
                      value: 'gemini', child: Text('Google Gemini')),
                ],
                onChanged: (v) => _saveAi(ai.copyWith(providerId: v)),
              ),
            ),
            SettingsField(
              title: 'API Key',
              subtitle: _keyLoaded
                  ? (_keyTail == null ? '未设置' : '已设置（尾 4 位 ****$_keyTail）')
                  : '读取中…',
              info: '用 Windows DPAPI 加密后存在本机数据目录，界面只回显尾 4 位；'
                  '保存成功后输入框立刻清空，不会长期明文显示。'
                  '点输入框右侧的眼睛可以临时看一眼这次输入的内容。',
              maxWidth: 480,
              child: TextFormField(
                key: const ValueKey('settings-api-key'),
                controller: _keyCtrl,
                obscureText: !_revealed,
                decoration: InputDecoration(
                  hintText: 'sk-…',
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 88, minHeight: 40),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('settings-api-key-reveal'),
                        tooltip: _revealed ? '隐藏输入内容' : '显示输入内容',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                            _revealed
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18),
                        onPressed: () => setState(() => _revealed = !_revealed),
                      ),
                      IconButton(
                        key: const ValueKey('settings-api-key-save'),
                        tooltip: '保存 API Key（点击或在该输入框内按回车）',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        onPressed: _saveKey,
                      ),
                    ],
                  ),
                ),
                onFieldSubmitted: (_) => _saveKey(),
              ),
            ),
            // M17 第 6 条（用户要求）：API Key 这一项下面直接给出去哪儿申请。
            SettingsRow(
              key: const ValueKey('settings-api-key-recommend'),
              title: '推荐用 DeepSeek 的 API',
              subtitle: ApiSettingsPage.deepSeekKeysUrl,
              info: '申请入口：${ApiSettingsPage.deepSeekKeysUrl}\n'
                  '本项目的默认模型（deepseek-flash）与默认 Base URL '
                  '就是 DeepSeek 官方的，填上 Key 就能直接用。',
              trailing: TextButton.icon(
                key: const ValueKey('settings-open-deepseek-keys'),
                onPressed: () => openExternal(ApiSettingsPage.deepSeekKeysUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('去申请 Key'),
              ),
            ),
            SettingsField(
              title: '模型名称',
              subtitle: '必须是能看图的多模态模型；默认已填 DeepSeek 的 deepseek-flash',
              info: 'DeepSeek：deepseek-flash（支持图片输入，官方推荐默认值）；'
                  '也可以换成 gpt-4o-mini / qwen-vl-max / glm-4v-plus 等。'
                  '模型名要与上面选的 Provider 配套，填错会返回 404 或 400。',
              maxWidth: 420,
              child: TextFormField(
                key: const ValueKey('settings-model'),
                controller: _modelCtrl,
                decoration: const InputDecoration(
                    hintText: AiUiSettings.defaultModel),
                onChanged: (v) => _saveAi(ai.copyWith(model: v.trim())),
              ),
            ),
            SettingsField(
              title: 'Base URL',
              subtitle: '默认已填 DeepSeek 官方地址；留空使用该服务的默认地址',
              info: '本项目会在结尾拼上 `/chat/completions`（OpenAI 兼容格式）。'
                  'DeepSeek 官方地址：${AiUiSettings.defaultBaseUrl}',
              maxWidth: 480,
              child: TextFormField(
                key: const ValueKey('settings-base-url'),
                controller: _baseUrlCtrl,
                decoration: const InputDecoration(
                    hintText: AiUiSettings.defaultBaseUrl),
                onChanged: (v) => _saveAi(ai.copyWith(baseUrl: v.trim())),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '高级设置',
          icon: Icons.tune,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SettingsField(
                    title: '请求超时',
                    maxWidth: 220,
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('settings-timeout'),
                      initialValue: ai.timeoutSeconds,
                      decoration: const InputDecoration(suffixText: '秒'),
                      items: const [30, 60, 90, 120, 180]
                          .map((v) => DropdownMenuItem(
                              value: v, child: Text('$v')))
                          .toList(),
                      onChanged: (v) =>
                          _saveAi(ai.copyWith(timeoutSeconds: v ?? 90)),
                    ),
                  ),
                ),
                Expanded(
                  child: SettingsField(
                    title: '每日调用上限',
                    maxWidth: 220,
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('settings-daily-limit'),
                      initialValue: ai.dailyLimit,
                      decoration: InputDecoration(
                          suffixText: ai.dailyLimit <= 0 ? null : '次'),
                      // M44 第 2 条（用户要求）：可以「不设上限」（存 0）。
                      items: const [0, 50, 100, 200, 500, 1000]
                          .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v == 0 ? '不设上限' : '$v')))
                          .toList(),
                      onChanged: (v) =>
                          _saveAi(ai.copyWith(dailyLimit: v ?? 200)),
                    ),
                  ),
                ),
              ],
            ),
            SettingsField(
              title: '今日用量',
              subtitle: ai.dailyLimit <= 0
                  ? '不含缓存命中；当前**不设上限**，用量只做统计'
                  : '不含缓存命中',
              maxWidth: 480,
              child: Row(
                children: [
                  SettingsProgressBar(
                    value: ai.dailyLimit <= 0 ? 0 : usage / ai.dailyLimit,
                  ),
                  const SizedBox(width: SettingsGap.s16),
                  Text(
                    ai.dailyLimit <= 0
                        ? '$usage 次'
                        : '$usage / ${ai.dailyLimit} 次',
                    key: const ValueKey('settings-usage'),
                    style: SettingsType.value(scheme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
