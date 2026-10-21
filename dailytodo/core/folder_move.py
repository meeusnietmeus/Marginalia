"""Planning the move of a workspace's folder: which files go where, and which links change.

Only paths are worked out here (no files are touched). A resource is part of the move when its
file lies inside the old folder, at any depth; its place inside the folder is kept. The PDF that was
made from a presentation lives in the folder too (named after the presentation), wherever the
presentation itself is, so it goes along.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Iterable

from .presentations import pdf_file_name
from .resources import is_inside


@dataclass(frozen=True, slots=True)
class MoveItem:
    resource_id: int  # the resource this file belongs to
    source: str
    target: str
    link: bool  # True: the resource's own file (its link changes); False: the PDF of a presentation


@dataclass(slots=True)
class FolderMovePlan:
    items: list[MoveItem] = field(default_factory=list)

    @property
    def link_updates(self) -> dict[int, str]:
        """resource id -> its new link, for the resources whose file moves."""
        return {i.resource_id: i.target for i in self.items if i.link}


def same_folder(a: str, b: str) -> bool:
    return os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))


def folder_problem(old: str, new: str) -> str:
    """Why ``new`` can't replace ``old`` as the workspace folder ("" when it can)."""
    if not new.strip():
        return "Choose a folder"
    if old and same_folder(old, new):
        return "That is already the workspace folder"
    if old and (is_inside(new, old) or is_inside(old, new)):
        return "The new folder can't be inside the old one, or the other way round"
    return ""


BACKUPS = ".backups"  # inside the workspace folder (see TodoController.exportBackup)


def plan_folder_move(
    old: str,
    new: str,
    resources: Iterable[tuple[int, str, bool, str]],
    backups: Iterable[str] = (),
) -> FolderMovePlan:
    """``resources``: (id, link, is a local file, kind) of the workspace's resources. ``backups``:
    the files in the old folder's backup folder, which go along (they belong to no resource)."""
    plan = FolderMovePlan()
    seen: set[str] = set()

    def add(resource_id: int, source: str, link: bool) -> None:
        key = os.path.normcase(os.path.abspath(source))
        if key in seen:
            return
        seen.add(key)
        target = os.path.normpath(os.path.join(new, os.path.relpath(source, old)))
        plan.items.append(MoveItem(resource_id, source, target, link))

    for resource_id, uri, is_path, kind in resources:
        if is_path and is_inside(uri, old):
            add(resource_id, uri, True)
        if kind == "powerpoint":
            pdf = os.path.join(old, pdf_file_name(uri))
            if os.path.isfile(pdf):
                add(resource_id, pdf, False)
    for backup in backups:
        add(-1, backup, False)
    return plan
