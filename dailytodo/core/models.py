from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime

# If an API hands out UUIDs, change these aliases and the `int` slot signatures in
# ui/todo_controller.py (QML passes ids straight through).
TodoId = int
WorkspaceId = int
ResourceId = int
TagId = int
NoteId = int
HighlightId = int


@dataclass(frozen=True, slots=True)
class Todo:
    id: TodoId
    text: str
    done: bool
    day: date | None  # None = in the backlog (no date yet)
    priority: bool = False  # flagged as important
    in_progress: bool = False  # being worked on (a done todo is never in progress)


@dataclass(frozen=True, slots=True)
class Workspace:
    id: WorkspaceId
    name: str


@dataclass(frozen=True, slots=True)
class Tag:
    id: TagId
    name: str
    parent_id: TagId | None = None  # the tag this is a sub-tag of
    # The colour of a top-level tag (an index into the palette). None: automatic, by position. A
    # sub-tag never has its own: it uses its top tag's.
    color: int | None = None


@dataclass(frozen=True, slots=True)
class Note:
    """A note on a resource (e.g. a PDF). ``page`` is 1-based; None = about the whole resource.

    One table holds three things:
      * a plain note:  is_question False, parent_id None
      * a question:    is_question True,  parent_id None
      * an answer:     is_question False, parent_id = the question (same resource and page)
    """

    id: NoteId
    resource_id: ResourceId
    page: int | None
    body: str
    is_question: bool
    parent_id: NoteId | None
    created_at: datetime  # UTC
    updated_at: datetime  # UTC
    # A local note or question can be tied to a highlighted passage on its page.
    highlight_id: HighlightId | None = None


# The colours a highlight can have ("none" = transparent: no marker, but notes can still hang on it).
HIGHLIGHT_COLORS = ("yellow", "green", "blue", "pink", "orange", "purple", "none")
DEFAULT_HIGHLIGHT_COLOR = "yellow"

# One highlighted rectangle (one line of text): x, y, width, height in PDF points, measured from
# the top-left corner of the page, so it does not depend on the zoom level.
Rect = tuple[float, float, float, float]


@dataclass(frozen=True, slots=True)
class Highlight:
    """A permanently highlighted passage of a PDF page. Notes and questions can point at it."""

    id: HighlightId
    resource_id: ResourceId
    page: int  # 1-based
    text: str  # what was highlighted, for quoting it next to a note
    rects: tuple[Rect, ...]
    created_at: datetime  # UTC
    color: str = DEFAULT_HIGHLIGHT_COLOR  # one of HIGHLIGHT_COLORS


@dataclass(frozen=True, slots=True)
class Resource:
    """A link (web, custom protocol like obsidian://) or an absolute local file path."""

    id: ResourceId
    name: str
    uri: str
    created_at: datetime  # UTC
    last_used_at: datetime  # UTC; starts at created_at, bumped whenever the resource is opened
