"""Importing many files as resources at once: which of the chosen paths become rows of the import
list, with what name and kind, and which are left out. No Qt and no storage in here.

Files and folders can be given; a folder brings every file inside it (at any depth), except the
hidden ones (names starting with a dot, and the folders that start with one, like ``.backups``).
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Iterable, Sequence

from .resources import file_kind, suggest_name

OK = "ok"
DUPLICATE = "duplicate"  # already a resource of the workspace, or listed twice


@dataclass(frozen=True, slots=True)
class ImportItem:
    path: str
    name: str  # a starting point; the user may change it
    kind: str  # for the icon (pdf, word, file ...)
    status: str  # OK or DUPLICATE
    folder: str  # where it is, to tell same-named files apart


def _key(path: str) -> str:
    return os.path.normcase(os.path.abspath(path))


def expand_paths(paths: Iterable[str]) -> list[str]:
    """The files behind the given paths: a folder is replaced by the files in it. Paths that don't
    exist are dropped. Order: as given, a folder's files by name."""
    files: list[str] = []
    for raw in paths:
        path = raw.strip()
        if not path:
            continue
        if os.path.isdir(path):
            for root, dirs, names in os.walk(path):
                dirs[:] = sorted(d for d in dirs if not d.startswith("."))
                for name in sorted(names):
                    if not name.startswith("."):
                        files.append(os.path.join(root, name))
        elif os.path.isfile(path):
            files.append(os.path.normpath(path))
    return files


def plan_import(paths: Sequence[str], existing_uris: Iterable[str], already_listed: Iterable[str] = ()) -> list[ImportItem]:
    """The import rows for ``paths``. ``existing_uris``: the links of the workspace's resources;
    ``already_listed``: paths already in the list (adding more files to it)."""
    taken = {_key(u) for u in existing_uris if u} | {_key(p) for p in already_listed}
    items = []
    for path in expand_paths(paths):
        key = _key(path)
        status = DUPLICATE if key in taken else OK
        taken.add(key)
        items.append(ImportItem(path, suggest_name(path), file_kind(path), status, os.path.dirname(path)))
    return items
