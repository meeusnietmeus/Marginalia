"""Searching the text of every note, question and answer of a workspace.

A plain, case-insensitive "contains" on the text as the user wrote it (``@{Name}`` rather than the
stored ``@{id|Name}``). The matches are grouped per resource. Nothing clever on purpose: no index,
no fuzzy matching. No Qt and no storage in here, so it is plain unit-testable logic.
"""
from __future__ import annotations

from typing import Callable, Mapping, Sequence

from .models import Note, ResourceId
from .open_questions import page_label
from .resources import ResourceCard


def _kind(note: Note) -> str:
    return "answer" if note.parent_id is not None else "question" if note.is_question else "note"


def search_notes(
    notes: Sequence[Note],
    cards: Mapping[ResourceId, ResourceCard],
    term: str,
    plain: Callable[[str], str] = lambda body: body,
) -> dict:
    """{"total": n, "groups": [...]}: one group per resource with a match, the one with most
    matches first (then by name). A group is {"resourceId", "name", "kind", "missing", "items"};
    an item is {"id", "kind" ("note" | "question" | "answer"), "page" (0: not about a page),
    "pageLabel", "body" (stored, to render), "text" (what was searched), "answered" (a question),
    "question" (for an answer: the question it belongs to)}. Within a group: General first, then by
    page, then oldest first. Notes of a resource that isn't in ``cards`` are skipped."""
    needle = term.strip().casefold()
    if not needle:
        return {"total": 0, "groups": []}
    by_id = {n.id: n for n in notes}
    answered = {n.parent_id for n in notes if n.parent_id is not None}
    found: dict[ResourceId, list[Note]] = {}
    for note in notes:
        if note.resource_id in cards and needle in plain(note.body).casefold():
            found.setdefault(note.resource_id, []).append(note)

    groups = []
    for resource_id, matches in found.items():
        card = cards[resource_id]
        video = card.kind == "video"
        slides = card.kind == "powerpoint"
        items = []
        for note in sorted(matches, key=lambda n: (n.page or 0, n.id)):
            parent = by_id.get(note.parent_id) if note.parent_id is not None else None
            page = note.page or 0
            items.append(
                {
                    "id": note.id,
                    "kind": _kind(note),
                    "page": page,
                    "pageLabel": f"Slide {page}" if slides and page else page_label(note.page, video),
                    "body": note.body,
                    "text": plain(note.body),
                    "answered": note.is_question and note.id in answered,
                    "question": plain(parent.body) if parent else "",
                }
            )
        groups.append(
            {"resourceId": resource_id, "name": card.name, "kind": card.kind, "missing": card.missing,
             "items": items}
        )
    groups.sort(key=lambda g: (-len(g["items"]), g["name"].casefold(), g["resourceId"]))
    return {"total": sum(len(g["items"]) for g in groups), "groups": groups}
