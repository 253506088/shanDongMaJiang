# 斗地主规则与语音来源

检索与实现日期：2026-11-05。此文件记录在线规则核对及音频来源；玩家实际规则以 [本版规则](doudizhu-rules.md) 和独立斗地主规则核心为准。

## 规则核对

| 来源 | 核对内容 |
| --- | --- |
| [Pagat：Dou Dizhu，John McLeod](https://www.pagat.com/climbing/doudizhu.html) | 三人54张、17张手牌及3张底牌、叫1／2／3分、地主先出、同型同张数压牌、两家过牌后重新领出、13类组合、炸弹与王炸、双方胜负及春天计分 |
| [Wikipedia：Dou dizhu](https://en.wikipedia.org/wiki/Dou_dizhu) | 交叉核对玩法概述、点数顺序和地方／平台变体的存在 |

本版是一名真人与两个机器人，共54张，每局独立结算。叫分采用每人一次、只能叫比当前更高的分，3分立即定地主；三人都不叫则重发。地主公开取得3张底牌。任何一名农民出完即农民方获胜。底分为叫分，炸弹、王炸、春天／反春天翻倍；地主输赢为单个农民的两倍，三家分数合计为零。没有账户资产、局外积分、累计战绩或固定局数限制。

Pagat描述的叫分可以绕桌继续直到连续两人不叫，本版明确选择上述常见的单轮叫分方式。Pagat的四带二单要求两个不同点，本版允许用一对作为两张单牌；四带两对仍要求不同点的两对。飞机单翅允许对子拆为两翼、每点最多两张，翅膀不能复用机身，飞机／四带均不能将双王一起作翼牌。这些变体写在本版规则中，不把任一网站的规则当作全国唯一标准。

来源页面用于理解规则，本项目未复制网页正文或第三方斗地主实现代码。程序牌面由本项目绘制，沿用已交付的庭院、织物及头像，不需要玩家另生成美术才能游玩。

## 音频调查与选用

曾查看 [dwg255/landlord](https://github.com/dwg255/landlord)、[mailgyc/doudizhu](https://github.com/mailgyc/doudizhu)、[songbaoming/DouDiZhu](https://github.com/songbaoming/DouDiZhu) 等公开项目。部分项目的代码标注MIT，但未找到独立录音作者／音轨来源说明，或者只有少量叫分／音乐片段；本版没有把这些录音当作已确认的原创开源素材直接复制。

最终采用开放模型生成的中文报牌，运行时离线播放短WAV：

- [Kokoro-82M-v1.1-zh 模型卡](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh/blob/01e7505bd6a7a2ac4975463114c3a7650a9f7218/README.md)：Apache-2.0；模型卡说明中文专业数据由LongMaoData授权提供。固定模型revision为 `01e7505bd6a7a2ac4975463114c3a7650a9f7218`。
- [sherpa-onnx 的Kokoro文档](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html)：使用其Kokoro v1.1 int8 ONNX转换包，下载按发布SHA-256校验；CPU运行时固定为sherpa-onnx 1.12.40，Apache-2.0。
- 60段播报覆盖单牌、对子、三张、各组合、叫分、不出、重发、春天和反春天；J／Q／K／A采用扑克牌中文俗称“勾／圈／凯／尖”，与牌面的J／Q／K／A对应。普通单张加“一张”前缀，避免孤立单音节过短；两王直接报“小王／大王”。
- 生成音色 `zm_010`（官方模型卡示例之一，speaker ID 59），语速1.0，单声道24kHz PCM16；剪除首尾多余静音并保留50／120ms余量，峰值标准化并增加5ms端点渐变。组合报名称，单牌／对子／三张报具体点数。

完整许可和归属见 `assets/licenses/doudizhu-Apache-2.0.txt`、`doudizhu-voice-NOTICE.txt`、`doudizhu-Kokoro-model-card.md`；每段文字、文件SHA-256与模型归档SHA-256见 `doudizhu-voice-manifest.json`。准确称呼是“开放模型生成的报牌语音”，不是“从开源游戏找到的真人录音”。

`tools/import_doudizhu_audio.py` 保存生成方法，`--verify` 可在不下载模型、不安装合成器的情况下核对所有成品文件。只把WAV和来源记录提交，下载模型及开发依赖放本轮独立 `tmp/ddz-audio-research-20261105/`。该目录原计划在生成和校验后清理，但自动审批以 `blocked by policy` 拒绝删除，逐文件核对后的清理也被拒绝；590个临时文件、587,188,703字节（约560MiB）仍保留，已由 `.gitignore` 排除，未打入安装包。运行游戏不安装TTS、不联网、不依赖系统语音，也不读取麦克风。

## 验证边界

成品逐段检查WAV格式、非静音、时长和SHA-256。开发时仅把生成文件送入本机中文语音识别器作辅助对照，没有访问麦克风；短数字、同音字、扑克牌俗称仍可能产生识别误差，不能单凭自动识别断言发音正确或错误。当前工具不支持音频听辨，未声称已完成人工逐段试听；四／五、十、两王及J／Q／K／A等具体发音和音色偏好仍待真人试听反馈。音色选择采用官方示例男声及完整短语，不影响界面上的准确牌面显示。
