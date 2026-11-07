# 莲花麻将体验迁移清单

2026-11-08补充（0.10.4）：对照`src/components/table/GameTableHud.vue`的`inspectedHandIndex`、选中后查看、触屏不按鼠标离开关闭提示，以及本家手牌变化时清除旧索引的做法，修复手机手牌未见余张提示闪退。现有Godot手牌选中会重建控件，旧控件的离开事件原先无条件清掉提示；触屏查看改为独立状态，并阻止旧控件清提示或触发出牌。提示常驻、避开动作行、点击不穿透；他人回合可只读查看，公开动作更新未见数。保留2026-11-05用户确认的“第二次点已选牌立即打出”，没有恢复前身的短时双击限制。

2026-11-02。用户确认：“莲花麻将”就是本项目的前身 `D:\code\my\2\开源麻将`，实际源码位于 `lianhuaguangdongmahjong`。参考 HEAD：`164822b0cfa21fcda6f73237b131ac0f3e012214`。该工程只读，本次修改均在山东麻将。

## 从前身发现的易用性处理

以下均在源码中核实，不是根据项目名字推测的设计。范围是当前山东单机牌桌；联网房间、其他玩法和多主题专属演出不属于本次单机迁移。

| 优化 | 莲花麻将依据（相对前身源码根目录） | 山东麻将本次处理 |
| --- | --- | --- |
| 电脑鼠标悬停看牌、单击出牌 | `src/components/table/GameTableHud.vue` 的 `handleTileHover` / `handleTileActivation` | 迁移，鼠标直接点击打牌，不再强迫二次点击 |
| 触屏选牌、再次点击打出、上划打出，空白处取消选择 | 同文件 `beginTileGesture` / `finishTileGesture` / `clearMobileSelection` | 2026-11-05 按用户要求取消原 360ms 双击门槛：再点选中牌打出，点其他牌切换；保留上划 28px / 700ms 门槛；设备手感仍需实机体验 |
| 新摸牌与原手牌隔开；选中牌抬起；可听弃牌有标识 | 同文件 `hand-rack` / `hand-tile-slot` | 保留间隔、抬起与“听”标记，增加“新摸”文字 |
| 看本牌和同花色相邻牌的未见张数 | `src/components/table/tileInspection.ts`、`TileUnseenHint.vue` | 悬停放大牌面，展示相邻牌和未见张数 |
| 检查公开弃牌、副露、明搂牌；不泄露暗牌 | `GameTableHud.vue` 的 `inspectPublicTile`、`three/tilePicking.ts` | 支持点击 3D 明牌查看，也可打开“查看桌面牌”大图列表 |
| 听牌提示显示听口、余张和预计倍数；选哪张打掉要明确 | `GameTableHud.vue` 的 `waiting-tip`、`src/game/shared/selectors/gameSelectors.ts` | “听牌一览”显示打出哪张、听哪些、未见张数、自摸估算倍数；悬停可听弃牌也显示听口 |
| 多种吃法给出牌面组合，而不是长文字 | `GameTableHud.vue` 的 `chi-picker-options` | 迁移图片组合选择器，单组合直接执行 |
| 多个杠候选使用图片选牌 | 同文件 `kong-picker-tiles` | 迁移多杠选牌；单个杠直接显示“暗杠／补杠 + 牌名” |
| 最后一张弃牌单独标记，并保留出牌者、牌名 | `lastDiscard`、`three/tileMarker.ts`、`tableTilePresenter.ts` | 牌河金边标记，左侧常驻“谁打出＋大牌面＋牌名” |
| 应牌时有提醒音、显著操作和独立的过牌按钮 | `GameTableHud.vue` 对 `actionPrompt` / `userKongs` 的 watch | 可碰吃杠胡时响提示音，显示“碰 四万”等具体目标；真人响应不倒计时 |
| 吃碰杠动作反馈与座位关联 | `TableActionCue.vue`、`themeEventPresentation.ts` | 保留座位动作字，补上对应真人语音通道 |
| 出牌逐牌播报，动作人声不被点击音覆盖 | `src/game/core/presentation/useAudio.ts`、`public/audio/` | 迁入 34 种牌名及吃碰杠胡自摸 MP3，独立语音队列、事件去重；静音立即清队列 |
| 动作节奏独立于 AI 计算速度 | `src/game/core/local/localGameConfig.ts` 的 `PACE_MS`、`shandongTurnOrchestrator.ts` | 采用独立表现等待；按用户反馈加长，默认出牌约 1.8 秒，吃碰杠约 2.1 秒，并等语音结束；可选舒缓／标准／利落 |
| 牌河、牌墙、副露、暗手分开；副露横牌按长边预留间距 | `src/game/core/presentation/tableLayout.ts` | 迁移区域划分与横牌占宽方式，适配本项目尺寸；四家坐标统一计算 |
| 牌河前三排六张，后续加宽；四家不能交叉挤压 | 同文件 `discardTileLayout` | 迁移前三排 6 张、后续 10 张，验证四家长牌河与牌墙间距 |
| 补杠保留碰牌结构，第四张有独立位置 | 同文件 `addedKongTileOffset`、`three/tableTilePresenter.ts` | 第四张叠在来源横牌上，使用真实牌高加间隙；吃牌横置的是实际被吃的那张 |
| 骰子只在开局阶段展示，结束后隐藏 | `src/components/table/three/dicePresenter.ts` | 移到中央保留区，落点高于台面，1.8 秒后收起，不留在牌河里 |
| 手牌和桌面使用同一套现成牌面 | `public/tiles`、`src/components/MahjongTile.vue` | 替换 34 张字体／几何生成牌面，使用前身 PNG；八花用其 CC BY-SA 4.0 SVG，记录来源和许可 |
| 弹层不能误触牌桌；重要信息可在小屏滚动查看 | `GameTableHud.vue` 的 picker / waiting-tip、响应式样式 | 选择器、听牌及桌面牌窗口暂停 AI、可关闭；长列表滚动；保持横屏等比缩放 |

