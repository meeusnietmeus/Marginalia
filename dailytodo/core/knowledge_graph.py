"""The knowledge graph of a workspace: every resource, the links between them, and where to draw
each one. No Qt and no storage in here, so it is plain unit-testable logic.

* Every resource is drawn, linked or not, in the region of its tag: the most specific one it has
  (a sub-tag before the tag above it; between equals, the first by name). A sub-tag's region sits
  inside its tag's region, so the picture follows the tag tree. Resources without a tag share an
  "Untagged" region.
* Inside a region, resources that link to each other are laid out together (a force-directed
  layout, so strongly linked resources end up close); the ones without a link in the region sit in
  a tidy grid. Links between regions are drawn as well, they just aren't used for placing.
* A tag family shares a colour: a top tag has the one it was given (or one by position), a sub-tag
  has its top tag's.
* Finding linked groups walks the links once: every link is looked at a single time and every
  resource is queued a single time, however many cycles there are.
"""
from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence

NODE_W = 185.0  # the narrowest a resource is drawn, in layout units: names grow it, up to MAX_NAME_CHARS
MAX_NAME_CHARS = 80  # a longer name is cut here and ends in an ellipsis
CHAR_W = 7.4  # about how wide a character of a name is drawn
NODE_PAD = 46.0  # what a resource's pill needs besides its name: the kind's tile and the margins
NODE_H = 30.0
LINK_LENGTH = 140.0  # the layout's preferred distance between two linked resources
GROUP_GAP = 36.0  # between the blocks inside a region
REGION_GAP = 90.0  # between the regions at the top
REGION_HEADER = 40.0  # room at the top of a region for its name
REGION_PADDING = 26.0
UNTAGGED = -1  # the region of the resources without a tag


@dataclass(frozen=True, slots=True)
class GraphTag:
    id: int
    name: str
    parent: int | None = None
    color: int | None = None  # a top-level tag's own colour; None: by position


@dataclass(frozen=True, slots=True)
class GraphResource:
    """What the graph needs to know about a resource."""

    id: int
    name: str
    kind: str
    missing: bool = False
    tags: tuple[str, ...] = ()  # tag names, with the ones above them (for the legend's filter)
    own: tuple[int, ...] = ()  # the ids of the tags it was given itself


@dataclass(frozen=True, slots=True)
class GraphNode:
    id: int
    name: str
    kind: str
    missing: bool
    tags: tuple[str, ...]
    region: int  # the tag whose region it is in (UNTAGGED: none)
    color: int  # its tag family's colour (index), -1 for none
    degree: int
    x: float  # centre, in layout units
    y: float
    label: str = ""  # the name as drawn: at most MAX_NAME_CHARS characters
    width: float = NODE_W  # how wide its pill is


@dataclass(frozen=True, slots=True)
class GraphEdge:
    a: int  # the smaller id
    b: int
    a_to_b: bool  # a mentions b
    b_to_a: bool  # b mentions a


@dataclass(frozen=True, slots=True)
class Region:
    tag: int  # UNTAGGED for the resources without a tag
    name: str
    depth: int  # 0 for a top tag
    color: int
    size: int  # resources in it, its sub-regions included
    x: float  # top-left corner
    y: float
    width: float
    height: float


@dataclass(frozen=True, slots=True)
class Area:
    """A tag, for the legend (every tag, in tree order: a tag, then its sub-tags)."""

    tag: int
    name: str
    path: str  # "Maths › Linear algebra"
    depth: int
    color: int
    count: int  # resources with this tag or one below it


@dataclass(frozen=True, slots=True)
class KnowledgeGraph:
    nodes: tuple[GraphNode, ...]
    edges: tuple[GraphEdge, ...]
    regions: tuple[Region, ...]  # outer ones before the ones inside them
    areas: tuple[Area, ...]
    width: float
    height: float


