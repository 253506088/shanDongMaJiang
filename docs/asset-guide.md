# 素材说明

2026-11-02 按用户反馈改为复用莲花麻将现成牌面与语音，当前不需要额外文生图。

- 34 张常规牌面：前身 `public/tiles/1m.png` 等 PNG 插画，适配为 256×344 象牙白牌体。运行时加载图片，不用字体临时画万字、条筒或风牌。
- 八花：前身已有 Cangjie6 / Wikimedia Commons 的八花 SVG，CC BY-SA 4.0。沿用其裁切、排序和许可。
- 语音：前身 34 段牌名 MP3，外加吃、碰、杠、胡、自摸 5 段。独立于点击音播放，不依赖网络或系统语音服务。
- 桌布：`tools/make_table_texture.py` 生成固定种子的海青织物与海岸曲线，3072×3072 PNG。低频微颗粒避免远处纹理闪烁；桌布使用稳定色彩渲染与独立接触阴影，避免桌框近距离叠层的阴影干扰纹。
- 牌背：同脚本生成 384×544 青蓝珐琅底与银白波纹标记；128×160 接触阴影；均为原创几何与程序纹理。Godot 牌壳独立建模并使用高光和圆角法线。
- 大厅渐变与圆弧、轻量面板由 UI 代码绘制；图标与短音效保留本项目资源。
- 字体：Noto Sans SC / Noto Serif SC，SIL OFL 1.1，字重与子集流程见 `tools/prepare_fonts.py`。

常规原图只有 75×100，当前采用插值放大并保留原有图案，不能把它当作新增的高清绘制。花牌为矢量。将来需要真正高清的大牌面时，可在同一编号接口下替换更高分辨率源图，交互和规则不受影响。

来源、原图与音频 SHA-256、作者与完整许可保存于 `assets/licenses/`，同时纳入游戏打包，详见 `THIRD_PARTY.md`。

重建导入资源：

```powershell
python tools/import_lotus_assets.py 'D:/code/my/2/开源麻将/lianhuaguangdongmahjong'
python tools/make_table_texture.py
```

`tools/make_assets.py` 检测到导入清单后，不再覆盖现成牌面。图片和语音已保存在项目内，玩家不需要 Python、原项目或网络。
