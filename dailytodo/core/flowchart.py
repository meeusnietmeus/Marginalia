"""Flowcharts: reading and writing the file a flowchart resource points at. No Qt, no storage.

A flowchart lives in a ``.canvas`` file in the JSON Canvas format (https://jsoncanvas.org, the
open format Obsidian's canvases use), so it can also be opened there, and an AI can be asked to
write one (``AI_PROMPT``). What this app uses of it:

* text nodes. The first line of ``text`` is the node's title (a leading ``#`` is dropped), the rest
  its body, which only shows on hover. File and link nodes become a node titled with their file or
  address; group nodes are left out.
* edges between nodes, with an optional ``label``, sides and arrow ends.
* one extra field on a node: ``page``, a page of the document the flowchart is attached to.

Reading is forgiving, because a hand- or AI-written file is often incomplete: ``title`` / ``body``
may be given instead of ``text``, edges may say ``from`` / ``to``, ids may be missing, and nodes
without a position are laid out left to right in the order of the arrows.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field

FILE_SUFFIX = ".canvas"

NODE_WIDTH = 220  # a node's width when the file doesn't give one
NODE_HEIGHT = 60
COLUMN_GAP = 120  # between the columns of an automatic layout
ROW_GAP = 60

SIDES = ("top", "right", "bottom", "left")
# JSON Canvas colour presets: 1 red, 2 orange, 3 yellow, 4 green, 5 cyan, 6 purple; or "#rrggbb"
PRESET_COLORS = ("1", "2", "3", "4", "5", "6")


class FlowchartError(ValueError):
    """The text is not a flowchart (not JSON, or not shaped like a canvas)."""


@dataclass(frozen=True, slots=True)
class FlowNode:
    id: str
    title: str
    body: str = ""
    x: float = 0
    y: float = 0
    width: float = NODE_WIDTH
    height: float = NODE_HEIGHT
    color: str = ""  # "" (none), a preset "1".."6" or "#rrggbb"
    page: int = 0  # a page of the attached document; 0: none


@dataclass(frozen=True, slots=True)
class FlowEdge:
    id: str
    source: str  # node ids
    target: str
    from_side: str = ""  # one of SIDES, or "": whichever side faces the other node
    to_side: str = ""
    label: str = ""
    from_arrow: bool = False
    to_arrow: bool = True
    color: str = ""


@dataclass(frozen=True, slots=True)
class Flowchart:
    nodes: list[FlowNode] = field(default_factory=list)
    edges: list[FlowEdge] = field(default_factory=list)

    # ---- the plain dicts QML works with ----
    def to_view(self) -> dict:
        return {
            "nodes": [
                {"id": n.id, "title": n.title, "body": n.body, "x": n.x, "y": n.y,
                 "width": n.width, "height": n.height, "color": n.color, "page": n.page}
                for n in self.nodes
            ],
            "edges": [
                {"id": e.id, "from": e.source, "to": e.target, "fromSide": e.from_side,
                 "toSide": e.to_side, "label": e.label, "fromArrow": e.from_arrow,
                 "toArrow": e.to_arrow, "color": e.color}
                for e in self.edges
            ],
        }


# ------------------------------------------------------------------ reading
def _text(value) -> str:
    return value.strip() if isinstance(value, str) else ""


def _number(value, default: float | None) -> float | None:
    if isinstance(value, bool):
        return default
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return default
    return default


def _color(value) -> str:
    if isinstance(value, int) and not isinstance(value, bool):
        value = str(value)
    value = _text(value)
    if value in PRESET_COLORS:
        return value
    if len(value) == 7 and value.startswith("#"):
        try:
            int(value[1:], 16)
            return value.lower()
        except ValueError:
            pass
    return ""


def split_text(text: str) -> tuple[str, str]:
    """A text node's ``text`` as (title, body): the first non-empty line without its heading
    marks, and everything after it."""
    lines = text.strip().splitlines()
    if not lines:
        return "", ""
    title = lines[0].strip().lstrip("#").strip()
    return title, "\n".join(lines[1:]).strip()


def join_text(title: str, body: str) -> str:
    """The other way round: the title as a heading, then the body."""
    title, body = title.strip(), body.strip()
    head = f"# {title}" if title else ""
    if not body:
        return head
    return f"{head}\n\n{body}" if head else body


def _node_title(raw: dict) -> tuple[str, str]:
    kind = _text(raw.get("type")) or "text"
    if "title" in raw or "body" in raw:  # the friendlier form
        return _text(raw.get("title")), _text(raw.get("body"))
    if kind == "file":
        path = _text(raw.get("file"))
        return path.replace("\\", "/").rsplit("/", 1)[-1], path
    if kind == "link":
        url = _text(raw.get("url"))
        return url, ""
    return split_text(raw.get("text") if isinstance(raw.get("text"), str) else "")


def parse_flowchart(text: str) -> Flowchart:
    """Read a ``.canvas`` file's text. An empty file is an empty flowchart."""
    if not text.strip():
        return Flowchart()
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise FlowchartError(f"not valid JSON (line {exc.lineno}: {exc.msg})") from exc
    if isinstance(data, list):  # just the nodes
        data = {"nodes": data}
    if not isinstance(data, dict):
        raise FlowchartError("expected an object with \"nodes\" and \"edges\"")
    raw_nodes = data.get("nodes") or []
    raw_edges = data.get("edges") or []
    if not isinstance(raw_nodes, list) or not isinstance(raw_edges, list):
        raise FlowchartError("\"nodes\" and \"edges\" must be lists")

    nodes: list[FlowNode] = []
    unplaced: set[str] = set()
    taken: set[str] = set()
    for index, raw in enumerate(raw_nodes):
        if not isinstance(raw, dict) or _text(raw.get("type")) == "group":
            continue
        node_id = _text(str(raw["id"])) if raw.get("id") not in (None, "") else ""
        if not node_id or node_id in taken:
            node_id = _free_id("n", index, taken)
        taken.add(node_id)
        title, body = _node_title(raw)
        x, y = _number(raw.get("x"), None), _number(raw.get("y"), None)
        if x is None or y is None:
            unplaced.add(node_id)
        page = _number(raw.get("page"), 0) or 0
        nodes.append(
            FlowNode(
                node_id,
                title or "Untitled",
                body,
                x or 0,
                y or 0,
                max(80.0, _number(raw.get("width"), NODE_WIDTH) or NODE_WIDTH),
                max(30.0, _number(raw.get("height"), NODE_HEIGHT) or NODE_HEIGHT),
                _color(raw.get("color")),
                max(0, int(page)),
            )
        )

    edges: list[FlowEdge] = []
    edge_ids: set[str] = set()
    for index, raw in enumerate(raw_edges):
        if not isinstance(raw, dict):
            continue
        source = _text(str(raw.get("fromNode", raw.get("from", ""))))
        target = _text(str(raw.get("toNode", raw.get("to", ""))))
        if source not in taken or target not in taken or source == target:
            continue  # an arrow to a node that isn't there: dropped
        edge_id = _text(str(raw["id"])) if raw.get("id") not in (None, "") else ""
        if not edge_id or edge_id in edge_ids:
            edge_id = _free_id("e", index, edge_ids)
        edge_ids.add(edge_id)
        from_side = _text(raw.get("fromSide"))
        to_side = _text(raw.get("toSide"))
        edges.append(
            FlowEdge(
                edge_id,
                source,
                target,
                from_side if from_side in SIDES else "",
                to_side if to_side in SIDES else "",
                _text(raw.get("label")),
                _text(raw.get("fromEnd")) == "arrow",
                _text(raw.get("toEnd")) != "none",
                _color(raw.get("color")),
            )
        )

    if unplaced:
        nodes = _place(nodes, edges, unplaced)
    return Flowchart(nodes, edges)


