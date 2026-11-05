"""Generate the bundled offline Dou Dizhu voice from an Apache-2.0 Kokoro model.

Development only. Nothing here is invoked by the game or included in packages.
Install sherpa-onnx==1.12.40 and numpy in an isolated directory, then run:
  python tools/import_doudizhu_audio.py --packages-root <packages> --download
Use --verify to check the shipped WAV hashes without any TTS dependency/network.
Temporary model data defaults to tmp/ddz-audio-research-20261105 and can be removed
after generation; retained assets and provenance live outside that directory.
"""

from __future__ import annotations

import argparse
from array import array
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile
import time
import urllib.request
import wave

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/doudizhu/audio"
LICENSES = ROOT / "assets/licenses"
MANIFEST = LICENSES / "doudizhu-voice-manifest.json"
ARCHIVE_NAME = "kokoro-int8-multi-lang-v1_1.tar.bz2"
ARCHIVE_SIZE = 147052523
ARCHIVE_SHA = "259c9c8bc906d6078e4e0570421885dabb68b539c2f970fcbb890a58eeaf3e9c"
ARCHIVE_URL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/" + ARCHIVE_NAME
MODEL_REPO = "hexgrad/Kokoro-82M-v1.1-zh"
MODEL_REVISION = "01e7505bd6a7a2ac4975463114c3a7650a9f7218"
SPEAKER = 59  # zm_010, verified against the model's id2speaker metadata.
SPEED = 1.0


def phrases() -> dict[str, str]:
    ranks = {3: "三", 4: "四", 5: "五", 6: "六", 7: "七", 8: "八", 9: "九",
             10: "十", 11: "勾", 12: "圈", 13: "凯", 14: "尖", 15: "二",
             16: "小王", 17: "大王"}
    result = {f"single_{rank}": ("一张" + text if rank <= 15 else text) for rank, text in ranks.items()}
    result.update({f"pair_{rank}": "对" + text for rank, text in ranks.items() if rank <= 15})
    result.update({f"triple_{rank}": "三个" + text for rank, text in ranks.items() if rank <= 15})
    result.update({
        "triple_single": "三带一", "triple_pair": "三带一对", "straight": "顺子",
        "pair_chain": "连对", "airplane": "飞机", "airplane_single": "飞机带单牌",
        "airplane_pair": "飞机带对子", "four_two_single": "四带二", "four_two_pair": "四带两对",
        "bomb": "炸弹", "rocket": "王炸", "bid_0": "不叫", "bid_1": "一分",
        "bid_2": "两分", "bid_3": "三分", "pass": "不要", "redeal": "无人叫分，重新发牌",
        "spring": "春天", "counter_spring": "反春天",
    })
    return result


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()


def download_model(scratch: Path) -> Path:
    """Fixed artifact with published digest; bounded parallel byte-range fetches."""
    archive = scratch / ARCHIVE_NAME
    if archive.exists() and sha256(archive) == ARCHIVE_SHA: return archive
    chunks = scratch / "chunks"
    chunks.mkdir(parents=True, exist_ok=True)
    count = 12
    block = (ARCHIVE_SIZE + count - 1) // count

    def fetch(index: int) -> Path:
        start, end = index * block, min(ARCHIVE_SIZE - 1, (index + 1) * block - 1)
        part = chunks / f"{index:02d}.part"
        if part.exists() and part.stat().st_size == end - start + 1: return part
        for attempt in range(4):
            try:
                request = urllib.request.Request(ARCHIVE_URL, headers={
                    "User-Agent": "QingyuMahjong-audio-build", "Range": f"bytes={start}-{end}"})
                with urllib.request.urlopen(request, timeout=90) as response:
                    expected = f"bytes {start}-{end}/{ARCHIVE_SIZE}"
                    if response.status != 206 or response.headers.get("Content-Range") != expected:
                        raise RuntimeError(f"Unexpected byte range: {response.status} {response.headers.get('Content-Range')}")
                    with part.open("wb") as output: shutil.copyfileobj(response, output)
                if part.stat().st_size != end - start + 1: raise RuntimeError("Incomplete model download")
                print(f"Model chunk {index + 1}/{count}", flush=True)
                return part
            except Exception:
                if attempt == 3: raise
                time.sleep(1 + attempt)
        raise AssertionError("unreachable")

    with ThreadPoolExecutor(max_workers=count) as pool: parts = list(pool.map(fetch, range(count)))
    with archive.open("wb") as output:
        for part in parts:
            with part.open("rb") as stream: shutil.copyfileobj(stream, output)
    if sha256(archive) != ARCHIVE_SHA: raise RuntimeError("Downloaded model digest mismatch")
    return archive


def extract_model(archive: Path, scratch: Path) -> Path:
    model_root = scratch / "kokoro-int8-multi-lang-v1_1"
    if (model_root / "model.int8.onnx").exists(): return model_root
    with tarfile.open(archive, "r:bz2") as package:
        root = scratch.resolve()
        for member in package.getmembers():
            target = (root / member.name).resolve()
            if not target.is_relative_to(root) or member.issym() or member.islnk():
                raise RuntimeError("Unsafe archive entry")
        package.extractall(scratch, filter="data")
    return model_root


