# ClipDict · 剪贴板查词

选中英文单词复制后，**连按两次 `Ctrl+C`**，鼠标旁即弹出输入法候选框大小的迷你卡片，显示 **音标 + 词义 + 词形变化**。

**纯本地离线查询** —— 基于 [ECDICT](https://github.com/skywind3000/ECDICT) 词典数据库，不联网、不要 API Key、内网隔离机器照样能用，查询次数无限。

## 功能特性

- 🔍 连按两次 `Ctrl+C`（或备用热键 `Ctrl+Alt+T`）即查剪贴板单词
- ⚡ 迷你浮窗：音标、词性释义、词形变化（过去式/复数/比较级…）、考试标签（中考·高考·CET4·CET6·考研·托福·雅思·GRE）
- 🔤 查不到原形时自动词形还原（`apples→apple`、`ran→run` 这类直接兜底）
- 🖱️ 点击浮窗任意处关闭；12 秒无操作自动消失；不抢焦点，不打断输入
- 🎨 GDI+ 抗锯齿圆角卡片，按内容自适应大小，多显示器下不超出工作区
- 🚀 词典服务由主程序按需自动拉起，失败自动退避，无需手动管理进程

## 工作原理

```
ClipDict.ahk        AutoHotkey v2 主程序（热键监听 + 浮窗 UI）
   │  HTTP 127.0.0.1:39777 /lookup?q=单词
   ▼
ecdict_server.exe          本地查词服务（由 ecdict_server.py 经 PyInstaller 打包，零第三方依赖）
   │  SQLite 只读
   ▼
stardict.db                ECDICT 词库（约 77 万词条，与本程序同目录放置）
```

主程序自动拉起同目录的 `ecdict_server.exe`（PyInstaller 打包的独立服务，目标机器**无需安装 Python**）。

服务只监听 `127.0.0.1`，不对外网开放。

## 下载词库

受 GitHub 单文件 100MB 限制，仓库**不含** `stardict.db`（约 800MB）。请自行到 [ECDICT Releases](https://github.com/skywind3000/ECDICT/releases) 下载 **`ecdict-sqlite-28.zip`**，解压出 `stardict.db`，放到主程序同目录。

使用其他 SQLite 版词库也可以，只要包含列 `word / phonetic / translation / definition / tag / exchange / frq` 即可。

## 安装使用

**方式一：绿色版直接运行**
1. 下载词库放入本目录（见上节）
2. 双击 `ClipDict.exe`（源码版 `ClipDict.ahk` 需安装 [AutoHotkey v2.0+](https://www.autohotkey.com/)）；想开机自启就把它的快捷方式放进启动文件夹（`Win+R` → `shell:startup`）
3. 若同目录没有 `ecdict_server.exe`，按下一节自行构建；临时应急也可手动 `python ecdict_server.py` 启动服务

**方式二：安装包（普通用户推荐）**
从 Releases 下载安装包，下一步装完即用。安装时可选：桌面快捷方式、开机自启。

## 从源码构建 / 打包

```bat
:: 0. 词库瘦身（强烈推荐）：全量重建为紧凑版——词条一条不少（340 万），
::    只删服务端用不到的列，体积 851MB → 约 200MB，安装包体积相差数倍
python make_compact_db.py dist\stardict.db

:: 1. 主程序 exe（AutoHotkey 自带的 Ahk2Exe）
Ahk2Exe.exe /in ClipDict.ahk /out dist\ClipDict.exe /base "D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

:: 2. 独立词典服务 exe（必需，主程序自动拉起它；需要 pip install pyinstaller）
pyinstaller -F ecdict_server.py --noconsole --name ecdict_server

:: 3. 安装包（把上面产物和 stardict.db 放进 dist\，再用 Inno Setup 打开 setup.iss 编译）
```

## 配置项

都在主脚本顶部「配置」区，改完重启脚本生效：

| 常量 | 默认 | 说明 |
|---|---|---|
| `DoublePressMs` | 400 | 连按两次 Ctrl+C 的判定间隔（毫秒） |
| `AltHotkey` | `^!t` | 备用热键 Ctrl+Alt+T，改成 `""` 关闭 |
| `AutoCloseSec` | 12 | 弹窗自动消失秒数 |
| `MaxPopupWidth` | 420 | 弹窗最大宽度（像素） |
| `DictPort` | 39777 | 服务端口；**改端口需与 `ecdict_server.py` 的 `PORT` 同步** |

## 常见问题

- **提示「未找到词库文件 stardict.db」**：词库必须和主程序放在同一目录。
- **想要更小的安装包**：删掉 `setup.iss` 里 `stardict.db` 那行（安装包仅约 10MB），使用者按上文自行下载完整词库；两者可共存发布。
- **端口冲突**：改 `DictPort` 与 `ecdict_server.py` 里的 `PORT` 为同一个值。
- **编译后的 exe 被杀毒/Defender 误报**：Ahk2Exe 打包脚本的常见现象，可代码签名或添加信任。
- **只支持英文单词**：本工具查的是**词典**不是翻译，句子和中文不适用。
- **服务占用内存吗**：服务本身极轻（Python 标准库 HTTP + SQLite），常驻几十 MB。

## 数据来源与许可

- 本项目代码以 **MIT License** 发布。
- 词库数据来自 [ECDICT](https://github.com/skywind3000/ECDICT)（MIT），再分发请同时遵守上游项目的许可与数据来源说明。
