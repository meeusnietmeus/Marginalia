"""Light markdown for todo text: ``- bullet``, ``*italic*``, ``**bold**`` and ``$formula$``.

The stored text keeps the raw markers; this only decides how to *show* it. It works on the pieces
``references.segments`` produced, so bold and italic can wrap a link or a reference too. The markers
are dropped from the shown text and a ``-`` at the start of a line becomes a bullet, so a piece's
``text`` is always exactly what is drawn.

No Qt and no storage in here, so it is plain unit-testable logic.
"""
from __future__ import annotations

import re

_PLACEHOLDER = "￼"  # stands in for a non-text piece (link, resource, tag) while scanning
_BULLET = re.compile(r"^([ \t]*)-( )", re.MULTILINE)
_BOLD = re.compile(r"\*\*(?=\S)(.+?)(?<=\S)\*\*")
# $...$ opens before a non-space, closes after one and not before a digit: "$5 and $6" is prices
_MATH = re.compile(r"\$(?=[^\s$])([^$\n" + _PLACEHOLDER + r"]+?)(?<=[^\s$])\$(?!\d)")
_ITALIC = re.compile(r"\*(?=[^\s*])(.+?)(?<=[^\s*])\*")
BULLET_CHAR = "•"


def style_pieces(pieces: list[dict]) -> list[dict]:
    """Give every piece "bold" / "italic" flags, drop the markers and turn ``- `` into a bullet."""
    flat: list[str] = []
    owner: list[tuple[int, int]] = []  # flat index -> (piece index, offset inside its text)
    for index, piece in enumerate(pieces):
        if piece["type"] == "text":
            for offset, char in enumerate(piece["text"]):
                flat.append(char)
                owner.append((index, offset))
        else:
            flat.append(_PLACEHOLDER)
            owner.append((index, 0))
    text = "".join(flat)

    formulas = {m.start(): m for m in _MATH.finditer(text)}  # start -> match, inside text pieces only
    in_formula = [False] * len(text)
    for match in formulas.values():
        for i in range(match.start(), match.end()):
            in_formula[i] = True

    removed = [False] * len(text)
    bold = [False] * len(text)
    italic = [False] * len(text)

    for match in _BULLET.finditer(text):
        flat[match.start() + len(match.group(1))] = BULLET_CHAR

    # emphasis never crosses a line: scan each line on its own
    line_start = 0
    for line in text.split("\n"):
        line_range = list(range(line_start, line_start + len(line)))
        _mark(text, [i for i in line_range if not in_formula[i]], _BOLD, 2, removed, bold)
        # bold's markers are gone, so they can't pair up as italic ones
        _mark(text, [i for i in line_range if not removed[i] and not in_formula[i]], _ITALIC, 1, removed, italic)
        line_start += len(line) + 1

    out: list[dict] = []
    for i, char in enumerate(flat):
        if in_formula[i]:
            if i in formulas:  # the formula is one piece; its other characters are skipped
                out.append({"type": "math", "text": formulas[i].group(1), "id": -1, "missing": False,
                            "url": "", "bold": bold[i], "italic": italic[i]})
            continue
        if removed[i]:
            continue
        index, _ = owner[i]
        piece = pieces[index]
        flags = (bold[i], italic[i])
        if piece["type"] != "text":
            out.append({**piece, "bold": flags[0], "italic": flags[1]})
        elif out and out[-1]["type"] == "text" and out[-1]["_src"] == index \
                and (out[-1]["bold"], out[-1]["italic"]) == flags:
            out[-1]["text"] += char
        else:
            out.append({**piece, "text": char, "bold": flags[0], "italic": flags[1], "_src": index})
    for piece in out:
        piece.pop("_src", None)
    return out


def _mark(text: str, indexes: list[int], pattern: re.Pattern, width: int, removed: list[bool],
          styled: list[bool]) -> None:
    """Style every match of ``pattern`` in the characters at ``indexes`` and mark the ``width``
    markers on each side of it as removed."""
    shown = "".join(text[i] for i in indexes)
    for match in pattern.finditer(shown):
        start, end = match.start(), match.end()
        for k in list(range(start, start + width)) + list(range(end - width, end)):
            removed[indexes[k]] = True
        for k in range(start + width, end - width):
            styled[indexes[k]] = True
