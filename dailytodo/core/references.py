"""Inline references in todo text: ``@{...}`` points at a resource, ``!{...}`` at a tag.

Three forms of the same text:

* edit form    ``review @{Quarterly report} !{work}``      what the user types and sees in a text box
* stored form  ``review @{12|Quarterly report} !{3|work}`` what the database holds: the id makes it
               a real link that survives renames; the name is only a fallback for display
* segments     plain text / resource / tag pieces, for rendering

No Qt and no storage in here, so it is plain unit-testable logic.
"""
from __future__ import annotations

import re
from typing import Callable, Sequence

from .links import split_links
from .markdown import style_pieces

ACTIVATORS = {"@": "resource", "!": "tag"}
_SYMBOL = {kind: symbol for symbol, kind in ACTIVATORS.items()}

_STORED = re.compile(r"([@!])\{(\d+)\|([^{}]*)\}")
_EDIT = re.compile(r"([@!])\{([^{}|]*)\}")

NameOf = Callable[[str, int], "str | None"]  # (kind, id) -> current name, None if it is gone
Resolve = Callable[[str, str], "tuple[int, str] | None"]  # (kind, typed name) -> (id, name)


def sanitize_name(name: str) -> str:
    """A name as it appears between the braces: braces and bars would break the format."""
    cleaned = name.replace("{", "(").replace("}", ")").replace("|", "/")
    return re.sub(r"\s+", " ", cleaned).strip()


def segments(stored: str, name_of: NameOf) -> list[dict]:
    """Split stored text into pieces: {"type": "text" | "link" | "resource" | "tag", "text", "id",
    "missing", "url", "bold", "italic"} (a link is ``[name](address)`` or a bare web address;
    bold / italic / bullets come from ``markdown.style_pieces``, which also drops their markers).

    A reference to something that no longer exists keeps its saved name and is marked missing.
    """
    pieces: list[dict] = []
    position = 0
    for match in _STORED.finditer(stored):
        if match.start() > position:
            pieces += _text_pieces(stored[position : match.start()])
        kind = ACTIVATORS[match.group(1)]
        ref_id = int(match.group(2))
        live = name_of(kind, ref_id)
        pieces.append(
            {
                "type": kind,
                "text": live if live is not None else match.group(3),
                "id": ref_id,
                "missing": live is None,
                "url": "",
            }
        )
        position = match.end()
    if position < len(stored):
        pieces += _text_pieces(stored[position:])
    return style_pieces(pieces)


def _text_pieces(text: str) -> list[dict]:
    """Plain text with its links cut out: ``[name](address)`` and bare web addresses become
    {"type": "link", "text": what is shown, "url": where it goes}."""
    return [
        {"type": kind, "text": shown, "id": -1, "missing": False, "url": address}
        for kind, shown, address in split_links(text)
    ]


def to_edit_text(stored: str, name_of: NameOf) -> str:
    """Stored form -> what a text box should show (current names, braces without ids)."""

    def replace(match: re.Match) -> str:
        kind = ACTIVATORS[match.group(1)]
        live = name_of(kind, int(match.group(2)))
        name = live if live is not None else match.group(3)
        return f"{match.group(1)}{{{sanitize_name(name)}}}"

    return _STORED.sub(replace, stored)


def to_storage_text(edit: str, resolve: Resolve) -> str:
    """Edit form -> stored form. ``@{name}`` becomes ``@{id|name}`` when the name matches
    something; otherwise it stays as typed (plain text)."""

    def replace(match: re.Match) -> str:
        found = resolve(ACTIVATORS[match.group(1)], match.group(2).strip())
        if found is None:
            return match.group(0)
        ref_id, name = found
        return f"{match.group(1)}{{{ref_id}|{sanitize_name(name)}}}"

    return _EDIT.sub(replace, edit)


def referenced_resource_ids(stored_texts: Sequence[str]) -> set[int]:
    """Every resource mentioned (as ``@{id|name}``) in these stored texts, each once however
    often it is mentioned."""
    return {
        int(match.group(2))
        for text in stored_texts
        for match in _STORED.finditer(text)
        if match.group(1) == "@"
    }


def search(candidates: Sequence[tuple[int, str]], query: str, limit: int = 5) -> list[tuple[int, str]]:
    """The best ``limit`` matches: names starting with the query first, then names containing it.
    Case-insensitive; an empty query lists the first names alphabetically."""
    needle = query.strip().casefold()
    ordered = sorted(candidates, key=lambda item: item[1].casefold())
    if not needle:
        return ordered[:limit]
    starts = [c for c in ordered if c[1].casefold().startswith(needle)]
    contains = [c for c in ordered if needle in c[1].casefold() and c not in starts]
    return (starts + contains)[:limit]