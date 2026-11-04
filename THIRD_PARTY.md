# 第三方许可与来源

本仓库为用户的独立私有项目。这里列出第三方部分的许可，不对项目全部自有代码另行授予开源许可。

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
