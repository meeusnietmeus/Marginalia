from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

from .base import BackupCapable


def backup_file_name(now: datetime, suffix: str) -> str:
    return f"todos-backup-{now:%Y-%m-%d_%H-%M-%S}{suffix}"


def export_backup(repo: BackupCapable, folder: Path, now: datetime | None = None) -> Path:
    """Write a timestamped full copy of the storage into ``folder``; returns the file path.

    Raises RepositoryError or OSError on failure.
    """
    folder.mkdir(parents=True, exist_ok=True)
    dest = folder / backup_file_name(now or datetime.now(), repo.backup_suffix)
    repo.backup_to(dest)
    return dest


def _created(path: Path) -> float:
    """When a file was created (not last changed): the birth time where the system has one."""
    stat = path.stat()
    return getattr(stat, "st_birthtime", stat.st_ctime)


def list_backups(folder: Path, suffix: str) -> list[Path]:
    """The backups in ``folder``, oldest first by creation date (the names are not trusted)."""
    if not folder.is_dir():
        return []
    found = []
    for path in folder.glob(f"todos-backup-*{suffix}"):
        try:
            found.append((_created(path), path.name, path))
        except OSError:
            continue  # gone in the meantime
    return [path for _, _, path in sorted(found)]


def prune_backups(folder: Path, keep: int, suffix: str) -> list[Path]:
    """Delete the oldest backups until ``keep`` are left (0: keep them all). Returns what went."""
    if keep <= 0:
        return []
    backups = list_backups(folder, suffix)
    removed = []
    for path in backups[: max(0, len(backups) - keep)]:
        try:
            path.unlink()
            removed.append(path)
        except OSError:
            pass  # can't delete it now: it stays, the next backup tries again
    return removed
