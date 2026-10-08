"""Video resources: recognising them, and the timestamps notes are pinned to.

A note on a video lives at a timestamp instead of a page. The database has one number for the
position of a note (its ``page``, 1 or more); for a video that number is the timestamp in seconds,
so the first second of a video, 0:00, is saved as 0:01.

No Qt and no storage in here, so it is plain unit-testable logic.
"""
from __future__ import annotations

import re
from urllib.parse import parse_qs, urlparse

from .models import Note, NoteId

MIN_SECONDS = 1  # the smallest position a note can have (see above)
MAX_SECONDS = 99 * 3600 + 59 * 60 + 59

# A gap is drawn as dots (a long stretch of the video) when it is at least this share of the whole
# stretch between the first and the last timestamp, and also at least this many seconds.
LONG_GAP_SHARE = 0.15
LONG_GAP_MIN_SECONDS = 60

_YOUTUBE_HOST = re.compile(r"(?:^|\.)(?:youtube(?:-nocookie)?\.[a-z]{2,3}(?:\.[a-z]{2})?|youtu\.be)$")
_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")
_CLOCK = re.compile(r"^(\d+):(\d{1,2})(?::(\d{1,2}))?$")  # 1:05   1:02:03
_UNITS = re.compile(r"^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m(?:in)?)?\s*(?:(\d+)\s*s?)?$", re.IGNORECASE)


def is_youtube(uri: str) -> bool:
    """A web link on YouTube (youtube.com, m.youtube.com, music.youtube.com, youtube.<country>,
    youtu.be, youtube-nocookie.com)."""
    parsed = urlparse(uri.strip())
    if parsed.scheme.lower() not in ("http", "https"):
        return False
    return bool(_YOUTUBE_HOST.search((parsed.hostname or "").lower()))


def youtube_video_id(uri: str) -> str | None:
    """The 11-character id of the video a YouTube link points at, if it names one (watch, short
    link, embed, shorts, live)."""
    if not is_youtube(uri):
        return None
    parsed = urlparse(uri.strip())
    host = (parsed.hostname or "").lower()
    parts = [p for p in parsed.path.split("/") if p]
    candidate: str | None = None
    if host.endswith("youtu.be"):
        candidate = parts[0] if parts else None
    elif parts and parts[0] == "watch":
        candidate = (parse_qs(parsed.query).get("v") or [None])[0]
    elif len(parts) >= 2 and parts[0] in ("embed", "shorts", "live", "v"):
        candidate = parts[1]
    return candidate if candidate and _VIDEO_ID.match(candidate) else None


def start_seconds(uri: str) -> int:
    """The ``t=`` / ``start=`` of a link (``90``, ``90s``, ``1m30s``), or 0."""
    query = parse_qs(urlparse(uri.strip()).query)
    for key in ("t", "start"):
        if key in query:
            seconds = parse_timestamp(query[key][0])
            if seconds is not None:
                return seconds
    return 0


def thumbnail_urls(video_id: str) -> list[str]:
    """Where YouTube keeps the preview picture of a video, the nicest size first."""
    base = f"https://i.ytimg.com/vi/{video_id}"
    return [f"{base}/maxresdefault.jpg", f"{base}/hqdefault.jpg", f"{base}/mqdefault.jpg"]


def link_at(uri: str, seconds: int) -> str:
    """The link to watch a video from ``seconds`` on. A YouTube video becomes a plain watch link
    with ``t=`` (whatever start the link had is replaced); any other link is returned as it is,
    since there is no telling how its site wants the time."""
    video_id = youtube_video_id(uri)
    if video_id is None:
        return uri
    seconds = max(0, int(seconds))
    return f"https://www.youtube.com/watch?v={video_id}" + (f"&t={seconds}s" if seconds > 0 else "")


def format_timestamp(seconds: int) -> str:
    """``65`` -> ``1:05``, ``3725`` -> ``1:02:05``."""
    seconds = max(0, int(seconds))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def parse_timestamp(text: str) -> int | None:
    """What a person types for a timestamp, in seconds; None when it is none.

    * ``1:05``  ``1:02:03``      clock style
    * ``1h2m3s``  ``2m``  ``45s``   with units
    * ``105``                    stopwatch style, the last two digits are the seconds: 1:05
      (``90`` and the like, which are no valid seconds after minutes, are plain seconds)
    """
    text = text.strip()
    if not text:
        return None
    clock = _CLOCK.match(text)
    if clock:
        if clock.group(3) is None:
            minutes, seconds, hours = int(clock.group(1)), int(clock.group(2)), 0
        else:
            hours, minutes, seconds = int(clock.group(1)), int(clock.group(2)), int(clock.group(3))
        if seconds > 59 or (clock.group(3) is not None and minutes > 59):
            return None
        return hours * 3600 + minutes * 60 + seconds
    if text.isdigit():
        if len(text) > 2 and int(text[-2:]) <= 59:
            tail = text[:-2]
            seconds = int(text[-2:])
            if len(tail) > 2 and int(tail[-2:]) <= 59:  # 10530 -> 1:05:30
                return int(tail[:-2]) * 3600 + int(tail[-2:]) * 60 + seconds
            return int(tail) * 60 + seconds
        return int(text)
    units = _UNITS.match(text)
    if units and any(units.groups()):
        hours, minutes, seconds = (int(g) if g else 0 for g in units.groups())
        return hours * 3600 + minutes * 60 + seconds
    return None


def position_of(text: str) -> int | None:
    """A typed timestamp as the position to save a note at (at least one second, and sane)."""
    seconds = parse_timestamp(text)
    if seconds is None or seconds > MAX_SECONDS:
        return None
    return max(MIN_SECONDS, seconds)


def gap_is_long(earlier: int, later: int, first: int, last: int) -> bool:
    """Is the stretch between two timestamps long enough to be drawn as dots on the timeline?
    Judged against everything the timeline spans, from the first to the last timestamp."""
    gap = later - earlier
    span = last - first
    return span > 0 and gap >= LONG_GAP_MIN_SECONDS and gap >= LONG_GAP_SHARE * span


def timeline_groups(notes: list[Note]) -> list[dict]:
    """The notes that sit at a timestamp, grouped per timestamp (earliest first), for the timeline
    of a video: each group has its entries (a question is followed by its answers) and whether the
    stretch since the previous timestamp is long enough to be drawn as dots."""
    timed = [n for n in notes if n.page is not None]
    answered = {n.parent_id for n in timed if n.parent_id is not None}
    times = sorted({n.page for n in timed})
    groups = []
    for index, time in enumerate(times):
        here = [n for n in timed if n.page == time]
        answers: dict[NoteId, list[Note]] = {}
        for n in here:
            if n.parent_id is not None:
                answers.setdefault(n.parent_id, []).append(n)
        ordered: list[Note] = []
        for n in here:
            if n.parent_id is None:
                ordered.append(n)
                ordered.extend(answers.get(n.id, []))
        groups.append(
            {
                "time": time,
                "label": format_timestamp(time),
                "longGap": index > 0 and gap_is_long(times[index - 1], time, times[0], times[-1]),
                "entries": [
                    {
                        "noteId": n.id,
                        "body": n.body,
                        "isQuestion": n.is_question,
                        "parentId": -1 if n.parent_id is None else n.parent_id,
                        "answered": n.id in answered,
                        "isGlobal": False,
                    }
                    for n in ordered
                ],
            }
        )
    return groups
