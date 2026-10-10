"""Tags (labels) can have sub-tags: ``Maths`` > ``Algebra`` > ``Linear``.

The rules live here, with no Qt and no storage:

* a tag has at most one parent, and never one of its own descendants (no loops);
* a resource tagged with a sub-tag counts for the tags above it too: filtering the library by
  ``Maths`` also finds what is tagged ``Algebra``;
* names stay unique within a workspace, wherever they sit in the tree, so ``!{Algebra}`` in a
  todo always means one tag.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from .models import Tag, TagId

SEPARATOR = " › "
COLOR_COUNT = 10  # the colours a top-level tag can have (Theme.areaColors)


@dataclass(frozen=True, slots=True)
class LabelRow:
    """A tag as the lists show it: in tree order, with how deep it sits."""

    id: TagId
    name: str
    parent_id: int  # -1: a top-level tag
    depth: int  # 0 for a top-level tag
    path: str  # "Maths › Algebra" (just the name for a top-level tag)
    child_count: int  # direct sub-tags
    family: int = 0  # its colour (see tag_colors): a tag and its sub-tags share one


def _children(tags: Sequence[Tag]) -> dict[int | None, list[Tag]]:
    ids = {t.id for t in tags}
    children: dict[int | None, list[Tag]] = {}
    for tag in sorted(tags, key=lambda t: (t.name.casefold(), t.id)):
        # a parent that is not there (another workspace, deleted) makes the tag a top-level one
        parent = tag.parent_id if tag.parent_id in ids else None
        children.setdefault(parent, []).append(tag)
    return children


def tag_colors(tags: Sequence[Tag]) -> dict[TagId, int]:
    """The colour (palette index) of every tag. A top-level tag has the one it was given, or else
    its position among the top-level tags; a sub-tag shares its top tag's."""
    children = _children(tags)
    colors: dict[TagId, int] = {}

    def paint(tag: Tag, color: int) -> None:
        if tag.id in colors:  # a loop in damaged data
            return
        colors[tag.id] = color
        for child in children.get(tag.id, []):
            paint(child, color)

    for number, top in enumerate(children.get(None, [])):
        paint(top, top.color if top.color is not None else number)
    return colors


def free_color(tags: Sequence[Tag]) -> int:
    """The first colour no top-level tag has yet (the palette starts over when all are taken)."""
    colors = tag_colors(tags)
    used = [colors[t.id] % COLOR_COUNT for t in tags if t.parent_id is None and t.id in colors]
    for color in range(COLOR_COUNT):
        if color not in used:
            return color
    return min(range(COLOR_COUNT), key=used.count)


def label_rows(tags: Sequence[Tag]) -> list[LabelRow]:
    """Every tag, depth first: a tag, then its sub-tags (by name), then the next tag."""
    children = _children(tags)
    colors = tag_colors(tags)
    rows: list[LabelRow] = []
    seen: set[TagId] = set()

    def walk(parent: int | None, depth: int, trail: tuple[str, ...], family: int) -> None:
        for number, tag in enumerate(children.get(parent, [])):
            if tag.id in seen:  # a loop in damaged data: show each tag once
                continue
            seen.add(tag.id)
            names = trail + (tag.name,)
            mine = colors.get(tag.id, number)
            rows.append(
                LabelRow(
                    tag.id, tag.name, -1 if parent is None else parent, depth,
                    SEPARATOR.join(names), len(children.get(tag.id, [])), mine,
                )
            )
            walk(tag.id, depth + 1, names, mine)

    walk(None, 0, (), 0)
    return rows


def descendants(tags: Sequence[Tag], tag_id: TagId) -> set[TagId]:
    """The tag itself and everything below it."""
    children = _children(tags)
    found: set[TagId] = set()
    pending = [tag_id]
    while pending:
        current = pending.pop()
        if current in found:
            continue
        found.add(current)
        pending.extend(t.id for t in children.get(current, []))
    return found


def ancestors(tags: Sequence[Tag], tag_id: TagId) -> list[TagId]:
    """The tags above one, nearest first."""
    parent_of = {t.id: t.parent_id for t in tags}
    chain: list[TagId] = []
    current = parent_of.get(tag_id)
    while current is not None and current in parent_of and current not in chain and current != tag_id:
        chain.append(current)
        current = parent_of[current]
    return chain


def valid_parents(tags: Sequence[Tag], tag_id: TagId | None) -> list[LabelRow]:
    """Where a tag may go: every tag except itself and what is below it (that would be a loop).
    For a tag that is not made yet (``None``) that is all of them."""
    banned = descendants(tags, tag_id) if tag_id is not None else set()
    return [row for row in label_rows(tags) if row.id not in banned]


def expand_filter(tags: Sequence[Tag], selected: set[TagId]) -> set[TagId]:
    """The tags a library filter really looks for: the picked ones and all their sub-tags."""
    expanded: set[TagId] = set()
    for tag_id in selected:
        expanded |= descendants(tags, tag_id)
    return expanded


def with_ancestors(tags: Sequence[Tag], tag_ids: Sequence[TagId]) -> list[TagId]:
    """The tags of a resource plus the ones above them (each once, own tags first)."""
    result = list(dict.fromkeys(tag_ids))
    for tag_id in list(result):
        for parent in ancestors(tags, tag_id):
            if parent not in result:
                result.append(parent)
    return result
