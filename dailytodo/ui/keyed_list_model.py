"""Reusable list model over immutable row objects (e.g. frozen dataclasses)."""
from __future__ import annotations

from typing import Any, ClassVar, Generic, Sequence, TypeVar

from PySide6.QtCore import QAbstractListModel, QModelIndex, QPersistentModelIndex, Qt

Row = TypeVar("Row")


class KeyedListModel(QAbstractListModel, Generic[Row]):
    """Exposes a list of rows to QML; ``set_rows`` diffs instead of resetting.

    Subclasses declare:
        ROLES: QML role name -> row attribute, e.g. {"dateIso": "date_iso"}
        KEY:   the attribute that identifies a row across updates

    Because updates are emitted as fine-grained inserts/removes/moves/changes, a
    ListView keeps its scroll position and untouched delegates are not rebuilt.
    """

    ROLES: ClassVar[dict[str, str]] = {}
    KEY: ClassVar[str] = ""

    def __init__(self, parent=None):
        super().__init__(parent)
        if not self.ROLES or not self.KEY:
            raise TypeError(f"{type(self).__name__} must define ROLES and KEY")
        first = int(Qt.ItemDataRole.UserRole) + 1
        self._role_attrs = {first + i: attr for i, attr in enumerate(self.ROLES.values())}
        self._role_names = {first + i: name.encode() for i, name in enumerate(self.ROLES)}
        self._rows: list[Row] = []

    # ------------------------------------------------------------ model API
    def rowCount(self, parent: QModelIndex | QPersistentModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._rows)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole) -> Any:
        if not index.isValid() or not 0 <= index.row() < len(self._rows):
            return None
        attr = self._role_attrs.get(role)
        return getattr(self._rows[index.row()], attr) if attr else None

    def roleNames(self):
        return self._role_names

    # ------------------------------------------------------------ python API
    @property
    def rows(self) -> Sequence[Row]:
        return tuple(self._rows)

    def index_of(self, predicate) -> int:
        """Index of the first row matching ``predicate``, or -1."""
        return next((i for i, row in enumerate(self._rows) if predicate(row)), -1)

    def set_rows(self, new_rows: Sequence[Row]) -> None:
        """Replace the contents, emitting only the changes.

        A row whose key moved (e.g. the library re-sorted) is moved, so its
        delegate survives. Keys must be unique.
        """
        key = self.KEY
        new_keys = {getattr(r, key) for r in new_rows}

        for i in range(len(self._rows) - 1, -1, -1):
            if getattr(self._rows[i], key) not in new_keys:
                self.beginRemoveRows(QModelIndex(), i, i)
                del self._rows[i]
                self.endRemoveRows()

        # Rows before i already match new_rows, so a key found further on can only be at j > i.
        for i, row in enumerate(new_rows):
            wanted = getattr(row, key)
            j = next(
                (j for j in range(i, len(self._rows)) if getattr(self._rows[j], key) == wanted), -1
            )
            if j < 0:
                self.beginInsertRows(QModelIndex(), i, i)
                self._rows.insert(i, row)
                self.endInsertRows()
                continue
            if j != i:
                self.beginMoveRows(QModelIndex(), j, j, QModelIndex(), i)
                self._rows.insert(i, self._rows.pop(j))
                self.endMoveRows()
            if self._rows[i] != row:
                self._rows[i] = row
                idx = self.index(i)
                self.dataChanged.emit(idx, idx)  # only rows that actually changed
