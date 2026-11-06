# 山东麻将 · 青玉台

Godot 4.5.1 项目，游戏主体使用 GDScript，Windows 附带一个小型原生窗口模块。支持单机和同一 Wi-Fi／手机热点下的局域网同桌：庭院茶室、深青绿织物与暖木牌桌、3D 麻将、山东玩法、机器人补位、结算和牌谱导出。

0.8.0 新增独立的**单机唬牌**：大厅点「唬牌」，选择 3–6 人（默认你 + 两位机器人）。三人一副牌、四至六人两副牌；猜拳定先手，领出 1–4 张、跟牌不限张数，支持顺位质疑／任何人抢开、死牌清理和大小王万能。最后一手仍可质疑；无局外积分，可无限续局。传统／国风牌面、男女离线宣言和节奏可配置，详见 [唬牌规则与操作](docs/bluff-rules.md)。

0.5.0 新增独立的**单机斗地主**：大厅左上点「斗地主」，一名玩家与两个机器人用54张牌叫分、出牌。每局独立计分，没有局外累计分或固定场数；打完点「再来一局」，也可随时暂停退出。

0.6.0 换用传统开源扑克牌面，数字牌为标准花色点阵，J／Q／K为双头人物；新增左键按住划选、可收起的记牌器，以及可保存选择的男声／女声报牌。

0.7.0 已接入用户交付的国风青玉牌组：顶部「牌面」可切换传统／国风并记住选择，手牌、底牌和已出牌同步换肤，保留已选牌。两套牌面的 **JOKER** 均为左上逐字竖排、右下倒置竖排；国风使用专属双头人物和青玉牌背。来源与处理见 [牌面说明](docs/doudizhu-card-art.md)。

项目定位、用户需求、三阶段安排和本次讨论的交接记录见 [my_doc/README.md](my_doc/README.md)。后续在新项目对话中继续开发时，可从这里了解已确认的共识与待定事项。

## 直接玩

Windows：双击仓库根目录的 **启动游戏.bat**。如果存在本地构建，它会启动 `build/windows/QingyuMahjong.exe`；否则自动导入 Godot 资源并运行源码。启动失败时窗口会保留错误信息。

Godot 标准版和 Mono 版均可，项目不含 C#，不需要 .NET SDK。本项目的前身“莲花麻将”位于 `D:\code\my\2\开源麻将`，实际源码在 `lianhuaguangdongmahjong`。项目注意事项见 [AGENTS.md](AGENTS.md)，逐项体验迁移清单见 [docs/lotus-ux-migration.md](docs/lotus-ux-migration.md)。

当前开发机的 Godot 路径已作为启动脚本的一个回退；其他机器可设置环境变量 `GODOT_BIN`。

电脑悬停看牌，单击出牌；触屏点一下选牌并抬起，再点同一张即可打出，不限制两次点击的间隔。点其他手牌切换选中，点桌面空白取消选中，也可向上划出牌。报听／明搂时先点声明按钮，再打出带“听”标记的牌。`H` 查看牌效建议，`Esc` 暂停单机对局或查看局域网房间，“交给 AI”开启本家托管。单机弹窗暂停牌局，局域网弹窗不暂停整桌。

斗地主中，电脑和触屏均可逐张点选手牌；鼠标也可按住左键连续划选，划过未选牌时选中、划过已选牌时取消，同一次拖动每张只切换一次。最后按「出牌」统一确认，点空白清空选择。「提示」只预选建议，不自动出牌；「不要」跳过跟牌，领出时不能不要。顶部「记牌器」可收起，统计自己手牌之外尚未打出的牌，叫分时包含未揭底牌，不读取机器人暗手。「男声报牌／女声报牌」可点击切换并保存选择。牌桌中央完整显示当前要压的牌，长的对手上一手可以点开查看。`Esc`／手机返回可暂停；退出后下次重新发牌，不写入麻将的续玩存档。玩法与采用的地方细则见 [斗地主规则](docs/doudizhu-rules.md)，素材见 [传统牌面来源](docs/doudizhu-card-art.md) 和 [规则与语音来源](docs/doudizhu-sources.md)。

多人同桌：大厅点 **附近同桌**，房主选择规则并创建房间，其他人在自动发现列表加入、准备，房主开始。支持安卓与 Windows 使用同一协议混玩，1–4 真人，不足四位自动补机器人；也可输入房主地址加入。详细用法与首版边界见 [附近同桌](docs/lan-play.md)，跨设备实机体验尚待验收。

电脑端可在 **设置 → 显示模式** 切换窗口／无边框全屏，也可按 `F11` 或 `Alt+Enter`。全屏选择会保存，退出全屏恢复原窗口位置、大小或最大化状态。Windows 拖动、缩放期间暂停更新游戏画面，由系统处理窗口边框，松手后统一刷新；实现和验证见 [桌面窗口与渲染优化](docs/window-performance.md)。