# ------------------------------------------------------------------ clusters
def find_clusters(
    ids: Iterable[int], links: Iterable[tuple[int, int]]
) -> tuple[list[list[int]], dict[tuple[int, int], GraphEdge]]:
    """Group resources into clusters and merge the links into edges.

    ``links`` are (source, target) pairs; a pair and its reverse become one edge. Links to
    something that is not in ``ids`` (another workspace) are dropped. Returns the clusters (each
    a list of ids, the biggest first, loose resources as clusters of one) and the edges by
    (smaller id, bigger id).
    """
    known = set(ids)
    merged: dict[tuple[int, int], list[bool]] = {}
    for source, target in links:
        if source == target or source not in known or target not in known:
            continue
        key = (source, target) if source < target else (target, source)
        directions = merged.setdefault(key, [False, False])
        directions[0 if source < target else 1] = True
    edges = {key: GraphEdge(key[0], key[1], d[0], d[1]) for key, d in merged.items()}

    incident: dict[int, list[tuple[int, int]]] = {i: [] for i in known}
    for key in edges:
        incident[key[0]].append(key)
        incident[key[1]].append(key)

    visited: set[int] = set()  # resources already queued
    walked: set[tuple[int, int]] = set()  # links already looked at
    clusters: list[list[int]] = []
    for start in sorted(known):
        if start in visited:
            continue
        visited.add(start)
        queue = deque([start])
        members: list[int] = []
        while queue:
            current = queue.popleft()
            members.append(current)
            for key in incident[current]:
                if key in walked:
                    continue  # reached from its other end already
                walked.add(key)
                other = key[1] if key[0] == current else key[0]
                if other not in visited:
                    visited.add(other)
                    queue.append(other)
        clusters.append(members)
    clusters.sort(key=lambda c: (-len(c), min(c)))
    return clusters, edges


def node_label(name: str) -> str:
    """A resource's name as the graph draws it: up to MAX_NAME_CHARS characters, then an ellipsis."""
    return name if len(name) <= MAX_NAME_CHARS else name[:MAX_NAME_CHARS].rstrip() + "…"


def node_width(name: str) -> float:
    """How wide a resource's pill is, in layout units: room for its label, never below NODE_W."""
    return max(NODE_W, NODE_PAD + CHAR_W * len(node_label(name)))


# -------------------------------------------------------------------- layout
def _iterations(n: int) -> int:
    return 150 if n <= 40 else 90 if n <= 120 else 40 if n <= 300 else 15


def layout_cluster(
    members: Sequence[int], edges: Iterable[tuple[int, int]], widths: Mapping[int, float] | None = None
) -> dict[int, tuple[float, float]]:
    """Positions for one linked group (top-left at 0, 0): linked resources attract, all repel
    (Fruchterman-Reingold). Deterministic: the same group always looks the same. ``widths`` says
    how wide each resource is (NODE_W when it isn't there)."""
    widths = widths or {}
    n = len(members)
    if n == 1:
        return {members[0]: (widths.get(members[0], NODE_W) / 2, NODE_H / 2)}
    side = max(260.0, LINK_LENGTH * 1.15 * math.sqrt(n))
    order = sorted(members)
    index = {m: i for i, m in enumerate(order)}
    px = [side / 2 + side / 3 * math.cos(2 * math.pi * i / n) for i in range(n)]
    py = [side / 2 + side / 3 * math.sin(2 * math.pi * i / n) for i in range(n)]
    pairs = [(index[a], index[b]) for a, b in edges]
    k = LINK_LENGTH
    steps = _iterations(n)
    heat = side / 6
    cooling = heat / (steps + 1)
    for _ in range(steps):
        dx = [0.0] * n
        dy = [0.0] * n
        for i in range(n):
            for j in range(i + 1, n):
                ddx, ddy = px[i] - px[j], py[i] - py[j]
                dist2 = ddx * ddx + ddy * ddy or 0.01
                force = k * k / dist2  # repulsion k^2/d, as a factor of the vector
                dx[i] += ddx * force
                dy[i] += ddy * force
                dx[j] -= ddx * force
                dy[j] -= ddy * force
        for i, j in pairs:
            ddx, ddy = px[i] - px[j], py[i] - py[j]
            dist = math.sqrt(ddx * ddx + ddy * ddy) or 0.1
            force = dist / k  # attraction d^2/k, as a factor of the vector
            dx[i] -= ddx * force
            dy[i] -= ddy * force
            dx[j] += ddx * force
            dy[j] += ddy * force
        for i in range(n):  # a weak pull to the middle keeps the group together
            dx[i] -= (px[i] - side / 2) * 0.06
            dy[i] -= (py[i] - side / 2) * 0.06
            length = math.sqrt(dx[i] * dx[i] + dy[i] * dy[i]) or 0.01
            step = min(length, heat)
            px[i] += dx[i] / length * step
            py[i] += dy[i] / length * step
        heat -= cooling
    wide = [widths.get(m, NODE_W) for m in order]
    _settle(px, py, wide)
    left, top = min(px[i] - wide[i] / 2 for i in range(n)), min(py)
    return {m: (px[index[m]] - left, py[index[m]] - top + NODE_H / 2) for m in order}


