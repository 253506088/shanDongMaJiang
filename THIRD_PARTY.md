# 第三方许可与来源

本仓库为用户的独立私有项目。这里列出第三方部分的许可，不对项目全部自有代码另行授予开源许可。

## 唬牌与离线宣言（2026-11-06）

`scripts/bluff/` 按用户提供的规则独立实现，没有复制第三方唬牌源码。牌面使用下述既有 SVG-cards／用户交付国风素材，保留各自来源，不重复复制牌图。

`assets/bluff/audio/` 现有256段由同一固定 Kokoro / sherpa-onnx 开放模型生成的离线宣言（男／女各128段）。数量和点数顺序播放，只朗读公开宣言；不是商业游戏录音或真人配音。模型、SHA-256、生成参数、台词和文件校验见 `assets/licenses/bluff-voice-manifest.json`，署名见 `bluff-voice-NOTICE.txt`，完整 Apache-2.0 正文共用 `doudizhu-Apache-2.0.txt`。生成脚本为 `tools/generate_bluff_audio.py`；模型、依赖和测试日志不进入游戏包。

## 斗地主与离线中文报牌（2026-11-05）

`scripts/doudizhu/` 的规则实现、AI和牌桌由本项目独立编写。玩法核对 [Pagat — Dou Dizhu](https://www.pagat.com/climbing/doudizhu.html) 等公开资料，未复制网页正文或第三方斗地主源码。采用的规则变体与资料差异见 `docs/doudizhu-rules.md`。0.6.0的传统牌面美术来源单列如下。

`assets/doudizhu/audio/` 的中文报牌为开放模型生成音频，并非从商业游戏提取的录音。模型为 [hexgrad/Kokoro-82M-v1.1-zh](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh)，固定revision `01e7505bd6a7a2ac4975463114c3a7650a9f7218`；采用Apache-2.0的 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 1.12.40 CPU转换模型离线生成。0.6.0按用户试听后的要求保留男声zm_010和女声zf_001，各60段，使用简短报牌；根目录为男声，`female/`为女声。仅分发24kHz PCM WAV，不分发模型与生成环境，运行时不联网。

完整Apache-2.0许可、来源声明、上游模型卡与逐文件SHA-256清单分别保存在 `assets/licenses/doudizhu-Apache-2.0.txt`、`doudizhu-voice-NOTICE.txt`、`doudizhu-Kokoro-model-card.md` 和 `doudizhu-voice-manifest.json`。剪静音、音量处理及可复核生成脚本为 `tools/import_doudizhu_audio.py`；调查和准确授权边界见 `docs/doudizhu-sources.md`。游戏内「关于 → 查看开源许可」同时收录来源和许可正文。

## 传统扑克牌面（0.6.0）

采用 [SVG-cards](https://github.com/htdebeer/SVG-cards)，Copyright (C) 2005 David Bellot，Copyright (C) 2016, 2017 Huub de Beer，GNU LGPL 2.1。固定提交 `6d88bf9c594997b82bc5668ab0877a4e9b717665`，使用上游2倍PNG的54张牌与青绿色牌背；做暖白乘色及小王灰度处理，标准点阵和双头人物保留。0.6.1移除原先的中文大小王覆盖，恢复原图JOKER文字。修改后的图片仍按原LGPL条款提供，此素材许可不扩展为对本项目游戏代码的授权。

完整LGPL、署名、原始SVG及其原始许可头、上游README和逐图SHA-256清单保存在 `assets/licenses/doudizhu-cards-*`，同时随游戏包分发。`doudizhu-cards-source.svg.txt` 是原始SVG的原字节副本，去掉末尾`.txt`可编辑；`tools/import_doudizhu_cards.py` 提供确定性的下载／处理／校验方法。具体来源和修改见 `docs/doudizhu-card-art.md`。

0.7.0接入用户按提示词交付的J／Q／K、黑红JOKER及青玉牌背，生成模型及独立许可文本未随交付提供，如实记录为用户提供的生成素材；不将传统牌组的LGPL、莲花MIT或其他素材许可套用到它们。`assets/licenses/doudizhu-guofeng-manifest.json` 记录12份原图与备份的SHA-256、裁切和55张运行图；`tools/prepare_doudizhu_guofeng.py` 可从本地原图重建。牌值和点阵由程序绘制，字形来自已随包提供OFL许可的Noto Sans SC Bold。两套牌面均使用粗体英文JOKER竖排角标；传统牌面只调整原横排文字区域，保留插画，其修改后图片仍按LGPL提供。

## 山东麻将规则和 AI 的移植

来源：https://github.com/253506088/lianhuaguangdongmahjong （上游 BestGuo2020/lianhuaguangdongmahjong）。
`scripts/core/` 中的玩法判定、计分、牌效策略和流程参考／移植了原项目的山东实现；参考牌例由其代码生成。保留原 MIT 许可如下：
MIT License

Copyright (c) 2026 BestGuo2020（我叫人员外婆）

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## 字体

Noto Sans SC / Noto Serif SC，来源 Google Fonts，SIL Open Font License 1.1。完整许可保存在 assets/fonts/OFL-NotoSansSC.txt 与 OFL-NotoSerifSC.txt。

界面统一使用 Noto Sans SC 的 600（SemiBold）字重，标题和中央方位／牌数使用 700（Bold）字重；由 `tools/prepare_fonts.py` 从原始可变字体生成静态子集，不依赖玩家电脑的系统字体。Noto Serif SC 保留为已有素材的兼容字体。

## 引擎

Godot Engine，MIT License。导出程序包含 Godot 的许可证信息；源码和完整许可见 https://github.com/godotengine/godot/blob/4.5.1-stable/LICENSE.txt 。

Windows 窗口移动模块使用 Godot 4.5.1 官方 `gdextension_interface.h`（MIT），原始接口与来源说明在 `native/windows/vendor/`。完整 Godot MIT 许可同时随包保存在 `assets/licenses/godot-MIT.txt`。窗口模块自身源码为本项目实现，未编入 godot-cpp 或外部运行库。

## 自有素材

牌背波纹标记、程序织物、胡桃木与地面纹理、UI 渐变和面板、线形图标及短合成音效由本项目代码创作；字体字形按上述字体许可使用。`tools/make_table_texture.py` 可确定性生成这些程序纹理。2026-11-03 的程序织物和地面仍保留，2026-11-04 的实际庭院、人物和桌布来源如下。

## 用户交付的生成美术（2026-11-04 接入）

用户按 `docs/art-generation-prompts.md` 生成并交付庭院、人物和织物，原始归档为本地 `artifacts/art-delivery-2026-11-03/`。当前使用庭院主选 01、我／听松／观澜／知秋四张人物头像及深青绿织物；它们不是莲花麻将素材，不沿用其 MIT 或花牌的 CC BY-SA 许可声明。交付 README 未提供生成模型、版本或独立许可文本，本项目如实记录为用户提供的生成素材。

运行资源位于 `assets/backgrounds/courtyard_day.jpg`、`assets/ui/avatars/` 和 `assets/textures/felt_delivered.png`。庭院保留原生 1376×768 像素；头像统一裁切为圆形透明 PNG；织物抑制 8px 横纵周期并低通过滤，加入低对比明暗和圆角。处理脚本为 `tools/prepare_delivered_art.py`，原始／命名交付／运行文件的来源对应、SHA-256 与处理说明见 `assets/art_manifest.json`；织物没有对应 raw 导出，清单保留该事实。

Git 保存运行素材与来源清单。原始导出、备选和放大图不入 Git，但不能仅凭脚本重新生成，需保留独立本机备份。

## 现有牌面与逐牌语音（2026-11-02）

34 张常规 PNG 牌面、34 段牌名 MP3、吃碰杠胡自摸 5 段动作 MP3 来自上述莲花麻将 MIT 仓库的 `public/tiles` 和 `public/audio`，保留仓库许可于 `assets/licenses/lotus-MIT.txt`。不是本项目原创牌面／录音；原仓库未给这些文件列出独立作者。图片仅放大并适配象牙白牌体，声音保持原文件。文件来源、原图及音频 SHA-256 见 `assets/licenses/lotus-assets.json`；导入脚本为 `tools/import_lotus_assets.py`。

## 八花 SVG

作者 Cangjie6，Wikimedia Commons，CC BY-SA 4.0。沿用莲花麻将裁切后的八花 SVG，保留同许可，完整许可证在 `assets/licenses/flowers-CC-BY-SA-4.0.txt`，逐图来源、修改说明和原始 SHA-256 在 `assets/licenses/flowers-sources.json`。此许可仅适用花牌素材。春夏秋冬梅兰竹菊原图为 MJh1-、MJh2-、MJh3-、MJh4-、MJh5-、MJh6-、MJh8-、MJh7-.svg；来源 https://commons.wikimedia.org/wiki/User:Cangjie6 。

2026-11-07补充：复用既有固定模型，为唬牌新增两段「报牌三张」、斗地主新增六段剩3／2／1张提醒。斗地主现共126段，原有374段音频均保持原哈希；两份来源清单新增台词和文件哈希。

## 2026-11-07 八角色和麻将男女声

用户提供6张正式角色头像和2张明确临时使用的表情包，运行图仅裁切、缩放、加圆形透明遮罩。来源、原始尺寸、哈希、外部备份和两项待替换映射见`assets/licenses/character-art-manifest.json`；不将临时表情包宣称为已核实开源授权。

麻将新增男女各39段Kokoro／sherpa-onnx离线语音（78段），复用既有固定Apache-2.0模型和运行时，仅分发WAV。原MP3保留其来源；新台词、哈希、生成参数及署名见`assets/licenses/mahjong-character-voice-manifest.json`和同名NOTICE。男女声按每位发言者角色选择，原斗地主和唬牌音频不重复生成。


2026-11-08／0.10.3更新：麻将按用户要求恢复上述39段莲花原MP3，所有角色使用同一套原声。78段合成麻将WAV保留在源码作为历史试样，导出排除，不再作为当前运行音频；斗地主与唬牌男女声保持原状。
