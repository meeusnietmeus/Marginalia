"""The notes of one open resource (one PDF tab): which page is showing, and its notes."""
from __future__ import annotations

from typing import Callable

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from ..core import (
    DEFAULT_HIGHLIGHT_COLOR,
    Highlight,
    HighlightId,
    Note,
    NoteId,
    Rect,
    ResourceId,
    timeline_groups,
)
from ..storage import RepositoryError, TodoRepository
from .note_list_model import NoteEntry, NoteListModel

PAGE_DEBOUNCE_MS = 250


def _entries(notes: list[Note], quotes: dict[int, Highlight]) -> list[NoteEntry]:
    answered = {n.parent_id for n in notes if n.parent_id is not None}
    entries = []
    for n in notes:
        h = quotes.get(n.highlight_id)
        entries.append(
            NoteEntry.from_note(
                n, n.id in answered, h.text if h else "", h.color if h else DEFAULT_HIGHLIGHT_COLOR
            )
        )
    return entries


def _plain(notes: list[Note], quotes: dict[int, Highlight]) -> list[NoteEntry]:
    return _entries([n for n in notes if not n.is_question and n.parent_id is None], quotes)


def _questions_with_answers(notes: list[Note], quotes: dict[int, Highlight]) -> list[NoteEntry]:
    """Each question, immediately followed by its answers (both oldest first)."""
    entries = {e.id: e for e in _entries(notes, quotes)}
    answers: dict[NoteId, list[Note]] = {}
    for n in notes:
        if n.parent_id is not None:
            answers.setdefault(n.parent_id, []).append(n)
    ordered: list[NoteEntry] = []
    for n in notes:
        if n.is_question:
            ordered.append(entries[n.id])
            ordered.extend(entries[a.id] for a in answers.get(n.id, []))
    return ordered


def _delete_message(snapshot: list[Note]) -> str:
    note = snapshot[0]
    if note.is_question:
        answers = len(snapshot) - 1
        return "Question deleted" if answers == 0 else f"Question and {answers} answer{'s' if answers > 1 else ''} deleted"
    return "Answer deleted" if note.parent_id is not None else "Note deleted"


class NotesSession(QObject):
    """Loads the notes of the page being viewed, and the global ones (not tied to a page).

    Page changes are debounced: scrolling quickly from page 1 to 50 emits dozens of
    ``setPage`` calls but only the page the user settles on is queried. The global lists do not
    depend on the page, so they are loaded once and after every change.
    """

    error = Signal(str)
    loadingChanged = Signal()
    highlightsChanged = Signal()
    notedPagesChanged = Signal()
    connectionsChanged = Signal()
    timelineChanged = Signal()
    globalCountsChanged = Signal()

    def __init__(
        self,
        repo: TodoRepository,
        resource_id: ResourceId,
        parent: QObject | None = None,
        debounce_ms: int = PAGE_DEBOUNCE_MS,
        undo_sink: Callable[[str, Callable[[], None]], None] | None = None,
        to_storage: Callable[[str], str] | None = None,
        connections: Callable[[ResourceId], list[dict]] | None = None,
    ):
        super().__init__(parent)
        self._to_storage = to_storage or (lambda text: text)  # `@{Name}` -> `@{id|Name}`
        self._connections_of = connections or (lambda resource_id: [])
        self._connections: list[dict] = []
        self._timeline: list[dict] = []
        self._global_counts = (0, 0)
        self._repo = repo
        self._undo_sink = undo_sink  # offered (message, restore) after every delete
        self._resource_id = resource_id
        self._page = 1
        self._loading = False
        self._notes = NoteListModel(self)  # plain notes of the page
        self._questions = NoteListModel(self)  # questions of the page, each followed by its answers
        self._global_notes = NoteListModel(self)
        self._global_questions = NoteListModel(self)
        self._highlights: list[Highlight] = []
        self._noted_pages: list[tuple[int, int]] = []
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.setInterval(debounce_ms)
        self._timer.timeout.connect(self._load)

    # ------------------------------------------------------------ properties
    @Property(QObject, constant=True)
    def notes(self) -> NoteListModel:
        return self._notes

    @Property(QObject, constant=True)
    def questions(self) -> NoteListModel:
        return self._questions

    @Property(QObject, constant=True)
    def globalNotes(self) -> NoteListModel:
        return self._global_notes

    @Property(QObject, constant=True)
    def globalQuestions(self) -> NoteListModel:
        return self._global_questions

    @Property("QVariantList", notify=highlightsChanged)
    def highlights(self) -> list:
        """Every highlight of the resource, as plain dicts for QML: id, page, text, rects
        ([x, y, w, h] in PDF points, from the page's top-left)."""
        return [
            {"id": h.id, "page": h.page, "text": h.text, "rects": [list(r) for r in h.rects],
             "color": h.color}
            for h in self._highlights
        ]

    @Property("QVariantList", notify=notedPagesChanged)
    def notedPages(self) -> list:
        """The pages that have notes or questions, as {page, count}: a resource without pages to
        scroll (a web link, a Word file) is browsed by these."""
        return [{"page": p, "count": c} for p, c in self._noted_pages]

    @Property("QVariantList", notify=connectionsChanged)
    def connections(self) -> list:
        """The resources directly connected to this one, for the graph: dicts with id, name, kind,
        missing, outgoing (this one mentions it) and incoming (it mentions this one)."""
        return self._connections

    @Property("QVariantList", notify=timelineChanged)
    def timeline(self) -> list:
        """Everything written at a timestamp of a video, per timestamp (see timeline_groups)."""
        return self._timeline

    @Property(int, notify=globalCountsChanged)
    def globalNoteCount(self) -> int:
        return self._global_counts[0]

    @Property(int, notify=globalCountsChanged)
    def globalQuestionCount(self) -> int:
        return self._global_counts[1]

    @Property(bool, notify=loadingChanged)
    def loading(self) -> bool:
        """True from a page change until that page's notes have arrived."""
        return self._loading

    def _set_loading(self, loading: bool) -> None:
        if loading != self._loading:
            self._loading = loading
            self.loadingChanged.emit()

    # ---------------------------------------------------------------- paging
    @Slot(int)
    def setPage(self, page: int) -> None:
        """The viewer moved to ``page`` (1-based). Loads its notes once things settle."""
        self._page = page
        self._set_loading(True)
        self._timer.start()  # restarts the countdown if it is already running

    @Slot(int)
    def loadNow(self, page: int) -> None:
        """Load immediately (when the tab opens)."""
        self._page = page
        self._timer.stop()
        self._load_highlights()
        self._load()
        self._load_global()
        self._load_connections()

    # --------------------------------------------------------------- writing
    @Slot(str, bool)
    def addNote(self, body: str, is_global: bool = False) -> None:
        self._add(body, is_global)

    @Slot(str, bool)
    def addQuestion(self, body: str, is_global: bool = False) -> None:
        self._add(body, is_global, is_question=True)

    @Slot(str, int)
    def addNoteTo(self, body: str, highlight_id: HighlightId) -> None:
        """A note about a highlighted passage (it lives on the highlight's page)."""
        self._add(body, False, highlight_id=highlight_id)

    @Slot(str, int)
    def addQuestionTo(self, body: str, highlight_id: HighlightId) -> None:
        self._add(body, False, is_question=True, highlight_id=highlight_id)

    @Slot(int, str)
    def addAnswer(self, question_id: NoteId, body: str) -> None:
        """Answer a question; the answer lives on the question's page (or is global with it)."""
        self._add(body, False, parent_id=question_id)

    @Slot(int, str)
    def editNote(self, note_id: NoteId, body: str) -> None:
        if body.strip():
            stored = self._to_storage(body.strip())
            self._write(lambda: self._repo.update_note(note_id, stored), "save")

    @Slot(int)
    def deleteNote(self, note_id: NoteId) -> None:
        """Delete a note / question (with its answers) / answer, and offer to undo it."""
        try:
            snapshot = self._repo.get_note_with_answers(note_id)  # kept for the undo
        except RepositoryError as exc:
            self.error.emit(f"Couldn't delete: {exc}")
            return
        if not snapshot or not self._write(lambda: self._repo.delete_note(note_id), "delete"):
            return
        if self._undo_sink is not None:
            self._undo_sink(_delete_message(snapshot), lambda: self._restore(snapshot))

    def _restore(self, snapshot: list[Note]) -> None:
        self._repo.restore_notes(snapshot)
        try:
            self._load()
            self._load_global()
            self._load_connections()
        except RuntimeError:
            pass  # the tab was closed in the meantime; the notes are back in the database

    @Slot(int)
    def moveToGlobal(self, note_id: NoteId) -> None:
        """Make a note (or a whole question with its answers) global."""
        self._write(lambda: self._repo.move_note(note_id, None), "move")

    @Slot(int, int)
    def moveToPage(self, note_id: NoteId, page: int) -> None:
        """Make a global note (or question thread) local to ``page``."""
        self._write(lambda: self._repo.move_note(note_id, page), "move")

    # ------------------------------------------------------------ highlights
    @Slot(int, str, "QVariantList", str, result=int)
    def addHighlight(
        self, page: int, text: str, rects: list, color: str = DEFAULT_HIGHLIGHT_COLOR
    ) -> int:
        """Permanently highlight a passage. ``rects`` is a list of [x, y, w, h] in PDF points.
        Returns the new highlight's id, or -1 if it could not be saved."""
        try:
            highlight = self._repo.add_highlight(
                self._resource_id, page, text.strip(), [tuple(r) for r in rects], color
            )
        except (RepositoryError, ValueError, TypeError) as exc:
            self.error.emit(f"Couldn't highlight: {exc}")
            return -1
        self._load_highlights()
        return highlight.id

    @Slot(int, str)
    def setHighlightColor(self, highlight_id: HighlightId, color: str) -> None:
        self._write_all(lambda: self._repo.set_highlight_color(highlight_id, color), "recolour")

    @Slot("QVariantList", result="QVariantList")
    def boundingRects(self, polygons: list) -> list:
        """The bounding [x, y, w, h] of each polygon of a text selection (QML can't read them)."""
        rects = []
        for polygon in polygons:
            box = polygon.boundingRect()
            if box.width() > 0 and box.height() > 0:
                rects.append([box.x(), box.y(), box.width(), box.height()])
        return rects

    @Slot(int)
    def deleteHighlight(self, highlight_id: HighlightId) -> None:
        """Remove a highlight (notes about it stay) and offer to undo."""
        highlight = next((h for h in self._highlights if h.id == highlight_id), None)
        if highlight is None:
            return
        try:
            note_ids = self._repo.highlight_note_ids(highlight_id)
            self._repo.delete_highlight(highlight_id)
        except RepositoryError as exc:
            self.error.emit(f"Couldn't remove the highlight: {exc}")
            return
        self._refresh_all()
        if self._undo_sink is not None:
            self._undo_sink(
                "Highlight removed", lambda: self._restore_highlight(highlight, note_ids)
            )

    def _restore_highlight(self, highlight: Highlight, note_ids: list[NoteId]) -> None:
        self._repo.restore_highlight(highlight, note_ids)
        try:
            self._refresh_all()
        except RuntimeError:
            pass  # the tab was closed in the meantime; the highlight is back in the database

    @Slot(int, int)
    def linkNote(self, note_id: NoteId, highlight_id: HighlightId) -> None:
        """Tie a local note or question to a highlight on its page."""
        self._write_all(lambda: self._repo.set_note_highlight(note_id, highlight_id), "link")

    @Slot(int)
    def unlinkNote(self, note_id: NoteId) -> None:
        self._write_all(lambda: self._repo.set_note_highlight(note_id, None), "unlink")

    @Slot()
    def dispose(self) -> None:
        """The tab was closed."""
        self._timer.stop()
        self.deleteLater()

    # ------------------------------------------------------------- internals
    def _add(
        self,
        body: str,
        is_global: bool,
        *,
        is_question: bool = False,
        parent_id: NoteId | None = None,
        highlight_id: HighlightId | None = None,
    ) -> None:
        body = self._to_storage(body.strip())
        if not body:
            return
        page = None if is_global else self._page
        self._write(
            lambda: self._repo.add_note(
                self._resource_id, page, body, is_question=is_question, parent_id=parent_id,
                highlight_id=highlight_id,
            ),
            "save",
        )

    def _write(self, action, verb: str) -> bool:
        """Run a repository write, report a failure, then reload. True when it was saved."""
        try:
            action()
        except RepositoryError as exc:
            self.error.emit(f"Couldn't {verb}: {exc}")
            return False
        self._load()
        self._load_global()
        self._load_connections()
        return True

    def _quotes(self) -> dict[int, Highlight]:
        return {h.id: h for h in self._highlights}

    def _write_all(self, action, verb: str) -> None:
        try:
            action()
        except RepositoryError as exc:
            self.error.emit(f"Couldn't {verb}: {exc}")
            return
        self._refresh_all()

    def _refresh_all(self) -> None:
        self._load_highlights()
        self._load()
        self._load_global()

    def _load_highlights(self) -> None:
        try:
            self._highlights = self._repo.list_highlights(self._resource_id)
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load highlights: {exc}")
            return
        self.highlightsChanged.emit()

    def _load_noted_pages(self) -> None:
        try:
            pages = self._repo.list_note_pages(self._resource_id)
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load notes: {exc}")
            return
        if pages != self._noted_pages:
            self._noted_pages = pages
            self.notedPagesChanged.emit()

    def _load(self) -> None:
        self._load_noted_pages()
        try:
            everything = self._repo.list_notes(self._resource_id, self._page)
            quotes = self._quotes()
            self._notes.set_rows(_plain(everything, quotes))
            self._questions.set_rows(_questions_with_answers(everything, quotes))
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load notes: {exc}")
        finally:
            self._set_loading(False)

    def _load_global(self) -> None:
        try:
            everything = self._repo.list_notes(self._resource_id, None)
            quotes = self._quotes()
            plain = _plain(everything, quotes)
            questions = _questions_with_answers(everything, quotes)
            self._global_notes.set_rows(plain)
            self._global_questions.set_rows(questions)
            counts = (len(plain), sum(1 for q in questions if q.is_question))
            if counts != self._global_counts:
                self._global_counts = counts
                self.globalCountsChanged.emit()
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load notes: {exc}")
        self._load_timeline()

    def _load_timeline(self) -> None:
        try:
            groups = timeline_groups(self._repo.list_all_notes(self._resource_id))
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load the timeline: {exc}")
            return
        if groups != self._timeline:
            self._timeline = groups
            self.timelineChanged.emit()

    def _load_connections(self) -> None:
        try:
            connections = self._connections_of(self._resource_id)
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load the connections: {exc}")
            return
        if connections != self._connections:
            self._connections = connections
            self.connectionsChanged.emit()

    @Slot()
    def refreshConnections(self) -> None:
        """Look again (a resource may have been renamed or deleted since)."""
        self._load_connections()