def _free_id(prefix: str, index: int, taken: set[str]) -> str:
    n = index + 1
    while f"{prefix}{n}" in taken:
        n += 1
    return f"{prefix}{n}"


def _ranks(ids: list[str], edges: list[FlowEdge]) -> dict[str, int]:
    """Each node's column: the length of the longest chain of arrows leading to it. Arrows that
    close a loop are ignored, so a cycle doesn't push its nodes ever further right."""
    following: dict[str, list[str]] = {i: [] for i in ids}
    for e in edges:
        if e.source in following and e.target in following:
            following[e.source].append(e.target)
    order: list[str] = []  # depth-first finishing order, reversed = a topological order
    state: dict[str, int] = {}  # 1: being visited, 2: done
    back: set[tuple[str, str]] = set()
    # start from the nodes nothing points at, so a loop back to the start is the arrow ignored
    pointed_at = {child for children in following.values() for child in children}
    for start in [i for i in ids if i not in pointed_at] + ids:
        if start in state:
            continue
        stack = [(start, iter(following[start]))]
        state[start] = 1
        while stack:
            node, children = stack[-1]
            child = next(children, None)
            if child is None:
                state[node] = 2
                order.append(node)
                stack.pop()
            elif state.get(child) == 1:
                back.add((node, child))
            elif child not in state:
                state[child] = 1
                stack.append((child, iter(following[child])))
    rank = {i: 0 for i in ids}
    for node in reversed(order):
        for child in following[node]:
            if (node, child) not in back:
                rank[child] = max(rank[child], rank[node] + 1)
    return rank


