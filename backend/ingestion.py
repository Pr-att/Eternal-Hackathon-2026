"""Video ingestion: URL -> metadata + transcript JSON.

The "web scraper" slice of docs/ai-video-recipe-shopping-project.md.
Fetches metadata + captions only — never downloads the video itself.

CLI: python3 ingestion.py <video_url> [--cookies-from-browser chrome]
"""
import argparse
import json
import re
import sys
import urllib.request

import yt_dlp


def ingest(url, cookies_from_browser=None):
    """Fetch a video's metadata and transcript. Returns the spec's Video shape.

    cookies_from_browser: browser name (e.g. "chrome") — needed when Instagram
    blocks anonymous access.
    """
    opts = {"skip_download": True, "quiet": True, "no_warnings": True}
    if cookies_from_browser:
        opts["cookiesfrombrowser"] = (cookies_from_browser,)
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    if info.get("_type") == "playlist":
        raise ValueError("URL resolves to multiple videos — share a single video link")
    transcript = _transcript(info)
    return {
        "source_url": url,
        "platform": (info.get("extractor_key") or "").lower(),
        "title": info.get("title"),
        "description": info.get("description"),
        "duration_s": info.get("duration"),
        "has_captions": transcript is not None,
        "transcript_text": transcript,
        "thumbnail": info.get("thumbnail"),
        "video_url": _video_url(info),
    }


def _video_url(info):
    """Direct media URL for frame extraction. Prefers progressive mp4 (has audio
    too, so the same URL serves a future Whisper fallback). None if unavailable."""
    fmts = [f for f in info.get("formats") or []
            if f.get("url") and f.get("vcodec") not in (None, "none")]
    if not fmts:
        return info.get("url")
    # yt-dlp sorts formats worst -> best, so take the last match
    mp4 = [f for f in fmts if f.get("ext") == "mp4" and f.get("acodec") not in (None, "none")]
    return (mp4 or fmts)[-1]["url"]


def _transcript(info):
    """Plain-text transcript from manual subs, else auto-captions, else None."""
    for tracks in (info.get("subtitles") or {}, info.get("automatic_captions") or {}):
        fmt = _pick_track(tracks)
        if not fmt:
            continue
        try:
            with urllib.request.urlopen(fmt["url"], timeout=30) as r:
                data = r.read().decode("utf-8", "replace")
        except OSError:
            continue
        text = _json3_to_text(data) if fmt.get("ext") == "json3" else _vtt_to_text(data)
        if text:
            return text
    return None


def _pick_track(tracks):
    """From {lang: [formats]} pick an English (else first) track, json3 > vtt."""
    langs = [l for l in sorted(tracks) if l != "live_chat"]
    if not langs:
        return None
    lang = next((l for l in langs if l.startswith("en")), langs[0])
    by_ext = {f.get("ext"): f for f in tracks[lang]}
    return by_ext.get("json3") or by_ext.get("vtt") or tracks[lang][0]


def _json3_to_text(data):
    events = json.loads(data).get("events") or []
    lines = []
    for ev in events:
        text = "".join(seg.get("utf8", "") for seg in ev.get("segs") or [])
        text = " ".join(text.split())
        if text:
            lines.append(text)
    return _dedupe(lines)


def _vtt_to_text(data):
    lines = []
    for line in data.splitlines():
        line = line.strip()
        if (not line or line == "WEBVTT" or "-->" in line or line.isdigit()
                or line.startswith(("Kind:", "Language:", "NOTE", "STYLE"))):
            continue
        line = " ".join(re.sub(r"<[^>]+>", "", line).split())
        if line:
            lines.append(line)
    return _dedupe(lines)


def _dedupe(lines):
    # auto-captions repeat each line as the next cue scrolls in
    out = []
    for line in lines:
        if not out or out[-1] != line:
            out.append(line)
    return " ".join(out)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("url", help="YouTube or Instagram video URL")
    p.add_argument("--cookies-from-browser", metavar="BROWSER",
                   help="e.g. 'chrome' — use when Instagram blocks anonymous access")
    a = p.parse_args()
    try:
        result = ingest(a.url, a.cookies_from_browser)
    except (yt_dlp.utils.DownloadError, ValueError) as e:
        sys.exit(f"error: {e}")
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