## 用户指出的问题及修正

1. **不知道在碰什么**：响应按钮写具体牌名，左栏同时展示牌面及来源玩家，底部状态再次说明目标。
2. **过曝、难认牌**：牌面采用不受灯光增亮的材质；牌体使用哑光灰绿侧面；减少金边与桌布装饰，扩大牌面图案。
3. **副露、骰子、弃牌穿模**：分离各区域，横牌采用长边间距，补杠上层使用牌体高度；骰子不驻留牌河。
4. **机器人太快**：默认节拍由约 0.7 秒改为 1.8 秒；吃碰杠留出 2.1 秒；计算完成不代表立即跳过展示。
5. **没有牌面播报**：接入前身 34 张牌对应音频，东风等字牌通过固定编号一一映射；点击音与人声分开播放。
6. **四万补杠缺按钮**：旧工程与首版都把报听／明搂后的杠一律过滤。本次依用户反馈修正，而不是照搬这个限制。

### 四万补杠回归牌例

截图的手牌：六筒×3、八筒、五六七条、新摸四万；副露：八万暗杠、四万碰；已报听，听八筒。

现在摸到已碰牌的第四张，且杠前后听口完全一致，即提供补杠。暗杠也要求新摸的是第四张且听口不变；仍不能吃碰或打掉锁定手牌。补杠沿用原抢杠、摸杠头、补花、计分流程。新锁手杠选项追加在原有操作之后，旧存档的操作编号不移位。

## 验证入口

```powershell
& tools/test.ps1 -Godot ''
& tools/run.ps1 -Godot '' --script res://tests/ui_smoke.gd
& tools/run.ps1 -Godot '' --script res://tests/ux_smoke.gd
```

