; =====================================================================
;  ClipDict 安装包脚本 (Inno Setup 6)
;  编译前准备 dist\ 目录(与本 .iss 同级):
;     ClipDict.exe    <- Ahk2Exe 编译主脚本得到
;     ecdict_server.exe     <- pyinstaller -F ecdict_server.py --noconsole 打包(必需)
;     stardict.db           <- 紧凑版词库: 先用 make_compact_db.py 重建原始库
;                              (全量词条不变, 851MB -> 约1/4; 勿提交 git)
;  AppId 请用 Inno Setup 菜单 Tool -> Generate GUID 重新生成
; =====================================================================

#define MyAppName "ClipDict 剪贴板查词"
#define MyAppVersion "1.0.0"
#define MyAppExe "ClipDict.exe"

[Setup]
AppId={{B7E3D2F1-6A4C-4E58-9D0A-1F2B3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=ClipDict
DefaultDirName={autopf}\ClipDict
DefaultGroupName={#MyAppName}
OutputBaseFilename=ClipDict-setup-{#MyAppVersion}
OutputDir=installer
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExe}
DisableProgramGroupPage=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式(&D)"; GroupDescription: "附加任务:"
Name: "autostart"; Description: "开机自动启动(推荐)(&A)"; GroupDescription: "附加任务:"

[Files]
Source: "dist\{#MyAppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\ecdict_server.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\stardict.db"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon
Name: "{userstartup}\ClipDict"; Filename: "{app}\{#MyAppExe}"; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "立即运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent
