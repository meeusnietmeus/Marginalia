"""PowerPoint presentations: when the PDF made from one is out of date, and what a presentation
carries besides its slides (speaker notes and comments).

A presentation is shown as a PDF made from it by PowerPoint (see ``dailytodo/powerpoint.py``).
Known limits of that approach, kept here so they are not forgotten:

* hidden slides are exported too, so slide n is always page n of the PDF;
* animations and transitions are gone: every slide is one still picture;
* ink (pen strokes) is only there if PowerPoint draws it into the slide, it is not read separately;
* a PDF is only made again when the presentation is newer than it (modified time), so a PDF that
  is edited by hand, or a clock that is wrong, is trusted;
* the PDF has the name of the presentation, so two presentations of the same name in different
  folders share one PDF in a workspace's folder.

Reading the annotations needs neither PowerPoint nor the PDF: a .pptx is a zip of XML files. No Qt
and no storage in here, so it is plain unit-testable logic.
"""
from __future__ import annotations

import zipfile
from dataclasses import dataclass, field
from pathlib import PurePath
from xml.etree import ElementTree

PRESENTATION_EXTENSIONS = (".ppt", ".pptx", ".pptm", ".pps", ".ppsx")


def is_presentation(uri: str) -> bool:
    return PurePath(uri.replace("\\", "/")).suffix.lower() in PRESENTATION_EXTENSIONS


LEGACY_EXTENSIONS = (".ppt", ".pps")  # binary files: only PowerPoint can read what is in them


def is_legacy_format(uri: str) -> bool:
    """An old (pre-2007) presentation: not a zip of XML files, so read_annotations can't open it."""
    return PurePath(uri.replace("\\", "/")).suffix.lower() in LEGACY_EXTENSIONS


def pdf_file_name(uri: str) -> str:
    """``C:\\decks\\Lecture 3.pptx`` -> ``Lecture 3.pdf``."""
    return PurePath(uri.replace("\\", "/")).stem + ".pdf"


def export_needed(pdf_modified: float | None, presentation_modified: float) -> bool:
    """Is there no PDF yet, or is it older than the presentation?"""
    return pdf_modified is None or pdf_modified < presentation_modified


# ------------------------------------------------------------------ annotations
@dataclass(frozen=True, slots=True)
class SlideComment:
    author: str
    text: str
    created: str = ""  # as saved in the file (ISO 8601), "" when unknown
    is_reply: bool = False


@dataclass(frozen=True, slots=True)
class SlideAnnotations:
    slide: int  # 1-based, the page of the PDF
    notes: str = ""  # the speaker notes
    comments: tuple[SlideComment, ...] = field(default_factory=tuple)

    @property
    def empty(self) -> bool:
        return not self.notes and not self.comments


_RELATIONSHIPS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _children(element: ElementTree.Element, name: str) -> list[ElementTree.Element]:
    return [c for c in element if _local(c.tag) == name]


def _descendants(element: ElementTree.Element, name: str) -> list[ElementTree.Element]:
    return [e for e in element.iter() if _local(e.tag) == name]


def _paragraphs(element: ElementTree.Element) -> str:
    """The text of every paragraph (``a:p``) below an element, one per line."""
    lines = [
        "".join(t.text or "" for t in _descendants(paragraph, "t"))
        for paragraph in _descendants(element, "p")
    ]
    return "\n".join(lines).strip()


def _resolve(base: str, target: str) -> str:
    """A relationship target (``../notesSlides/n.xml``) as a path inside the zip."""
    if target.startswith("/"):
        return target.lstrip("/")
    parts = base.split("/")[:-1]
    for piece in target.split("/"):
        if piece == "..":
            parts and parts.pop()
        elif piece and piece != ".":
            parts.append(piece)
    return "/".join(parts)


