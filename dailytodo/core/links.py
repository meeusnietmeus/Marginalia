"""Links in text: ``[name](address)`` shows ``name`` as a link, and a bare web address
(``https://...`` or ``www...``) is a link as it stands. No Qt and no storage in here.

Todos, notes, questions and answers all use this one function, so they read links the same way.
"""
from __future__ import annotations

import re

# [name](address): the address is a web address, anything with :// (obsidian://, file://...) or mailto:
_MARKDOWN = (
    r"\[(?P<label>[^\[\]\n]+)\]\(\s*(?P<target>"
    r"(?:[A-Za-z][A-Za-z0-9+.\-]*://|mailto:|www\.)[^\s()]+"
    r")\s*\)"
)
_BARE = r"(?P<bare>\b(?:https?://|www\.)[^\s<>\"]+)"
_LINK = re.compile(f"{_MARKDOWN}|{_BARE}", re.IGNORECASE)
_TRAILING = re.compile(r"[.,;:!?'\")\]]+$")  # sentence punctuation after an address is not part of it


def with_scheme(address: str) -> str:
    """``www.example.org`` -> ``https://www.example.org``."""
    return "https://" + address if address.lower().startswith("www.") else address


def split_links(text: str) -> list[tuple[str, str, str]]:
    """Cut text into ("text", text, "") and ("link", shown text, address) pieces, in order."""
    pieces: list[tuple[str, str, str]] = []
    position = 0
    for match in _LINK.finditer(text):
        if match.group("bare") is not None:
            address = _TRAILING.sub("", match.group("bare"))
            end = match.start() + len(address)
            shown = address
        else:
            address, shown, end = match.group("target"), match.group("label"), match.end()
        if match.start() > position:
            pieces.append(("text", text[position : match.start()], ""))
        pieces.append(("link", shown, with_scheme(address)))
        position = end
    if position < len(text):
        pieces.append(("text", text[position:], ""))
    return pieces
