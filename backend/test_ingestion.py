"""Offline checks for caption parsing. Run: python3 test_ingestion.py"""
import json

from ingestion import _dedupe, _json3_to_text, _pick_track, _video_url, _vtt_to_text

JSON3 = json.dumps({"events": [
    {"segs": [{"utf8": "chop the "}, {"utf8": "onions"}]},
    {"segs": [{"utf8": "\n"}]},
    {"segs": [{"utf8": "chop the onions"}]},
    {"segs": [{"utf8": "add  turmeric"}]},
]})
assert _json3_to_text(JSON3) == "chop the onions add turmeric"

VTT = """WEBVTT
Kind: captions
Language: en

00:00:00.000 --> 00:00:02.000
add <c>two</c> cups of rice

00:00:02.000 --> 00:00:04.000
add two cups of rice

2
00:00:04.000 --> 00:00:06.000
stir well
"""
assert _vtt_to_text(VTT) == "add two cups of rice stir well"

assert _dedupe(["a", "a", "b", "a"]) == "a b a"

tracks = {
    "live_chat": [{"ext": "json"}],
    "hi": [{"ext": "vtt", "url": "hi-vtt"}],
    "en": [{"ext": "vtt", "url": "en-vtt"}, {"ext": "json3", "url": "en-json3"}],
}
assert _pick_track(tracks)["url"] == "en-json3"  # english preferred, json3 over vtt
assert _pick_track({"hi": [{"ext": "vtt", "url": "hi-vtt"}]})["url"] == "hi-vtt"
assert _pick_track({"live_chat": [{"ext": "json"}]}) is None
assert _pick_track({}) is None

formats = [  # yt-dlp order: worst -> best
    {"url": "a", "ext": "m4a", "vcodec": "none", "acodec": "mp4a"},   # audio-only: skip
    {"url": "b", "ext": "mp4", "vcodec": "avc1", "acodec": "none"},   # video-only
    {"url": "c", "ext": "mp4", "vcodec": "avc1", "acodec": "mp4a"},   # progressive mp4: winner
    {"url": "d", "ext": "webm", "vcodec": "vp9", "acodec": "opus"},   # "best" but not mp4
]
assert _video_url({"formats": formats}) == "c"
assert _video_url({"formats": formats[:2]}) == "b"  # no progressive mp4 -> best with video
assert _video_url({"formats": [formats[0]], "url": "direct"}) == "direct"
assert _video_url({}) is None

formats_vp9 = [  # Instagram case: VP9-in-mp4 with audio vs H.264 video-only
    {"url": "v", "ext": "mp4", "vcodec": "vp09.00.31.08", "acodec": "mp4a"},
    {"url": "h", "ext": "mp4", "vcodec": "avc1.64001f", "acodec": "none"},
]
assert _video_url({"formats": formats_vp9}) == "h"  # Apple-decodable beats has-audio
assert _video_url({"formats": formats_vp9[:1]}) == "v"  # nothing decodable -> best effort

formats_ig = [  # real Instagram shape: unknown-codec progressive mp4s + VP9 DASH
    {"url": "p1", "ext": "mp4", "vcodec": None, "acodec": None},
    {"url": "p2", "ext": "mp4", "vcodec": None, "acodec": None},
    {"url": "dash", "ext": "mp4", "vcodec": "vp09.00.40.08", "acodec": "none"},
]
assert _video_url({"formats": formats_ig}) == "p2"  # progressive (H.264) over VP9 DASH

print("ok")
