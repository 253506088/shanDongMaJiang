# 斗地主报牌：可选男声、女声与来源调查

检索与更新日期：2026-11-05。用户反馈原Kokoro男声有些呆板。本轮先制作简短男声、女声试听；用户针对两段试听明确要求「都做上，让用户可配置」。因此两套均补齐为正式报牌，每套60段，共120段。没有采用Arena项目或其他模型的配音替代这两个已选择的音色。

## 游戏中的两套声音

| 配置 | 音色 | 运行文件 |
| --- | --- | --- |
| 男声（默认） | Kokoro zm_010，speaker ID 59 | `assets/doudizhu/audio/*.wav` |
| 女声 | Kokoro zf_001，speaker ID 3 | `assets/doudizhu/audio/female/*.wav` |

两套都保留试听版本的语速1.0和精简话术：单张直接报点数，J／Q／K／A分别报「勾／圈／凯／尖」；「不要」「顺子」平稳收尾，「炸弹」「王炸」「三分」使用果断的感叹句。运行配置值为 `male`／`female`，无效值回退男声。切换时清除旧声音队列，从下一次动作使用新音色，不补播刚才那一手；静音仍独立控制。

`tools/import_doudizhu_audio.py` 一次生成两套；`--verify` 不依赖模型和合成器，可以核对120个文件的路径、配置、文案、标点、SHA-256、PCM格式、时长、非静音和无削顶。生成参数及逐文件记录见 `assets/licenses/doudizhu-voice-manifest.json`，格式版本为2。

## 先听少量样本

三个本地WAV均按「三／对A／顺子／不要／炸弹／王炸／三分」的顺序播放，句间留0.4秒。它们只供比较，位于带 `.gdignore` 的 `assets/doudizhu/voice-previews/`，不进入游戏运行资源。

| 样本 | 含义 |
| --- | --- |
| [旧版男声原句](../assets/doudizhu/voice-previews/current-male.wav) | 0.5.0旧报牌的比较基线，第一句仍为「一张三」，不再作为正式报牌 |
| [女声短句](../assets/doudizhu/voice-previews/brief-female.wav) | 用户已选择；Kokoro的zf_001音色，直接报「三」，炸弹、王炸和叫分使用感叹句 |
| [男声短句](../assets/doudizhu/voice-previews/brief-male.wav) | 用户已选择；zm_010音色重新合成简短报牌，便于区分文案和音色各自的影响 |

这三份样本仍属于Kokoro模型，语速均为1.0，没有用变速或升降调伪装成新真人声音。用户选择的是短句男声和女声的风格；完整120段仍需实际游玩反馈，不能把选择少量样本写成全部逐段人工试听完成。工具未把波形、自动识别或生成成功当作主观试听通过。

生成时只读复用上轮已下载的Apache-2.0模型与本地sherpa-onnx依赖，没有再次下载安装环境，没有访问麦克风。使用模型revision `01e7505bd6a7a2ac4975463114c3a7650a9f7218`，女声speaker ID 3、男声ID 59；中文词典分词，24kHz单声道PCM16，保留50／120ms首尾余量、峰值归一化至−2dBFS并加5ms端点渐变。文案、片段时间、源版本及文件SHA-256见 `assets/licenses/doudizhu-voice-preview-manifest.json`；完整Apache许可沿用 `doudizhu-Apache-2.0.txt`。

## 找到的其他开源方案