- 规则／AI 参考牌例、12 局模拟、守恒、存档重放测试。
- 四万补杠、明搂杠、听口不变暗杠、听口改变拒绝、抢杠回归。
- 四家长牌河／牌墙碰撞检查，真实渲染物体包围盒检查。
- 真实窗口点击碰、补杠、吃牌组合、听牌／公开牌面板；逐牌语音资源解码及去重。
- 截图位于 `tmp/ux-*.png`，Windows 最新构建在 `build/windows/QingyuMahjong.exe`。触屏协议已实现，Android／iOS 实机手感不等同于 Windows 验证。

## 2026-11-03：视觉打磨中的交互复核

- 删除常驻操作说明和重复的桌面“杠头”浮字；应牌对象仍在左侧显示牌图、牌名、来源玩家，本家待应牌时增加金边。上文“底部状态再次说明目标”属于历史实现，当前已不再重复展示。
- 参照 `GameTableHud.vue` 的 `clearMobileSelection`，触摸操作按钮时不清空选择／报听模式；点桌面空白时同时清理双击记录，防止立即重选被误判为打牌。
- `tests/touch_smoke.gd` 通过 Godot 输入分发覆盖触摸打出按钮、取消报听、空白取消后重新选牌。与鼠标、布局及规则测试分开运行；Windows 输入模拟不代替手机实机验收。
- 本轮视觉说明与实测结果分别见 `table-visual-refresh.md`、`verification.md`。暂不提交，继续本地打磨。

## 2026-11-04：报听后的连续行牌

- 对照 `src/game/variants/shandong/shandongTurnOrchestrator.ts` 的锁手自动摸打思路，在 `LocalSession` 完成自动提交：报听／明搂、自己摸牌回合、无胡牌和合法杠牌时，等待原动作／语音节拍后打出新摸牌。不启动本家 AI，不改变核心规则、操作编号或存档版本。
- 胡牌与合法暗杠／补杠继续等待真人；有杠牌选择时增加“过杠 · 出牌”，只打新摸牌。暂停冻结等待，续玩后恢复自动摸打。
- 听口参照前身 `gameSelectors.ts` 的公开余张算法，以及 `shandongSelectors.ts` 的番型倍数口径；已听后在右侧常驻，避免随回合关闭，显示牌面、牌名、未见余张及自摸预估番数。支持多听口滚动，更新时保留滚动位置；零余张仍显示。
- 未听时仍可打开候选弃牌的一览弹窗，点击窗口外可关闭，鼠标及触摸释放不会误操作底下手牌。
- 新增 `tests/locked_turn_regressions.gd`（已接入 `tools/test.ps1`）和 `tests/waits_smoke.gd`。具体验证结果见 `verification.md`。

## 2026-11-04：交付美术接入与本轮交付范围

- 用户已交付提示词对应的独立素材，并最新授权完成优化、验证与打包后写好提交记录、推送远端；上文 11-03 的“暂不提交”为历史阶段安排。
- 庭院主选 01、四位圆形默认头像和经去周期／低通过滤的深青绿织物替换本地试样；暖木桌边、开源牌面、逐牌语音及成熟应牌方式继续保留。大厅、弹窗和结算同步为深色暖金配色。
- 牌桌左上品牌与图标、桌面及 HUD 重复“杠头”标签移除；公开牌图、牌名与悬停解释继续保留。中央方位和余牌数放大，文字统一使用 Noto Sans SC 600／700。
- 已报听／明搂的非胡摸打继续走既有 `submit`、journal 和存档链路，合法暗杠／补杠与胡牌仍需真人选择。美术接入不改变规则、存档版本、动作编号或隐藏信息边界。
- 源图、运行图的对应关系和 SHA-256 见 `assets/art_manifest.json`，处理见 `tools/prepare_delivered_art.py`；背景使用原生 1376×768，不把插值图当作原生 2K。原始交付留本地并备份，运行素材进入 Git。实测结果与 Windows 包状态统一记录在 `verification.md`。
