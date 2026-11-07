"""Generate male/female Mahjong calls with the project's pinned Kokoro cache.

Development only; no downloads. --verify uses only the standard library.
"""
from pathlib import Path
from array import array
import argparse
import hashlib
import json
import os
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/audio/characters"
MANIFEST = ROOT / "assets/licenses/mahjong-character-voice-manifest.json"
PROFILES = {"male": 59, "female": 3}


def phrases():
    digits = "一二三四五六七八九"
    result = {str(tile): digits[tile % 9] + ["万", "筒", "条"][tile // 9] for tile in range(27)}
    result.update({str(tile): text for tile, text in enumerate(["东风", "南风", "西风", "北风", "红中", "发财", "白板"], 27)})
    result.update({"chi": "吃", "peng": "碰", "gang": "杠", "hu": "胡", "zimo": "自摸"})
    return result


def filename(key):
    return f"{int(key):02d}.wav" if key.isdigit() else key + ".wav"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(packages, model):
    sys.path.insert(0, str(packages.resolve()))
    import numpy as np
    import sherpa_onnx
    os.chdir(ROOT)
    model = model.resolve().relative_to(ROOT)
    source = json.loads((ROOT / "assets/licenses/doudizhu-voice-manifest.json").read_text(encoding="utf-8"))
    for file, key in [("model.int8.onnx", "onnx_sha256"), ("voices.bin", "voices_sha256")]:
        if digest(model / file) != source["model"][key]:
            raise RuntimeError("Pinned model mismatch")
    config = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(model=str(model / "model.int8.onnx"),
            voices=str(model / "voices.bin"), tokens=str(model / "tokens.txt"),
            lexicon=str(model / "lexicon-zh.txt"), data_dir=str(model / "espeak-ng-data"), lang=""),
        provider="cpu", num_threads=2), max_num_sentences=1)
    if not config.validate(): raise RuntimeError("Invalid TTS configuration")
    tts = sherpa_onnx.OfflineTts(config)
    clips = []
    for profile, speaker in PROFILES.items():
        directory = OUTPUT / profile
        directory.mkdir(parents=True, exist_ok=True)
        for key, text in phrases().items():
            spoken = text + "！"
            audio = tts.generate(spoken, sid=speaker, speed=1.0)
            samples = np.asarray(audio.samples, dtype=np.float64)
            rate = audio.sample_rate
            nonzero = np.flatnonzero(np.abs(samples) > .003)
            if len(nonzero) == 0: raise RuntimeError(f"Silent speech: {profile}/{key}")
            samples = samples[max(0, nonzero[0] - int(rate * .05)):min(len(samples), nonzero[-1] + int(rate * .12))]
            samples *= min(4, (10 ** (-2 / 20)) / float(np.max(np.abs(samples))))
            fade = min(int(rate * .005), len(samples) // 2)
            samples[:fade] *= np.linspace(0, 1, fade)
            samples[-fade:] *= np.linspace(1, 0, fade)
            pcm = np.clip(np.rint(samples * 32767), -32768, 32767).astype("<i2")
            path = directory / filename(key)
            with wave.open(str(path), "wb") as stream:
                stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(rate)
                stream.writeframes(pcm.tobytes())
            clips.append({"profile": profile, "key": key, "text": text, "synthesis_text": spoken,
                "path": path.relative_to(ROOT).as_posix(), "sha256": digest(path),
                "bytes": path.stat().st_size, "duration_seconds": round(len(pcm) / rate, 6)})
            print(f"Generated {profile}/{key}: {len(pcm)/rate:.2f}s", flush=True)
    MANIFEST.write_text(json.dumps({"format_version": 1, "generated_date": "2026-11-07",
        "model": source["model"], "generation": {"runtime": "sherpa-onnx", "runtime_version": sherpa_onnx.__version__,
        "profiles": PROFILES, "speed": 1.0, "format": "mono PCM16 24000 Hz",
        "processing": "trim <0.003 silence; retain 50ms/120ms; -2dBFS peak, max gain 4; 5ms fades"},
        "notes": "Inactive since 0.10.3 at user request: Mahjong uses the original Lotus MP3 recordings for every character. These generated WAVs remain as historical source assets and are excluded from exports. Poker gender voices are unchanged.",
        "clips": clips}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def verify():
    metadata = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {(profile, key) for profile in PROFILES for key in phrases()}
    assert len(metadata["clips"]) == len(expected)
    assert {(c["profile"], c["key"]) for c in metadata["clips"]} == expected
    for clip in metadata["clips"]:
        path = ROOT / clip["path"]
        assert path == OUTPUT / clip["profile"] / filename(clip["key"])
        assert digest(path) == clip["sha256"] and path.stat().st_size == clip["bytes"]
        assert clip["text"] == phrases()[clip["key"]] and clip["synthesis_text"] == clip["text"] + "！"
        with wave.open(str(path), "rb") as stream:
            assert (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) == (1, 2, 24000)
            duration = stream.getnframes() / 24000
            assert .15 < duration < 8 and abs(duration - clip["duration_seconds"]) < .00001
            samples = array("h", stream.readframes(stream.getnframes()))
            assert 1000 < max(abs(sample) for sample in samples) < 32767
    print(f"MAHJONG_CHARACTER_AUDIO_VERIFIED: {len(expected)} clips; hashes, PCM, phrases, durations and signal levels match")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--packages-root", type=Path, default=ROOT / "tmp/ddz-audio-research-20261105/packages")
    parser.add_argument("--model-dir", type=Path, default=ROOT / "tmp/ddz-audio-research-20261105/kokoro-int8-multi-lang-v1_1")
    args = parser.parse_args()
    if not args.verify: generate(args.packages_root, args.model_dir)
    verify()
