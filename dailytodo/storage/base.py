"""Storage contract for the todo app.

The UI layer only ever talks to ``TodoRepository``; whether the data lives in
SQLite or behind an HTTP API is decided in exactly one place (factory.py).
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import date
from pathlib import Path
from typing import Protocol, Sequence, runtime_checkable

from ..core.models import (
    DEFAULT_HIGHLIGHT_COLOR,
    Highlight,
    HighlightId,
    Note,
    NoteId,
    Rect,
    Resource,
    ResourceId,
    Tag,
    TagId,
    Todo,
    TodoId,
    Workspace,
    WorkspaceId,
)


class RepositoryError(Exception):
    """Any storage failure (SQLite error, network error, bad response...).

    Implementations translate their own exceptions into this one so the UI
    layer never needs to know what is behind the repository.
    """


class TodoRepository(ABC):
    """Everything the app needs from persistent storage."""

    @abstractmethod
    def list_workspaces(self) -> list[Workspace]:
        """All workspaces, in a stable order. There is always at least one."""

    @abstractmethod
    def create_workspace(self, name: str) -> Workspace:
        """Add a workspace. Raises RepositoryError if the name is already taken."""

    @abstractmethod
    def rename_workspace(self, workspace_id: WorkspaceId, name: str) -> None:
        """Raises RepositoryError if the name is already taken."""

    @abstractmethod
    def delete_workspace(self, workspace_id: WorkspaceId) -> None:
        """Delete a workspace together with all its todos."""

    @abstractmethod
    def list_resources(self, workspace_id: WorkspaceId) -> list[Resource]:
        """The resources of one workspace, oldest first."""

    @abstractmethod
    def list_resource_tags(self, workspace_id: WorkspaceId) -> dict[ResourceId, list[TagId]]:
        """Tag ids per resource (resources without tags are absent)."""

    @abstractmethod
    def add_resource(
        self, workspace_id: WorkspaceId, uri: str, name: str, tag_ids: Sequence[TagId] = ()
    ) -> Resource: ...

    @abstractmethod
    def update_resource(
        self, resource_id: ResourceId, uri: str, name: str, tag_ids: Sequence[TagId] = ()
    ) -> None:
        """Change the URI, name and tags (replaced as a whole). Does not count as a use."""

    @abstractmethod
    def touch_resource(self, resource_id: ResourceId) -> None:
        """Record that the resource was just opened (sets ``last_used_at``; an "unopened"
        resource becomes "opened", any other status stays)."""

    @abstractmethod
    def set_resource_status(self, resource_id: ResourceId, status: str) -> None:
        """Set how far along a resource is (one of ``core.STATUSES``)."""

    @abstractmethod
    def list_tags(self, workspace_id: WorkspaceId) -> list[Tag]:
        """The tags of one workspace, sorted by name."""

    @abstractmethod
    def create_tag(
        self, workspace_id: WorkspaceId, name: str, parent_id: TagId | None = None, color: int | None = None
    ) -> Tag:
        """Raises RepositoryError if the workspace already has a tag with that name."""

    @abstractmethod
    def set_tag_color(self, tag_id: TagId, color: int | None) -> None:
        """The colour (a palette index) of a top-level tag; None: automatic."""

    @abstractmethod
    def rename_tag(self, tag_id: TagId, name: str) -> None:
        """Raises RepositoryError if the workspace already has a tag with that name."""

    @abstractmethod
    def set_tag_parent(self, tag_id: TagId, parent_id: TagId | None) -> None:
        """Make a tag a sub-tag of another one of its workspace (None: top level). Refuses a loop."""

    @abstractmethod
    def delete_tag(self, tag_id: TagId) -> None:
        """Delete a tag; resources that had it simply lose it."""

    @abstractmethod
    def delete_resource(self, resource_id: ResourceId) -> None: ...

    @abstractmethod
    def count_notes(self, resource_id: ResourceId) -> tuple[int, int]:
        """(plain notes, questions) written on a resource, on any page. Answers are not counted:
        they belong to their question."""

    @abstractmethod
    def list_workspace_notes(self, workspace_id: WorkspaceId) -> list[Note]:
        """Every note, question and answer of the workspace's resources, oldest first."""

    @abstractmethod
    def list_open_questions(self, workspace_id: WorkspaceId) -> list[Note]:
        """Every question of the workspace's resources that has no answer yet, oldest first."""

    @abstractmethod
    def list_note_pages(self, resource_id: ResourceId) -> list[tuple[int, int]]:
        """(page, how many notes and questions) for every page of a resource that has any."""

    @abstractmethod
    def list_resource_links(self, resource_id: ResourceId) -> list[tuple[ResourceId, ResourceId]]:
        """(source, target) for every link that starts or ends at a resource: ``x -> y`` exists
        when a note of x mentions y with ``@{...}``, once however often it is mentioned. Kept up
        to date by the note writes."""

    @abstractmethod
    def list_workspace_links(self, workspace_id: WorkspaceId) -> list[tuple[ResourceId, ResourceId]]:
        """Every (source, target) link between resources of one workspace, in one read."""

    @abstractmethod
    def list_all_notes(self, resource_id: ResourceId) -> list[Note]:
        """Every note, question and answer of a resource, whatever its page, oldest first."""

    @abstractmethod
    def list_notes(self, resource_id: ResourceId, page: int | None) -> list[Note]:
        """Everything written on one page (None: not tied to a page), oldest first: plain notes,
        questions and answers alike (see ``Note``)."""

    @abstractmethod
    def add_note(
        self,
        resource_id: ResourceId,
        page: int | None,
        body: str,
        *,
        is_question: bool = False,
        parent_id: NoteId | None = None,
        highlight_id: HighlightId | None = None,
    ) -> Note:
        """Add a note or a question. With ``parent_id`` (a question) it becomes an answer to it,
        on the question's page. With ``highlight_id`` it is tied to that highlighted passage and
        lives on its page."""

    @abstractmethod
    def add_highlight(
        self,
        resource_id: ResourceId,
        page: int,
        text: str,
        rects: Sequence[Rect],
        color: str = DEFAULT_HIGHLIGHT_COLOR,
    ) -> Highlight:
        """Permanently highlight a passage (one rectangle per line, in PDF points)."""

    @abstractmethod
    def set_highlight_color(self, highlight_id: HighlightId, color: str) -> None:
        """Recolour a highlight (one of HIGHLIGHT_COLORS)."""

    @abstractmethod
    def list_highlights(self, resource_id: ResourceId) -> list[Highlight]:
        """All highlights of a resource, by page."""

    @abstractmethod
    def delete_highlight(self, highlight_id: HighlightId) -> None:
        """Remove a highlight. Notes that pointed at it stay, just without the link."""

    @abstractmethod
    def highlight_note_ids(self, highlight_id: HighlightId) -> list[NoteId]:
        """The notes tied to a highlight (to put the links back on undo)."""

    @abstractmethod
    def restore_highlight(self, highlight: Highlight, note_ids: Sequence[NoteId]) -> None:
        """Put a deleted highlight back, and re-tie the notes that pointed at it."""

    @abstractmethod
    def set_note_highlight(self, note_id: NoteId, highlight_id: HighlightId | None) -> None:
        """Tie a note or question to a highlight on its page, or untie it with None."""

    @abstractmethod
    def move_note(self, note_id: NoteId, page: int | None) -> None:
        """Make a note local (``page``) or global (None). A question and its answers always share a
        page, so moving either one moves the whole thread."""

    @abstractmethod
    def update_note(self, note_id: NoteId, body: str) -> None:
        """Change a note's text and bump ``updated_at``."""

    @abstractmethod
    def delete_note(self, note_id: NoteId) -> None: ...

    @abstractmethod
    def get_note_with_answers(self, note_id: NoteId) -> list[Note]:
        """The note, followed by its answers when it is a question (what deleting it removes).
        Empty if there is no such note."""

    @abstractmethod
    def restore_notes(self, notes: Sequence[Note]) -> None:
        """Put back notes that were deleted, with their old ids (a question before its answers)."""

    @abstractmethod
    def list_todos(self, workspace_id: WorkspaceId) -> list[Todo]:
        """The todos of one workspace, ordered by day then id. Backlog todos (``day`` None)
        come first, in the order they were added."""

    @abstractmethod
    def add(self, workspace_id: WorkspaceId, day: date | None, text: str) -> Todo:
        """Add a todo; ``day`` None puts it in the backlog."""

    @abstractmethod
    def set_done(self, todo_id: TodoId, done: bool) -> None:
        """Done or not; a todo that is done is no longer in progress."""

    @abstractmethod
    def set_priority(self, todo_id: TodoId, priority: bool) -> None: ...

    @abstractmethod
    def set_in_progress(self, todo_id: TodoId, in_progress: bool) -> None:
        """In progress or not; a todo that is put in progress is no longer done."""

    @abstractmethod
    def move_to_day(self, todo_id: TodoId, day: date | None) -> None:
        """Give a todo a day, or ``None`` to move it to the backlog."""

    @abstractmethod
    def move_open_todos(self, workspace_id: WorkspaceId, from_day: date, to_day: date) -> None:
        """Move every uncompleted todo of ``from_day`` (in one workspace) to ``to_day``."""

    @abstractmethod
    def update_text(self, todo_id: TodoId, text: str) -> None: ...

    @abstractmethod
    def delete(self, todo_id: TodoId) -> None: ...

    @abstractmethod
    def restore_todo(self, workspace_id: WorkspaceId, todo: Todo) -> None:
        """Put back a deleted todo with its old id (so it returns to its old place in the day)."""

    def close(self) -> None:
        """Release resources (connections, sessions). Optional."""


@runtime_checkable
class BackupCapable(Protocol):
    """Optional capability: repositories that can dump themselves to a file.

    A local database can; a remote API usually can't, so it isn't part of
    ``TodoRepository``. The UI checks for it with ``isinstance``.
    """

    backup_suffix: str  # file extension of the dump, e.g. ".db"

    def backup_to(self, dest: Path) -> None: ...
