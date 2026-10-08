"""State of the "Open questions" page: resources with unanswered questions, and the questions of
the one that is selected, or of all of them (selection -1)."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Mapping

from PySide6.QtCore import Property, QObject, Signal, Slot

from ..core import (
    Note,
    NoteId,
    ResourceCard,
    ResourceId,
    ResourceQuestions,
    WorkspaceId,
    group_by_resource,
    order_for_resource,
    page_label,
)
from ..storage import RepositoryError, TodoRepository
from .keyed_list_model import KeyedListModel


class OpenResourceModel(KeyedListModel[ResourceQuestions]):
    ROLES = {
        "resourceId": "resource_id",
        "name": "name",
        "kind": "kind",
        "missing": "missing",
        "count": "count",
    }
    KEY = "resource_id"


@dataclass(frozen=True, slots=True)
class OpenQuestion:
    id: NoteId
    page: int | None
    body: str
    page_label: str  # "Page 3" / "General"
    resource_id: ResourceId
    resource_name: str
    kind: str
    # one heading per resource and page, carrying what it shows: "<id>|<page label>|<kind>|<name>"
    section: str


class OpenQuestionModel(KeyedListModel[OpenQuestion]):
    ROLES = {
        "noteId": "id",
        "page": "page",
        "body": "body",
        "pageLabel": "page_label",
        "resourceId": "resource_id",
        "resourceName": "resource_name",
        "kind": "kind",
        "section": "section",
    }
    KEY = "id"


class OpenQuestions(QObject):
    """Unanswered questions of the active workspace.

    Nothing here is live: notes are written from PDF tabs through their own sessions, so the page
    calls ``refresh()`` whenever it comes into view, and every change made here refreshes too.
    """

    error = Signal(str)
    changed = Signal()
    selectionChanged = Signal()

    def __init__(
        self,
        repo: TodoRepository,
        workspace_id: Callable[[], WorkspaceId],
        cards: Callable[[], Mapping[ResourceId, ResourceCard]],
        undo_sink: Callable[[str, Callable[[], None]], None],
        parent: QObject | None = None,
        to_storage: Callable[[str], str] | None = None,
    ):
        super().__init__(parent)
        self._to_storage = to_storage or (lambda text: text)  # `@{Name}` -> `@{id|Name}`
        self._repo = repo
        self._workspace_id = workspace_id
        self._cards = cards
        self._undo_sink = undo_sink
        self._all: list[Note] = []
        self._selected: ResourceId = -1
        self._resources = OpenResourceModel(self)
        self._questions = OpenQuestionModel(self)

    # ------------------------------------------------------------ properties
    @Property(QObject, constant=True)
    def resources(self) -> OpenResourceModel:
        return self._resources

    @Property(QObject, constant=True)
    def questions(self) -> OpenQuestionModel:
        return self._questions

    @Property(int, notify=changed)
    def total(self) -> int:
        return len(self._all)

    @Property(int, notify=selectionChanged)
    def selectedResourceId(self) -> int:
        """The resource whose questions are shown; -1: those of every resource."""
        return self._selected

    @Property(int, notify=selectionChanged)
    def shownCount(self) -> int:
        """How many questions are shown (those of the selected resource, or all)."""
        return self._questions.rowCount()

    @Property(str, notify=selectionChanged)
    def selectedName(self) -> str:
        card = self._cards().get(self._selected)
        return card.name if card else ""

    @Property(bool, notify=selectionChanged)
    def selectedIsVideo(self) -> bool:
        card = self._cards().get(self._selected)
        return card is not None and card.kind == "video"

    @Property(bool, notify=selectionChanged)
    def selectedCanOpen(self) -> bool:
        """The selected resource is still there (a file that was deleted is not): a question can
        be shown in its tab, the PDF at its page or a notes / video tab at its position."""
        card = self._cards().get(self._selected)
        return card is not None and not card.missing

    # --------------------------------------------------------------- actions
    @Slot()
    def refresh(self) -> None:
        try:
            self._all = self._repo.list_open_questions(self._workspace_id())
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load the open questions: {exc}")
            return
        rows = group_by_resource(self._all, self._cards())
        self._resources.set_rows(rows)
        if self._selected not in {r.resource_id for r in rows}:
            self._selected = -1  # all of its questions got answered (or it is gone): show all
        self._show_selected()
        self.changed.emit()
        self.selectionChanged.emit()

    @Slot(int)
    def select(self, resource_id: ResourceId) -> None:
        self._selected = resource_id
        self._show_selected()
        self.selectionChanged.emit()

    @Slot(int, str)
    def answer(self, question_id: NoteId, body: str) -> None:
        """Answer a question. It is then no longer open, so it leaves the list."""
        body = self._to_storage(body.strip())
        question = next((q for q in self._all if q.id == question_id), None)
        if not body or question is None:
            return
        self._write(
            lambda: self._repo.add_note(
                question.resource_id, question.page, body, parent_id=question_id
            ),
            "save",
        )

    @Slot(int, str)
    def edit(self, question_id: NoteId, body: str) -> None:
        if body.strip():
            self._write(lambda: self._repo.update_note(question_id, self._to_storage(body.strip())), "save")

    @Slot(int)
    def delete(self, question_id: NoteId) -> None:
        try:
            snapshot = self._repo.get_note_with_answers(question_id)  # for the undo
        except RepositoryError as exc:
            self.error.emit(f"Couldn't delete: {exc}")
            return
        if not snapshot or not self._write(lambda: self._repo.delete_note(question_id), "delete"):
            return
        self._undo_sink("Question deleted", lambda: self._restore(snapshot))

    @Slot(int, result=int)
    def pageOf(self, question_id: NoteId) -> int:
        """The page of a question, or 0 when it is about the whole resource."""
        question = next((q for q in self._all if q.id == question_id), None)
        return question.page or 0 if question else 0

    # ------------------------------------------------------------- internals
    def _restore(self, snapshot: list[Note]) -> None:
        self._repo.restore_notes(snapshot)
        try:
            self.refresh()
        except RuntimeError:
            pass  # the page is gone; the question is back in the database

    def _write(self, action, verb: str) -> bool:
        """Run a repository write, report a failure, then refresh. True when it was saved."""
        try:
            action()
        except RepositoryError as exc:
            self.error.emit(f"Couldn't {verb}: {exc}")
            return False
        self.refresh()
        return True

    def _show_selected(self) -> None:
        """The questions of the selected resource in reading order; with none selected, those of
        every resource, resource by resource (most questions first, like the list of them)."""
        cards = self._cards()
        if self._selected >= 0:
            shown = [self._selected]
        else:
            shown = [r.resource_id for r in self._resources.rows]
        rows = []
        for rid in shown:
            card = cards.get(rid)
            if card is None:
                continue
            video = card.kind == "video"
            for n in order_for_resource(self._all, rid):
                label = page_label(n.page, video)
                rows.append(OpenQuestion(n.id, n.page, n.body, label, rid, card.name, card.kind, f"{rid}|{label}|{card.kind}|{card.name}"))
        self._questions.set_rows(rows)
