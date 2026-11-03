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

## 引擎

Godot Engine，MIT License。导出程序包含 Godot 的许可证信息；源码和完整许可见 https://github.com/godotengine/godot/blob/4.5.1-stable/LICENSE.txt 。

## 自有素材

牌背波纹标记、桌布海岸曲线、大厅几何背景、图标和短合成音效由本项目代码创作；字体字形按上述字体许可使用。2026-11-03 的海青桌布与牌背由 `tools/make_table_texture.py` 确定性生成，不包含第三方桌布或人物插图。

## 现有牌面与逐牌语音（2026-11-02）

34 张常规 PNG 牌面、34 段牌名 MP3、吃碰杠胡自摸 5 段动作 MP3 来自上述莲花麻将 MIT 仓库的 `public/tiles` 和 `public/audio`，保留仓库许可于 `assets/licenses/lotus-MIT.txt`。不是本项目原创牌面／录音；原仓库未给这些文件列出独立作者。图片仅放大并适配象牙白牌体，声音保持原文件。文件来源、原图及音频 SHA-256 见 `assets/licenses/lotus-assets.json`；导入脚本为 `tools/import_lotus_assets.py`。

## 八花 SVG

作者 Cangjie6，Wikimedia Commons，CC BY-SA 4.0。沿用莲花麻将裁切后的八花 SVG，保留同许可，完整许可证在 `assets/licenses/flowers-CC-BY-SA-4.0.txt`，逐图来源、修改说明和原始 SHA-256 在 `assets/licenses/flowers-sources.json`。此许可仅适用花牌素材。春夏秋冬梅兰竹菊原图为 MJh1-、MJh2-、MJh3-、MJh4-、MJh5-、MJh6-、MJh8-、MJh7-.svg；来源 https://commons.wikimedia.org/wiki/User:Cangjie6 。
