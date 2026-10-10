"""Pure logic: what kind of thing a resource URI points at, and how its card is labelled.

The database only stores the URI. Whether it is a local file or a link is worked out here,
every time resources are loaded.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Literal, Sequence
from urllib.parse import unquote, urlparse

from .models import Resource, ResourceId, TagId
from .video import is_youtube

ResourceKind = Literal["pdf", "word", "excel", "powerpoint", "file", "web", "video", "link"]

# How far along a resource is. Set by hand (the resource's menu, or the button at the end of a
# document); the first is the start, and opening an unopened resource makes it "opened" by itself.
STATUSES = ("unopened", "opened", "in_progress", "finished")
STATUS_LABELS = {
    "unopened": "Not opened",
    "opened": "Opened",
    "in_progress": "In progress",
    "finished": "Finished",
}
DEFAULT_STATUS = STATUSES[0]


def is_status(value: str) -> bool:
    return value in STATUSES


MAX_TITLE = 64  # characters of a name shown on a card (it wraps to 2 lines)

_LOCAL_PATH = re.compile(r"^(?:[A-Za-z]:[\\/]|\\\\|/)")  # C:\..., C:/..., \\server\..., /posix
_LINK = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]+:\S+$")  # scheme of 2+ chars, so "C:" is no link
_FILE_KINDS: dict[str, ResourceKind] = {
    ".pdf": "pdf",
    ".doc": "word",
    ".docx": "word",
    ".xls": "excel",
    ".xlsx": "excel",
    ".ppt": "powerpoint",
    ".pptx": "powerpoint",
    ".pptm": "powerpoint",
    ".pps": "powerpoint",
    ".ppsx": "powerpoint",
}


@dataclass(frozen=True, slots=True)
class ResourceCard:
    """One card in the library. ui/resource_list_model.py maps these fields to QML roles."""

    id: ResourceId
    name: str  # as the user named it
    uri: str
    kind: ResourceKind
    title: str  # the name, shortened for the card
    is_path: bool
    missing: bool  # a local file that no longer exists
    tag_ids: list[TagId]
    created_at: datetime  # for sorting
    last_used_at: datetime  # for sorting
    status: str = DEFAULT_STATUS  # one of STATUSES


def is_inside(path: str, folder: str) -> bool:
    """Is a file somewhere in a folder (at any depth)? Compared the way Windows does it: not case
    sensitive, slashes and backslashes alike."""
    if not folder or not path:
        return False
    try:
        inner = os.path.normcase(os.path.abspath(path))
        outer = os.path.normcase(os.path.abspath(folder))
        return os.path.commonpath([inner, outer]) == outer and inner != outer
    except ValueError:  # another drive
        return False


def is_local_path(uri: str) -> bool:
    return bool(_LOCAL_PATH.match(uri))


def is_valid_link(uri: str) -> bool:
    return bool(_LINK.match(uri))


def is_valid_uri(uri: str) -> bool:
    return is_local_path(uri) or is_valid_link(uri)


def _last_segment(path: str) -> str:
    parts = [p for p in re.split(r"[\\/]", path) if p]
    return parts[-1] if parts else ""


def suggest_name(uri: str) -> str:
    """A starting point for a resource name, taken from the URI itself (no network)."""
    uri = uri.strip()
    if is_local_path(uri):
        filename = _last_segment(uri)
        dot = filename.rfind(".")
        return (filename[:dot] if dot > 0 else filename) or uri  # no extension
    parsed = urlparse(uri)
    segment = unquote(_last_segment(parsed.path))
    if parsed.scheme.lower() in ("http", "https"):
        return segment or (parsed.hostname or "").removeprefix("www.") or uri
    return segment or parsed.netloc or uri


def delete_warning(name: str, notes: int, questions: int, todos: int) -> str:
    """The text of the "delete this resource?" dialog. A resource nothing is attached to gets
    the plain warning; otherwise it says what hangs on it and what happens to that."""
    head = f'Delete "{name}"?'
    parts = [
        f"{count} {word}{'' if count == 1 else 's'}"
        for count, word in ((notes, "note"), (questions, "question"), (todos, "todo"))
        if count
    ]
    if not parts:
        return f"{head} Deleting a resource cannot be undone."
    attached = parts[0] if len(parts) == 1 else ", ".join(parts[:-1]) + " and " + parts[-1]
    effects = []
    if notes or questions:
        effects.append("its notes, questions and answers are deleted with it")
    if todos:
        effects.append("the todos that link to it will show a broken link")
    consequence = effects[0] if len(effects) == 1 else " and ".join(effects)
    return (
        f"{head} It has {attached} attached: {consequence}. "
        "Deleting a resource cannot be undone."
    )


def _truncate(text: str) -> str:
    return text if len(text) <= MAX_TITLE else text[: MAX_TITLE - 1] + "…"


def describe(
    resource: Resource, exists: Callable[[str], bool], tag_ids: Sequence[TagId] = ()
) -> ResourceCard:
    """Classify a resource. ``exists`` checks a local path (injected so tests need no files)."""
    uri = resource.uri
    name = resource.name or suggest_name(uri)
    title = _truncate(name)
    tags = list(tag_ids)
    if is_local_path(uri):
        filename = _last_segment(uri) or uri
        dot = filename.rfind(".")
        kind = _FILE_KINDS.get(filename[dot:].lower(), "file") if dot > 0 else "file"
        return ResourceCard(
            resource.id, name, uri, kind, title, True, not exists(uri), tags,
            resource.created_at, resource.last_used_at, resource.status,
        )
    if urlparse(uri).scheme.lower() in ("http", "https"):
        return ResourceCard(
            resource.id, name, uri, "video" if is_youtube(uri) else "web", title, False, False, tags,
            resource.created_at, resource.last_used_at, resource.status,
        )
    return ResourceCard(
        resource.id, name, uri, "link", title, False, False, tags,
        resource.created_at, resource.last_used_at, resource.status,
    )

# ---------------------------------------------------------------- library: filter and sort
SORTS = ("recent", "name", "added")  # most recently used (default), alphabetical, newest first


def filter_and_sort(
    cards: Sequence[ResourceCard], query: str, tag_ids: set[TagId], sort: str
) -> list[ResourceCard]:
    """What the library shows. ``query`` matches part of the name (case-insensitive); with tags
    selected, a resource must have at least one of them."""
    needle = query.strip().casefold()
    shown = [
        c
        for c in cards
        if (not needle or needle in c.name.casefold()) and (not tag_ids or tag_ids & set(c.tag_ids))
    ]
    if sort == "name":
        shown.sort(key=lambda c: (c.name.casefold(), c.id))
    elif sort == "added":
        shown.sort(key=lambda c: (c.created_at, c.id), reverse=True)
    else:  # "recent"
        shown.sort(key=lambda c: (c.last_used_at, c.id), reverse=True)
    return shown


def recently_used(cards: Sequence[ResourceCard], limit: int) -> list[ResourceCard]:
    """The resources opened most recently (a new one counts from when it was added), leaving out
    files that have disappeared: what "Jump back in" offers."""
    present = [c for c in cards if not c.missing]
    present.sort(key=lambda c: (c.last_used_at, c.id), reverse=True)
    return present[:limit]


def time_ago(then: datetime, now: datetime) -> str:
    """How long ago, the short way: "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago",
    and the date itself ("12 Mar") after a week."""
    seconds = (now - then).total_seconds()
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{int(seconds // 60)} min ago"
    if seconds < 86400:
        return f"{int(seconds // 3600)} h ago"
    days = int(seconds // 86400)
    if days == 1:
        return "yesterday"
    if days < 7:
        return f"{days} days ago"
    return f"{then.day} {then:%b}"
