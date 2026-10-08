"""Per-machine UI state ("where was I"), kept apart from the central database.

The central database holds what the user *made* (todos, resources, notes) and is the part that
could one day live on a server and be shared. This one holds what only makes sense on this
machine, such as the page a PDF was last read to. Losing it costs nothing, so failures here are
never fatal for the app.

Rows refer to central ids (``resource_id``) with no foreign key, since they are different files;
the controller forgets a row when its resource is deleted.
"""
from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from ..core.models import ResourceId

SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS pdf_progress (
    resource_id INTEGER PRIMARY KEY,
    page        INTEGER NOT NULL CHECK (page > 0),   -- 1-based
    updated_at  TEXT    NOT NULL                     -- ISO 8601, UTC
);

-- App-wide preferences that belong to this machine (e.g. scroll speed).
CREATE TABLE IF NOT EXISTS app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Per-workspace preferences that belong to this machine (e.g. a folder path). One row per
-- setting, so new settings need no schema change.
CREATE TABLE IF NOT EXISTS workspace_settings (
    workspace_id INTEGER NOT NULL,
    key          TEXT    NOT NULL,
    value        TEXT    NOT NULL,
    PRIMARY KEY (workspace_id, key)
);
"""


class ClientStateError(Exception):
    pass


@contextmanager
def _translate_errors() -> Iterator[None]:
    try:
        yield
    except sqlite3.Error as exc:
        raise ClientStateError(str(exc)) from exc


class ClientState:
    def __init__(self, path: str | Path):
        with _translate_errors():
            self._conn = sqlite3.connect(str(path))
            self._conn.executescript(SCHEMA)
            self._conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
            self._conn.commit()

    def pdf_page(self, resource_id: ResourceId) -> int | None:
        """The page to resume at, or None when this PDF was never left open."""
        with _translate_errors():
            row = self._conn.execute(
                "SELECT page FROM pdf_progress WHERE resource_id = ?", (resource_id,)
            ).fetchone()
        return row[0] if row else None

    def set_pdf_page(self, resource_id: ResourceId, page: int) -> None:
        """Create or update."""
        now = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
        with _translate_errors(), self._conn:
            self._conn.execute(
                "INSERT INTO pdf_progress (resource_id, page, updated_at) VALUES (?, ?, ?) "
                "ON CONFLICT(resource_id) DO UPDATE SET page = excluded.page, "
                "updated_at = excluded.updated_at",
                (resource_id, page, now),
            )

    def forget_pdf(self, resource_id: ResourceId) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute("DELETE FROM pdf_progress WHERE resource_id = ?", (resource_id,))

    def app_setting(self, key: str) -> str | None:
        with _translate_errors():
            row = self._conn.execute(
                "SELECT value FROM app_settings WHERE key = ?", (key,)
            ).fetchone()
        return row[0] if row else None

    def set_app_setting(self, key: str, value: str | None) -> None:
        """Create or update; None removes the setting."""
        with _translate_errors(), self._conn:
            if value is None:
                self._conn.execute("DELETE FROM app_settings WHERE key = ?", (key,))
            else:
                self._conn.execute(
                    "INSERT INTO app_settings (key, value) VALUES (?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                    (key, value),
                )

    def workspace_setting(self, workspace_id: int, key: str) -> str | None:
        with _translate_errors():
            row = self._conn.execute(
                "SELECT value FROM workspace_settings WHERE workspace_id = ? AND key = ?",
                (workspace_id, key),
            ).fetchone()
        return row[0] if row else None

    def set_workspace_setting(self, workspace_id: int, key: str, value: str | None) -> None:
        """Create or update; None removes the setting."""
        with _translate_errors(), self._conn:
            if value is None:
                self._conn.execute(
                    "DELETE FROM workspace_settings WHERE workspace_id = ? AND key = ?",
                    (workspace_id, key),
                )
            else:
                self._conn.execute(
                    "INSERT INTO workspace_settings (workspace_id, key, value) VALUES (?, ?, ?) "
                    "ON CONFLICT(workspace_id, key) DO UPDATE SET value = excluded.value",
                    (workspace_id, key, value),
                )

    def forget_workspace(self, workspace_id: int) -> None:
        with _translate_errors(), self._conn:
            self._conn.execute(
                "DELETE FROM workspace_settings WHERE workspace_id = ?", (workspace_id,)
            )

    def close(self) -> None:
        self._conn.close()
