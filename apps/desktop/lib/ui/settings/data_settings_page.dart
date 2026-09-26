import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quizsync_core/quizsync_core.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

import '../../services/shell_open.dart';
import '../../state/collections.dart';
import '../collection_export.dart';
import '../collection_picker_page.dart';
import '../home_page.dart' show dataRootProvider;
import 'settings_actions.dart';

/// 数据管理（M9）：任务集合、导出、备份与日志。
/// 原来的「任务合集」与「数据」两张卡片的内容按语义重新分组；
/// 涉及覆盖/吊销/导出的动作仍全部带二次确认。
class DataSettingsPage extends ConsumerStatefulWidget {
  const DataSettingsPage({super.key});

  @override
  ConsumerState<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends ConsumerState<DataSettingsPage> {
  /// 选中的「要导出的合集」；null = 跟随当前选中的合集。
  String? _exportCollectionId;

  @override
  Widget build(BuildContext context) {
    final collections =
        ref.watch(collectionsProvider).valueOrNull ?? const <Collection>[];
    final activeId = ref.watch(activeCollectionIdProvider);
    final active = ref.watch(activeCollectionProvider);
    final dataRoot = ref.read(dataRootProvider);

    // 默认导出当前选中的合集；选中项已消失时退回第一个。
    var exportId = _exportCollectionId ?? activeId;
    if (exportId == null || !collections.any((c) => c.collectionId == exportId)) {
      exportId = collections.isEmpty ? null : collections.first.collectionId;
    }
    final exportTarget = exportId == null
        ? null
        : collections.firstWhere((c) => c.collectionId == exportId);

    return SettingsSection(
      title: '数据管理',
      description: '任务集合、导出与备份。数据默认就在软件所在目录下，'
          '导出时会让你自己选保存位置（默认也指向该目录）。',
      children: [
        SettingsGroup(
          title: '任务集合',
          icon: Icons.folder_outlined,
          children: [
            SettingsRow(
              title: '当前集合',
              subtitle:
                  active == null ? '未选择合集' : '当前合集：${active.name}',
              info: '每次打开程序都要重新选一次合集：识别结果都记在当前合集里，'
                  '手机端的历史也按合集分组；没选合集时不能开始识别。',
              trailing: OutlinedButton.icon(
                key: const ValueKey('settings-switch-collection'),
                onPressed: () => showCollectionPicker(context, ref),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('切换任务合集…'),
              ),
            ),
            SettingsField(
              title: '按合集导出',
              subtitle: '识别结果按识别顺序生成 Markdown 与 JSON；点导出后可自己选保存位置',
              maxWidth: 560,
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      key: const ValueKey('settings-export-collection-pick'),
                      isExpanded: true,
                      value: exportId,
                      hint: const Text('（还没有合集，先新建一个）'),
                      items: [
                        for (final c in collections)
                          DropdownMenuItem(
                              value: c.collectionId, child: Text(c.name)),
                      ],
                      onChanged:
                          collections.isEmpty ? null : (v) => setState(() => _exportCollectionId = v),
                    ),
                  ),
                  const SizedBox(width: SettingsGap.s16),
                  FilledButton.tonalIcon(
                    key: const ValueKey('settings-export-collection'),
                    onPressed: exportTarget == null
                        ? null
                        : () => exportCollection(
                              context,
                              ref,
                              collection: exportTarget,
                              dataRoot: dataRoot,
                            ),
                    icon: const Icon(Icons.ios_share_outlined, size: 18),
                    label: const Text('导出集合'),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: '数据与备份',
          icon: Icons.backup_outlined,
          children: [
            SettingsTile(
              key: const ValueKey('settings-backup'),
              icon: Icons.backup_outlined,
              title: '一键备份',
              subtitle: '数据库 + 图片打包成 zip，存到数据目录 backups/ 下',
              onTap: () => backupNow(ref, context),
            ),
            SettingsTile(
              key: const ValueKey('settings-restore'),
              icon: Icons.restore,
              title: '从最近备份恢复',
              subtitle: '恢复前自动为当前数据留底；数据库被占用时下次启动生效',
              onTap: () => restoreFromLatestBackup(ref, context),
            ),
            SettingsRow(
              title: '导出全部历史',
              subtitle: '全部识别记录，按识别顺序；导出时可选保存位置',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    key: const ValueKey('settings-export-all-md'),
                    onPressed: () =>
                        exportAllHistory(ref, context, markdown: true),
                    child: const Text('Markdown'),
                  ),
                  const SizedBox(width: SettingsGap.s8),
                  OutlinedButton(
                    key: const ValueKey('settings-export-all-json'),
                    onPressed: () =>
                        exportAllHistory(ref, context, markdown: false),
                    child: const Text('JSON'),
                  ),
                ],
              ),
            ),
            SettingsTile(
              key: const ValueKey('settings-export-log'),
              icon: Icons.article_outlined,
              title: '导出日志',
              subtitle: '不含 API Key 与 Token',
              onTap: () => exportLogFile(ref, context),
            ),
          ],
        ),
        SettingsGroup(
          title: '数据位置',
          icon: Icons.storage_outlined,
          children: [
            SettingsRow(
              title: '应用数据目录',
              subtitle: dataRoot,
              info: '应用产生的图片、数据库、备份、导出、日志都放在'
                  '**软件所在目录**下的 userdata\\ 里（便携版拷走整个文件夹 = 数据一起走；'
                  '不叫 data 是因为那个目录属于程序自己的引擎文件）。'
                  '安装到 Program Files 这类只读位置时会自动退回系统数据目录，'
                  '这里的路径永远是当前真实生效的位置。',
              trailing: Wrap(
                spacing: SettingsGap.s8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('settings-open-data-root'),
                    onPressed: () => revealFolder(dataRoot),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('打开目录'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('settings-copy-data-root'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: dataRoot));
                      messenger.showSnackBar(
                          const SnackBar(content: Text('数据目录路径已复制')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制路径'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SettingsNote(
          text: '恢复会覆盖当前数据、吊销会让手机的 token 立即失效：这两类操作都会先弹确认框。',
        ),
      ],
    );
  }
}
