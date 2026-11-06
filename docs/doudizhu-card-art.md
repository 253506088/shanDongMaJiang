# 斗地主传统扑克牌面

2026-11-05。用户反馈首版单花色和皇冠的程序牌面不像传统扑克牌，选择采用标准花色点阵、双头J／Q／K人物和清楚耐看的传统牌面。

## 已选素材

采用 [SVG-cards](https://github.com/htdebeer/SVG-cards) 的完整牌组，作者David Bellot、Huub de Beer；固定提交为 `6d88bf9c594997b82bc5668ab0877a4e9b717665`。上游牌组包含52张普通牌、黑红两王及传统牌背，J／Q／K为完整法式双头人物，数字牌使用标准点阵。使用上游已经栅格化的2倍PNG，避免Godot对复杂SVG及系统字体的差异影响牌面。

图片本身的许可有明确说明：上游README授权用于游戏及非自由软件，要求保留源码及LGPL许可；本项目保存完整原SVG、上游README、LGPL-2.1正文和署名。原SVG许可证头原样保留，不以另一份仓库MIT许可替换素材的实际授权。

同时调查过 [hayeah/playing-cards-assets](https://github.com/hayeah/playing-cards-assets)，其README将素材追溯至旧Google Code公共领域牌组；本轮选择来源和随附源代码更直接的SVG-cards，不混用另一牌组。

## 接入与处理

- `assets/doudizhu/cards/00.png` 至 `53.png` 对应独立斗地主的54张实体牌编码；`back.png` 为青绿色传统牌背。
- 保留标准点阵、字体角标和双头人像。只以 `#f6f1e7` 做轻微暖白乘色，避免桌上大面积纯白刺眼，不模糊图案或改变牌点。
- 小王图案转为灰度，大王保留彩色。2026-11-06先删除中文覆盖，0.7.0再按追加要求改为黑／红 **JOKER** 粗体竖排文字，不再将“大王／小王”印在牌面上；逻辑牌名、记牌器列名与中文语音保持原语义。
- 选中金边、上抬、悬停、点击／划选状态仍由现有独立牌组件与牌桌控制，换素材不改麻将代码、斗地主牌值、计分或合法出牌判定。
- 55张牌图开启mipmaps，牌组件使用线性mipmap采样，降低小窗口和叠牌时细线、点阵的缩小混叠；原图像素与牌点不改变。

## 国风青玉（0.7.0，2026-11-06交付）

用户已交付全部6张专属插画，每张原生848×1264，PNG／JPG共12文件。J／Q／K四花色共用各自人物画心，按腰线以下裁切并旋转180°拼成双头；两张王使用黑红不同人物，程序添加标准角标与点阵。人物等比例缩小，不拉宽脸部或裁断手部。牌背取上半幅再旋转拼接，实现严格180°对称。

两套主题的JOKER均为左上逐字竖排、右下倒置竖排，使用随包Noto Sans SC Bold；没有中文“大王／小王”覆盖。传统牌面替换原横排文字区域，原人物插画保持；该次更新改变52／53两图的像素与SHA-256。逻辑牌名、记牌器和语音继续沿用原语义。

顶部「牌面」可查看七张实物样例（10、J、Q、K、黑王、红王、牌背），再应用传统或国风。主题保存在独立偏好中，重开游戏后恢复；仅预览不会提前换肤，切换即时刷新手牌、底牌及已出牌，保留选牌、对局revision与待提交动作。换肤不重新创建实体手牌。未知主题安全回退传统，发布状态仍由主题目录显式控制。

- 运行图：`assets/doudizhu/guofeng/`，55张338×490 RGBA PNG，开启mipmaps。
- 处理：`python tools/prepare_doudizhu_guofeng.py --prepare`；使用Pillow，从本地原图重建。
- 离线核对：`--verify` 校验运行图、尺寸、字体和牌背对称；`--verify-sources` 校验全部原图及仓库外副本。
- 原图：`artifacts/art-delivery-doudizhu-guofeng-2026-11-06/raw/`；备份：`D:/code/my/2/山东麻将-美术备份/art-delivery-doudizhu-guofeng-2026-11-06/raw/`，12文件逐一SHA-256一致。
- 来源：`assets/licenses/doudizhu-guofeng-manifest.json` 和 `doudizhu-guofeng-NOTICE.txt`；交付未提供生成模型或独立许可文本，不套用传统牌组LGPL。

原始PNG／JPG排除Git及安装包，但属于不可由脚本再生的用户美术，不可作为临时文件删除。运行图、脚本、导入设置、来源清单和测试随Git保存。

## 许可、来源与复核

`assets/licenses/doudizhu-cards-LGPL-2.1.txt` 保存完整许可，`doudizhu-cards-NOTICE.txt` 保存署名与修改说明。`doudizhu-cards-source.svg.txt` 是未经修改的上游SVG源代码，去掉末尾`.txt`即可用SVG编辑器打开；该后缀避免引擎把整套源图库再次导入成闲置纹理。上述文件随安装包一并保存。

`doudizhu-cards-manifest.json` 逐张记录固定来源URL、源文件SHA-256、处理后SHA-256、尺寸及修改；`tools/import_doudizhu_cards.py --download` 可重做下载和处理，`--verify` 无需Pillow或联网即可校验54张牌、牌背及来源许可。下载直接在内存中处理，没有另留模型、压缩包或临时素材目录。

静态素材已检查标准10点、J／Q／K双头人物、两王与牌背；1440×810及960×540真实渲染已检查20张叠牌、划选抬牌、长目标牌、两王角标与记牌器，具体断言和发布包结果见 `docs/verification.md`。传统普通牌角标保留原牌组窄体，两张王改用粗体竖排英文；人物与牌点保持。
