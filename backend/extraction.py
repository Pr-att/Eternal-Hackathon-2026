"""Ingredient extraction: recipe text (+ video) -> classified items, fully on-device.

Delegates to the app's Swift MVVM code (Models/ExtractedItem.swift +
Services/IngredientExtractor.swift via tools/ExtractCLI.swift): AVFoundation frame
walk + Vision OCR/classification + Apple FoundationModels. No external AI, no ffmpeg.

CLI:
  python3 extraction.py <video_url>              # ingest -> extract (text only)
  python3 extraction.py <video_url> --video      # + download video, analyze frames
  python3 extraction.py --text "recipe text"     # raw recipe text, no video
"""
import argparse
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

from ingestion import ingest

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [
    ROOT / "Eternal-Hackathon-2026" / "Models" / "ExtractedItem.swift",
    ROOT / "Eternal-Hackathon-2026" / "Services" / "IngredientExtractor.swift",
    ROOT / "tools" / "ExtractCLI.swift",
]
BIN = Path(__file__).with_name("apple_extract")


def _binary():
    # mtime can't see toolchain/OS switches — after changing Xcode or macOS,
    # `rm backend/apple_extract` by hand. DEVELOPER_DIR=<Xcode-beta> builds
    # against the 27 SDK (image path in); default 26.6 compiles the gate out.
    if not BIN.exists() or BIN.stat().st_mtime < max(s.stat().st_mtime for s in SOURCES):
        subprocess.run(
            ["swiftc", "-O", "-parse-as-library", *map(str, SOURCES), "-o", str(BIN)],
            check=True,
        )
    return BIN


def _download(url, dest):
    with urllib.request.urlopen(url, timeout=60) as r, open(dest, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    return dest


def extract_items(text=None, video_path=None, *, title=None, description=None, transcript=None):
    """Tagged recipe evidence (+ optional local video file) -> classified item dicts."""
    payload = json.dumps({
        "title": title,
        "description": description,
        "transcript": transcript,
        "text": text,
        "video_path": str(video_path) if video_path else None,
    })
    proc = subprocess.run([str(_binary())], input=payload, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "apple_extract failed")
    return json.loads(proc.stdout)["items"]


def _clean(description):
    # social-video descriptions carry hashtags and [SEO keyword] blocks that the
    # small on-device model mistakes for ingredients — strip before extraction
    description = re.sub(r"\[[^\]]*\]", "", description)
    description = re.sub(r"#\S+", "", description)
    return description.strip()


def extract_from_video(video, video_path=None):
    """ingestion.ingest() result dict -> same dict + extracted items."""
    title = video.get("title") or None
    description = _clean(video["description"]) or None if video.get("description") else None
    transcript = video.get("transcript_text") or None
    if not (title or description or transcript or video_path):
        raise ValueError("video has no title, description, transcript, or file to extract from")
    items = extract_items(video_path=video_path, title=title,
                          description=description, transcript=transcript)
    return {**video, "items": items}


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("source", help="video URL (or raw recipe text with --text)")
    p.add_argument("--text", action="store_true", help="treat source as raw recipe text")
    p.add_argument("--video", "--frames", action="store_true", dest="video",
                   help="also download the video and analyze its frames (vision)")
    a = p.parse_args()
    if a.text:
        result = {"items": extract_items(a.source)}
    else:
        video = ingest(a.source)
        if a.video:
            if not video["video_url"]:
                sys.exit("error: no downloadable video URL found for this video")
            with tempfile.TemporaryDirectory() as td:
                path = _download(video["video_url"], Path(td) / "video.mp4")
                result = extract_from_video(video, path)
        else:
            result = extract_from_video(video)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
