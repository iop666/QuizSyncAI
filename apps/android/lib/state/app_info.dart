/// 应用身份常量（安卓端）。
///
/// 与 `apps/android/pubspec.yaml` 的 `version:` 保持一致。
///
/// M18 第 1 条（用户原话：「关于不要写构建 8，这就是 1.0.0 正式版，前面全是
/// 预览版」）：**界面上一律只显示版本号**，不再出现「（构建 N）」。
/// 出包序号（pubspec 的 `1.1.0+N`）只用来保证 `versionCode` 只增不减、
/// 新包能覆盖安装，不进任何界面文案。
///
/// M46 第 4 条：双端统一到 **1.1.0**（安卓端从 1.0.0 升上来）。
/// M50：1.1.0 之后的修复线从 **1.2.0** 起，第三个数字每出一个包 +1（不设上限）。
library;

const String kAppName = 'AI 双端搜题';

/// 项目名（GitHub 仓库名与包名保持英文）。
const String kAppNameEn = 'QuizSync AI';

/// 项目地址（M17 第 3 条：关于页要标明）。
const String kGitHubUrl = 'https://github.com/iop666/QuizSyncAI';

const String kAppVersion = '1.2.1';
