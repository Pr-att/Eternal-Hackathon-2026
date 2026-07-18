"""Ingestion API: the iOS app sends a page link, gets back the video's metadata.

Run:  .venv/bin/uvicorn server:app --host 0.0.0.0 --port 8000
Test: curl "http://127.0.0.1:8000/ingest?url=https://www.instagram.com/reel/..."

The simulator reaches it at http://127.0.0.1:8000 (shares the Mac's loopback);
a physical iPhone needs the Mac's LAN IP in ExtractionViewModel.backendURL.
"""
from fastapi import FastAPI, HTTPException

from extraction import _clean
from ingestion import ingest

app = FastAPI()


@app.get("/ingest")
def ingest_endpoint(url: str):
    # sync def on purpose: FastAPI runs it in a worker thread, and yt-dlp blocks
    try:
        video = ingest(url)
    except Exception as e:  # yt-dlp raises many types; the app just needs the why
        raise HTTPException(status_code=422, detail=str(e))
    video["description"] = _clean(video["description"]) if video.get("description") else None
    return video
