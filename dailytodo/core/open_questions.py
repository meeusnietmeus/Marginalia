"""The "open questions" overview: unanswered questions, per resource and grouped by page."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

from .models import Note, ResourceId
from .resources import ResourceCard
from .video import format_timestamp


@dataclass(frozen=True, slots=True)
class ResourceQuestions:
    """One resource with how many unanswered questions it has."""

    resource_id: ResourceId
    name: str
    kind: str
    missing: bool
    count: int


def page_label(page: int | None, video: bool = False) -> str:
    """The heading a question is listed under: its page, or for a video its timestamp."""
    if page is None:
        return "General"
    return f"At {format_timestamp(page)}" if video else f"Page {page}"


def group_by_resource(
    questions: Sequence[Note], cards: Mapping[ResourceId, ResourceCard]
) -> list[ResourceQuestions]:
    """Resources that have open questions, most questions first (then by name).

    Questions of a resource the workspace doesn't list are skipped."""
    counts: dict[ResourceId, int] = {}
    for q in questions:
        counts[q.resource_id] = counts.get(q.resource_id, 0) + 1
    rows = [
        ResourceQuestions(rid, cards[rid].name, cards[rid].kind, cards[rid].missing, n)
        for rid, n in counts.items()
        if rid in cards
    ]
    return sorted(rows, key=lambda r: (-r.count, r.name.casefold(), r.resource_id))


def order_for_resource(questions: Sequence[Note], resource_id: ResourceId) -> list[Note]:
    """One resource's questions in reading order: the general ones (no page) first, then by page,
    and within a page oldest first, so that questions on the same page sit together."""
    mine = [q for q in questions if q.resource_id == resource_id]
    return sorted(mine, key=lambda q: (q.page is not None, q.page or 0, q.id))
