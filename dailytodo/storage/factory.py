from __future__ import annotations

from pathlib import Path

from .base import TodoRepository
from .sqlite_repository import SqliteTodoRepository


def build_repository(db_path: str | Path) -> TodoRepository:
    """The one place that decides which storage strategy is used.

    To move to an API later: add e.g. ApiTodoRepository in this package, add an
    `--api-url` option to config.py, and return it from here. Nothing else changes.
    """
    return SqliteTodoRepository(db_path)
