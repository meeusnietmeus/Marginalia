"""A PDF's notes, questions and highlights as one Markdown document, grouped by page."""
from __future__ import annotations

import re
from datetime import date
from typing import Sequence

from .models import Highlight, Note
from .video import format_timestamp

_FORBIDDEN_IN_FILE_NAMES = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def safe_file_name(title: str, suffix: str = " - notes.md") -> str:
    """A file name that is valid on Windows, from a resource's name."""
    cleaned = _FORBIDDEN_IN_FILE_NAMES.sub(" ", title)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .")
    return (cleaned[:100].strip(" .") or "PDF") + suffix


def _plural(count: int, word: str) -> str:
    return f"{count} {word}{'' if count == 1 else 's'}"


def _indent(text: str, spaces: int) -> str:
    """Continuation lines of a list item line up under its text."""
    pad = " " * spaces
    first, *rest = text.strip().splitlines() or [""]
    return "\n".join([first] + [pad + line if line.strip() else "" for line in rest])


def _quote(text: str) -> list[str]:
    lines = text.strip().splitlines() or [""]
    return [f"> {line}".rstrip() for line in lines]


def _thread(note: Note, answers: dict[int, list[Note]]) -> list[str]:
    """A note, or a question with its answers, as list items."""
    if not note.is_question:
        return [f"- **Note:** {_indent(note.body, 2)}"]
    lines = [f"- **Question:** {_indent(note.body, 2)}"]
    given = answers.get(note.id, [])
    if not given:
        lines.append("  - *Not answered yet*")
    for answer in given:
        lines.append(f"  - **Answer:** {_indent(answer.body, 4)}")
    return lines


def _reading_order(highlight: Highlight) -> tuple[float, float, int]:
    first = highlight.rects[0] if highlight.rects else (0.0, 0.0, 0.0, 0.0)
    return (round(first[1]), first[0], highlight.id)  # top to bottom, then left to right


def pdf_markdown(
    title: str,
    notes: Sequence[Note],
    highlights: Sequence[Highlight],
    exported_on: date,
    timestamps: bool = False,
) -> str:
    """Everything written about a PDF, one section per page ("General" for what belongs to no page).

    Each highlighted passage is quoted, followed by the notes and questions about it; the notes
    that are not about a passage come after the quotes. Answers sit under their question."""
    answers: dict[int, list[Note]] = {}
    for n in notes:
        if n.parent_id is not None:
            answers.setdefault(n.parent_id, []).append(n)
    top_level = [n for n in notes if n.parent_id is None]
    about: dict[int, list[Note]] = {}
    for n in top_level:
        if n.highlight_id is not None:
            about.setdefault(n.highlight_id, []).append(n)

    pages = sorted({n.page for n in top_level if n.page is not None}
                   | {h.page for h in highlights})
    n_notes = sum(1 for n in top_level if not n.is_question)
    n_questions = sum(1 for n in top_level if n.is_question)

    out = [f"# {title}", ""]
    stats = [_plural(len(highlights), "highlight"), _plural(n_notes, "note"),
             _plural(n_questions, "question")]
    out += [f"*Exported {exported_on.day} {exported_on:%b %Y} · {' · '.join(stats)}*", ""]

    general = [n for n in top_level if n.page is None]
    if general:
        out += ["## General", ""]
        for n in general:
            out += _thread(n, answers)
        out.append("")

    for page in pages:
        out += [f"## At {format_timestamp(page)}" if timestamps else f"## Page {page}", ""]
        on_page = sorted((h for h in highlights if h.page == page), key=_reading_order)
        for h in on_page:
            out += _quote(h.text)
            linked = about.get(h.id, [])
            if linked:
                out.append("")
                for n in linked:
                    out += _thread(n, answers)
            out.append("")
        loose = [n for n in top_level if n.page == page and n.highlight_id is None]
        for n in loose:
            out += _thread(n, answers)
        if loose:
            out.append("")

    return "\n".join(out).rstrip() + "\n"
