from __future__ import annotations

from ..core import DayRow
from .keyed_list_model import KeyedListModel


class DayListModel(KeyedListModel[DayRow]):
    """One row per visible day. Role names are what DayDelegate.qml declares."""

    ROLES = {
        "dateIso": "date_iso",
        "dayTitle": "title",
        "dateLabel": "date_label",
        "dayKind": "kind",
        "todos": "todos",
        "weekLabel": "week_label",
    }
    KEY = "date_iso"
