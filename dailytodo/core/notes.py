"""Pure rules about the text of notes and questions."""
from __future__ import annotations

_QUESTION_MARKS = ("?", "？", "؟")  # ASCII, full-width, Arabic


def with_question_mark(text: str) -> str:
    """A question always ends in a question mark: ``"why does it work"`` -> ``"why does it work?"``.

    Surrounding whitespace is dropped, and so is a closing full stop (``"Why."`` -> ``"Why?"``).
    Blank text stays blank, so the "a note needs text" rule still catches it.
    """
    text = text.strip()
    if not text:
        return ""
    if text.endswith(_QUESTION_MARKS):
        return text
    return text.rstrip(".").rstrip() + "?" if text.endswith(".") else text + "?"