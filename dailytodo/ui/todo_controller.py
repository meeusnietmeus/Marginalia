"""The object QML talks to: exposes the day model and the actions on todos."""
from __future__ import annotations

from dataclasses import replace
import itertools
import os
import shutil
import sys
import tempfile
import threading
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Callable

from PySide6.QtCore import Property, QDir, QObject, QProcess, QStandardPaths, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices, QGuiApplication, QTextCharFormat, QTextCursor
from PySide6.QtQuick import QQuickTextDocument

from ..core import (
    SORTS,
    DayPlanner,
    ResourceCard,
    ResourceId,
    Tag,
    TagId,
    Todo,
    TodoId,
    WorkspaceId,
    delete_warning,
    describe,
    filter_and_sort,
    is_inside,
    is_local_path,
    is_valid_uri,
    last_visible_day,
    pdf_markdown,
    safe_file_name,
    sanitize_name,
    search,
    segments,
    suggest_name,
    to_edit_text,
    to_storage_text,
    youtube_video_id,
    link_at,
    parse_capture,
    same_page,
    expand_filter,
    export_needed,
    format_timestamp,
    is_legacy_format,
    label_rows,
    valid_parents,
    with_ancestors,
    pdf_file_name,
    position_of,
    read_annotations,
    recently_used,
    time_ago,
)
from ..powerpoint import ExportResult, convert_to_pptx, export_pdf
from ..thumbnails import cached_thumbnail, fetch_thumbnail
from ..titles import fetch_html_title
from ..storage import (
    BackupCapable,
    ClientState,
    ClientStateError,
    RepositoryError,
    TodoRepository,
    export_backup,
    write_text_unique,
)
from .backlog_list_model import BacklogListModel, BacklogTodo
from .day_list_model import DayListModel
from .notes_session import NotesSession
from .knowledge_graph import KnowledgeGraphModel
from .open_questions import OpenQuestions
from .resource_list_model import ResourceListModel
from .tag_list_model import TagListModel

DAY_CHECK_INTERVAL_MS = 30_000
RECENT_COUNT = 4  # how many resources "Jump back in" offers, unless chosen otherwise
RECENT_COUNT_RANGE = (1, 10)


def _ids(values: list | None) -> list[TagId]:
    """QML hands numbers over as floats sometimes."""
    return [int(v) for v in values or ()]


def _downloads_folder() -> Path:
    downloads = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.DownloadLocation)
    return Path(downloads) if downloads else Path.home()


def _thumbnail_folder() -> Path:
    cache = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.TempLocation)
    return Path(cache or ".") / "marginalia-thumbnails"


