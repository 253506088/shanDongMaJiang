# 桌面窗口与渲染优化

日期：2026-11-04。对应电脑端无边框全屏、移动及调整窗口卡顿反馈。

## 使用方式

大厅和牌桌的「设置 → 显示模式」均可切换窗口／无边框全屏。`F11`、`Alt+Enter` 在设置弹窗内也有效，长按不会反复切换；`Alt+Enter` 不会触发打牌。全屏偏好保存在原有 `user://preferences.json`，旧偏好文件缺少该字段时仍使用窗口模式。

使用 Godot `Window.MODE_FULLSCREEN`，不改变显示器分辨率。退出后恢复进入前的位置、大小或最大化状态；若显示器可用区域变小，会按包含标题栏的完整窗口外框调整到屏幕内。手机上不显示此电脑选项。窗口显示设置独立于规则、牌谱和存档，不改变对局版本。

## 卡顿来源与处理

Godot 4.5.1 Windows 在原生拖动／调整尺寸的消息循环中，通过 `WM_TIMER` 同步执行 `Main::iteration()`。绘制、VSync 等待和 `Engine.max_fps` 睡眠因此会占用窗口消息线程。参见该版本 [Windows 源码](https://github.com/godotengine/godot/blob/4.5.1-stable/platform/windows/display_server_windows.cpp#L5872)。

`scripts/ui/desktop_window.gd` 同时观察位置与尺寸变化。在 Windows 窗口调整期间临时关闭 VSync 等待，并将帧率上限暂设 120，连续 180ms 没有变化后恢复。始终保留上限，避免短暂移动也变成无约束渲染。尺寸改变时临时使用固定 1600×900 的 viewport 拉伸，避免每个尺寸都重建 MSAA 渲染目标和中文字体缓存；稳定后恢复原生分辨率的 `canvas_items`，保证静止时文字和牌面清晰。仅移动窗口时保持原生画布，不切换渲染尺寸。平时省电画质采用 30 FPS，大厅和精致画质采用 60 FPS。

没有打开该 Godot 版本仍标为实验性且存在缩放崩溃风险的独立渲染线程，也没有全局关闭 VSync 或永久降低画质。

另一个开销来自每张实体牌的五个独立 MeshInstance 和附加阴影绘制。沿用前身莲花麻将 `tileInstanceRenderer.ts` 的实例化思路，改用 `MultiMesh` 按牌体、牌背、牌面材质、接触阴影合批。原几何、开源牌面、立姿、隐藏牌面、拾取和布局保持一致。动画同步到实例矩阵；同一牌的新动画会替换旧动画，移除牌时停止对应动画并回收实例位置，避免残影。

## 渲染测量

Windows、Godot 4.5.1 Compatibility、Intel Arc，1440×810 精致画质，相同种子 93000 的开局及 35 次决策后中局，预热后采样 90 次真实绘制。前后都关闭 VSync 和帧率上限用于测量。

| 场景 | 绘制调用：之前 → 之后 | 提交耗时中位数 | 提交耗时 P95 |
| --- | --- | --- | --- |
| 开局，130 张实体牌 | 1261 → 81，减少 93.6% | 8.689 → 7.464ms | 11.905 → 8.616ms |
| 中局，136 张实体牌 | 1322 → 106，减少 92.0% | 8.682 → 7.314ms | 11.879 → 8.518ms |

耗时是 `RenderingServer.force_draw(false)` 调用区间，包含本机提交／同步成本，不等于纯 GPU 时间或鼠标拖动延迟。Compatibility 后端在 visible 计数中包含阴影绘制，独立 shadow 计数返回 0。测量时机器上还运行其他程序，毫秒值会波动；自动回归检查绘制数量与渲染正确性，不对单次速度设置易波动的门槛。

原始测量、同场景截图保存在本机 `artifacts/window-performance-baseline/` 和 `artifacts/window-performance-batched/`，按 `.gitignore` 排除。运行 `tests/render_performance.gd` 可重测当前版本。实际窗口交互、截图复核和本轮发布包结果见 [验收记录](verification.md)。

上表是首次实现时的历史测量。用户反馈密集测试影响其他项目后，已停止后续可见测试；性能回归改为默认 30 FPS／6 次采样，显式 `--benchmark` 也只采样 30 次且保持 60 FPS 上限，不再提供无限帧采样。全屏往返测试从默认批次移出，必须单独指定 `window_smoke` 和 `-AllowDesktopChanges`。限帧修订后的版本没有再次进行可见窗口验收，不把历史耗时冒充最终版本重测结果。
