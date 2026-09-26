; AI 双端搜题（QuizSync AI）- Inno Setup 6 installer script
; Build: ISCC.exe tools\installer.iss
; 用户数据（数据库/图片缓存/日志/备份）在软件自己的 userdata 下，卸载不删除。
; 注意：本文件含中文，必须存成 **UTF-8 with BOM**（Inno Setup 6 认 BOM；
; 无 BOM 时会按系统 ANSI 码页读，中文会变乱码）。

#define AppName "AI 双端搜题"
; M47：版本号唯一来源 = apps\desktop\pubspec.yaml（由 package_windows.ps1 用
; `/DAppVersion=<版本>` 传进来）。这里的默认值只是**单独手工编译**时的兜底，
; 平时不会用到；改版本时改 pubspec 即可。
#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif
#define AppExeName "quizsync_desktop.exe"
; M32 用户需求 2：**安装目录必须是英文**（QuizSyncAI），不要中文名。
; 显示名（开始菜单/快捷方式/程序名）仍然是中文，只有落盘路径用英文 ——
; 中文目录在部分工具链/脚本/命令行里会出问题，英文目录更稳。
#define AppDirName "QuizSyncAI"
#define ReleaseDir "..\apps\desktop\build\windows\x64\runner\Release"

[Setup]
AppId={{7C6E1F42-9A3B-4D8E-B5C7-1A2D4F6E8B90}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=AI 双端搜题 (QuizSync AI)
DefaultDirName={autopf}\{#AppDirName}
; 老版本的安装目录是中文名（AI 双端搜题）。AppId 不变时 Inno 默认会沿用**上次
; 的安装目录**，那样升级上来的用户永远停在中文目录里 —— 这里显式关掉，
; 让 1.0.1 起一律装到英文目录（安装界面仍允许用户自己改）。
UsePreviousAppDir=no
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\apps\desktop\windows\runner\resources\app_icon.ico
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
CloseApplications=yes
CloseApplicationsFilter={#AppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
OutputDir=..\dist
OutputBaseFilename=quizsync-windows-setup-{#AppVersion}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Excludes userdata：那是运行时生成的用户数据（库/截图/密钥），绝不能进安装包。
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "userdata\*,userdata"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
