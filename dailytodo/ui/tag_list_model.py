from __future__ import annotations

from ..core import LabelRow
from .keyed_list_model import KeyedListModel


class TagListModel(KeyedListModel[LabelRow]):
    """The active workspace's tags in tree order: a tag, then its sub-tags, then the next tag.
    ``depth`` says how far a row is indented, ``path`` is "Maths › Algebra"."""

    ROLES = {
        "tagId": "id",
        "name": "name",
        "parentId": "parent_id",
        "depth": "depth",
        "path": "path",
        "childCount": "child_count",
        "family": "family",
    }
    KEY = "id"
