from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Iterator, Sequence

from ..core.notes import with_question_mark
from ..core.references import referenced_resource_ids
from ..core.resources import suggest_name
from ..core.models import (
    DEFAULT_HIGHLIGHT_COLOR,
    HIGHLIGHT_COLORS,
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
from .base import RepositoryError, TodoRepository

DEFAULT_WORKSPACES = ("Personal", "Work", "Side projects")  # seeded into an empty database

WORKSPACES_SCHEMA = """
CREATE TABLE IF NOT EXISTS workspaces (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT    NOT NULL UNIQUE
);
"""


def _create_todos(table: str) -> str:
    return f"""
CREATE TABLE {table} (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    text         TEXT    NOT NULL,
    is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),
    date         TEXT,                       -- ISO format: YYYY-MM-DD; NULL = backlog
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE
);
"""


RESOURCES_SCHEMA = """
CREATE TABLE IF NOT EXISTS resources (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL CHECK (length(trim(name)) > 0),
    uri          TEXT    NOT NULL,           -- web link, custom protocol, or absolute file path
    created_at   TEXT    NOT NULL,           -- ISO 8601, UTC
    last_used_at TEXT    NOT NULL,           -- ISO 8601, UTC; for "most recently used" ordering
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_resources_workspace ON resources(workspace_id);
"""

TAGS_SCHEMA = """
CREATE TABLE IF NOT EXISTS tags (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT    NOT NULL,
    workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    -- the tag this one is a sub-tag of; if that tag goes, its sub-tags move up (see delete_tag)
    parent_id    INTEGER REFERENCES tags(id) ON DELETE SET NULL,
    UNIQUE (workspace_id, name)
);
CREATE TABLE IF NOT EXISTS resource_tags (
    resource_id INTEGER NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    tag_id      INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (resource_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_resource_tags_tag ON resource_tags(tag_id);
"""

HIGHLIGHTS_SCHEMA = """
CREATE TABLE IF NOT EXISTS highlights (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    resource_id INTEGER NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    page        INTEGER NOT NULL CHECK (page > 0),          -- 1-based
    text        TEXT    NOT NULL,                            -- the highlighted words, for quoting
    rects       TEXT    NOT NULL,                            -- JSON [[x, y, w, h], ...] in PDF points
    created_at  TEXT    NOT NULL,                            -- ISO 8601, UTC
    color       TEXT    NOT NULL DEFAULT 'yellow'            -- see HIGHLIGHT_COLORS
);
CREATE INDEX IF NOT EXISTS idx_highlights_resource ON highlights(resource_id, page);
"""

NOTES_SCHEMA = """
CREATE TABLE IF NOT EXISTS notes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    resource_id INTEGER NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    page        INTEGER CHECK (page IS NULL OR page > 0),   -- 1-based; NULL = whole resource
    body        TEXT    NOT NULL CHECK (length(trim(body)) > 0),
    is_question INTEGER NOT NULL DEFAULT 0 CHECK (is_question IN (0, 1)),
    -- an answer is a note whose parent is a question; deleting the question deletes its answers
    parent_id   INTEGER REFERENCES notes(id) ON DELETE CASCADE,
    created_at  TEXT    NOT NULL,            -- ISO 8601, UTC
    updated_at  TEXT    NOT NULL,            -- ISO 8601, UTC
    -- the highlighted passage this note is about; removing the highlight keeps the note
    highlight_id INTEGER REFERENCES highlights(id) ON DELETE SET NULL,
    CHECK (NOT (is_question = 1 AND parent_id IS NOT NULL))     -- answers are not questions
);
CREATE INDEX IF NOT EXISTS idx_notes_resource_page ON notes(resource_id, page);
"""

# Which resource mentions which (forward references only: x -> y when a note of x mentions y; y
# does not get x -> y back). Kept up to date whenever the notes of x are written, so the graph
# of a resource never has to read the notes themselves.
LINKS_SCHEMA = """
CREATE TABLE IF NOT EXISTS resource_links (
    source_id INTEGER NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    target_id INTEGER NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
    PRIMARY KEY (source_id, target_id),                  -- a mention counts once
    CHECK (source_id <> target_id)
);
CREATE INDEX IF NOT EXISTS idx_resource_links_target ON resource_links(target_id);
"""

NOTES_PARENT_INDEX = "CREATE INDEX IF NOT EXISTS idx_notes_parent ON notes(parent_id);"

TODOS_INDEX = "CREATE INDEX IF NOT EXISTS idx_todos_workspace_date ON todos(workspace_id, date);"

# Databases from before workspaces existed: every todo moves into the first default workspace.
# (SQLite can't add a NOT NULL foreign key column in place, so the table is rebuilt.)
MIGRATE_TODOS = f"""
BEGIN;
INSERT OR IGNORE INTO workspaces (name) VALUES ('{DEFAULT_WORKSPACES[0]}');
{_create_todos("todos_new")}
INSERT INTO todos_new (id, text, is_completed, date, workspace_id)
    SELECT id, text, is_completed, date,
           (SELECT id FROM workspaces WHERE name = '{DEFAULT_WORKSPACES[0]}')
    FROM todos;
DROP TABLE todos;
ALTER TABLE todos_new RENAME TO todos;
COMMIT;
"""


def _note(r: sqlite3.Row) -> Note:
    return Note(
        r["id"],
        r["resource_id"],
        r["page"],
        r["body"],
        bool(r["is_question"]),
        r["parent_id"],
        datetime.fromisoformat(r["created_at"]),
        datetime.fromisoformat(r["updated_at"]),
        r["highlight_id"],
    )


def _highlight(r: sqlite3.Row) -> Highlight:
    return Highlight(
        r["id"],
        r["resource_id"],
        r["page"],
        r["text"],
        tuple((float(x), float(y), float(w), float(h)) for x, y, w, h in json.loads(r["rects"])),
        datetime.fromisoformat(r["created_at"]),
        r["color"],
    )


NOTE_COLUMNS = "id, resource_id, page, body, is_question, parent_id, created_at, updated_at, highlight_id"


def _require_name(name: str) -> None:
    # The CHECK constraint covers new databases; databases migrated from before names existed
    # can't get one added in place, so the repository enforces it too.
    if not name.strip():
        raise ValueError("A resource needs a name")


def _require_color(color: str) -> None:
    if color not in HIGHLIGHT_COLORS:
        raise ValueError(f"Unknown highlight colour: {color}")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


@contextmanager
def _translate_errors() -> Iterator[None]:
    try:
        yield
    except (sqlite3.Error, ValueError) as exc:  # ValueError: corrupt date string
        raise RepositoryError(str(exc)) from exc


class SqliteTodoRepository(TodoRepository):
    """Local SQLite storage. Also BackupCapable."""

    backup_suffix = ".db"

    def __init__(self, db_path: str | Path):
        with _translate_errors():
            self._conn = sqlite3.connect(db_path)
            self._conn.row_factory = sqlite3.Row
            self._conn.execute("PRAGMA foreign_keys = ON")
            self._init_schema()

    def _init_schema(self) -> None:
        conn = self._conn
        conn.executescript(WORKSPACES_SCHEMA)
        columns = {r["name"] for r in conn.execute("PRAGMA table_info(todos)")}
        if columns and "workspace_id" not in columns:
            conn.executescript(MIGRATE_TODOS)
        conn.executescript(_create_todos("IF NOT EXISTS todos"))
        self._migrate_todos()
        conn.execute(TODOS_INDEX)
        conn.executescript(RESOURCES_SCHEMA)
        self._migrate_resources()
        conn.executescript(TAGS_SCHEMA)
        self._migrate_tags()
        conn.executescript(HIGHLIGHTS_SCHEMA)
        self._migrate_highlights()
        conn.executescript(LINKS_SCHEMA)
        conn.executescript(NOTES_SCHEMA)
        self._migrate_notes()
        conn.execute(NOTES_PARENT_INDEX)
        if not conn.execute("SELECT 1 FROM workspaces").fetchone():
            conn.executemany(
                "INSERT INTO workspaces (name) VALUES (?)", [(n,) for n in DEFAULT_WORKSPACES]
            )
        conn.commit()

    def _migrate_todos(self) -> None:
        """Todos created before the backlog existed have a NOT NULL date; the backlog needs it
        optional. SQLite cannot relax a column in place, so the table is rebuilt."""
        conn = self._conn
        date_column = next(r for r in conn.execute("PRAGMA table_info(todos)") if r["name"] == "date")
        if date_column["notnull"]:
            conn.executescript(
                "BEGIN;"
                + _create_todos("todos_new")
                + "INSERT INTO todos_new (id, text, is_completed, date, workspace_id)"
                " SELECT id, text, is_completed, date, workspace_id FROM todos;"
                "DROP TABLE todos;"
                "ALTER TABLE todos_new RENAME TO todos;"
                "COMMIT;"
            )

    def _migrate_notes(self) -> None:
        """Notes created before questions and answers existed."""
        conn = self._conn
        columns = {r["name"] for r in conn.execute("PRAGMA table_info(notes)")}
        if "is_question" not in columns:
            conn.execute(
                "ALTER TABLE notes ADD COLUMN is_question INTEGER NOT NULL DEFAULT 0"
                " CHECK (is_question IN (0, 1))"
            )
        if "parent_id" not in columns:
            conn.execute(
                "ALTER TABLE notes ADD COLUMN parent_id INTEGER REFERENCES notes(id) ON DELETE CASCADE"
            )
        if "highlight_id" not in columns:
            conn.execute(
                "ALTER TABLE notes ADD COLUMN highlight_id INTEGER"
                " REFERENCES highlights(id) ON DELETE SET NULL"
            )

    def _migrate_highlights(self) -> None:
        """Highlights made before they had colours are yellow."""
        conn = self._conn
        columns = {r["name"] for r in conn.execute("PRAGMA table_info(highlights)")}
        if "color" not in columns:
            conn.execute("ALTER TABLE highlights ADD COLUMN color TEXT NOT NULL DEFAULT 'yellow'")

    def _migrate_resources(self) -> None:
        """Resources created before they had names / last_used_at."""
        conn = self._conn
        columns = {r["name"] for r in conn.execute("PRAGMA table_info(resources)")}
        if "updated_at" in columns:
            conn.execute("ALTER TABLE resources RENAME COLUMN updated_at TO last_used_at")
        if "name" not in columns:
            conn.execute("ALTER TABLE resources ADD COLUMN name TEXT NOT NULL DEFAULT ''")
            for row in conn.execute("SELECT id, uri FROM resources").fetchall():
                conn.execute(
                    "UPDATE resources SET name = ? WHERE id = ?", (suggest_name(row["uri"]), row["id"])
                )

    # ------------------------------------------------------------- reads
    def list_workspaces(self) -> list[Workspace]:
        with _translate_errors():
            rows = self._conn.execute("SELECT id, name FROM workspaces ORDER BY id").fetchall()
            return [Workspace(r["id"], r["name"]) for r in rows]

    def create_workspace(self, name: str) -> Workspace:
        with _translate_errors(), self._conn:
            cur = self._conn.execute("INSERT INTO workspaces (name) VALUES (?)", (name,))
            return Workspace(cur.lastrowid, name)

    def rename_workspace(self, workspace_id: WorkspaceId, name: str) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute("UPDATE workspaces SET name = ? WHERE id = ?", (name, workspace_id))

    def delete_workspace(self, workspace_id: WorkspaceId) -> None:
        with _translate_errors(), self._conn:  # its todos go too (ON DELETE CASCADE)
            self._conn.execute("DELETE FROM workspaces WHERE id = ?", (workspace_id,))

    def list_resources(self, workspace_id: WorkspaceId) -> list[Resource]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT id, name, uri, created_at, last_used_at FROM resources"
                " WHERE workspace_id = ? ORDER BY id",
                (workspace_id,),
            ).fetchall()
            return [
                Resource(
                    r["id"],
                    r["name"],
                    r["uri"],
                    datetime.fromisoformat(r["created_at"]),
                    datetime.fromisoformat(r["last_used_at"]),
                )
                for r in rows
            ]

    def list_resource_tags(self, workspace_id: WorkspaceId) -> dict[ResourceId, list[TagId]]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT rt.resource_id, rt.tag_id FROM resource_tags rt"
                " JOIN resources r ON r.id = rt.resource_id"
                " WHERE r.workspace_id = ? ORDER BY rt.tag_id",
                (workspace_id,),
            ).fetchall()
            result: dict[ResourceId, list[TagId]] = {}
            for r in rows:
                result.setdefault(r["resource_id"], []).append(r["tag_id"])
            return result

    def _set_resource_tags(self, resource_id: ResourceId, tag_ids: Sequence[TagId]) -> None:
        """Replace a resource's tags. Tags of other workspaces are ignored."""
        self._conn.execute("DELETE FROM resource_tags WHERE resource_id = ?", (resource_id,))
        self._conn.executemany(
            "INSERT OR IGNORE INTO resource_tags (resource_id, tag_id)"
            " SELECT ?, id FROM tags WHERE id = ?"
            "   AND workspace_id = (SELECT workspace_id FROM resources WHERE id = ?)",
            [(resource_id, t, resource_id) for t in tag_ids],
        )

    def add_resource(
        self, workspace_id: WorkspaceId, uri: str, name: str, tag_ids: Sequence[TagId] = ()
    ) -> Resource:
        now = _now()
        with _translate_errors(), self._conn:
            _require_name(name)
            cur = self._conn.execute(
                "INSERT INTO resources (name, uri, created_at, last_used_at, workspace_id)"
                " VALUES (?, ?, ?, ?, ?)",
                (name, uri, now, now, workspace_id),
            )
            self._set_resource_tags(cur.lastrowid, tag_ids)
            stamp = datetime.fromisoformat(now)
            return Resource(cur.lastrowid, name, uri, stamp, stamp)

    def update_resource(
        self, resource_id: ResourceId, uri: str, name: str, tag_ids: Sequence[TagId] = ()
    ) -> None:
        with _translate_errors(), self._conn:
            _require_name(name)
            self._conn.execute(
                "UPDATE resources SET uri = ?, name = ? WHERE id = ?", (uri, name, resource_id)
            )
            self._set_resource_tags(resource_id, tag_ids)

    def touch_resource(self, resource_id: ResourceId) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute(
                "UPDATE resources SET last_used_at = ? WHERE id = ?", (_now(), resource_id)
            )

    def list_open_questions(self, workspace_id: WorkspaceId) -> list[Note]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT n.id, n.resource_id, n.page, n.body, n.is_question, n.parent_id,"
                " n.created_at, n.updated_at, n.highlight_id FROM notes n"
                " JOIN resources r ON r.id = n.resource_id"
                " WHERE r.workspace_id = ? AND n.is_question = 1"
                " AND NOT EXISTS (SELECT 1 FROM notes a WHERE a.parent_id = n.id)"
                " ORDER BY n.id",
                (workspace_id,),
            ).fetchall()
            return [_note(r) for r in rows]

    def count_notes(self, resource_id: ResourceId) -> tuple[int, int]:
        with _translate_errors():
            row = self._conn.execute(
                "SELECT COALESCE(SUM(is_question = 0 AND parent_id IS NULL), 0),"
                " COALESCE(SUM(is_question = 1), 0) FROM notes WHERE resource_id = ?",
                (resource_id,),
            ).fetchone()
            return row[0], row[1]

    # ----------------------------------------------------------- resource links
    def _sync_links(self, resource_id: ResourceId) -> None:
        """Rebuild the links that start at a resource from its notes (inside the caller's
        transaction). Only that one resource's notes are read."""
        bodies = [
            r[0]
            for r in self._conn.execute("SELECT body FROM notes WHERE resource_id = ?", (resource_id,))
        ]
        self._conn.execute("DELETE FROM resource_links WHERE source_id = ?", (resource_id,))
        for target in referenced_resource_ids(bodies):
            if target != resource_id:
                self._conn.execute(  # a mention of a deleted resource links to nothing
                    "INSERT OR IGNORE INTO resource_links (source_id, target_id)"
                    " SELECT ?, id FROM resources WHERE id = ?",
                    (resource_id, target),
                )

    def list_resource_links(self, resource_id: ResourceId) -> list[tuple[ResourceId, ResourceId]]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT source_id, target_id FROM resource_links"
                " WHERE source_id = ? OR target_id = ? ORDER BY source_id, target_id",
                (resource_id, resource_id),
            ).fetchall()
            return [(r[0], r[1]) for r in rows]

    def list_workspace_links(self, workspace_id: WorkspaceId) -> list[tuple[ResourceId, ResourceId]]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT l.source_id, l.target_id FROM resource_links l"
                " JOIN resources s ON s.id = l.source_id JOIN resources t ON t.id = l.target_id"
                " WHERE s.workspace_id = ? AND t.workspace_id = ? ORDER BY l.source_id, l.target_id",
                (workspace_id, workspace_id),
            ).fetchall()
            return [(r[0], r[1]) for r in rows]

    def list_note_pages(self, resource_id: ResourceId) -> list[tuple[int, int]]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT page, COUNT(*) FROM notes WHERE resource_id = ? AND page IS NOT NULL"
                " AND parent_id IS NULL GROUP BY page ORDER BY page",
                (resource_id,),
            ).fetchall()
            return [(r[0], r[1]) for r in rows]

    def list_all_notes(self, resource_id: ResourceId) -> list[Note]:
        with _translate_errors():
            rows = self._conn.execute(
                f"SELECT {NOTE_COLUMNS} FROM notes WHERE resource_id = ? ORDER BY id",
                (resource_id,),
            ).fetchall()
            return [_note(r) for r in rows]

    def list_notes(self, resource_id: ResourceId, page: int | None) -> list[Note]:
        with _translate_errors():
            rows = self._conn.execute(
                f"SELECT {NOTE_COLUMNS}"
                " FROM notes WHERE resource_id = ? AND page IS ? ORDER BY id",
                (resource_id, page),
            ).fetchall()
            return [_note(r) for r in rows]

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
        now = _now()
        if is_question:
            body = with_question_mark(body)  # a question always ends in "?"
        with _translate_errors(), self._conn:
            if highlight_id is not None:
                if parent_id is not None:
                    raise ValueError("Only a note or a question can be tied to a highlight")
                page = self._highlight_page(highlight_id, resource_id)  # lives on the highlight's page
            if parent_id is not None:
                # An answer: it belongs to a question of the same resource, on the same page.
                parent = self._conn.execute(
                    "SELECT resource_id, page, is_question FROM notes WHERE id = ?", (parent_id,)
                ).fetchone()
                if parent is None or not parent["is_question"] or parent["resource_id"] != resource_id:
                    raise ValueError("An answer needs a question on the same resource")
                if is_question:
                    raise ValueError("An answer cannot be a question")
                page = parent["page"]
            cur = self._conn.execute(
                "INSERT INTO notes (resource_id, page, body, is_question, parent_id, created_at,"
                " updated_at, highlight_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (resource_id, page, body, int(is_question), parent_id, now, now, highlight_id),
            )
            self._sync_links(resource_id)
            stamp = datetime.fromisoformat(now)
            return Note(
                cur.lastrowid, resource_id, page, body, is_question, parent_id, stamp, stamp, highlight_id
            )

    def move_note(self, note_id: NoteId, page: int | None) -> None:
        with _translate_errors(), self._conn:
            row = self._conn.execute(
                "SELECT COALESCE(parent_id, id) AS root FROM notes WHERE id = ?", (note_id,)
            ).fetchone()
            if row is None:
                raise ValueError("No such note")
            # a note stays tied to its highlight only while it is on the highlight's page
            self._conn.execute(
                "UPDATE notes SET page = ?, updated_at = ?, highlight_id = CASE WHEN"
                " (SELECT page FROM highlights WHERE id = notes.highlight_id) IS ?"
                " THEN highlight_id ELSE NULL END WHERE id = ? OR parent_id = ?",
                (page, _now(), page, row["root"], row["root"]),
            )

    def get_note_with_answers(self, note_id: NoteId) -> list[Note]:
        with _translate_errors():
            rows = self._conn.execute(
                f"SELECT {NOTE_COLUMNS}"
                " FROM notes WHERE id = ? OR parent_id = ? ORDER BY (id = ?) DESC, id",
                (note_id, note_id, note_id),
            ).fetchall()
            return [_note(r) for r in rows]

    def restore_notes(self, notes: Sequence[Note]) -> None:
        with _translate_errors(), self._conn:
            self._conn.executemany(
                "INSERT INTO notes (id, resource_id, page, body, is_question, parent_id,"
                " created_at, updated_at, highlight_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?,"
                " (SELECT id FROM highlights WHERE id = ?))",  # the highlight may be gone by now
                [
                    (
                        n.id, n.resource_id, n.page, n.body, int(n.is_question), n.parent_id,
                        n.created_at.isoformat(timespec="milliseconds"),
                        n.updated_at.isoformat(timespec="milliseconds"),
                        n.highlight_id,
                    )
                    for n in notes
                ],
            )
            for resource_id in {n.resource_id for n in notes}:
                self._sync_links(resource_id)

    # ------------------------------------------------------------ highlights
    def _highlight_page(self, highlight_id: HighlightId, resource_id: ResourceId) -> int:
        row = self._conn.execute(
            "SELECT page, resource_id FROM highlights WHERE id = ?", (highlight_id,)
        ).fetchone()
        if row is None or row["resource_id"] != resource_id:
            raise ValueError("No such highlight on this resource")
        return row["page"]

    def add_highlight(
        self,
        resource_id: ResourceId,
        page: int,
        text: str,
        rects: Sequence[Rect],
        color: str = DEFAULT_HIGHLIGHT_COLOR,
    ) -> Highlight:
        now = _now()
        with _translate_errors(), self._conn:
            if not rects or page < 1:
                raise ValueError("A highlight needs a page and at least one rectangle")
            _require_color(color)
            clean = [[float(v) for v in r] for r in rects]
            cur = self._conn.execute(
                "INSERT INTO highlights (resource_id, page, text, rects, created_at, color)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                (resource_id, page, text, json.dumps(clean), now, color),
            )
            return Highlight(
                cur.lastrowid, resource_id, page, text,
                tuple(tuple(r) for r in clean), datetime.fromisoformat(now), color,
            )

    def list_highlights(self, resource_id: ResourceId) -> list[Highlight]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT id, resource_id, page, text, rects, created_at, color FROM highlights"
                " WHERE resource_id = ? ORDER BY page, id",
                (resource_id,),
            ).fetchall()
            return [_highlight(r) for r in rows]

    def set_highlight_color(self, highlight_id: HighlightId, color: str) -> None:
        with _translate_errors(), self._conn:
            _require_color(color)
            self._conn.execute(
                "UPDATE highlights SET color = ? WHERE id = ?", (color, highlight_id)
            )

    def delete_highlight(self, highlight_id: HighlightId) -> None:
        with _translate_errors(), self._conn:  # notes that pointed at it keep existing
            self._conn.execute("DELETE FROM highlights WHERE id = ?", (highlight_id,))

    def highlight_note_ids(self, highlight_id: HighlightId) -> list[NoteId]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT id FROM notes WHERE highlight_id = ? ORDER BY id", (highlight_id,)
            ).fetchall()
            return [r["id"] for r in rows]

    def restore_highlight(self, highlight: Highlight, note_ids: Sequence[NoteId]) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute(
                "INSERT INTO highlights (id, resource_id, page, text, rects, created_at, color)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    highlight.id, highlight.resource_id, highlight.page, highlight.text,
                    json.dumps([list(r) for r in highlight.rects]),
                    highlight.created_at.isoformat(timespec="milliseconds"),
                    highlight.color,
                ),
            )
            self._conn.executemany(
                "UPDATE notes SET highlight_id = ? WHERE id = ?",
                [(highlight.id, n) for n in note_ids],  # notes deleted since are simply skipped
            )

    def set_note_highlight(self, note_id: NoteId, highlight_id: HighlightId | None) -> None:
        with _translate_errors(), self._conn:
            note = self._conn.execute(
                "SELECT resource_id, page, parent_id FROM notes WHERE id = ?", (note_id,)
            ).fetchone()
            if note is None:
                raise ValueError("No such note")
            if highlight_id is not None:
                if note["parent_id"] is not None:
                    raise ValueError("Only a note or a question can be tied to a highlight")
                if self._highlight_page(highlight_id, note["resource_id"]) != note["page"]:
                    raise ValueError("The note and the highlight must be on the same page")
            self._conn.execute(
                "UPDATE notes SET highlight_id = ?, updated_at = ? WHERE id = ?",
                (highlight_id, _now(), note_id),
            )

    def update_note(self, note_id: NoteId, body: str) -> None:
        with _translate_errors(), self._conn:
            row = self._conn.execute(
                "SELECT is_question FROM notes WHERE id = ?", (note_id,)
            ).fetchone()
            if row is not None and row["is_question"]:
                body = with_question_mark(body)  # editing a question keeps the "?"
            self._conn.execute(
                "UPDATE notes SET body = ?, updated_at = ? WHERE id = ?", (body, _now(), note_id)
            )
            self._sync_links_of_note(note_id)

    def _sync_links_of_note(self, note_id: NoteId) -> None:
        row = self._conn.execute("SELECT resource_id FROM notes WHERE id = ?", (note_id,)).fetchone()
        if row is not None:
            self._sync_links(row["resource_id"])

    def delete_note(self, note_id: NoteId) -> None:
        with _translate_errors(), self._conn:
            row = self._conn.execute(
                "SELECT resource_id FROM notes WHERE id = ?", (note_id,)
            ).fetchone()
            self._conn.execute("DELETE FROM notes WHERE id = ?", (note_id,))
            if row is not None:
                self._sync_links(row["resource_id"])

    def _migrate_tags(self) -> None:
        columns = {r["name"] for r in self._conn.execute("PRAGMA table_info(tags)")}
        if "parent_id" not in columns:
            self._conn.execute(
                "ALTER TABLE tags ADD COLUMN parent_id INTEGER REFERENCES tags(id) ON DELETE SET NULL"
            )

    def _check_parent(self, tag_id: TagId | None, workspace_id: WorkspaceId, parent_id: TagId | None) -> None:
        """A parent must be a tag of the same workspace and not the tag itself or below it."""
        if parent_id is None:
            return
        row = self._conn.execute("SELECT workspace_id FROM tags WHERE id = ?", (parent_id,)).fetchone()
        if row is None or row["workspace_id"] != workspace_id:
            raise ValueError("The parent tag is not in this workspace")
        seen: set[int] = set()
        current: int | None = parent_id
        while current is not None and current not in seen:  # walk up from the new parent
            if current == tag_id:
                raise ValueError("A tag can't go below itself")
            seen.add(current)
            above = self._conn.execute("SELECT parent_id FROM tags WHERE id = ?", (current,)).fetchone()
            current = above["parent_id"] if above else None

    def list_tags(self, workspace_id: WorkspaceId) -> list[Tag]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT id, name, parent_id FROM tags WHERE workspace_id = ?"
                " ORDER BY name COLLATE NOCASE, id",
                (workspace_id,),
            ).fetchall()
            return [Tag(r["id"], r["name"], r["parent_id"]) for r in rows]

    def create_tag(self, workspace_id: WorkspaceId, name: str, parent_id: TagId | None = None) -> Tag:
        with _translate_errors(), self._conn:
            self._check_parent(None, workspace_id, parent_id)
            cur = self._conn.execute(
                "INSERT INTO tags (name, workspace_id, parent_id) VALUES (?, ?, ?)",
                (name, workspace_id, parent_id),
            )
            return Tag(cur.lastrowid, name, parent_id)

    def rename_tag(self, tag_id: TagId, name: str) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute("UPDATE tags SET name = ? WHERE id = ?", (name, tag_id))

    def set_tag_parent(self, tag_id: TagId, parent_id: TagId | None) -> None:
        with _translate_errors(), self._conn:
            row = self._conn.execute("SELECT workspace_id FROM tags WHERE id = ?", (tag_id,)).fetchone()
            if row is None:
                raise ValueError("No such tag")
            self._check_parent(tag_id, row["workspace_id"], parent_id)
            self._conn.execute("UPDATE tags SET parent_id = ? WHERE id = ?", (parent_id, tag_id))

    def delete_tag(self, tag_id: TagId) -> None:
        with _translate_errors(), self._conn:  # resource_tags rows go too (ON DELETE CASCADE)
            # its sub-tags move up one level, to where it was
            self._conn.execute(
                "UPDATE tags SET parent_id = (SELECT parent_id FROM tags WHERE id = ?)"
                " WHERE parent_id = ?",
                (tag_id, tag_id),
            )
            self._conn.execute("DELETE FROM tags WHERE id = ?", (tag_id,))

    def delete_resource(self, resource_id: ResourceId) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute("DELETE FROM resources WHERE id = ?", (resource_id,))

    def list_todos(self, workspace_id: WorkspaceId) -> list[Todo]:
        with _translate_errors():
            rows = self._conn.execute(
                "SELECT id, text, is_completed, date FROM todos"
                " WHERE workspace_id = ? ORDER BY date IS NOT NULL, date, id",  # backlog first
                (workspace_id,),
            ).fetchall()
            return [
                Todo(
                    r["id"],
                    r["text"],
                    bool(r["is_completed"]),
                    date.fromisoformat(r["date"]) if r["date"] else None,
                )
                for r in rows
            ]

    # ------------------------------------------------------------ writes
    def add(self, workspace_id: WorkspaceId, day: date | None, text: str) -> Todo:
        with _translate_errors(), self._conn:
            cur = self._conn.execute(
                "INSERT INTO todos (text, is_completed, date, workspace_id) VALUES (?, 0, ?, ?)",
                (text, day.isoformat() if day else None, workspace_id),
            )
            return Todo(cur.lastrowid, text, False, day)

    def set_done(self, todo_id: TodoId, done: bool) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute(
                "UPDATE todos SET is_completed = ? WHERE id = ?", (int(done), todo_id)
            )

    def move_to_day(self, todo_id: TodoId, day: date | None) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute(
                "UPDATE todos SET date = ? WHERE id = ?", (day.isoformat() if day else None, todo_id)
            )

    def move_open_todos(self, workspace_id: WorkspaceId, from_day: date, to_day: date) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute(
                "UPDATE todos SET date = ? WHERE workspace_id = ? AND date = ? AND is_completed = 0",
                (to_day.isoformat(), workspace_id, from_day.isoformat()),
            )

    def update_text(self, todo_id: TodoId, text: str) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute("UPDATE todos SET text = ? WHERE id = ?", (text, todo_id))

    def delete(self, todo_id: TodoId) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute("DELETE FROM todos WHERE id = ?", (todo_id,))

    def restore_todo(self, workspace_id: WorkspaceId, todo: Todo) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute(
                "INSERT INTO todos (id, text, is_completed, date, workspace_id) VALUES (?, ?, ?, ?, ?)",
                (todo.id, todo.text, int(todo.done), todo.day.isoformat() if todo.day else None, workspace_id),
            )

    def close(self) -> None:
        self._conn.close()

    # ------------------------------------------------- BackupCapable
    def backup_to(self, dest: Path) -> None:
        """Consistent snapshot of the database, safe while the app is running."""
        with _translate_errors():
            target = sqlite3.connect(dest)
            try:
                self._conn.backup(target)
            finally:
                target.close()
