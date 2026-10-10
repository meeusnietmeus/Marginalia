"""Everything written about one PDF / presentation as a single ordered list, for the unified view.

Rows come in two kinds: a "page" heading and the "thread" under it (a note, or a question with its
answers). What belongs to no page ("General") comes first, then the pages in order; inside a page
the notes about a highlighted passage come first (in reading order), then the others, oldest first.
No Qt and no storage in here, so it is plain unit-testable logic.
"""
from __future__ import annotations

from typing import Callable, Sequence

from .models import Highlight, Note
from .open_questions import page_label

FILTERS = ("all", "notes", "questions", "unanswered")


def _position(highlight: Highlight | None, note: Note) -> tuple:
    if highlight is None:
        return (1, 0.0, 0.0, note.id)
    first = highlight.rects[0] if highlight.rects else (0.0, 0.0, 0.0, 0.0)
    return (0, round(first[1]), first[0], note.id)  # top to bottom, then left to right


def unified_rows(
    notes: Sequence[Note],
    highlights: Sequence[Highlight],
    plain: Callable[[str], str] = lambda body: body,
    mode: str = "all",
    slides: bool = False,
) -> dict:
    """{"rows": [...], "notes": n, "questions": n, "unanswered": n} (the counts ignore ``mode``).

    A page row is {"kind": "page", "page", "label", "notes", "questions"}; a thread row is
    {"kind": "thread", "id", "page", "body", "text", "isQuestion", "answered", "quote",
    "quoteColor", "answers": [{"id", "body", "text"}]}. ``body`` is the stored text (to render),
    ``text`` what ``plain`` makes of it (to search in). ``slides`` calls the pages "Slide n"."""
    quotes = {h.id: h for h in highlights}
    answers: dict[int, list[Note]] = {}
    for n in notes:
        if n.parent_id is not None:
            answers.setdefault(n.parent_id, []).append(n)
    threads = [n for n in notes if n.parent_id is None]

    counts = {
        "notes": sum(1 for n in threads if not n.is_question),
        "questions": sum(1 for n in threads if n.is_question),
        "unanswered": sum(1 for n in threads if n.is_question and n.id not in answers),
    }

    def wanted(n: Note) -> bool:
        return (
            mode == "all"
            or (mode == "notes" and not n.is_question)
            or (mode == "questions" and n.is_question)
            or (mode == "unanswered" and n.is_question and n.id not in answers)
        )

    by_page: dict[int, list[Note]] = {}
    for n in threads:
        if wanted(n):
            by_page.setdefault(0 if n.page is None else n.page, []).append(n)

    rows: list[dict] = []
    for page in sorted(by_page):  # 0 = General sorts first
        group = sorted(by_page[page], key=lambda n: _position(quotes.get(n.highlight_id), n))
        label = "General" if page == 0 else (f"Slide {page}" if slides else page_label(page))
        rows.append(
            {
                "kind": "page", "page": page, "label": label,
                "notes": sum(1 for n in group if not n.is_question),
                "questions": sum(1 for n in group if n.is_question),
            }
        )
        for n in group:
            quote = quotes.get(n.highlight_id)
            rows.append(
                {
                    "kind": "thread", "id": n.id, "page": page, "body": n.body, "text": plain(n.body),
                    "isQuestion": n.is_question, "answered": n.id in answers,
                    "quote": quote.text if quote else "", "quoteColor": quote.color if quote else "",
                    "answers": [
                        {"id": a.id, "body": a.body, "text": plain(a.body)}
                        for a in sorted(answers.get(n.id, []), key=lambda a: a.id)
                    ],
                }
            )
    return {"rows": rows, **counts}