def _place(nodes: list[FlowNode], edges: list[FlowEdge], unplaced: set[str]) -> list[FlowNode]:
    """Give the nodes without a position one: columns by the arrows between them (left to right),
    each column centred on the same line; to the right of the nodes that do have a position."""
    ids = [n.id for n in nodes if n.id in unplaced]
    rank = _ranks(ids, edges)
    by_id = {n.id: n for n in nodes}
    columns: dict[int, list[str]] = {}
    for node_id in ids:
        columns.setdefault(rank[node_id], []).append(node_id)
    placed = [n for n in nodes if n.id not in unplaced]
    left = max((n.x + n.width for n in placed), default=-COLUMN_GAP) + COLUMN_GAP
    top = min((n.y for n in placed), default=0)
    width = max(by_id[i].width for i in ids)
    spots: dict[str, tuple[float, float]] = {}
    tallest = max(
        sum(by_id[i].height for i in column) + ROW_GAP * (len(column) - 1)
        for column in columns.values()
    )
    for column_index in sorted(columns):
        column = columns[column_index]
        height = sum(by_id[i].height for i in column) + ROW_GAP * (len(column) - 1)
        y = top + (tallest - height) / 2
        for node_id in column:
            spots[node_id] = (left + column_index * (width + COLUMN_GAP), y)
            y += by_id[node_id].height + ROW_GAP
    result = []
    for n in nodes:
        if n.id in spots:
            x, y = spots[n.id]
            n = FlowNode(n.id, n.title, n.body, x, y, n.width, n.height, n.color, n.page)
        result.append(n)
    return result


def flowchart_from_view(data: dict) -> Flowchart:
    """What QML hands over (``Flowchart.to_view``'s shape) back into a flowchart. Goes through the
    same forgiving reader as a file, so bad values from the view can't end up in the file."""
    nodes = [
        {"id": n.get("id"), "title": n.get("title", ""), "body": n.get("body", ""),
         "x": n.get("x"), "y": n.get("y"), "width": n.get("width"), "height": n.get("height"),
         "color": n.get("color"), "page": n.get("page")}
        for n in data.get("nodes") or [] if isinstance(n, dict)
    ]
    edges = [
        {"id": e.get("id"), "fromNode": e.get("from"), "toNode": e.get("to"),
         "fromSide": e.get("fromSide"), "toSide": e.get("toSide"), "label": e.get("label"),
         "fromEnd": "arrow" if e.get("fromArrow") else "none",
         "toEnd": "none" if e.get("toArrow") is False else "arrow", "color": e.get("color")}
        for e in data.get("edges") or [] if isinstance(e, dict)
    ]
    return parse_flowchart(json.dumps({"nodes": nodes, "edges": edges}))


# ------------------------------------------------------------------ writing
def _round(value: float) -> int | float:
    return int(round(value))  # JSON Canvas positions are integers


def dump_flowchart(chart: Flowchart) -> str:
    """The ``.canvas`` file's text: standard JSON Canvas, plus ``page`` on nodes that have one."""
    nodes = []
    for n in chart.nodes:
        node = {"id": n.id, "type": "text", "text": join_text(n.title, n.body),
                "x": _round(n.x), "y": _round(n.y),
                "width": _round(n.width), "height": _round(n.height)}
        if n.color:
            node["color"] = n.color
        if n.page > 0:
            node["page"] = n.page
        nodes.append(node)
    edges = []
    for e in chart.edges:
        edge = {"id": e.id, "fromNode": e.source, "toNode": e.target}
        if e.from_side:
            edge["fromSide"] = e.from_side
        if e.to_side:
            edge["toSide"] = e.to_side
        if e.from_arrow:
            edge["fromEnd"] = "arrow"
        if not e.to_arrow:
            edge["toEnd"] = "none"
        if e.color:
            edge["color"] = e.color
        if e.label:
            edge["label"] = e.label
        edges.append(edge)
    return json.dumps({"nodes": nodes, "edges": edges}, indent=2, ensure_ascii=False) + "\n"


# ------------------------------------------------------------------ for an AI
AI_PROMPT = """\
Make a flowchart of the talking points of the document below, and answer with only a JSON \
object in the JSON Canvas format (https://jsoncanvas.org), nothing before or after it.

Format:
{
  "nodes": [
    {"id": "intro", "type": "text", "text": "# Short title\\n\\nA few sentences that explain it.", "page": 1},
    {"id": "method", "type": "text", "text": "# Another point\\n\\nIts explanation.", "page": 4, "color": "4"}
  ],
  "edges": [
    {"id": "e1", "fromNode": "intro", "toNode": "method", "label": "leads to"}
  ]
}

Rules:
- One node per talking point. The first line of "text" is the title (keep it under 8 words, \
start it with "# "); after an empty line comes the explanation, which is shown when hovering \
over the node. Markdown is allowed in the explanation.
- "page" (optional) is the page or slide number of the document where the point is made.
- "color" (optional) groups related nodes: "1" red, "2" orange, "3" yellow, "4" green, \
"5" cyan, "6" purple.
- An edge is an arrow from one node to the next; "label" (optional) says how they relate, in a \
word or two.
- Leave out "x", "y", "width" and "height": the nodes are laid out automatically, from left to \
right in the direction of the arrows.
- Ids are short and unique; every "fromNode" and "toNode" is the id of a node.
"""
