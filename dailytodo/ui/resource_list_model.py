from __future__ import annotations

from ..core import ResourceCard
from .keyed_list_model import KeyedListModel


class ResourceListModel(KeyedListModel[ResourceCard]):
    """One row per resource card. Role names are what the library's QML declares."""

    ROLES = {
        "resourceId": "id",
        "name": "name",
        "uri": "uri",
        "kind": "kind",
        "title": "title",
        "isPath": "is_path",
        "missing": "missing",
        "tagIds": "tag_ids",
        "status": "status",
    }
    KEY = "id"