"""How the todos of a day (or of the backlog) are ordered. No Qt and no storage in here.

``created``   the order they were added in (the default)
``priority``  flagged ones first, then the rest, each in the order they were added
``tags``      a todo that starts with a ``!{tag}`` goes with the others of that tag, the tags in the
              order of the tag list; the todos without one come after the tagged ones

Every mode is stable, so inside a group todos keep the order they were added in.
"""
from __future__ import annotations

import re
from typing import Mapping, Sequence

from .models import Todo

SORT_CREATED = "created"
SORT_PRIORITY = "priority"
SORT_TAGS = "tags"
SORT_MODES = (SORT_CREATED, SORT_PRIORITY, SORT_TAGS)

_LEADING_TAG = re.compile(r"^\s*!\{(\d+)\|")


def leading_tag(text: str) -> int | None:
    """The tag a todo starts with (stored text, ``!{id|name}``), or None."""
    match = _LEADING_TAG.match(text)
    return int(match.group(1)) if match else None


def sort_todos(
    todos: Sequence[Todo],
    mode: str = SORT_CREATED,
    done_last: bool = False,
    tag_rank: Mapping[int, int] | None = None,
) -> list[Todo]:
    """``todos`` (in the order they were added) in the order ``mode`` asks for. With ``done_last``
    the done ones go behind the open ones, keeping that order among themselves."""
    rank = tag_rank or {}

    def key(todo: Todo) -> tuple:
        if mode == SORT_PRIORITY:
            group = 0 if todo.priority else 1
        elif mode == SORT_TAGS:
            tag = leading_tag(todo.text)
            group = rank[tag] if tag in rank else len(rank)  # no tag (or a gone one): after them all
        else:
            group = 0
        return (todo.done if done_last else False, group)

    return sorted(todos, key=key)  # sorted() is stable
