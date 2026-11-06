"""Generate independent offline bluff declarations using the existing Kokoro cache.

No download or game-time synthesis. --verify requires only the Python stdlib.
The model and license are the same pinned Apache-2.0 Kokoro release documented
in assets/licenses/doudizhu-voice-manifest.json; this manifest records new clips.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/bluff/audio"
MANIFEST = ROOT / "assets/licenses/bluff-voice-manifest.json"
PROFILES = {"male": 59, "female": 3}


def number(n: int) -> str:
    digits = "零一二三四五六七八九"
    if n < 10: return digits[n]
    if n < 20: return "十" + (digits[n % 10] if n % 10 else "")
    if n < 100: return digits[n // 10] + "十" + (digits[n % 10] if n % 10 else "")
    return "一百" + ("零" + digits[n % 100] if n % 100 else "")


def phrases() -> dict[str, str]:
    result = {f"count_{n}": ("两" if n == 2 else number(n)) + "张" for n in range(1, 109)}
    result.update({f"rank_{n}": text for n, text in zip(range(3, 16), ["三", "四", "五", "六", "七", "八", "九", "十", "勾", "圈", "凯", "尖", "二"])})
    result.update({"pass": "过", "challenge": "开", "truth": "全是真的", "lie": "有假牌", "dead": "全部过牌，移出牌堆", "win": "本局结束"})
    return result


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(packages: Path, model: Path) -> None:
    sys.path.insert(0, str(packages.resolve()))
    import numpy as np
    import sherpa_onnx
    os.chdir(ROOT)
    model = model.resolve().relative_to(ROOT)
    source = json.loads((ROOT / "assets/licenses/doudizhu-voice-manifest.json").read_text(encoding="utf-8"))
    for filename, key in [("model.int8.onnx", "onnx_sha256"), ("voices.bin", "voices_sha256")]:
        if digest(model / filename) != source["model"][key]: raise RuntimeError("Pinned model mismatch")
    kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(model=str(model / "model.int8.onnx"),
        voices=str(model / "voices.bin"), tokens=str(model / "tokens.txt"),
        lexicon=str(model / "lexicon-zh.txt"), data_dir=str(model / "espeak-ng-data"), lang="")
    config = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        kokoro=kokoro, provider="cpu", num_threads=2), max_num_sentences=1)
    if not config.validate(): raise RuntimeError("Invalid TTS config")
    tts = sherpa_onnx.OfflineTts(config)
    clips = []
    for profile, speaker in PROFILES.items():
        directory = OUTPUT / profile
        directory.mkdir(parents=True, exist_ok=True)
        for key, text in phrases().items():
            spoken = text + ("！" if key in ["challenge", "win"] else "。")
            audio = tts.generate(spoken, sid=speaker, speed=1.0)
            samples = np.asarray(audio.samples, dtype=np.float64)
            rate = audio.sample_rate
            nonzero = np.flatnonzero(np.abs(samples) > 0.003)
            if len(nonzero) == 0: raise RuntimeError(f"Silent clip: {key}")
            samples = samples[max(0, nonzero[0] - int(rate * .035)):min(len(samples), nonzero[-1] + int(rate * .055))]
            samples *= min(4, (10 ** (-2 / 20)) / float(np.max(np.abs(samples))))
            fade = min(int(rate * .005), len(samples) // 2)
            samples[:fade] *= np.linspace(0, 1, fade); samples[-fade:] *= np.linspace(1, 0, fade)
            pcm = np.clip(np.rint(samples * 32767), -32768, 32767).astype("<i2")
            path = directory / (key + ".wav")
            with wave.open(str(path), "wb") as stream:
                stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(rate); stream.writeframes(pcm.tobytes())
            clips.append({"profile": profile, "key": key, "text": text, "synthesis_text": spoken,
                "path": path.relative_to(ROOT).as_posix(), "sha256": digest(path),
                "bytes": path.stat().st_size, "duration_seconds": round(len(pcm) / rate, 6)})
            print(f"Generated {profile}/{key}: {len(pcm) / rate:.2f}s", flush=True)
    metadata = {"format_version": 1, "generated_date": "2026-11-06", "model": source["model"],
        "generation": {"runtime": "sherpa-onnx", "runtime_version": sherpa_onnx.__version__,
            "profiles": PROFILES, "speed": 1.0, "format": "mono PCM16 24000 Hz",
            "processing": "trim <0.003 silence; retain 35ms/55ms; -2dBFS peak, max gain 4; 5ms fades"},
        "notes": "Generated offline speech, not human recordings. Declarations concatenate count and rank. Independent bluff runtime; no model ships.", "clips": clips}
    MANIFEST.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def verify() -> None:
    from array import array
    metadata = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {(p, k) for p in PROFILES for k in phrases()}
    assert {(c["profile"], c["key"]) for c in metadata["clips"]} == expected
    for clip in metadata["clips"]:
        path = ROOT / clip["path"]
        assert path == OUTPUT / clip["profile"] / (clip["key"] + ".wav")
        assert digest(path) == clip["sha256"] and path.stat().st_size == clip["bytes"]
        assert clip["text"] == phrases()[clip["key"]]
        with wave.open(str(path), "rb") as stream:
            assert (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) == (1, 2, 24000)
            duration = stream.getnframes() / 24000
            assert .15 < duration < 8 and abs(duration - clip["duration_seconds"]) < .00001
            samples = array("h", stream.readframes(stream.getnframes()))
            assert 1000 < max(abs(s) for s in samples) < 32767
    print(f"BLUFF_AUDIO_VERIFIED: {len(expected)} clips; hashes, PCM, phrases, durations and signal levels pass")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--packages-root", type=Path, default=ROOT / "tmp/ddz-audio-research-20261105/packages")
    parser.add_argument("--model-dir", type=Path, default=ROOT / "tmp/ddz-audio-research-20261105/kokoro-int8-multi-lang-v1_1")
    args = parser.parse_args()
    if not args.verify: generate(args.packages_root, args.model_dir)
    verify()