class TodoController(QObject):
    """Actions on todos + the ``days`` model. Every write refreshes the model."""

    notify = Signal(str)  # short messages for the UI to show as a toast
    workspaceChanged = Signal()
    workspacesChanged = Signal()
    # Answer to fetchTitle: (url, page title or "", error message or "")
    titleLookup = Signal(str, str, str)
    resourceViewChanged = Signal()  # search text, tag filter, sort or the totals changed
    undoOffered = Signal(int, str)  # (token, message): show an "Undo" toast for something just deleted
    referencesChanged = Signal()  # resources or tags changed: rendered ``@{}`` / ``!{}`` text is stale
    # (resource id, name, path, page or 0 for where it was left): open this PDF in a tab
    pdfRequested = Signal(int, str, str, int)
    # (id, name, uri, page): open the notes tab of a resource that is not a PDF (no pages to scroll)
    notesRequested = Signal(int, str, str, int)
    videoRequested = Signal(int, str, str, int)  # (id, name, link, timestamp or 0)
    _presentationExported = Signal(int, str, str, str, int)  # (id, name, pdf, error, page)
    _annotationsConverted = Signal(int, str)  # (id, error)
    presentationAnnotationsReady = Signal(int)  # the notes and comments of this one can be read now
    subTagsChanged = Signal()
    resourceTabsShouldClose = Signal(int)  # its PDF is about to be replaced: let go of the file
    thumbnailReady = Signal(str, str, str)  # (video link, picture file url or "", error)
    resourceRemoved = Signal(int)  # a resource is gone for good: close its PDF tab
    pdfScrollSpeedChanged = Signal()
    recentChanged = Signal()  # what was opened last, or where a PDF was left, changed
    tagRequested = Signal(int)  # a tag was clicked in some text: show it (the Knowledge graph)
    # A capture from outside (the browser extension, see ``handleLink``):
    captureReady = Signal(int, str, int)  # (resource id, note|question, seconds): its tab is open, open the box
    captureNeedsResource = Signal(str, str, str, int)  # (link, its title, note|question, seconds): nothing has that link yet

    def __init__(
        self,
        repo: TodoRepository,
        today: Callable[[], date] = date.today,  # injectable for tests
        parent: QObject | None = None,
        client_state: ClientState | None = None,  # local UI state; None = remember nothing
        data_dir: Path | None = None,  # where the PDFs of presentations go when a workspace has no folder
        export_presentation: Callable[[Path, Path], ExportResult] = export_pdf,  # injectable for tests
        convert_presentation: Callable[[Path, Path], ExportResult] = convert_to_pptx,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),  # injectable for tests
    ):
        super().__init__(parent)
        self._data_dir = data_dir
        self._export_presentation = export_presentation
        self._convert_presentation = convert_presentation
        self._converting: set[int] = set()  # old .ppt files being saved as .pptx right now
        self._annotation_state: dict[int, str] = {}  # for the debug info
        self._exporting: set[int] = set()  # presentations being turned into a PDF right now
        self._annotations_cache: dict[tuple[str, float], list[dict]] = {}
        self._repo = repo
        self._today = today
        self._now = now
        self._client = client_state
        self._removed_resources: set[int] = set()  # ids are never reused (AUTOINCREMENT)
        self._pdf_scroll_speed = self._load_pdf_scroll_speed()
        self._recent_count = self._load_recent_count()

        # Failures here abort startup (see app.py).
        self._workspaces = self._repo.list_workspaces()
        self._workspace_id: WorkspaceId = self._workspaces[0].id
        todos = self._repo.list_todos(self._workspace_id)
        # One planner per workspace, so a workspace remembers its pinned (missed) days
        # when you switch away and back.
        self._planners = {self._workspace_id: DayPlanner(self._today(), todos)}
        self._days = DayListModel(self)
        self._backlog = BacklogListModel(self)
        self._show(todos)
        self._resources = ResourceListModel(self)
        self._tags = TagListModel(self)
        self._cards: dict[ResourceId, ResourceCard] = {}  # every resource, whatever the filter hides
        self._presentationExported.connect(self._on_presentation_exported)
        self._annotationsConverted.connect(self._on_annotations_converted)
        self._open_questions = OpenQuestions(
            repo,
            lambda: self._workspace_id,
            lambda: self._cards,
            self._offer_undo,
            parent=self,
            to_storage=self._to_storage,
        )
        self._open_questions.error.connect(self.notify)
        self._knowledge_graph = KnowledgeGraphModel(
            repo,
            lambda: self._workspace_id,
            lambda: self._cards,
            lambda: self._all_tags,
            parent=self,
        )
        self._knowledge_graph.error.connect(self.notify)
        self._resource_names: dict[int, str] = {}  # for inline references in todo text
        self._tag_names: dict[int, str] = {}
        self._all_tags: list[Tag] = []  # with their parents (the model only has the tree order)
        self._references_revision = 0
        # Things that were just deleted and can still come back: token -> restore function. The UI
        # shows a toast per token and calls expireUndo() when it goes away, which forgets it.
        self._undo: dict[int, Callable[[], None]] = {}
        self._undo_ids = itertools.count(1)
        self._resource_query = ""  # library: filter by name
        self._resource_tag_filter: set[int] = set()  # library: only resources with one of these tags
        self._resource_sort = "recent"
        self._resource_total = 0  # resources in the workspace, before filtering
        self._refresh_resources()
        self._refresh_tags()

        # Handles the app being left open past midnight.
        self._day_timer = QTimer(self)
        self._day_timer.setInterval(DAY_CHECK_INTERVAL_MS)
        self._day_timer.timeout.connect(self.checkNewDay)
        self._day_timer.start()

    # ------------------------------------------------------------ properties
    @Property(QObject, constant=True)
    def days(self) -> DayListModel:
        return self._days

    @Property(QObject, constant=True)
    def backlog(self) -> BacklogListModel:
        """Todos without a date."""
        return self._backlog

    @Property(QObject, constant=True)
    def resources(self) -> ResourceListModel:
        return self._resources

    @Property(QObject, constant=True)
    def tags(self) -> TagListModel:
        return self._tags

    @Property(str, notify=resourceViewChanged)
    def resourceSort(self) -> str:
        return self._resource_sort

    @Property("QVariantList", notify=resourceViewChanged)
    def resourceTagFilter(self) -> list[int]:
        return sorted(self._resource_tag_filter)

    @Property(int, notify=resourceViewChanged)
    def resourceTotal(self) -> int:
        """How many resources the workspace has, whatever the filter hides."""
        return self._resource_total

    @Property(bool, notify=resourceViewChanged)
    def resourceFilterActive(self) -> bool:
        return bool(self._resource_query.strip() or self._resource_tag_filter)

    @Property(int, notify=referencesChanged)
    def referencesRevision(self) -> int:
        """Changes whenever a resource or tag name may have changed; bind rendered text to it."""
        return self._references_revision

    @Property("QVariantList", notify=workspacesChanged)
    def workspaces(self) -> list[dict]:
        return [{"id": w.id, "name": w.name} for w in self._workspaces]

    @Property(int, notify=workspaceChanged)
    def currentWorkspaceId(self) -> WorkspaceId:
        return self._workspace_id

    @Property("QVariantList", notify=recentChanged)
    def recentResources(self) -> list[dict]:
        """The resources opened last ("Jump back in"): id, name, kind, the page a PDF was left on
        (0: none) and when it was opened ("2 h ago")."""
        now = self._now()
        rows = []
        for card in recently_used(list(self._cards.values()), self._recent_count):
            page = self.lastPdfPage(card.id) if card.kind in ("pdf", "powerpoint") else 0
            rows.append({"id": card.id, "name": card.name, "kind": card.kind,
                         "page": page if page > 1 else 0, "when": time_ago(card.last_used_at, now)})
        return rows

    @Property(bool, constant=True)
    def canBackup(self) -> bool:
        """Lets QML hide the Export button for storage that can't be backed up."""
        return isinstance(self._repo, BackupCapable)

    # ------------------------------------------------------ workspace actions
    @Slot(int)
    def setWorkspace(self, workspace_id: WorkspaceId) -> None:
        """Switch the active workspace and load its todos."""
        if workspace_id == self._workspace_id or not any(
            w.id == workspace_id for w in self._workspaces
        ):
            return
        todos = self._fetch(workspace_id)
        if todos is None:
            return  # stay on the current workspace
        today = self._today()
        planner = self._planners.get(workspace_id)
        if planner is None:
            planner = self._planners[workspace_id] = DayPlanner(today, todos)
        elif planner.today != today:
            planner.roll_over(today, todos)  # the day changed while this workspace was inactive
        self._workspace_id = workspace_id
        self._show(todos, planner)
        self._resource_query = ""
        self._resource_tag_filter.clear()
        self._refresh_resources()
        self._refresh_tags()
        self._open_questions.select(-1)
        self._open_questions.refresh()
        self.workspaceChanged.emit()

    @Slot(str, str)
    def createWorkspace(self, name: str, folder: str = "") -> None:
        """Add a workspace and switch to it. A workspace needs a folder (made if it isn't there):
        the files of its resources live there, and it can't be changed afterwards."""
        name = name.strip()
        folder = folder.strip()
        if not name:
            return
        if not folder:
            self.notify.emit("Choose a folder for the workspace")
            return
        if any(w.name.casefold() == name.casefold() for w in self._workspaces):
            self.notify.emit(f"A workspace named \"{name}\" already exists")
            return
        try:
            Path(folder).mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            self.notify.emit(f"Couldn't use that folder: {exc}")
            return
        try:
            workspace = self._repo.create_workspace(name)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't create workspace: {exc}")
            return
        if self._client is not None:
            try:
                self._client.set_workspace_setting(workspace.id, self.RESOURCE_FOLDER_KEY, folder)
            except ClientStateError as exc:
                self.notify.emit(f"Couldn't save the workspace folder: {exc}")
        self._workspaces.append(workspace)
        self.workspacesChanged.emit()
        self.setWorkspace(workspace.id)

    @Slot(str)
    def renameWorkspace(self, name: str) -> None:
        """Rename the active workspace."""
        name = name.strip()
        current = self._workspace_id
        if not name or any(w.id == current and w.name == name for w in self._workspaces):
            return
        if any(w.id != current and w.name.casefold() == name.casefold() for w in self._workspaces):
            self.notify.emit(f"A workspace named \"{name}\" already exists")
            return
        try:
            self._repo.rename_workspace(current, name)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't rename workspace: {exc}")
            return
        self._workspaces = [replace(w, name=name) if w.id == current else w for w in self._workspaces]
        self.workspacesChanged.emit()

    @Slot()
    def deleteWorkspace(self) -> None:
        """Delete the active workspace and all its todos, then open another one."""
        if len(self._workspaces) <= 1:
            self.notify.emit("You can't delete the only workspace")
            return
        doomed = self._workspace_id
        target = next(w for w in self._workspaces if w.id != doomed)
        if self._fetch(target.id) is None:
            return  # can't open the next workspace, so don't delete this one
        doomed_resources = list(self._cards)  # the active workspace's resources go with it
        doomed_pdfs = [(c, doomed) for c in self._cards.values() if c.kind == "powerpoint"]
        try:
            self._repo.delete_workspace(doomed)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't delete workspace: {exc}")
            return
        self._workspaces = [w for w in self._workspaces if w.id != doomed]
        self._planners.pop(doomed, None)
        for card, workspace_id in doomed_pdfs:  # (before its folder setting is forgotten below)
            self._delete_presentation_pdf(card, workspace_id)
        if self._client is not None:
            try:
                self._client.forget_workspace(doomed)
            except ClientStateError:
                pass
        self.setWorkspace(target.id)
        self.workspacesChanged.emit()
        for resource_id in doomed_resources:
            self._forget_resource(resource_id)
            self.resourceRemoved.emit(resource_id)

    # ------------------------------------------------------ resource actions
    @Slot(str)
    def setResourceQuery(self, query: str) -> None:
        """Library search: keep resources whose name contains ``query``."""
        self._resource_query = query
        self._refresh_resources()

    @Slot(str)
    def setResourceSort(self, sort: str) -> None:
        if sort in SORTS:
            self._resource_sort = sort
            self._refresh_resources()

    @Slot(int)
    def toggleResourceTag(self, tag_id: TagId) -> None:
        """Library filter: select / unselect a tag."""
        self._resource_tag_filter ^= {tag_id}
        self._refresh_resources()

    @Slot()
    def clearResourceTagFilter(self) -> None:
        self._resource_tag_filter.clear()
        self._refresh_resources()

    @Property(bool, notify=subTagsChanged)
    def hasSubTags(self) -> bool:
        """At least one tag of the workspace is a sub-tag."""
        return any(t.parent_id is not None for t in self._all_tags)

    @Slot(str, int, result=int)
    def createTag(self, name: str, parent_id: int = -1) -> int:
        """A new tag; ``parent_id`` >= 0 makes it a sub-tag of that tag. Returns its id, or -1 when
        nothing was made (no name, the name is taken, the database refused)."""
        name = name.strip()
        if not name:
            return -1
        if any(t.name.casefold() == name.casefold() for t in self._tags.rows):
            self.notify.emit(f"A tag named \"{name}\" already exists")
            return -1
        try:
            tag = self._repo.create_tag(self._workspace_id, name, parent_id if parent_id >= 0 else None)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't create tag: {exc}")
            return -1
        self._refresh_tags()
        return tag.id

    @Slot(int, result="QVariantList")
    def tagChoicesIn(self, workspace_id: WorkspaceId) -> list[dict]:
        """Every tag of a workspace (any, not only the open one), in tree order: for picking tags
        for a resource that is about to be made there."""
        if workspace_id == self._workspace_id:
            return self.tagParentChoices(-1)
        try:
            tags = self._repo.list_tags(workspace_id)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't load the tags: {exc}")
            return []
        return [{"id": r.id, "name": r.name, "depth": r.depth, "path": r.path, "family": r.family}
                for r in label_rows(tags)]

    @Slot(int, str, result=int)
    def createTagIn(self, workspace_id: WorkspaceId, name: str) -> int:
        """A new top-level tag in a workspace (any, not only the open one). Returns its id, or -1."""
        if workspace_id == self._workspace_id:
            return self.createTag(name, -1)
        name = name.strip()
        if not name:
            return -1
        try:
            if any(t.name.casefold() == name.casefold() for t in self._repo.list_tags(workspace_id)):
                self.notify.emit(f"A tag named \"{name}\" already exists")
                return -1
            return self._repo.create_tag(workspace_id, name).id
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't create tag: {exc}")
            return -1

    @Slot(int, str, int)
    def updateTag(self, tag_id: TagId, name: str, parent_id: int = -1) -> None:
        """Rename a tag and put it below ``parent_id`` (-1: top level), as one change."""
        name = name.strip()
        current = next((t for t in self._all_tags if t.id == tag_id), None)
        if not name or current is None:
            return
        if any(t.id != tag_id and t.name.casefold() == name.casefold() for t in self._tags.rows):
            self.notify.emit(f"A tag named \"{name}\" already exists")
            return
        parent = parent_id if parent_id >= 0 else None
        try:
            if name != current.name:
                self._repo.rename_tag(tag_id, name)
            if parent != current.parent_id:
                self._repo.set_tag_parent(tag_id, parent)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't save tag: {exc}")
            self._refresh_tags()
            return
        self._refresh_tags()
        self._refresh_resources()

    @Slot(int, result="QVariantList")
    def tagParentChoices(self, tag_id: TagId = -1) -> list[dict]:
        """Where a tag may go, in tree order: every tag but itself and its own sub-tags
        (-1: a tag that is not made yet)."""
        rows = valid_parents(self._all_tags, tag_id if tag_id >= 0 else None)
        return [{"id": r.id, "name": r.name, "depth": r.depth, "path": r.path, "family": r.family}
                for r in rows]

    @Slot(int)
    def deleteTag(self, tag_id: TagId) -> None:
        self._resource_tag_filter.discard(tag_id)
        try:
            self._repo.delete_tag(tag_id)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't delete tag: {exc}")
            return
        self._refresh_tags()
        self._refresh_resources()  # cards carry their tag ids

    @Slot(str, result=str)
    def suggestName(self, uri: str) -> str:
        """A name taken from the link or path itself (instant, no network)."""
        return suggest_name(uri)

    @Slot(str)
    def fetchTitle(self, url: str) -> None:
        """Look up a web page title in the background; the answer arrives as ``titleLookup``."""
        threading.Thread(target=self._fetch_title, args=(url,), daemon=True).start()

    @Slot(str, result=int)
    def timestampOf(self, text: str) -> int:
        """What was typed as a timestamp, in seconds (at least 1), or -1 when it is none."""
        position = position_of(text)
        return -1 if position is None else position

    @Slot(int, result=str)
    def timestampLabel(self, seconds: int) -> str:
        return format_timestamp(seconds)

    @Slot(str, int)
    def openVideoAt(self, uri: str, seconds: int) -> None:
        """Watch a video from ``seconds`` on (a YouTube video; any other link just opens)."""
        self.openResource(link_at(uri, seconds))

    @Slot(str, result=str)
    def thumbnailFor(self, uri: str) -> str:
        """The preview picture of a video as a file url when it is already downloaded, else ""
        and it is fetched in the background: the answer arrives as ``thumbnailReady``."""
        video_id = youtube_video_id(uri)
        if video_id is None:
            QTimer.singleShot(0, lambda: self.thumbnailReady.emit(uri, "", "no preview for this link"))
            return ""
        hit = cached_thumbnail(video_id, _thumbnail_folder())
        if hit is not None:
            return QUrl.fromLocalFile(str(hit)).toString()
        threading.Thread(target=self._fetch_thumbnail, args=(uri, video_id), daemon=True).start()
        return ""

    def _fetch_thumbnail(self, uri: str, video_id: str) -> None:
        result = fetch_thumbnail(video_id, _thumbnail_folder())
        url = QUrl.fromLocalFile(str(result.path)).toString() if result.path else ""
        self.thumbnailReady.emit(uri, url, result.error)

    def _fetch_title(self, url: str) -> None:
        result = fetch_html_title(url)
        self.titleLookup.emit(url, result.title or "", result.error or "")

    @Slot(str, result=bool)
    def isInWorkspaceFolder(self, path: str) -> bool:
        """Is this file inside the active workspace's folder? (Without a folder: yes, there is
        nowhere to move it to.)"""
        folder = self.defaultResourceFolder()
        return not folder or is_inside(path, folder)

    def _move_into_workspace_folder(self, path: str) -> str | None:
        """Cut the file and paste it in the workspace's folder. Returns its new path, or None when
        it stayed where it was (with a message why)."""
        folder = self.defaultResourceFolder()
        source = Path(path)
        if not folder or not source.is_file() or is_inside(path, folder):
            return None
        target = Path(folder) / source.name
        if target.exists():
            self.notify.emit(
                f"\"{source.name}\" is already in the workspace folder: the file was left where it was"
            )
            return None
        try:
            Path(folder).mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(target))  # also across drives
        except OSError as exc:
            self.notify.emit(f"Couldn't move the file to the workspace folder: {exc}")
            return None
        return str(target)

    @Slot(str, str, "QVariantList", bool, result=str)
    def addResource(
        self, uri: str, name: str, tag_ids: list | None = None, move_file: bool = False
    ) -> str:
        """Create a resource. With ``move_file`` a file outside the workspace's folder is moved
        into it. Returns the name to use for it in ``@{...}`` references, or "" when nothing was
        created."""
        uri = uri.strip()
        if not self._valid_resource(uri, name):
            return ""
        original = uri
        if move_file and is_local_path(uri):
            moved = self._move_into_workspace_folder(uri)
            if moved is not None:
                uri = moved
        try:
            self._repo.add_resource(self._workspace_id, uri, name.strip(), _ids(tag_ids))
        except RepositoryError as exc:
            if uri != original:  # nothing was added: put the file back
                try:
                    shutil.move(uri, original)
                except OSError:
                    pass
            self.notify.emit(f"Couldn't add resource: {exc}")
            return ""
        self._refresh_resources()
        return sanitize_name(name.strip())

    @Slot(int, str, str, "QVariantList")
    def updateResource(
        self, resource_id: ResourceId, uri: str, name: str, tag_ids: list | None = None
    ) -> None:
        uri = uri.strip()
        if not self._valid_resource(uri, name):
            return
        try:
            self._repo.update_resource(resource_id, uri, name.strip(), _ids(tag_ids))
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't update resource: {exc}")
            return
        self._refresh_resources()

    @Property(QObject, constant=True)
    def knowledgeGraph(self) -> KnowledgeGraphModel:
        return self._knowledge_graph

    @Property(QObject, constant=True)
    def openQuestions(self) -> OpenQuestions:
        return self._open_questions

    # ------------------------------------------------------------ presentations
    def _presentation_pdf(self, card: ResourceCard, workspace_id: WorkspaceId | None = None) -> Path:
        """Where the PDF of a presentation lives: in the folder of its workspace (the default
        resource folder), else in the app's data folder; named like the presentation."""
        workspace_id = self._workspace_id if workspace_id is None else workspace_id
        name = pdf_file_name(card.uri)
        folder = self._resource_folder_of(workspace_id)
        if folder:
            try:
                Path(folder).mkdir(parents=True, exist_ok=True)
                return Path(folder) / name
            except OSError:
                pass  # a folder that can't be used: fall back to the data folder
        base = self._data_dir if self._data_dir is not None else Path(tempfile.gettempdir())
        return base / "presentations" / f"workspace-{workspace_id}" / name

    def _open_presentation(self, card: ResourceCard, page: int = 0) -> None:
        """Show a presentation as the PDF PowerPoint makes of it: made now when there is none yet
        or the presentation is newer, else the one that is there."""
        if card.id in self._exporting:
            self.notify.emit(f"Still preparing \"{card.name}\"...")
            return
        pdf = self._presentation_pdf(card)
        try:
            presentation_modified = os.path.getmtime(card.uri)
            pdf_modified = os.path.getmtime(pdf) if pdf.is_file() else None
        except OSError:
            self.notify.emit(f"File not found: {card.name}")
            return
        if not export_needed(pdf_modified, presentation_modified):
            self._show_presentation(card.id, card.name, str(pdf), page)
            return
        self._exporting.add(card.id)
        self.resourceTabsShouldClose.emit(card.id)  # an open tab keeps the old PDF locked
        self.notify.emit(f"Preparing \"{card.name}\" with PowerPoint...")
        threading.Thread(target=self._export, args=(card, pdf, page), daemon=True).start()

    def _export(self, card: ResourceCard, pdf: Path, page: int) -> None:
        result = self._export_presentation(Path(card.uri), pdf)
        self._presentationExported.emit(card.id, card.name, str(pdf), result.error, page)

    def _on_presentation_exported(self, resource_id: int, name: str, pdf: str, error: str, page: int) -> None:
        self._exporting.discard(resource_id)
        if error:
            self.notify.emit(
                f"Couldn't export \"{name}\" with PowerPoint ({error}). Export it to PDF yourself "
                "(File > Export > PDF) and add that PDF as a new resource."
            )
        elif resource_id not in self._cards:  # deleted while it was being made
            Path(pdf).unlink(missing_ok=True)
        else:
            self._show_presentation(resource_id, name, pdf, page)

    def _show_presentation(self, resource_id: int, name: str, pdf: str, page: int) -> None:
        # The tab is the PDF viewer on the PDF, but its notes belong to the presentation.
        self.pdfRequested.emit(resource_id, name, pdf, page)

    def _delete_presentation_pdf(self, card: ResourceCard, workspace_id: WorkspaceId | None = None) -> None:
        if card.kind == "powerpoint":
            self._delete_file_soon(self._presentation_pdf(card, workspace_id), card.name)

    def _delete_file_soon(self, path: Path, name: str, tries: int = 20) -> None:
        """Delete a file; if a viewer tab that is just closing still has it open, try again shortly."""
        try:
            path.unlink(missing_ok=True)
        except OSError as exc:
            if tries > 0:
                QTimer.singleShot(300, lambda: self._delete_file_soon(path, name, tries - 1))
            else:
                self.notify.emit(f"Couldn't delete the PDF of \"{name}\": {exc}")

    # --- speaker notes and comments of a presentation
    def _converted_pptx(self, card: ResourceCard) -> Path:
        """Where the .pptx copy of an old .ppt lives (made by PowerPoint, see below)."""
        base = self._data_dir if self._data_dir is not None else Path(tempfile.gettempdir())
        return base / "presentations" / "converted" / f"{card.id}.pptx"

    @staticmethod
    def _modified(path: Path) -> float | None:
        try:
            return os.path.getmtime(path)
        except OSError:
            return None

    def _annotation_file(self, card: ResourceCard) -> Path | None:
        """The file the notes and comments are read from: the presentation itself, or for an old
        .ppt (a binary format) the .pptx copy PowerPoint made of it. None until that copy exists."""
        if not is_legacy_format(card.uri):
            return Path(card.uri)
        copy, original = self._converted_pptx(card), self._modified(Path(card.uri))
        modified = self._modified(copy)
        if original is not None and modified is not None and modified >= original:
            return copy
        return None

    def _convert_for_annotations(self, card: ResourceCard) -> None:
        if card.id in self._converting:
            return
        self._converting.add(card.id)
        self._annotation_state[card.id] = "converting the old .ppt with PowerPoint..."
        threading.Thread(target=self._convert, args=(card,), daemon=True).start()

    def _convert(self, card: ResourceCard) -> None:
        result = self._convert_presentation(Path(card.uri), self._converted_pptx(card))
        self._annotationsConverted.emit(card.id, result.error)

    def _on_annotations_converted(self, resource_id: int, error: str) -> None:
        self._converting.discard(resource_id)
        if error:
            self._annotation_state[resource_id] = f"conversion failed: {error}"
            card = self._cards.get(resource_id)
            name = card.name if card else "the presentation"
            self.notify.emit(f"Couldn't read the notes and comments of \"{name}\": {error}")
        else:
            self._annotation_state[resource_id] = "converted"
            self.presentationAnnotationsReady.emit(resource_id)

    def _slide_annotations(self, card: ResourceCard) -> list[dict]:
        source = self._annotation_file(card)
        modified = self._modified(source) if source is not None else None
        if source is None or modified is None:
            return []
        key = (str(source), modified)
        if key not in self._annotations_cache:
            self._annotations_cache = {key: [
                {
                    "slide": a.slide,
                    "notes": a.notes,
                    "comments": [
                        {"author": c.author, "text": c.text, "created": c.created, "isReply": c.is_reply}
                        for c in a.comments
                    ],
                }
                for a in read_annotations(str(source))
            ]}
        return self._annotations_cache[key]

    @Slot(int, result="QVariantList")
    def presentationAnnotations(self, resource_id: ResourceId) -> list[dict]:
        """The speaker notes and comments of a presentation, per slide that has some:
        {slide, notes, comments: [{author, text, created, isReply}]}. [] for anything else.

        An old .ppt can only be read by PowerPoint: it is saved as a .pptx copy in the background,
        and ``presentationAnnotationsReady`` says when to ask again."""
        card = self._cards.get(resource_id)
        if card is None or card.kind != "powerpoint" or self._modified(Path(card.uri)) is None:
            return []
        if self._annotation_file(card) is None:
            self._convert_for_annotations(card)
            return []
        return self._slide_annotations(card)

    @Slot(int, result=bool)
    def isPresentation(self, resource_id: ResourceId) -> bool:
        card = self._cards.get(resource_id)
        return card is not None and card.kind == "powerpoint"

    @Slot(int, result=str)
    def presentationDebugInfo(self, resource_id: ResourceId) -> str:
        """Everything about how a presentation is shown, as text for a "what is going on" dialog."""
        card = self._cards.get(resource_id)
        if card is None or card.kind != "powerpoint":
            return "This resource is not a presentation."
        source = Path(card.uri)
        pdf = self._presentation_pdf(card)

        def stamp(path: Path) -> str:
            modified = self._modified(path)
            if modified is None:
                return "not there"
            when = datetime.fromtimestamp(modified).strftime("%Y-%m-%d %H:%M:%S")
            return f"{path.stat().st_size:,} bytes, modified {when}"

        lines = [
            f"Presentation: {card.name}",
            f"File: {source}",
            f"  {stamp(source)}",
            f"  format: {'old binary (.ppt / .pps): only PowerPoint can read its notes' if is_legacy_format(card.uri) else 'OpenXML (zip)'}",
            "",
            f"PDF: {pdf}",
            f"  {stamp(pdf)}",
            f"  {'up to date' if not export_needed(self._modified(pdf), self._modified(source) or 0) else 'older than the presentation (it is made again on the next open)'}",
            "",
        ]
        annotation_file = self._annotation_file(card)
        if is_legacy_format(card.uri):
            copy = self._converted_pptx(card)
            lines += [f".pptx copy for the notes: {copy}", f"  {stamp(copy)}",
                      f"  state: {self._annotation_state.get(card.id, 'not made yet')}"]
        lines.append(f"Notes and comments are read from: {annotation_file if annotation_file else 'nothing yet'}")
        slides = self._slide_annotations(card) if annotation_file is not None else []
        notes = sum(1 for s in slides if s["notes"])
        comments = sum(len(s["comments"]) for s in slides)
        lines += ["", f"Slides with notes or comments: {len(slides)} (notes on {notes}, {comments} comments)"]
        for s in slides:
            first = s["notes"].splitlines()[0][:70] if s["notes"] else ""
            lines.append(f"  slide {s['slide']}: {'notes ' + repr(first) if first else 'no notes'}, {len(s['comments'])} comments")
        if annotation_file is not None and not slides:
            lines.append("  (the file was read, and has no speaker notes or comments)")
        return "\n".join(lines)

    # ------------------------------------------------------------ opening resources
    # ------------------------------------------------------------ captures from outside
    @Slot(str)
    def handleLink(self, link: str) -> None:
        """A ``marginalia://`` link the app was asked to open (by the browser extension, through
        Windows): a note or question to write about a page, at a moment of it."""
        capture = parse_capture(link)
        if capture is None:
            self.notify.emit("Marginalia was asked to open a link it doesn't understand")
            return
        self.capture(capture.kind, capture.url, capture.seconds, capture.title)

    @Slot(str, str, int)
    @Slot(str, str, int, str)
    def capture(self, kind: str, url: str, seconds: int, title: str = "") -> None:
        """Write a note (or ask a question) about ``url`` at ``seconds``: open the tab of the
        resource with that link, in whatever workspace it is (``captureReady``), or ask for the
        resource to be made first when there is none (``captureNeedsResource``, with ``title`` as
        the name to suggest)."""
        found = self._find_resource_by_link(url)
        if found is None:
            self.captureNeedsResource.emit(url, title, kind, seconds)
            return
        workspace_id, resource_id = found
        if workspace_id != self._workspace_id:
            self.setWorkspace(workspace_id)
        card = self._cards.get(resource_id)
        if card is None:
            return
        self._open(resource_id, seconds if card.kind == "video" else 0, launch=False)
        self.captureReady.emit(resource_id, kind, seconds if card.kind == "video" else 0)

    def _find_resource_by_link(self, url: str) -> tuple[WorkspaceId, ResourceId] | None:
        """The resource with this link (the same video, for YouTube): in the active workspace
        first, then in the others."""
        for card in self._cards.values():
            if same_page(card.uri, url):
                return self._workspace_id, card.id
        for workspace in self._workspaces:
            if workspace.id == self._workspace_id:
                continue
            try:
                resources = self._repo.list_resources(workspace.id)
            except RepositoryError:
                continue
            for resource in resources:
                if same_page(resource.uri, url):
                    return workspace.id, resource.id
        return None

    @Slot(int, result="QVariantMap")
    def resourceInfo(self, resource_id: ResourceId) -> dict:
        """One resource of the active workspace, for its context menu wherever it is shown (the
        library, "Jump back in", its own tab): {} when it isn't there (any more)."""
        card = self._cards.get(resource_id)
        if card is None:
            return {}
        return {"id": card.id, "name": card.name, "uri": card.uri, "kind": card.kind,
                "isPath": card.is_path, "missing": card.missing, "tagIds": list(card.tag_ids)}

    @Slot(int)
    def openResourceById(self, resource_id: ResourceId) -> None:
        """Open a resource like clicking its card in the library: its tab, and a resource the app
        cannot show (a web page, a Word file...) also in its own program."""
        self._open(resource_id, 0, launch=True)

    @Slot(int, int)
    def openResourceAtPage(self, resource_id: ResourceId, page: int) -> None:
        """Open a resource's tab at ``page`` (0: wherever it was left). Nothing is launched outside
        the app."""
        self._open(resource_id, page, launch=False)

    def _open(self, resource_id: ResourceId, page: int, launch: bool) -> None:
        """The one place that decides which tab a resource opens in. A PDF shows its pages, a
        presentation the PDF PowerPoint makes of it, a video its own page, anything else a notes
        tab (where the page of a note is typed in)."""
        card = self._cards.get(resource_id)  # not the library's rows: a search may hide it there
        if card is None:
            self.notify.emit("That resource is not in this workspace any more")
            return
        if card.missing:
            self.notify.emit(f"File not found: {card.name}")
            return
        self.touchResource(card.id)  # re-sorts the library; `card` is already in hand
        if card.kind == "pdf":
            self.pdfRequested.emit(card.id, card.name, card.uri, page)
        elif card.kind == "powerpoint":
            self._open_presentation(card, page)
        elif card.kind == "video":
            self.videoRequested.emit(card.id, card.name, card.uri, page)
        else:
            self.notesRequested.emit(card.id, card.name, card.uri, page)
            if launch:
                self.openResource(card.uri)

    @Slot(int, result=QObject)
    def createNotesSession(self, resource_id: ResourceId) -> NotesSession:
        """Notes of one open PDF. The caller (the PDF tab) calls ``dispose()`` when done."""
        session = NotesSession(
            self._repo,
            resource_id,
            parent=self,
            undo_sink=self._offer_undo,
            to_storage=self._to_storage,
            connections=self._connections_for,
        )
        session.error.connect(self.notify)
        return session

    def _to_storage(self, text: str) -> str:
        return to_storage_text(text, self._resolve_reference)

    def _connections_for(self, resource_id: ResourceId) -> list[dict]:
        """The resources linked to this one in either direction (the graph of its tab): only
        those of the current workspace, which is where names can be shown."""
        links: dict[int, dict] = {}
        for source, target in self._repo.list_resource_links(resource_id):
            other, outgoing = (target, True) if source == resource_id else (source, False)
            card = self._cards.get(other)
            if card is None:
                continue
            entry = links.setdefault(
                other,
                {"id": other, "name": card.name, "kind": card.kind, "missing": card.missing,
                 "outgoing": False, "incoming": False},
            )
            entry["outgoing" if outgoing else "incoming"] = True
        return sorted(links.values(), key=lambda e: e["name"].casefold())

    @Slot(int, result=int)
    def lastPdfPage(self, resource_id: ResourceId) -> int:
        """The page this PDF was left on, or 1."""
        if self._client is None:
            return 1
        try:
            return self._client.pdf_page(resource_id) or 1
        except ClientStateError:
            return 1  # only a convenience: never bother the user with it

    @Slot(int, int)
    def savePdfPage(self, resource_id: ResourceId, page: int) -> None:
        """Remember where a PDF tab was closed (create or update)."""
        if self._client is None or page < 1 or resource_id in self._removed_resources:
            return
        try:
            self._client.set_pdf_page(resource_id, page)
        except ClientStateError:
            return
        self.recentChanged.emit()

    # ---- app settings (client side) ----
    PDF_SCROLL_SPEED_KEY = "pdf_scroll_speed"
    PDF_SCROLL_SPEED_DEFAULT = 1.5  # times Qt's default wheel step
    PDF_SCROLL_SPEED_RANGE = (0.5, 4.0)

    def _load_pdf_scroll_speed(self) -> float:
        if self._client is not None:
            try:
                saved = self._client.app_setting(self.PDF_SCROLL_SPEED_KEY)
                if saved is not None:
                    return self._clamp_speed(float(saved))
            except (ClientStateError, ValueError):
                pass
        return self.PDF_SCROLL_SPEED_DEFAULT

    def _clamp_speed(self, speed: float) -> float:
        low, high = self.PDF_SCROLL_SPEED_RANGE
        return round(max(low, min(high, speed)), 2)

    @Property(float, notify=pdfScrollSpeedChanged)
    def pdfScrollSpeed(self) -> float:
        """How fast the mouse wheel scrolls the PDF viewer, as a multiple of the default step."""
        return self._pdf_scroll_speed

    @Slot(float)
    def setPdfScrollSpeed(self, speed: float) -> None:
        speed = self._clamp_speed(speed)
        if speed == self._pdf_scroll_speed:
            return
        self._pdf_scroll_speed = speed
        self.pdfScrollSpeedChanged.emit()
        if self._client is not None:
            try:
                self._client.set_app_setting(self.PDF_SCROLL_SPEED_KEY, str(speed))
            except ClientStateError as exc:
                self.notify.emit(f"Couldn't save the setting: {exc}")

    RECENT_COUNT_KEY = "recent_count"

    def _load_recent_count(self) -> int:
        if self._client is not None:
            try:
                saved = self._client.app_setting(self.RECENT_COUNT_KEY)
                if saved is not None:
                    return self._clamp_recent(int(saved))
            except (ClientStateError, ValueError):
                pass
        return RECENT_COUNT

    @staticmethod
    def _clamp_recent(count: int) -> int:
        low, high = RECENT_COUNT_RANGE
        return max(low, min(high, int(count)))

    @Property(int, notify=recentChanged)
    def recentCount(self) -> int:
        """How many resources "Jump back in" shows (1 to 10)."""
        return self._recent_count

    @Slot(int)
    def setRecentCount(self, count: int) -> None:
        count = self._clamp_recent(count)
        if count == self._recent_count:
            return
        self._recent_count = count
        self.recentChanged.emit()
        if self._client is not None:
            try:
                self._client.set_app_setting(self.RECENT_COUNT_KEY, str(count))
            except ClientStateError as exc:
                self.notify.emit(f"Couldn't save the setting: {exc}")

    # ---- workspace settings (client side) ----
    RESOURCE_FOLDER_KEY = "resource_folder"

    @Slot(result=str)
    def defaultResourceFolder(self) -> str:
        """Where "pick file" starts for the active workspace (a native path), or ""."""
        return self._resource_folder_of(self._workspace_id)

    def _resource_folder_of(self, workspace_id: WorkspaceId) -> str:
        if self._client is None:
            return ""
        try:
            return self._client.workspace_setting(workspace_id, self.RESOURCE_FOLDER_KEY) or ""
        except ClientStateError:
            return ""

    @Slot(str)
    def setDefaultResourceFolder(self, path: str) -> None:
        """Empty clears it."""
        if self._client is None:
            return
        try:
            self._client.set_workspace_setting(
                self._workspace_id, self.RESOURCE_FOLDER_KEY, path.strip() or None
            )
        except ClientStateError as exc:
            self.notify.emit(f"Couldn't save the setting: {exc}")

    def _forget_resource(self, resource_id: ResourceId) -> None:
        self._removed_resources.add(resource_id)
        if self._client is not None:
            try:
                self._client.forget_pdf(resource_id)
            except ClientStateError:
                pass

    @Slot(str, result=QUrl)
    def fileUrl(self, path: str) -> QUrl:
        return QUrl.fromLocalFile(path)

    @Slot(int)
    def touchResource(self, resource_id: ResourceId) -> None:
        """Record that a resource was opened; the library re-sorts right away ("recently used")."""
        try:
            self._repo.touch_resource(resource_id)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't update resource: {exc}")
            return
        self._refresh_resources()

    @Slot(int, str, result=str)
    def deleteResourceWarning(self, resource_id: ResourceId, name: str) -> str:
        """Text for the "delete this resource?" dialog: says what is attached to it, if anything."""
        try:
            notes, questions = self._repo.count_notes(resource_id)
            marker = f"@{{{resource_id}|"  # how a todo's stored text refers to it
            todos = sum(marker in t.text for t in self._repo.list_todos(self._workspace_id))
        except RepositoryError:
            notes = questions = todos = 0  # the delete itself will report a broken database
        return delete_warning(name, notes, questions, todos)

    @Slot(int)
    def deleteResource(self, resource_id: ResourceId) -> None:
        card = self._cards.get(resource_id)
        try:
            self._repo.delete_resource(resource_id)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't delete resource: {exc}")
            return
        self._refresh_resources()
        self._forget_resource(resource_id)
        if card is not None:
            self._delete_presentation_pdf(card)  # the PDF made from a presentation goes with it
        self.resourceRemoved.emit(resource_id)

    @Slot(str)
    def openResource(self, uri: str) -> None:
        """Let the OS open a file with its default app, or a link with the protocol's handler."""
        url = QUrl.fromLocalFile(uri) if is_local_path(uri) else QUrl(uri)
        if not QDesktopServices.openUrl(url):
            self.notify.emit(f"Couldn't open {uri}")

    @Slot(str)
    def revealInExplorer(self, path: str) -> None:
        """Show a file in the file explorer, selected. If it is gone, open the nearest folder that
        still exists instead."""
        target = Path(path)
        if target.exists():
            if sys.platform == "win32":
                # the well-known explorer incantation: "/select," then the path (with backslashes)
                if QProcess.startDetached(
                    "explorer.exe", ["/select,", QDir.toNativeSeparators(str(target))]
                ):
                    return
            else:
                target = target.parent
        else:
            target = next((p for p in target.parents if p.exists()), None)
        if target is None or not QDesktopServices.openUrl(QUrl.fromLocalFile(str(target))):
            self.notify.emit(f"Couldn't open the folder of {path}")

    @Slot()
    def refreshResources(self) -> None:
        """Re-check which local files still exist (e.g. when the window regains focus)."""
        self._refresh_resources()

    @Slot(str, result=bool)
    def pathExists(self, path: str) -> bool:
        return bool(path) and os.path.exists(path)

    @Slot(QUrl, result=str)
    def localPath(self, url: QUrl) -> str:
        """A file dialog's result as a native path (C:\\...)."""
        return QDir.toNativeSeparators(url.toLocalFile())

    # ---------------------------------------------------------- todo actions
    @Slot(str, str)
    def addTodo(self, date_iso: str, text: str) -> None:
        text = to_storage_text(text.strip(), self._resolve_reference)
        if not text:
            return
        day = date.fromisoformat(date_iso)  # raises on garbage input
        self._mutate(lambda: self._repo.add(self._workspace_id, day, text))

    @Slot(int, bool)
    def setDone(self, todo_id: TodoId, done: bool) -> None:
        self._mutate(lambda: self._repo.set_done(todo_id, done))

    @Slot(str)
    def addBacklogTodo(self, text: str) -> None:
        """Jot a todo down without a date."""
        text = to_storage_text(text.strip(), self._resolve_reference)
        if not text:
            return
        self._mutate(lambda: self._repo.add(self._workspace_id, None, text))

    @Slot(int)
    def moveToBacklog(self, todo_id: TodoId) -> None:
        """Take a todo off the timeline: it keeps its text and done state but loses its date."""
        self._mutate(lambda: self._repo.move_to_day(todo_id, None))

    @Slot(int, str)
    def moveToTimeline(self, todo_id: TodoId, date_iso: str) -> None:
        """Give a backlog todo a day. Only days the timeline shows are accepted, otherwise the todo
        would simply disappear from both lists."""
        day = date.fromisoformat(date_iso)
        today = self._planner.today
        if not today <= day <= last_visible_day(today):
            self.notify.emit("Pick a day from today to the end of next week")
            return
        self._mutate(lambda: self._repo.move_to_day(todo_id, day))

    @Slot(result="QVariantMap")
    def timelineRange(self) -> dict:
        """The first and last day the timeline shows (ISO dates), for the date picker."""
        today = self._planner.today
        return {"min": today.isoformat(), "max": last_visible_day(today).isoformat()}

    @Slot(int)
    def moveToToday(self, todo_id: TodoId) -> None:
        self._mutate(lambda: self._repo.move_to_day(todo_id, self._planner.today))

    @Slot(str)
    def moveAllToToday(self, date_iso: str) -> None:
        """Move every uncompleted todo of a (past) day to today."""
        day = date.fromisoformat(date_iso)
        self._mutate(
            lambda: self._repo.move_open_todos(self._workspace_id, day, self._planner.today)
        )

    @Slot(int)
    def deleteTodo(self, todo_id: TodoId) -> None:
        workspace = self._workspace_id
        todo = next((t for t in self._fetch(workspace) or [] if t.id == todo_id), None)
        if not self._mutate(lambda: self._repo.delete(todo_id)) or todo is None:
            return
        shown = to_edit_text(todo.text, self._name_of).replace("\n", " ")
        shown = shown if len(shown) <= 28 else shown[:27] + "..."
        self._offer_undo(f"Deleted \"{shown}\"", lambda: self._restore_todo(workspace, todo))

    def _restore_todo(self, workspace: WorkspaceId, todo: Todo) -> None:
        self._repo.restore_todo(workspace, todo)
        if workspace == self._workspace_id:
            self._refresh()

    # ----------------------------------------------------------------------- undo
    def _offer_undo(self, message: str, restore: Callable[[], None]) -> None:
        token = next(self._undo_ids)
        self._undo[token] = restore
        self.undoOffered.emit(token, message)

    @Slot(int)
    def undo(self, token: int) -> None:
        """Bring back what the toast with this token was about."""
        restore = self._undo.pop(token, None)
        if restore is None:
            return
        try:
            restore()
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't undo: {exc}")

    @Slot(int)
    def expireUndo(self, token: int) -> None:
        """The toast went away: the deletion is final, forget what was kept for undoing it."""
        self._undo.pop(token, None)

    @Slot(int, str)
    def editTodo(self, todo_id: TodoId, text: str) -> None:
        text = to_storage_text(text.strip(), self._resolve_reference)
        if not text:
            return
        self._mutate(lambda: self._repo.update_text(todo_id, text))

    # ---------------------------------------------- inline references in todo text
    @Slot(str, str, result="QVariantList")
    def searchReferences(self, activator: str, query: str) -> list[dict]:
        """The best matches for ``@{query}`` (resources) or ``!{query}`` (tags), at most five."""
        names = self._resource_names if activator == "@" else self._tag_names
        candidates = [(i, sanitize_name(n)) for i, n in names.items()]
        found = search(candidates, query, limit=5)
        hints = {r.id: r.path.rpartition(" › ")[0] for r in label_rows(self._all_tags)} if activator == "!" else {}
        return [{"id": i, "name": n, "hint": hints.get(i, "")} for i, n in found]

    @Slot(str, int, result="QVariantList")
    def segments(self, text: str, revision: int = 0) -> list[dict]:
        """Todo text split into plain / resource / tag pieces for rendering. ``revision`` only
        exists so QML can bind to ``referencesRevision`` and re-render after renames."""
        return segments(text, self._name_of)

    @Slot(QQuickTextDocument)
    def styleLinks(self, quick_document: QQuickTextDocument) -> None:
        """Switch off the built-in underline of the links in a rich text document.

        Qt Quick can only draw solid underlines (a dotted one is simply not drawn), so
        ReferenceText.qml draws its own dotted lines under the links and needs the default
        underline gone."""
        document = quick_document.textDocument()
        spans: list[tuple[int, int]] = []
        block = document.begin()
        while block.isValid():
            fragments = block.begin()
            while not fragments.atEnd():
                fragment = fragments.fragment()
                if fragment.isValid() and fragment.charFormat().isAnchor():
                    spans.append((fragment.position(), fragment.length()))
                fragments += 1
            block = block.next()
        cursor = QTextCursor(document)
        plain = QTextCharFormat()
        plain.setFontUnderline(False)
        plain.setUnderlineStyle(QTextCharFormat.UnderlineStyle.NoUnderline)
        for position, length in spans:
            cursor.setPosition(position)
            cursor.setPosition(position + length, QTextCursor.MoveMode.KeepAnchor)
            cursor.mergeCharFormat(plain)

    @Slot(str, result=str)
    def toEditText(self, stored: str) -> str:
        """Stored todo text -> what to show in a text box (``@{Name}`` instead of ``@{id|Name}``)."""
        return to_edit_text(stored, self._name_of)

    @Slot(str)
    def openLink(self, link: str) -> None:
        """A link in note text: ``resource:<id>`` opens that resource, ``tag:<id>`` shows that tag
        (``tagRequested``: the Knowledge graph goes to it), anything else is a web address."""
        if link.startswith("resource:") and link[9:].isdigit():
            self.openResourceById(int(link[9:]))
        elif link.startswith("tag:") and link[4:].isdigit():
            self.tagRequested.emit(int(link[4:]))
        else:
            self.openResource(link)

    # --------------------------------------------------------- app actions
    @Slot(str)
    def copyText(self, text: str) -> None:
        QGuiApplication.clipboard().setText(text)
        self.notify.emit("Copied to clipboard")

    @Slot()
    def exportBackup(self) -> None:
        """Write a full copy of the storage to the user's Downloads folder."""
        if not isinstance(self._repo, BackupCapable):
            self.notify.emit("Backup isn't available for this storage")
            return
        try:
            dest = export_backup(self._repo, _downloads_folder())
        except (RepositoryError, OSError) as exc:
            self.notify.emit(f"Backup failed: {exc}")
            return
        self.notify.emit(f"Backup saved to {dest}")

    @Slot(int, str)
    def exportPdfMarkdown(self, resource_id: ResourceId, title: str) -> None:
        """Write a PDF's notes, questions and highlights, grouped by page, as a Markdown file in
        the Downloads folder."""
        try:
            notes = self._repo.list_all_notes(resource_id)
            highlights = self._repo.list_highlights(resource_id)
        except RepositoryError as exc:
            self.notify.emit(f"Export failed: {exc}")
            return
        if not notes and not highlights:
            self.notify.emit("Nothing to export yet: no notes, questions or highlights")
            return
        title = title.strip() or "PDF"
        notes = [replace(n, body=to_edit_text(n.body, self._name_of)) for n in notes]
        card = self._cards.get(resource_id)
        text = pdf_markdown(
            title, notes, highlights, self._today(), timestamps=card is not None and card.kind == "video"
        )
        try:
            dest = write_text_unique(_downloads_folder(), safe_file_name(title), text)
        except OSError as exc:
            self.notify.emit(f"Export failed: {exc}")
            return
        self.notify.emit(f"Exported to {dest}")

    @Slot()
    def checkNewDay(self) -> None:
        """Roll the list over when the date changed (runs on a timer)."""
        today = self._today()
        if today == self._planner.today:
            return
        todos = self._fetch(self._workspace_id)
        if todos is None:
            return  # keep the old day; we'll retry on the next tick
        self._planner.roll_over(today, todos)
        self._show(todos)

    # ------------------------------------------------------------ internals
    def _mutate(self, action: Callable[[], object]) -> bool:
        """Run a repository write, report failures as a toast, then refresh. True on success."""
        try:
            action()
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't save change: {exc}")
            return False
        self._refresh()
        return True

    def _bump_references(self) -> None:
        """Every rendered todo re-renders on this, so only call it when a name really changed (not
        on every refresh, e.g. each time the window gets focus)."""
        self._references_revision += 1
        self.referencesChanged.emit()

    def _name_of(self, kind: str, ref_id: int) -> str | None:
        return (self._resource_names if kind == "resource" else self._tag_names).get(ref_id)

    def _resolve_reference(self, kind: str, typed: str) -> tuple[int, str] | None:
        """The resource / tag of this workspace whose name is ``typed`` (as it appears in text)."""
        names = self._resource_names if kind == "resource" else self._tag_names
        wanted = typed.casefold()
        for ref_id, name in names.items():
            if sanitize_name(name).casefold() == wanted:
                return ref_id, name
        return None

    def _valid_resource(self, uri: str, name: str) -> bool:
        if not name.strip():
            self.notify.emit("A resource needs a name")
            return False
        return self._valid_resource_uri(uri)

    def _valid_resource_uri(self, uri: str) -> bool:
        if is_valid_uri(uri):
            return True
        self.notify.emit("Enter a full link (e.g. https://...) or choose a file")
        return False

    def _refresh_resources(self) -> None:
        try:
            resources = self._repo.list_resources(self._workspace_id)
            tags = self._repo.list_resource_tags(self._workspace_id)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't load resources: {exc}")
            return
        cards = [describe(r, os.path.exists, tags.get(r.id, ())) for r in resources]
        self._cards = {c.id: c for c in cards}
        self._resource_total = len(cards)
        self._resources.set_rows(
            filter_and_sort(
                cards,
                self._resource_query,
                expand_filter(self._all_tags, self._resource_tag_filter),  # a tag brings its sub-tags
                self._resource_sort,
            )
        )
        self.resourceViewChanged.emit()
        self.recentChanged.emit()
        names = {r.id: r.name for r in resources}
        if names != self._resource_names:
            self._resource_names = names
            self._bump_references()

    def _refresh_tags(self) -> None:
        try:
            tags = self._repo.list_tags(self._workspace_id)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't load tags: {exc}")
            return
        had_sub_tags = self.hasSubTags
        self._all_tags = tags
        self._tags.set_rows(label_rows(tags))
        if had_sub_tags != self.hasSubTags:
            self.subTagsChanged.emit()
        names = {t.id: t.name for t in tags}
        if names != self._tag_names:
            self._tag_names = names
            self._bump_references()

    @property
    def _planner(self) -> DayPlanner:
        return self._planners[self._workspace_id]

    def _show(self, todos: list[Todo], planner: DayPlanner | None = None) -> None:
        """Fill the timeline and the backlog from one list of todos."""
        self._days.set_rows((planner or self._planner).rows(todos))
        self._backlog.set_rows([BacklogTodo.from_todo(t) for t in todos if t.day is None])

    def _fetch(self, workspace_id: WorkspaceId) -> list[Todo] | None:
        try:
            return self._repo.list_todos(workspace_id)
        except RepositoryError as exc:
            self.notify.emit(f"Couldn't load todos: {exc}")
            return None

    def _refresh(self) -> None:
        todos = self._fetch(self._workspace_id)
        if todos is not None:
            self._show(todos)