报听／明搂后，非胡的新摸牌会按动作与语音节拍自动打出，胡牌和合法暗杠／补杠仍等真人选择。未听时的“听牌一览”可点击窗口外关闭；已听时改为常驻听口、未见余张和自摸预估番数，可收起、展开及滚动，显示期间继续行牌。

其他玩家明搂后，其头像旁也会常驻显示听口牌图、牌名和每张「未见余张」，多听口可滚动。余张按你已知的手牌、公开牌和明搂手牌计算；暗手不泄露，零余张仍保留提示。

## 当前功能

- 用户交付的庭院背景、四位圆形人物头像和深青绿细织物；暖木桌边、深色大厅／信息面板／弹窗／结算、金色重点操作。
- 暖白开源牌面、圆角双色牌体、立起的三家暗手、随真实牌墙移动的公开杠头；手牌直接展示于桌面，保留目标牌图与牌名，去掉重复的“杠头”标签和牌桌左上品牌。
- Noto Sans SC 600／700 随包字体，中央方位与余牌计数放大，统一厚实的文字层次。
- 二五八将／乱将、允许／不允许吃牌、经典／牌效 AI。
- 独立「场地规则」设置，默认关闭；可每局随机，也可指定16种规则中的一种，后续各局沿用。包含循环顺子、透明手牌、红中癞子、三选一摸牌、换牌等；主动能力每人每局一次，桌上可查看说明与剩余次数。
- 东风 4 局、半庄 8 局、自由续局，每局轮庄，积分累计。
- 起手补花、公开杠头、吃碰明杠暗杠补杠、抢杠、报听、明搂、过圈、截胡、天地胡、海底、八花与现有番型结算。
- AI 工作线程，按玩家可见信息计算；画面不控制规则推进。
- 每次有效操作自动存档，关闭后续玩，当前存档保留一份 `.bak`。
- 导出本局 JSON 牌谱（完整初始牌墙和操作日志）；这是本地调试／复盘数据，不是局域网广播内容。
- 无边框全屏、省电画质、声音开关、AI 行牌速度。横屏设计，其他比例保留画面比例。

0.2.0 新增局域网发现、建房、入座、准备、房主配置、机器人补位和进程存活时的断线重连。规则和单机存档格式不变；局域网房间尚不支持退出应用后恢复，也不写入单机续玩存档。

0.3.0 新增 [场地规则与完整玩家说明](docs/field-rules.md)。场地是地方玩法之外的增强选项，未来更换四川／福建玩法也不影响“关闭场地＝正常模式”的定义。正常对局保留 v1 存档；场地对局使用 v2 并从开局与操作日志重放。联网协议升级为 2，同桌玩家需要安装相同版本。锁手时有合法场地能力会保留选择，可直接点“出牌 · 暂不使用”继续。

0.4.0 支持指定场地，并优化完整手牌选牌：换牌中每张同牌分别展示，可同时比较要传出的三张和保留手牌。天使的施舍先正常摸一张，不再每次询问；在这次出牌前主动追加两张，参照完整手牌与副露三选一。变白、撤回副露也提供结果预览，能力可从桌上具名按钮直接打开；收起窗口保留当前选择。新场地存档为v3，兼容旧v1／v2重放，LAN协议为3，联机各端需使用0.4.0。

## 开发和验证

```powershell
powershell -File tools/test.ps1
# 常规五组真实渲染（会打开游戏窗口）；工作桌面空闲时再运行。
powershell -File tools/test_ui.ps1
# 斗地主选牌、触摸配对、长牌组与结算的独立渲染回归：
& tools/test_ui.ps1 -Suites doudizhu_ui_test
# 唬牌人数配置、猜拳、六人牌桌、质疑、完整手牌与结算的独立渲染回归：
& tools/test_ui.ps1 -Suites bluff_ui_test
# 真实 Godot 渲染窗口的 UI 输入事件测试：
& tools/run.ps1 -Godot '' --script res://tests/ui_smoke.gd
& tools/run.ps1 -Godot '' --script res://tests/ux_smoke.gd
& tools/run.ps1 -Godot '' --script res://tests/touch_smoke.gd
& tools/run.ps1 -Godot '' --script res://tests/waits_smoke.gd
# 立姿、墙尾、旧局亮牌与花牌遮挡的真实渲染回归：
& tools/run.ps1 -Godot '' --script res://tests/table_art_smoke.gd
# 全屏往返／移动／缩放会操作桌面，只在桌面空闲时单独运行：
& tools/test_ui.ps1 -Suites window_smoke -Resolutions 1440x810 -AllowDesktopChanges
# 单独执行合批正确性回归，默认限帧且仅少量采样：
& tools/run.ps1 -Godot '' --script res://tests/render_performance.gd -- --qa
```

核心测试直接由 Godot 运行，无 npm、Python 或外部游戏服务依赖。包含原项目生成的 1,140 组胡牌／计分参考牌例、64 组 AI 选择参考，以及整局模拟、牌张守恒、积分守恒、私有手牌和存档重放检查。

