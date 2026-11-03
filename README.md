# 山东麻将 · 青玉台

Godot 4.5.1 原生 GDScript 项目。当前为第一阶段单机版本：现代海青牌桌、3D 麻将、三位电脑牌友、山东玩法、存档续玩、结算和牌谱导出。

项目定位、用户需求、三阶段安排和本次讨论的交接记录见 [my_doc/README.md](my_doc/README.md)。后续在新项目对话中继续开发时，可从这里了解已确认的共识与待定事项。

## 直接玩

Windows：双击仓库根目录的 **启动游戏.bat**。如果存在本地构建，它会启动 `build/windows/QingyuMahjong.exe`；否则自动导入 Godot 资源并运行源码。启动失败时窗口会保留错误信息。

Godot 标准版和 Mono 版均可，项目不含 C#，不需要 .NET SDK。本项目的前身“莲花麻将”位于 `D:\code\my\2\开源麻将`，实际源码在 `lianhuaguangdongmahjong`。项目注意事项见 [AGENTS.md](AGENTS.md)，逐项体验迁移清单见 [docs/lotus-ux-migration.md](docs/lotus-ux-migration.md)。

当前开发机的 Godot 路径已作为启动脚本的一个回退；其他机器可设置环境变量 `GODOT_BIN`。

操作沿用莲花麻将：电脑悬停看牌，单击出牌；触屏单击选牌，快速双击或向上划出牌。报听／明搂时先点声明按钮，再打出带“听”标记的牌。`H` 查看牌效建议，`Esc` 暂停，“交给 AI”开启本家托管。弹窗期间牌局暂停。

## 当前功能

- 浅雾白界面、海青织物与陶瓷桌框；高位透视、圆角双色牌体、立起的三家暗手、随真实牌墙移动的公开杠头。
- 二五八将／乱将、允许／不允许吃牌、经典／牌效 AI。
- 东风 4 局、半庄 8 局、自由续局，每局轮庄，积分累计。
- 起手补花、公开杠头、吃碰明杠暗杠补杠、抢杠、报听、明搂、过圈、截胡、天地胡、海底、八花与现有番型结算。
- AI 工作线程，按玩家可见信息计算；画面不控制规则推进。
- 每次有效操作自动存档，关闭后续玩，当前存档保留一份 `.bak`。
- 导出本局 JSON 牌谱（完整初始牌墙和操作日志）；这是本地调试／复盘数据，不是局域网广播内容。
- 省电画质、声音开关、AI 行牌速度。横屏设计，其他比例保留画面比例。

第一阶段**没有联网建房**。局域网房间的设置和行为基线已记录，权威引擎／座位视图／动作接口已分离；第二阶段再实现传输、入座、准备与重连。

## 开发和验证

```powershell
powershell -File tools/test.ps1
# 真实 Godot 渲染窗口的 UI 输入事件测试：
& tools/run.ps1 -Godot '' --script res://tests/ui_smoke.gd
& tools/run.ps1 -Godot '' --script res://tests/ux_smoke.gd
# 立姿、墙尾、旧局亮牌与花牌遮挡的真实渲染回归：
& tools/run.ps1 -Godot '' --script res://tests/table_art_smoke.gd
```

核心测试直接由 Godot 运行，无 npm、Python 或外部游戏服务依赖。包含原项目生成的 1,140 组胡牌／计分参考牌例、64 组 AI 选择参考，以及整局模拟、牌张守恒、积分守恒、私有手牌和存档重放检查。

重建原项目参考牌例（开发工具，需原仓库已安装 TypeScript）：

```powershell
node tools/generate_reference.mjs 'D:\code\my\2\开源麻将\lianhuaguangdongmahjong'
```

## 打包

双击根目录的 **打包游戏.bat**，选择 Windows、Android、macOS 或全部打包。结束后会显示结果并保留窗口，产物位于 `build/` 下的对应平台文件夹。命令行也可使用 `打包游戏.bat windows`、`打包游戏.bat android`、`打包游戏.bat macos` 或 `打包游戏.bat all`；自动化运行时设置 `MAHJONG_NO_PAUSE=1` 可跳过结束等待。

首先运行 `python tools/fetch_templates.py` 下载 Godot 4.5.1 官方模板到被忽略的 `tmp/export_templates/`。脚本只提取所需 ZIP 条目并校验 CRC，不必下载所有平台的完整包。

移动端导出请使用 Godot **标准版**。现有 Mono 编辑器可以打开并运行本 GDScript 工程，但本机 Mono 4.5.1 的 Android 导出插件触发了 C# 实验性导出检查。可运行 `python tools/fetch_editor.py`，将官方标准版放入 `tmp/godot/`；构建脚本会自动使用它，不改动现有 Godot 安装。

```powershell
powershell -File tools/build.ps1 -Target windows
powershell -File tools/build.ps1 -Target android
powershell -File tools/build.ps1 -Target macos
```

- Windows：本地输出 `build/windows/QingyuMahjong.exe`，内嵌 PCK。
- Android：需要 JDK 17 和 Android SDK，输出调试 APK；正式发布需独立正式签名和发布流程。
- macOS：导出预设已提供，未签名包需在 Mac 上验证并按发布渠道签名／公证。
- iOS：导出预设已提供。需要 Mac、Xcode、对应导出模板和自己的 Apple 签名身份；本次 Windows 环境不能代替 iOS 实机验证。

详细架构、迁移差异和后续联网约定见 [docs/architecture.md](docs/architecture.md)、[docs/rule-baseline.md](docs/rule-baseline.md)。实际验收结果见 [docs/verification.md](docs/verification.md)。

本轮视觉重做的设计与实现说明见 [docs/table-visual-refresh.md](docs/table-visual-refresh.md)。

## 文件边界

提交源码、原创素材、字体许可、规则参考数据、Godot `.uid`／导入配置、导出预设和构建工具。`.gitignore` 排除 `.godot` 缓存、`build` 安装包、`tmp` 下载与测试截图、日志、本机 IDE 配置、证书和签名密码。玩家存档位于 Godot `user://`，不在源码仓库；“关于”可打开存档文件夹。

代码和素材来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。本仓库没有自动上传遥测，也不需要配置 API Key。
