"""Capture requests from outside the app: "write a note / ask a question about this, at this moment".

They arrive as a link of the app's own protocol, which the browser extension opens (and Windows
hands to the app, see register_protocol.ps1):

    marginalia://capture?kind=note&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D...&t=754

* ``kind``: ``note`` or ``question``
* ``url``:  the page it is about (http or https only)
* ``t``:    the moment in the video, in whole seconds (optional, 0 when missing)
* ``title``: the page's title, as a name for a new resource (optional)

Anything else, or anything malformed, is no capture at all: these links can come from any web
page, so they are read strictly. No Qt and no storage in here, so it is plain unit-testable logic.
"""
from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import parse_qs, urlparse, urlunparse

from .video import MAX_SECONDS, youtube_video_id

SCHEME = "marginalia"
KINDS = ("note", "question")
MAX_TITLE = 200


@dataclass(frozen=True, slots=True)
class Capture:
    kind: str  # "note" | "question"
    url: str
    seconds: int = 0
    title: str = ""


def parse_capture(link: str) -> Capture | None:
    """The capture a ``marginalia://capture?...`` link asks for, or None."""
    parsed = urlparse(link.strip())
    if parsed.scheme.lower() != SCHEME:
        return None
    # "marginalia://capture?..." puts "capture" in the host; "marginalia:capture?..." in the path
    action = (parsed.netloc or parsed.path).strip("/").lower()
    if action != "capture":
        return None
    query = parse_qs(parsed.query)
    kind = (query.get("kind") or [""])[0].lower()
    url = (query.get("url") or [""])[0].strip()
    if kind not in KINDS or urlparse(url).scheme.lower() not in ("http", "https"):
        return None
    try:
        seconds = int(float((query.get("t") or ["0"])[0]))
    except ValueError:
        return None
    title = " ".join((query.get("title") or [""])[0].split())[:MAX_TITLE]
    return Capture(kind, url, max(0, min(seconds, MAX_SECONDS)), title)


def _plain(url: str) -> str:
    """A link without what doesn't change the page: scheme case, "www.", a trailing slash, the
    fragment."""
    p = urlparse(url.strip())
    host = (p.hostname or "").lower().removeprefix("www.")
    return urlunparse(("", host, p.path.rstrip("/"), "", p.query, ""))


def same_page(a: str, b: str) -> bool:
    """Do two links point at the same thing? Two YouTube links are the same when they are the same
    video, whatever their form (youtu.be, watch?v=, a start time, a playlist); any other two links
    when they are equal but for the details _plain drops."""
    video_a, video_b = youtube_video_id(a), youtube_video_id(b)
    if video_a is not None or video_b is not None:
        return video_a == video_b
    return _plain(a) == _plain(b)