def generate(model_root: Path) -> None:
    import numpy as np
    import sherpa_onnx

    model_root = model_root.resolve()
    # Native Windows TTS file APIs may not accept an absolute non-ASCII path.
    # Our scratch directory names are ASCII, so resolve them relative to ROOT.
    os.chdir(ROOT)
    if model_root.is_relative_to(ROOT): model_root = model_root.relative_to(ROOT)
    kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(
        model=str(model_root / "model.int8.onnx"), voices=str(model_root / "voices.bin"),
        tokens=str(model_root / "tokens.txt"),
        lexicon=",".join(str(model_root / name) for name in ["lexicon-us-en.txt", "lexicon-zh.txt"]),
        # Follow the upstream Chinese lexicon workflow. No language override
        # is needed; card terms are mapped by the supplied Mandarin lexicon.
        data_dir=str(model_root / "espeak-ng-data"), lang="",
    )
    config = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        kokoro=kokoro, provider="cpu", num_threads=2, debug=False), max_num_sentences=1)
    if not config.validate(): raise RuntimeError("Invalid Kokoro model configuration")
    tts = sherpa_onnx.OfflineTts(config)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for key, text in phrases().items():
        audio = tts.generate(text + "。", sid=SPEAKER, speed=SPEED)
        samples = np.asarray(audio.samples, dtype=np.float64)
        rate = audio.sample_rate
        non_silent = np.flatnonzero(np.abs(samples) > 0.003)
        if len(non_silent) == 0: raise RuntimeError(f"Silent speech: {key}")
        samples = samples[max(0, non_silent[0] - int(rate * 0.05)):min(len(samples), non_silent[-1] + int(rate * 0.12))]
        peak = float(np.max(np.abs(samples)))
        samples *= min(4.0, (10 ** (-2 / 20)) / peak)
        fade = min(int(rate * 0.005), len(samples) // 2)
        samples[:fade] *= np.linspace(0, 1, fade)
        samples[-fade:] *= np.linspace(1, 0, fade)
        pcm = np.clip(np.rint(samples * 32767), -32768, 32767).astype("<i2")
        if not 0.15 <= len(pcm) / rate <= 8: raise RuntimeError(f"Unexpected duration: {key}")
        path = OUTPUT / (key + ".wav")
        with wave.open(str(path), "wb") as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(rate)
            output.writeframes(pcm.tobytes())
        entries.append({"key": key, "text": text, "synthesis_text": text + "。", "path": path.relative_to(ROOT).as_posix(),
                        "sha256": sha256(path), "bytes": path.stat().st_size, "duration_seconds": round(len(pcm) / rate, 6)})
        print(f"Generated {key}: {text} ({len(pcm) / rate:.2f}s)", flush=True)
    metadata = {
        "format_version": 1, "generated_date": "2026-11-05", "method": "offline open-model speech synthesis",
        "model": {"id": MODEL_REPO, "revision": MODEL_REVISION, "license": "Apache-2.0",
                  "model_card": f"https://huggingface.co/{MODEL_REPO}/blob/{MODEL_REVISION}/README.md",
                  "onnx_archive": ARCHIVE_URL, "archive_sha256": ARCHIVE_SHA,
                  "onnx_sha256": sha256(model_root / "model.int8.onnx"), "voices_sha256": sha256(model_root / "voices.bin")},
        "generation": {"runtime": "sherpa-onnx", "runtime_version": sherpa_onnx.__version__, "provider": "cpu",
                       "num_threads": 2, "voice": "zm_010", "speaker_id": SPEAKER, "speed": SPEED,
                       "phonemizer": "Kokoro Chinese lexicon; lang empty (not eSpeak Mandarin IPA); espeak data_dir required by sherpa-onnx 1.12.40 for English fallback only",
                       "format": "mono PCM16 WAV", "sample_rate": 24000,
                       "processing": "trim <0.003 leading/trailing silence retaining 50ms/120ms; normalize peak to -2dBFS (max gain 4); 5ms fades"},
        "notes": "Generated speech, not a redistributed recording pack. J/Q/K/A use Chinese card names 勾/圈/凯/尖. The game ships WAV only; no model, synthesizer, network or system voice dependency.",
        "clips": entries,
    }
    LICENSES.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def verify() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = set(phrases())
    if {clip["key"] for clip in manifest["clips"]} != expected: raise RuntimeError("Voice catalog mismatch")
    for clip in manifest["clips"]:
        path = ROOT / clip["path"]
        if sha256(path) != clip["sha256"]: raise RuntimeError(f"WAV checksum mismatch: {path}")
        with wave.open(str(path), "rb") as stream:
            if (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) != (1, 2, 24000):
                raise RuntimeError(f"WAV format mismatch: {path}")
            duration = stream.getnframes() / stream.getframerate()
            samples = array("h", stream.readframes(stream.getnframes()))
            if sys.byteorder != "little": samples.byteswap()
            if not 0.15 <= duration <= 8 or abs(duration - clip["duration_seconds"]) > 0.00001:
                raise RuntimeError(f"WAV duration mismatch: {path}")
            if not samples or max(abs(value) for value in samples) < 1000:
                raise RuntimeError(f"Silent or nearly silent WAV: {path}")
            if max(abs(value) for value in samples) >= 32767: raise RuntimeError(f"Clipped WAV: {path}")
            if clip["text"] != phrases()[clip["key"]]: raise RuntimeError(f"Phrase catalog mismatch: {path}")
    print(f"Verified {len(expected)} offline voice clips; SHA-256, PCM formats, durations, phrases and signal levels match.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages-root", type=Path)
    parser.add_argument("--scratch", type=Path, default=ROOT / "tmp/ddz-audio-research-20261105")
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify: verify(); return
    if args.packages_root: sys.path.insert(0, str(args.packages_root.resolve()))
    args.scratch.mkdir(parents=True, exist_ok=True)
    model_root = args.model_dir
    if args.download: model_root = extract_model(download_model(args.scratch), args.scratch)
    if model_root is None: parser.error("Use --model-dir or --download, or --verify to inspect shipped clips")
    generate(model_root)
    verify()


if __name__ == "__main__": main()
