"""Preview pictures of videos: downloaded once into a cache folder and reused afterwards."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .core import thumbnail_urls

MIN_BYTES = 1500  # smaller than this is an error page or a blank placeholder, not a picture


@dataclass(frozen=True, slots=True)
class ThumbnailResult:
    path: Path | None
    error: str = ""


def cached_thumbnail(video_id: str, folder: Path) -> Path | None:
    path = folder / f"{video_id}.jpg"
    return path if path.is_file() and path.stat().st_size >= MIN_BYTES else None


def _download(url: str, timeout: float) -> bytes:
    # urllib.request is imported here, when first needed: with http.client and email it adds
    # about 50 ms to every start of the app.
    import urllib.error
    import urllib.request

    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Marginalia)"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        if not response.headers.get("Content-Type", "image/jpeg").startswith("image/"):
            raise urllib.error.URLError("not a picture")
        return response.read(5_000_000)


def fetch_thumbnail(
    video_id: str,
    folder: Path,
    download: Callable[[str, float], bytes] = _download,
    timeout: float = 8.0,
) -> ThumbnailResult:
    """The preview picture of a YouTube video, from the cache or (nicest size first) the web."""
    hit = cached_thumbnail(video_id, folder)
    if hit is not None:
        return ThumbnailResult(hit)
    import urllib.error  # (see _download)

    error = "no preview available"
    for url in thumbnail_urls(video_id):
        try:
            data = download(url, timeout)
        except urllib.error.HTTPError:
            continue  # this size does not exist for the video: try a smaller one
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            return ThumbnailResult(None, f"couldn't load the preview: {getattr(exc, 'reason', exc)}")
        if len(data) < MIN_BYTES:
            continue
        try:
            folder.mkdir(parents=True, exist_ok=True)
            path = folder / f"{video_id}.jpg"
            path.write_bytes(data)
        except OSError as exc:
            return ThumbnailResult(None, f"couldn't save the preview: {exc}")
        return ThumbnailResult(path)
    return ThumbnailResult(None, error)