def _relationships(archive: zipfile.ZipFile, part: str) -> list[tuple[str, str, str]]:
    """(id, type, target path) of every relationship of a part."""
    folder, _, name = part.rpartition("/")
    rels = f"{folder}/_rels/{name}.rels" if folder else f"_rels/{name}.rels"
    if rels not in archive.namelist():
        return []
    root = ElementTree.fromstring(archive.read(rels))
    return [
        (r.get("Id", ""), r.get("Type", ""), _resolve(part, r.get("Target", "")))
        for r in root
        if r.get("TargetMode") != "External"
    ]


def _authors(archive: zipfile.ZipFile) -> dict[str, str]:
    """Author id -> name, from both the old (commentAuthors.xml) and the modern (authors.xml) list."""
    names: dict[str, str] = {}
    for part in ("ppt/commentAuthors.xml", "ppt/authors.xml"):
        if part in archive.namelist():
            for author in ElementTree.fromstring(archive.read(part)):
                if author.get("id") is not None:
                    names[author.get("id", "")] = author.get("name", "")
    return names


def _notes_text(archive: zipfile.ZipFile, part: str) -> str:
    root = ElementTree.fromstring(archive.read(part))
    for shape in _descendants(root, "sp"):
        for placeholder in _descendants(shape, "ph"):
            if placeholder.get("type") == "body":
                body = next(iter(_descendants(shape, "txBody")), None)
                if body is not None:
                    return _paragraphs(body)
    return ""


def _comments(archive: zipfile.ZipFile, part: str, authors: dict[str, str]) -> list[SlideComment]:
    root = ElementTree.fromstring(archive.read(part))
    found: list[SlideComment] = []
    for comment in _descendants(root, "cm"):
        author = authors.get(comment.get("authorId", ""), "")
        if _children(comment, "text"):  # the old format: <p:text>plain text</p:text>
            found.append(SlideComment(author, (_children(comment, "text")[0].text or "").strip(),
                                      comment.get("dt", "")))
            continue
        bodies = _children(comment, "txBody")  # the modern format: rich text, then replies
        found.append(SlideComment(author, _paragraphs(bodies[0]) if bodies else "", comment.get("created", "")))
        for reply in _descendants(comment, "reply"):
            reply_body = _children(reply, "txBody")
            found.append(
                SlideComment(
                    authors.get(reply.get("authorId", ""), ""),
                    _paragraphs(reply_body[0]) if reply_body else "",
                    reply.get("created", ""),
                    is_reply=True,
                )
            )
    return [c for c in found if c.text]


def read_annotations(path: str) -> list[SlideAnnotations]:
    """The speaker notes and comments of every slide that has some, in slide order.

    Anything that is not a readable .pptx (an old .ppt, a damaged file) has none: this is only a
    bonus next to the slides, so it never raises.
    """
    try:
        with zipfile.ZipFile(path) as archive:
            return _read(archive)
    except (OSError, zipfile.BadZipFile, ElementTree.ParseError, KeyError, ValueError):
        return []


def _read(archive: zipfile.ZipFile) -> list[SlideAnnotations]:
    presentation = "ppt/presentation.xml"
    slide_ids = [
        e.get(f"{{{_RELATIONSHIPS}}}id") or ""
        for e in ElementTree.fromstring(archive.read(presentation)).iter()
        if _local(e.tag) == "sldId"
    ]
    target_of = {rid: target for rid, _, target in _relationships(archive, presentation)}
    authors = _authors(archive)
    result: list[SlideAnnotations] = []
    for number, rid in enumerate(slide_ids, start=1):
        slide = target_of.get(rid)
        if slide is None or slide not in archive.namelist():
            continue
        notes = ""
        comments: list[SlideComment] = []
        for _, kind, target in _relationships(archive, slide):
            if target not in archive.namelist():
                continue
            if kind.endswith("/notesSlide"):
                notes = _notes_text(archive, target)
            elif kind.endswith("/comments"):
                comments += _comments(archive, target, authors)
        annotations = SlideAnnotations(number, notes, tuple(comments))
        if not annotations.empty:
            result.append(annotations)
    return result
