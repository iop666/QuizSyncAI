/// 应用身份常量（M9「关于」页用）。
///
/// 版本号与 `apps/desktop/pubspec.yaml` 的 `version:` 保持一致——
/// 发布脚本 `tools/package_windows.ps1` 也用同一个号命名安装包与便携版。
/// 这里不引入 package_info_plus：为一个字符串再加一个平台插件不值得。
library;

/// 应用**显示名**（M17 第 2 条：中文名）。窗口标题、托盘提示、关于页、
/// 安装包与快捷方式都用它。
const String kAppName = 'AI 双端搜题';

/// 项目名（GitHub 仓库名与代码里的包名保持英文，便于检索）。
const String kAppNameEn = 'QuizSync AI';

/// 项目地址（M17 第 3 条：关于页要标明）。
const String kGitHubUrl = 'https://github.com/iop666/QuizSyncAI';

/// 赞助支持地址（M46 第 3 条：用户要求填自己的爱发电主页）。
///
/// 放在「关于」页最下面；原来那个独立的「赞助」页（微信/支付宝收款码图片）
/// 已按用户要求**整页连图片一起删除**。
const String kSponsorUrl = 'https://afdian.com/a/iop666';

/// 语义化版本（pubspec 里是 `1.1.0+30`，`+30` 只是**出包序号**，不是产品版本）。
///
/// M18 第 1 条（用户原话：「关于不要写构建 8，这就是 1.0.0 正式版，前面全是
/// 预览版」）：**界面上只显示版本号**，不再出现「（构建 N）」。出包序号只留
/// 在 pubspec 与打包脚本里，用来保证安装包能覆盖升级。
///
/// M46 第 4 条：双端统一到 **1.1.0**（电脑端从 1.1.3 归位、手机端从 1.0.0 升上来）。
/// M50：1.1.0 之后的修复线从 **1.2.0** 起，第三个数字每出一个包 +1（不设上限）。
const String kAppVersion = '1.2.1';

const String kAppTagline = '局域网内的跨端 AI 搜题工具';

/// 一句话能力说明（关于页副标题）。
const String kAppSummary = 'Windows 截屏 → 多模态 AI 识别题目并给出答案与解析 → 结果同步到手机。';