| 方案 | 已核对的授权与能力 | 本轮结论 |
| --- | --- | --- |
| [CosyVoice 3](https://github.com/FunAudioLLM/CosyVoice)／[模型卡](https://huggingface.co/FunAudioLLM/Fun-CosyVoice3-0.5B-2512) | 代码和该模型卡均为Apache-2.0；官方明确支持情绪、音量、语速和方言指令，含普通话与山东等方言 | 优先用于做真正有情绪层次的下一组候选。官方完整模型目录有多份GB级权重，本轮不为几句试听重新下载整套环境；[官方演示](https://funaudiollm.github.io/cosyvoice3/)可先比较表现力 |
| [Chatterbox中文模型](https://huggingface.co/ResembleAI/Chatterbox-Multilingual-zh-cmn)／[代码](https://github.com/resemble-ai/chatterbox) | 模型卡与代码均为MIT；中文专门微调，支持情绪强度，生成音频带内置PerTh水印 | 可作为第二条路线。所需T3与声码器权重约3.2GB，未本地下载；[官方中文演示](https://huggingface.co/spaces/ResembleAI/Chatterbox-Multilingual-TTS-zh-cmn)一次匿名生成尝试返回 `error/null`，未生成可用样本，不将其记为本机已验证 |
| [MeloTTS Chinese](https://huggingface.co/myshell-ai/MeloTTS-Chinese)／[代码](https://github.com/myshell-ai/MeloTTS) | 模型卡及代码为MIT，官方支持CPU实时推理 | 更侧重高效清晰朗读，没有证据证明能解决本次「游戏表情不足」；本轮未下载、未合成 |
| [ChatTTS](https://github.com/2noise/ChatTTS) | 代码AGPLv3+，模型CC BY-NC 4.0；官方明确非商用用途 | 不能只看到「开源」就按普通可商用资产接入；本轮不选 |
| [IndexTTS](https://github.com/index-tts/index-tts/blob/main/LICENSE) | 当前为bilibili Model Use License自定义条款，定义明确涉及模型输出及衍生作品 | 有情绪控制能力，但不能沿用旧印象写成MIT；需按计划用途核对完整条款，本轮不选 |
| [Piper中文huayan音色](https://huggingface.co/rhasspy/piper-voices/blob/main/zh/zh_CN/huayan/medium/MODEL_CARD) | 该音色模型卡把训练数据许可列为 `Unknown`；当前Piper引擎另为GPLv3 | 引擎开源不等于音色来源明确，这个中文音色本轮不选 |

## 现成游戏配音的调查

本轮新增检查了 [qufang888/landlord-ai](https://github.com/qufang888/landlord-ai)。README明确其报牌使用浏览器Speech API，缺音频时回退程序音效，并不是一套可直接搬运的真人报牌库。[Zephaniah-H/DouDZ](https://github.com/Zephaniah-H/DouDZ)等搜索结果未给出清楚音轨许可，也不直接采用。上轮检查过的其他项目见 [已有来源记录](doudizhu-sources.md)。

找到一个授权更明确的候选：[lin08277-source/codex-doudizhu-arena](https://github.com/lin08277-source/codex-doudizhu-arena)。其 [ASSETS.md](https://github.com/lin08277-source/codex-doudizhu-arena/blob/9f25b94ce65857df127f568dda395d7fd6fe804b/ASSETS.md)明确表示 `public/audio/` 配音与音效随开源示例提供，素材按MIT提供至发布者有权许可的范围，可用于运行、修改和分享派生娱乐作品。固定来源commit为 `9f25b94ce65857df127f568dda395d7fd6fe804b`。

该工程是固定牌局动画，其声音是角色配音，不能据文件名“recorded”断言为真人原始录音。已核对源码包中有「三带二」「不要」「过」「我来接，对K」「再大点，对A」等带表演台词，但并非覆盖全部点数和牌型的统一声库。部分话语含特定牌点、人物名或胜负场景，不能随便映射成通用报牌。适合作为现成表演风格试听，整套替换仍需补齐同一音色的合法来源录音。

## 配音方向

本轮已按选择将短句男声与女声配齐。以后若进一步升级，应先调整「说法和表演」：普通单张直接报点数；对子和三张语气明确；「不要」自然收尾；炸弹、王炸略带得意和力度，但不突然增大音量。每套保持统一音色、录音条件和响度，避免不同来源生硬拼接。每段保持短促、清楚，不能为了热闹拖慢回合，也不加入不符合实际动作的台词。

可给情绪可控模型或配音者的方向文本：

> 普通话，像朋友坐在牌桌旁轻松打斗地主，口语自然，字头清楚，句尾干脆。不要新闻播音、客服朗读或夸张广告腔。普通出牌从容，「不要」随意但清楚，「炸弹」「王炸」有一点得意和突然发力，「三分」果断。不要额外解释，不加笑声、背景音乐、回声或长尾；只读给定报牌词。整套音色和录音距离保持一致。

示例词：三、对尖、三带一、顺子、连对、飞机、不要、炸弹、王炸、三分。需要进一步制作时，先把这10句作为同条件试听片段，确认发音和风格后再生成完整60段。
