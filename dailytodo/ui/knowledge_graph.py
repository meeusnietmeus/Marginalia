"""State of the "Knowledge graph" page: every resource of the workspace and the links between them.

The data is read here, on the main thread (one query for the links, one pass over the cards); the
layout, which can take a while for a big workspace, is computed on a worker thread. The page shows
a loading indicator only when that takes longer than ``delay_ms``.
"""
from __future__ import annotations

import threading
from dataclasses import asdict
from typing import Callable, Mapping, Sequence

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

from ..core import (
    GraphResource,
    GraphTag,
    KnowledgeGraph,
    ResourceCard,
    ResourceId,
    Tag,
    WorkspaceId,
    build_graph,
    with_ancestors,
)
from ..storage import RepositoryError, TodoRepository

LOADING_DELAY_MS = 150


class KnowledgeGraphModel(QObject):
    error = Signal(str)
    changed = Signal()
    loadingChanged = Signal()
    _computed = Signal(int, object)  # (build number, KnowledgeGraph | Exception), from the worker

    def __init__(
        self,
        repo: TodoRepository,
        workspace_id: Callable[[], WorkspaceId],
        cards: Callable[[], Mapping[ResourceId, ResourceCard]],
        tags: Callable[[], Sequence[Tag]],
        parent: QObject | None = None,
        delay_ms: int = LOADING_DELAY_MS,
        compute: Callable[..., KnowledgeGraph] = build_graph,
    ):
        super().__init__(parent)
        self._repo = repo
        self._workspace_id = workspace_id
        self._cards = cards
        self._tags = tags
        self._compute = compute
        self._graph: KnowledgeGraph | None = None
        self._input = None  # what the current graph was built from
        self._build = 0  # number of the newest build; older answers are ignored
        self._computing = False
        self._loading = False
        self._delay = QTimer(self)
        self._delay.setSingleShot(True)
        self._delay.setInterval(delay_ms)
        self._delay.timeout.connect(self._show_loading)
        self._computed.connect(self._apply)

    # ------------------------------------------------------------ properties
    @Property(bool, notify=loadingChanged)
    def loading(self) -> bool:
        """True while a build has been running for longer than the delay."""
        return self._loading

    @Property(bool, notify=changed)
    def built(self) -> bool:
        return self._graph is not None

    @Property("QVariantList", notify=changed)
    def nodes(self) -> list:
        return [asdict(n) | {"tags": list(n.tags)} for n in self._graph.nodes] if self._graph else []

    @Property("QVariantList", notify=changed)
    def edges(self) -> list:
        return [asdict(e) for e in self._graph.edges] if self._graph else []

    @Property("QVariantList", notify=changed)
    def regions(self) -> list:
        return [asdict(r) for r in self._graph.regions] if self._graph else []

    @Property("QVariantList", notify=changed)
    def areas(self) -> list:
        return [asdict(a) for a in self._graph.areas] if self._graph else []

    @Property(float, notify=changed)
    def worldWidth(self) -> float:
        return self._graph.width if self._graph else 0.0

    @Property(float, notify=changed)
    def worldHeight(self) -> float:
        return self._graph.height if self._graph else 0.0

    # --------------------------------------------------------------- actions
    @Slot()
    def rebuild(self) -> None:
        """Build the graph again, unless nothing it is made of has changed."""
        try:
            links = self._repo.list_workspace_links(self._workspace_id())
        except RepositoryError as exc:
            self.error.emit(f"Couldn't load the links: {exc}")
            return
        tags = self._tags()
        names = {t.id: t.name for t in tags}
        graph_tags = tuple(GraphTag(t.id, t.name, t.parent_id, t.color) for t in tags)
        resources = []
        for c in self._cards().values():
            # the legend's filter also finds what is tagged with a sub-tag
            every = {names[t] for t in with_ancestors(tags, c.tag_ids) if t in names}
            resources.append(
                GraphResource(c.id, c.name, c.kind, c.missing,
                              tuple(sorted(every, key=str.casefold)), tuple(c.tag_ids), c.status)
            )
        signature = (tuple(resources), tuple(links), graph_tags)
        if signature == self._input:
            return
        self._input = signature
        self._build += 1
        number = self._build
        self._computing = True
        self._delay.start()
        threading.Thread(
            target=self._work, args=(number, resources, links, graph_tags), daemon=True
        ).start()

    # ------------------------------------------------------------- internals
    def _work(self, number: int, resources: list, links: list, tags: tuple) -> None:
        try:
            result: object = self._compute(resources, links, tags)
        except Exception as exc:  # shown to the user; the worker must not die silently
            result = exc
        self._computed.emit(number, result)

    def _apply(self, number: int, result: object) -> None:
        if number != self._build:
            return  # a newer build is on its way
        self._computing = False
        self._delay.stop()
        self._set_loading(False)
        if isinstance(result, Exception):
            self._input = None
            self.error.emit(f"Couldn't build the graph: {result}")
            return
        self._graph = result  # type: ignore[assignment]
        self.changed.emit()

    def _show_loading(self) -> None:
        if self._computing:
            self._set_loading(True)

    def _set_loading(self, loading: bool) -> None:
        if loading != self._loading:
            self._loading = loading
            self.loadingChanged.emit()
