from __future__ import annotations

from dataclasses import dataclass

from ..core import DEFAULT_HIGHLIGHT_COLOR, Note, NoteId
from .keyed_list_model import KeyedListModel


@dataclass(frozen=True, slots=True)
class NoteEntry:
    """One row of a notes list: a note, a question or an answer, plus what the list needs to know."""

    id: NoteId
    page: int | None
    body: str
    is_question: bool
    parent_id: NoteId | None
    answered: bool  # a question that already has at least one answer
    is_global: bool  # not tied to a page
    highlight_id: int = -1  # the highlighted passage it is about, or -1
    quote: str = ""  # that passage's text, to show next to the note
    quote_color: str = DEFAULT_HIGHLIGHT_COLOR  # and its colour (a HIGHLIGHT_COLORS name)

    @classmethod
    def from_note(
        cls, note: Note, answered: bool = False, quote: str = "", quote_color: str = DEFAULT_HIGHLIGHT_COLOR
    ) -> NoteEntry:
        return cls(
            note.id, note.page, note.body, note.is_question, note.parent_id, answered,
            note.page is None,
            -1 if note.highlight_id is None else note.highlight_id,
            quote,
            quote_color,
        )


class NoteListModel(KeyedListModel[NoteEntry]):
    """Notes, or questions with their answers, for QML lists."""

    ROLES = {
        "noteId": "id",
        "page": "page",
        "body": "body",
        "isQuestion": "is_question",
        "parentId": "parent_id",
        "answered": "answered",
        "isGlobal": "is_global",
        "highlightId": "highlight_id",
        "quote": "quote",
        "quoteColor": "quote_color",
    }
    KEY = "id"