GAP_X = 22.0  # the least room between two resources side by side
GAP_Y = 16.0  # ... and one above the other


def _settle(px: list[float], py: list[float], wide: list[float]) -> None:
    """The force layout spaces resources as if they were round, but they are wide, low pills:
    squash it vertically, then push apart whatever overlaps (along the axis that needs the least
    moving), so a group stays compact and readable."""
    n = len(px)
    for i in range(n):
        py[i] *= 0.5
    for _ in range(60):
        moved = False
        for i in range(n):
            for j in range(i + 1, n):
                dx, dy = px[j] - px[i], py[j] - py[i]
                over_x = (wide[i] + wide[j]) / 2 + GAP_X - abs(dx)
                over_y = NODE_H + GAP_Y - abs(dy)
                if over_x <= 0 or over_y <= 0:
                    continue
                moved = True
                if over_y <= over_x:  # cheaper to move apart vertically
                    push = over_y / 2 * (1 if dy > 0 or (dy == 0 and j > i) else -1)
                    py[i] -= push
                    py[j] += push
                else:
                    push = over_x / 2 * (1 if dx > 0 or (dx == 0 and j > i) else -1)
                    px[i] -= push
                    px[j] += push
        if not moved:
            break


def _grid(members: Sequence[int], widths: Mapping[int, float] | None = None) -> dict[int, tuple[float, float]]:
    widths = widths or {}
    columns = max(1, math.ceil(math.sqrt(len(members) * 1.2)))
    cell_w = max(widths.get(m, NODE_W) for m in members) + 16  # every cell as wide as the widest name
    cell_h = NODE_H + 14
    return {
        m: ((cell_w - 16) / 2 + (i % columns) * cell_w, NODE_H / 2 + (i // columns) * cell_h)
        for i, m in enumerate(members)
    }


def _extent(
    positions: Mapping[int, tuple[float, float]], widths: Mapping[int, float] | None = None
) -> tuple[float, float]:
    widths = widths or {}
    return (
        max(x + widths.get(m, NODE_W) / 2 for m, (x, _) in positions.items()),
        max(y for _, y in positions.values()) + NODE_H / 2,
    )


def _shelve(boxes: Sequence[tuple[float, float]], gap: float) -> tuple[list[tuple[float, float]], float, float]:
    """Put boxes (width, height) in rows, left to right, a new row when one gets too wide: their
    top-left corners and the size of the whole."""
    if not boxes:
        return [], 0.0, 0.0
    area = sum(w * h for w, h in boxes)
    limit = max(max(w for w, _ in boxes), math.sqrt(area) * 1.5)
    spots: list[tuple[float, float]] = []
    x = y = row = width = 0.0
    for w, h in boxes:
        if x > 0 and x + w > limit:
            x, y, row = 0.0, y + row + gap, 0.0
        spots.append((x, y))
        x += w + gap
        row = max(row, h)
        width = max(width, x - gap)
    return spots, width, y + row


# ---------------------------------------------------------------------- tags
def _tag_tree(tags: Sequence[GraphTag]) -> tuple[list[GraphTag], dict[int, list[GraphTag]], dict[int, int]]:
    """The tags as a tree: every tag in tree order (a tag, then its sub-tags, by name), the
    children of each, and each one's depth. A tag whose parent is unknown is a top tag; a loop in
    damaged data is cut where it closes."""
    by_id = {t.id: t for t in tags}
    children: dict[int, list[GraphTag]] = {}
    roots: list[GraphTag] = []
    for t in tags:
        if t.parent is None or t.parent not in by_id or t.parent == t.id:
            roots.append(t)
        else:
            children.setdefault(t.parent, []).append(t)

    def key(t: GraphTag) -> tuple[str, int]:
        return (t.name.casefold(), t.id)

    roots.sort(key=key)
    for kids in children.values():
        kids.sort(key=key)
    depth: dict[int, int] = {}
    order: list[GraphTag] = []

    def walk(t: GraphTag, d: int) -> None:
        if t.id in depth:
            return
        depth[t.id] = d
        order.append(t)
        for child in children.get(t.id, []):
            walk(child, d + 1)

    for root in roots:
        walk(root, 0)
    for t in sorted(tags, key=key):  # only in a loop: never reached from a top tag
        if t.id not in depth:
            walk(t, 0)
    return order, children, depth


# --------------------------------------------------------------------- build
@dataclass
class _Block:
    """A laid-out region before it has its place: its size, and where everything in it goes,
    relative to its own top-left corner."""

    width: float
    height: float
    nodes: dict[int, tuple[float, float]]
    regions: list[tuple[int, float, float, float, float]]  # (tag, x, y, w, h); itself first


def build_graph(
    resources: Sequence[GraphResource],
    links: Iterable[tuple[int, int]],
    tags: Sequence[GraphTag] = (),
) -> KnowledgeGraph:
    """The whole picture: every resource in the region of its tag, regions nested like the tags."""
    by_id = {r.id: r for r in resources}
    widths = {r.id: node_width(r.name) for r in resources}
    _, edges = find_clusters(by_id, links)
    degree: dict[int, int] = {}
    for edge in edges.values():
        degree[edge.a] = degree.get(edge.a, 0) + 1
        degree[edge.b] = degree.get(edge.b, 0) + 1

    order, children, depth = _tag_tree(tags)
    tag_by_id = {t.id: t for t in order}
    top_of: dict[int, int] = {}
    for t in order:  # tree order: a parent is always seen before its children
        top_of[t.id] = top_of[t.parent] if depth[t.id] > 0 and t.parent in top_of else t.id
    tops = [t.id for t in order if depth[t.id] == 0]
    color_of = {  # a family shares its top tag's colour: the one it was given, else its position
        tag_id: (tag_by_id[top_of[tag_id]].color if tag_by_id[top_of[tag_id]].color is not None
                 else tops.index(top_of[tag_id]))
        for tag_id in tag_by_id
    }

    # every resource's region: its most specific own tag (the first by name between equals)
    home: dict[int, int] = {}
    for r in resources:
        mine = [t for t in r.own if t in tag_by_id]
        home[r.id] = (min(mine, key=lambda t: (-depth[t], tag_by_id[t].name.casefold(), t))
                      if mine else UNTAGGED)
    direct: dict[int, list[int]] = {}
    for r in sorted(resources, key=lambda r: (r.name.casefold(), r.id)):
        direct.setdefault(home[r.id], []).append(r.id)

    # how many resources each region holds, its sub-regions included
    size: dict[int, int] = {}
    for t in reversed(order):
        size[t.id] = len(direct.get(t.id, [])) + sum(size.get(c.id, 0) for c in children.get(t.id, []))

    def own_blocks(members: list[int]) -> list[tuple[float, float, dict[int, tuple[float, float]]]]:
        """The resources of one region itself: a block per linked group, and one grid of the rest."""
        inside = set(members)
        own_links = [(e.a, e.b) for e in edges.values() if e.a in inside and e.b in inside]
        groups, _ = find_clusters(members, own_links)
        blocks = []
        for group in groups:
            if len(group) > 1:
                group_set = set(group)
                positions = layout_cluster(group, [k for k in own_links if k[0] in group_set], widths)
                blocks.append((*_extent(positions, widths), positions))
        loose = sorted((g[0] for g in groups if len(g) == 1), key=lambda i: (by_id[i].name.casefold(), i))
        if loose:
            positions = _grid(loose, widths)
            blocks.append((*_extent(positions, widths), positions))
        return blocks

    def block_of(tag: int) -> _Block:
        parts: list[tuple[float, float, object]] = list(own_blocks(direct.get(tag, [])))
        kids = [c for c in children.get(tag, []) if size.get(c.id, 0) > 0]
        for child in sorted(kids, key=lambda c: (-size[c.id], c.name.casefold())):
            inner = block_of(child.id)
            parts.append((inner.width, inner.height, inner))
        spots, w, h = _shelve([(pw, ph) for pw, ph, _ in parts], GROUP_GAP)
        ox, oy = REGION_PADDING, REGION_PADDING + REGION_HEADER
        width, height = w + 2 * REGION_PADDING, h + 2 * REGION_PADDING + REGION_HEADER
        block = _Block(width, height, {}, [(tag, 0.0, 0.0, width, height)])
        for (px, py), (_, _, part) in zip(spots, parts):
            if isinstance(part, _Block):
                for node, (nx, ny) in part.nodes.items():
                    block.nodes[node] = (ox + px + nx, oy + py + ny)
                for t, rx, ry, rw, rh in part.regions:
                    block.regions.append((t, ox + px + rx, oy + py + ry, rw, rh))
            else:
                for node, (nx, ny) in part.items():  # type: ignore[union-attr]
                    block.nodes[node] = (ox + px + nx, oy + py + ny)
        return block

    top_blocks = [block_of(t) for t in sorted(tops, key=lambda t: (-size[t], tag_by_id[t].name.casefold()))
                  if size[t] > 0]
    if direct.get(UNTAGGED):
        top_blocks.append(block_of(UNTAGGED))
    spots, width, height = _shelve([(b.width, b.height) for b in top_blocks], REGION_GAP)

    nodes: list[GraphNode] = []
    regions: list[Region] = []
    for (bx, by), block in zip(spots, top_blocks):
        for t, rx, ry, rw, rh in block.regions:
            if t == UNTAGGED:
                regions.append(Region(UNTAGGED, "Untagged", 0, -1, len(direct[UNTAGGED]),
                                      bx + rx, by + ry, rw, rh))
            else:
                regions.append(Region(t, tag_by_id[t].name, depth[t], color_of[t], size[t],
                                      bx + rx, by + ry, rw, rh))
        for node, (nx, ny) in block.nodes.items():
            r = by_id[node]
            nodes.append(GraphNode(
                node, r.name, r.kind, r.missing, tuple(sorted(r.tags, key=str.casefold)), home[node],
                color_of.get(home[node], -1), degree.get(node, 0), bx + nx, by + ny,
                node_label(r.name), widths[node],
            ))

    # the legend counts every resource that has a tag (or one below it), wherever it is drawn
    tagged: dict[int, int] = {}
    for r in resources:
        reached: set[int] = set()
        for t in r.own:
            while t in tag_by_id and t not in reached:
                reached.add(t)
                if depth[t] == 0:
                    break
                t = tag_by_id[t].parent  # type: ignore[assignment]
        for t in reached:
            tagged[t] = tagged.get(t, 0) + 1

    def path(t: GraphTag) -> str:
        names = [t.name]
        seen = {t.id}
        while depth[t.id] > 0 and t.parent in tag_by_id and t.parent not in seen:
            t = tag_by_id[t.parent]
            seen.add(t.id)
            names.append(t.name)
        return " › ".join(reversed(names))

    areas = tuple(Area(t.id, t.name, path(t), depth[t.id], color_of[t.id], tagged.get(t.id, 0)) for t in order)
    return KnowledgeGraph(
        tuple(sorted(nodes, key=lambda n: n.id)),
        tuple(edges[k] for k in sorted(edges)),
        tuple(regions),
        areas,
        width,
        height,
    )