`tools/test.ps1` 同时无界面检查明搂听口、信息隔离、跨局清理，以及连续尺寸变化仅更新一次场景渲染目标。窗口卡顿的定向复核使用 `tests/desktop_review.gd`：单个 30 FPS 测试窗口，按 F8 结束，120 秒自动退出；只在修改与无界面检查完成后单独运行，不连续打扰工作桌面。

局域网回归也纳入 `tools/test.ps1`。重建 Windows 包后可运行 `tools/test_lan_process.ps1`，用四个独立的无界面发布程序完成一局、续到第二局并核对积分与四个座位；该脚本不打开可见游戏窗口，不代表跨设备或无线网络验收。

允许启动游戏和普通可见测试窗口、读取测试生成的截图；禁止接管电脑、控制系统鼠标键盘或操纵其他桌面窗口。测试脚本只向自己的Godot视口分发事件。`desktop_review.gd` 仍为手动入口，不自动运行；当前窗口拖动手感尚未完成受控验收。

重建原项目参考牌例（开发工具，需原仓库已安装 TypeScript）：

```powershell
node tools/generate_reference.mjs 'D:\code\my\2\开源麻将\lianhuaguangdongmahjong'
```

## 打包

双击根目录的 **打包游戏.bat**，选择 Windows、Android、macOS 或全部打包。结束后会显示结果并保留窗口，产物位于 `build/` 下的对应平台文件夹。命令行也可使用 `打包游戏.bat windows`、`打包游戏.bat android`、`打包游戏.bat macos` 或 `打包游戏.bat all`；自动化运行时设置 `MAHJONG_NO_PAUSE=1` 可跳过结束等待。

首先运行 `python tools/fetch_templates.py` 下载 Godot 4.5.1 官方模板到被忽略的 `tmp/export_templates/`。脚本只提取所需 ZIP 条目并校验 CRC，不必下载所有平台的完整包。

Windows 源码运行／打包会先增量编译 `native/windows/` 的窗口模块，需要 MSVC x64 C++ 工具和 Windows SDK；开发机已有工具链。`tools/build_native.ps1` 可单独构建，源码或编译脚本未变化时跳过编译。导出包包含 DLL，不要求玩家安装编译器或额外 C++ 运行库；分发时保留完整 `build/windows/` 文件夹，不能只取 EXE。原生模块仅用于 Godot 4.5.1 Windows，其他平台导出会排除它。

移动端导出请使用 Godot **标准版**。现有 Mono 编辑器可以打开并运行本 GDScript 工程，但本机 Mono 4.5.1 的 Android 导出插件触发了 C# 实验性导出检查。可运行 `python tools/fetch_editor.py`，将官方标准版放入 `tmp/godot/`；构建脚本会自动使用它，不改动现有 Godot 安装。

```powershell
powershell -File tools/build.ps1 -Target windows
powershell -File tools/build.ps1 -Target android
powershell -File tools/build.ps1 -Target macos
```

- Windows：本地输出 `build/windows/QingyuMahjong.exe`，内嵌 PCK。
- Android：需要 JDK 17 和 Android SDK，输出调试 APK；正式发布需独立正式签名和发布流程。
- Android 签名临时文件使用项目下 `tmp/android-export/` 的独立子目录；成功或失败后自动清理本次临时文件并恢复环境，避免签名副本占满系统盘。
- macOS：导出预设已提供，未签名包需在 Mac 上验证并按发布渠道签名／公证。
- iOS：导出预设已提供。需要 Mac、Xcode、对应导出模板和自己的 Apple 签名身份；本次 Windows 环境不能代替 iOS 实机验证。

详细架构、迁移差异和后续联网约定见 [docs/architecture.md](docs/architecture.md)、[docs/rule-baseline.md](docs/rule-baseline.md)。实际验收结果见 [docs/verification.md](docs/verification.md)。

本轮视觉重做的设计与实现说明见 [docs/table-visual-refresh.md](docs/table-visual-refresh.md)。

## 文件边界

提交源码、`assets/` 内实际运行素材及来源清单、字体许可、规则参考数据、Godot `.uid`／导入配置、导出预设和构建工具。`.gitignore` 排除 `.godot` 缓存、`build` 安装包、`tmp` 下载与测试产物、`artifacts` 美术交付原始归档／备选／放大图／验收截图、日志、本机 IDE 配置、证书和签名密码。玩家存档位于 Godot `user://`，不在源码仓库；“关于”可打开存档文件夹。

美术整理脚本为 `tools/prepare_delivered_art.py`，原始文件对应关系、SHA-256 和处理步骤保存在 `assets/art_manifest.json`。庭院使用原生 1376×768 主选图，不把插值版当作原生 2K。运行和打包只需已提交的 `assets/`；重新裁切／处理需要本地 `artifacts/art-delivery-2026-11-03/` 归档。该归档中的生成原图不能仅凭脚本再生成，须单独保留本机备份，不能按普通构建缓存清理。素材细节见 [docs/asset-guide.md](docs/asset-guide.md)。

代码和素材来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。本仓库没有自动上传遥测，也不需要配置 API Key。
