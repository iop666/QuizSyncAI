import 'package:flutter/material.dart';
import 'package:quizsync_ui/quizsync_ui.dart';

/// 使用说明（M32 用户需求 5）：Windows 应用设置的**第一项**。
///
/// 只写这个应用**真的有**的能力与设置项：先说「可以用哪几种方式把题目交给它」，
/// 再逐项说明左侧每个设置分类是干什么的。写作口径与 README 一致 ——
/// 不写没做的功能（例如手机端没有内置拍照入口）。
class GuideSettingsPage extends StatelessWidget {
  const GuideSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: '使用说明',
      description: '先看「怎么把题目交给它」，再按下面的分类说明逐项设置。'
          '第一次使用建议按顺序：API 配置 → 连接设备 → 识别设置。',
      children: [
        SettingsGroup(
          title: '可识别的五种方式',
          icon: Icons.checklist_rtl,
          description: '识别结果都写进「当前合集」，并同步到已配对的手机。',
          showDividers: true,
          children: const [
            SettingsRow(
              icon: Icons.keyboard_outlined,
              title: '① 全局热键截屏（最常用）',
              subtitle: '默认 **F8**：截当前屏幕 → 自动识别。键被占用时会自动'
                  '换到备用键，真实生效的键显示在「热键设置」里。',
            ),
            SettingsRow(
              icon: Icons.bubble_chart_outlined,
              title: '② 桌面悬浮球',
              subtitle: '单击 = 截屏识别；左键长按 500ms 或右键 = 加一页（进入多页'
                  '识别）。球会吸附到屏幕左右边缘，截屏时自动隐藏。',
            ),
            SettingsRow(
              icon: Icons.dashboard_customize_outlined,
              title: '③ 桌面悬浮窗',
              subtitle: '贴在桌面上的结果小窗：窗内直接识别、加页、翻上一条/下一条、'
                  '调字号、重新识别，不用切回主窗口。',
            ),
            SettingsRow(
              icon: Icons.content_paste_search,
              title: '④ 剪贴板 / 拖入 / Ctrl+V',
              subtitle: '开启剪贴板监听后，复制一张图就会自动识别；也可以把图片文件'
                  '拖进主窗口，或在主窗口里按 Ctrl+V 粘贴。',
            ),
            SettingsRow(
              icon: Icons.phone_android,
              title: '⑤ 手机端上传',
              subtitle: '在「连接设备」里打开开关并完成配对后，手机悬浮球截屏或从相册'
                  '选图，都会送到这台电脑识别，两端同时显示结果。',
            ),
          ],
        ),
        SettingsGroup(
          title: '多页识别怎么用',
          icon: Icons.filter_none,
          description: '一套卷子/一本书需要截好几屏时用它：所有页作为**一次识别**'
              '提交，题目跨页也能对齐。',
          children: [
            SettingsRow(
              title: '开始与结束',
              subtitle: '加页：默认 **F9**（多页模式）——按第一下进入多页并抓第一张，'
                  '继续按接着加；也可以用悬浮球长按/右键、或悬浮窗的「多页识别」。\n'
                  '结束并上传：按默认 **F8**（截屏识别）即结束多页，把已抓的图一次'
                  '上传识别；悬浮球单击、悬浮窗的「结束多页识别」同样是这个动作。',
            ),
            SettingsRow(
              title: '页数上限',
              subtitle: '在「识别设置」里调（默认 6 页，硬上限 6 页）。抓满 6 张会'
                  '**自动上传识别**，不用再按键；没满就按 F8 结束并上传。',
            ),
            SettingsRow(
              title: '随时取消',
              subtitle: '悬浮窗的「取消多页」会丢掉暂存页、退出多页模式，不会上传；'
                  '识别进行中还能点最上层的「取消识别」中止这一次。',
            ),
          ],
        ),
        SettingsGroup(
          title: '各项设置怎么用',
          icon: Icons.tune,
          children: const [
            SettingsRow(
              icon: Icons.palette_outlined,
              title: '显示设置',
              subtitle: '主题三态（跟随系统/明亮/深色）、配色、题目字重、界面缩放'
                  '（50%–300%，窗口边界会跟着一起缩放）、剪贴板监听。',
            ),
            SettingsRow(
              icon: Icons.auto_awesome_outlined,
              title: 'API 配置',
              subtitle: '填 AI 服务的 API Key、模型和地址。默认 DeepSeek'
                  '（deepseek-flash）。Key 只存在这台电脑上（Windows DPAPI 加密）。',
            ),
            SettingsRow(
              icon: Icons.wifi_tethering,
              title: '连接设备',
              subtitle: '默认关闭。打开后软件才会启动局域网服务并申请网络权限，'
                  '然后扫码或用「配对链接」把手机配上；关掉后本页其余功能都不可用。',
            ),
            SettingsRow(
              icon: Icons.center_focus_strong_outlined,
              title: '识别设置',
              subtitle: '是否保存图片文件、本地图片缓存上限、多页上限、'
                  '「未识别到题目」时的行为。',
            ),
            SettingsRow(
              icon: Icons.bubble_chart_outlined,
              title: '悬浮球设置',
              subtitle: '悬浮球的开关、大小、透明度与描边（描边颜色跟随当前状态'
                  '主色：待识别=蓝 / 识别中=黄 / 多页=绿）。',
            ),
            SettingsRow(
              icon: Icons.select_all,
              title: '悬浮窗设置',
              subtitle: '悬浮窗的开关、置顶、位置锁定与归位、透明度、显示比例、'
                  '窗内字号、明暗模式与显示模式（默认模式 / 详细解析模式）。',
            ),
            SettingsRow(
              icon: Icons.keyboard_outlined,
              title: '热键设置',
              subtitle: '两个全局热键（截屏识别 / 多页模式）都能改，'
                  '并会显示每个键当前是否真的注册成功。停在本页时按键不会触发，'
                  '离开本页或切到别的程序立刻恢复。',
            ),
            SettingsRow(
              icon: Icons.folder_outlined,
              title: '数据管理',
              subtitle: '任务合集、导出（Markdown / JSON）、备份与恢复、'
                  '数据目录位置、导出日志。',
            ),
            SettingsRow(
              icon: Icons.info_outline,
              title: '关于',
              subtitle: '版本号、技术栈、GitHub 地址、开源许可与赞助支持。',
            ),
          ],
        ),
        const SettingsGroup(
          title: '常见问题',
          icon: Icons.help_outline,
          showDividers: true,
          children: [
            SettingsRow(
              title: '按了热键没反应？',
              subtitle: '先看「热键设置」里的真实注册状态：三个键都可能被别的程序'
                  '占用，占用时会自动回退到备用键。识别失败会把主窗口带到前台并写明原因。',
            ),
            SettingsRow(
              title: '悬浮球 / 悬浮窗不见了？',
              subtitle: '到「悬浮球设置」或「悬浮窗设置」确认开关是打开的；'
                  '两者的开关也在托盘右键菜单里。',
            ),
            SettingsRow(
              title: '手机连不上？',
              subtitle: '「连接设备」的开关要先打开；再确认手机与电脑在同一局域网、'
                  'Windows 防火墙放行 8765–8770 端口。',
            ),
          ],
        ),
      ],
    );
  }
}
