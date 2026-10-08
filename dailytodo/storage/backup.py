from __future__ import annotations

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
