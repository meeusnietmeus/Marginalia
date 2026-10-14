import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Effects
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// A flowchart resource in its own tab: nodes (a title, and a body that shows on hover) joined by
// arrows, and free-floating notes (always shown in full, on a lighter card), on a dotted grid. The
// chart lives in its .canvas file (JSON Canvas, see core/flowchart.py); every change is written
// back to it a moment later.
//   View  drag with the middle button to move around, scroll to zoom, hover a node to read its
//         body; the button under a node with arrows going out folds away what they lead to
//         (right-click it to show one level at a time)
// An arrow can also be shown as a list item: its end then sits in a list under its start, stacked
// and joined by a bracket line (like the cases of a switch), laid out by itself.
//   Edit  the same, and: double-click the grid for a new node, drag a node to move it, drag from
//         one of the dots on its sides to another node for an arrow (or to empty space for a new
//         node), drag on the grid (or Ctrl+click) to select several and move, level or delete them
//         together, click a node or arrow to change it on the right; Del removes, Ctrl+Z undoes
//   top left      the name, what is in it, and the document it is attached to
//   top right     View / Edit, and the AI prompt / paste / file menu
//   bottom left   fit / zoom out / zoom / zoom in (and undo / redo while editing)
Item {
    id: view

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    // Set by the tab that hosts this page.
    property string title
    property string uri
    property int resourceId: -1
    property int startPage: 0
    function goToPage(page) {}               // the tab interface (a PDF's tab goes to a page)
    function openBox(kind, opts) {}

    onResourceIdChanged: if (resourceId >= 0) Qt.callLater(load)
    Component.onDestruction: save()

    // ---- the chart ----
    // nid, title, body, nx, ny, nw, nh (world units), tint (a colour key), docPage (0: none),
    // note (a free-floating note), collapsed (what its arrows lead to is hidden)
    ListModel { id: nodeModel }
    property var edges: []                   // { id, from, to, fromSide, toSide, label, fromArrow, toArrow, color }
    property var indexById: ({})
    property int revision: 0                 // bumped on every change: bindings on positions re-read
    property bool loaded: false
    property string loadError: ""
    property bool editing: false
    property bool dirty: false

    // The selected nodes: id -> true. selectedNode is the one the panel on the right edits, when
    // exactly one is selected.
    property var selection: ({})
    readonly property int selectionCount: Object.keys(selection).length
    property string selectedNode: ""
    property string selectedEdge: ""
    property var hidden: ({})                // the nodes folded away under a collapsed one: id -> true
    property string hiddenKey: "{}"
    property string hoverNode: ""
    property bool dragging: false
    // drawing an arrow: from this node to the pointer (viewport coordinates), onto linkTarget
    property string linkFrom: ""
    property real linkX: 0
    property real linkY: 0
    property string linkTarget: ""

    // ---- the document it is attached to ----
    property int attachedTo: -1
    property string attachedName: ""
    property string attachedKind: ""
    function refreshAttachment() {
        const info = controller.resourceInfo(resourceId)
        attachedTo = info.attachedTo !== undefined ? info.attachedTo : -1
        const doc = attachedTo >= 0 ? controller.resourceInfo(attachedTo) : ({})
        attachedName = doc.name || ""
        attachedKind = doc.kind || ""
    }
    Connections {
        target: view.controller
        function onAttachmentsChanged() { view.refreshAttachment() }
        function onResourceViewChanged() { if (view.resourceId >= 0) view.refreshAttachment() }
    }

    // ---- loading and saving ----
    function load() {
        const r = controller.loadFlowchart(resourceId)
        refreshAttachment()
        if (!r.ok) { loadError = r.error; loaded = false; return }
        loadError = ""
        apply(r)
        if (!loaded) {
            loaded = true
            editing = nodeModel.count === 0          // a new chart starts in the editor
            Qt.callLater(fit, false)
        }
    }
    // The file may have been changed elsewhere (by hand, or an AI): read it again when the tab is
    // shown, unless there is something of ours still to write.
    onVisibleChanged: {
        if (!visible) save()
        else if (resourceId >= 0 && loaded && !dirty) load()
    }

    function snapshot() {
        const nodes = []
        for (let i = 0; i < nodeModel.count; i++) {
            const n = nodeModel.get(i)
            nodes.push({ id: n.nid, title: n.title, body: n.body, x: n.nx, y: n.ny, width: n.nw,
                         height: n.nh, color: n.tint, page: n.docPage, note: n.note,
                         collapsed: n.collapsed })
        }
        return { nodes: nodes, edges: edges.map(e => Object.assign({}, e)) }
    }
    function apply(data) {
        nodeModel.clear()
        for (const n of data.nodes)
            nodeModel.append({ nid: n.id, title: n.title, body: n.body || "", nx: n.x, ny: n.y,
                               nw: n.width, nh: n.height, tint: n.color || "", docPage: n.page || 0,
                               note: n.note === true, collapsed: n.collapsed === true })
        edges = data.edges.map(e => ({ id: e.id, from: e.from, to: e.to, fromSide: e.fromSide || "",
                                       toSide: e.toSide || "", label: e.label || "",
                                       fromArrow: e.fromArrow === true, toArrow: e.toArrow !== false,
                                       color: e.color || "", list: e.list === true }))
        reindex()
        if (!edges.some(e => e.id === selectedEdge)) selectedEdge = ""
        touched()
        setSelection(Object.keys(selection))         // what is gone (or folded away) drops out
    }
    function reindex() {
        const map = {}
        for (let i = 0; i < nodeModel.count; i++) map[nodeModel.get(i).nid] = i
        indexById = map
    }
    function nodeOf(id) {
        const i = indexById[id]
        return i === undefined || i >= nodeModel.count ? null : nodeModel.get(i) || null
    }
    function edgeOf(id) { return edges.find(e => e.id === id) || null }

    // something moved or changed: redraw (no save)
    function touched() {
        recomputeHidden()
        layoutLists()
        revision++
        edgeCanvas.requestPaint()
    }

    // ---- folding: a collapsed node hides what its arrows lead to, and on down ----
    function childrenOf(id) { return edges.filter(e => e.from === id).map(e => e.to) }
    function descendants(id) {
        const seen = {}
        const stack = childrenOf(id)
        while (stack.length > 0) {
            const c = stack.pop()
            if (seen[c] || c === id) continue
            seen[c] = true
            for (const next of childrenOf(c)) stack.push(next)
        }
        return Object.keys(seen)
    }
    function recomputeHidden() {
        const h = {}
        for (let i = 0; i < nodeModel.count; i++) {
            const n = nodeModel.get(i)
            if (n.collapsed) for (const d of descendants(n.nid)) h[d] = true
        }
        const key = JSON.stringify(h)
        if (key !== hiddenKey) { hiddenKey = key; hidden = h }
    }
    function toggleCollapsed(id) {
        const n = nodeOf(id)
        if (!n) return
        tapTakenAt = Date.now()
        checkpoint()
        setNode(id, "collapsed", !n.collapsed)       // (saved, in View too: it opens as it was left)
        setSelection(Object.keys(selection))
    }
    property double tapTakenAt: 0            // a button on the grid took this click: the grid ignores it

    // Show one level more: unfold the node, and fold each of its children that has children itself.
    function showNextLevel(id) {
        if (!nodeOf(id)) return
        checkpoint()
        nodeModel.setProperty(indexById[id], "collapsed", false)
        for (const c of childrenOf(id)) {
            const i = indexById[c]
            if (i !== undefined && childrenOf(c).length > 0) nodeModel.setProperty(i, "collapsed", true)
        }
        changed()
        setSelection(Object.keys(selection))
    }
    // unfold everything under a node, all the way down
    function showAllBelow(id) {
        if (!nodeOf(id)) return
        checkpoint()
        for (const d of [id].concat(descendants(id))) nodeModel.setProperty(indexById[d], "collapsed", false)
        changed()
    }
    function foldAllBelow(id) {
        const n = nodeOf(id)
        if (!n || n.collapsed) return
        toggleCollapsed(id)
    }
    function openFoldMenu(id, button) {
        tapTakenAt = Date.now()
        foldMenu.target = id
        // under the button, placed in the page (a popup inside the zoomed chart lands elsewhere)
        const at = button.mapToItem(view, 0, button.height + 6)
        foldMenu.popup(view, at.x, at.y)
    }

    // ---- lists: the ends of "list" edges stacked under their start instead of joined by arrows ----
    readonly property real listLine: 18      // where the bracket line runs, from the parent's left
    readonly property real listIndent: 40    // where the items start
    property var memberOf: ({})              // a list item's id -> its list's node (one list per item)
    property string memberKey: "{}"
    property string reordering: ""           // the list item being dragged to another place in its list
    function listItems(pid) {
        return edges.filter(e => e.list && e.from === pid && memberOf[e.to] === pid && !hidden[e.to])
                    .map(e => e.to)
    }
    // the room under a node before what comes next: more when its fold button sits there
    function gapBelow(id) {
        return childrenOf(id).some(c => !hidden[c]) ? 44 : 12
    }
    function layoutLists() {
        const m = {}
        for (const e of edges) {
            if (e.list && e.from !== e.to && m[e.to] === undefined && indexById[e.from] !== undefined
                    && indexById[e.to] !== undefined)
                m[e.to] = e.from
        }
        const key = JSON.stringify(m)
        if (key !== memberKey) { memberKey = key; memberOf = m }
        const done = {}
        const parents = Object.keys(m).map(c => m[c])
        for (const pid of parents) if (m[pid] === undefined) placeList(pid, done)   // top lists first
        for (const pid of parents) placeList(pid, done)                            // (a loop of lists)
    }
    // Put a node's list items under it, each with its own list under it in turn. Returns the
    // bottom of the node and everything stacked under it.
    function placeList(pid, done) {
        const p = nodeOf(pid)
        if (!p) return 0
        let bottom = p.ny + p.nh
        if (done[pid]) return bottom
        done[pid] = true
        let y = bottom + gapBelow(pid)
        for (const id of listItems(pid)) {
            const i = indexById[id]
            const item = nodeModel.get(i)
            let end = y + item.nh
            if (id !== reordering) {           // the one being dragged keeps its place free
                if (item.nx !== p.nx + listIndent) nodeModel.setProperty(i, "nx", p.nx + listIndent)
                if (item.ny !== y) nodeModel.setProperty(i, "ny", y)
                end = placeList(id, done)
            }
            bottom = Math.max(bottom, end)
            y = end + gapBelow(id)
        }
        return bottom
    }
    // A list item was dropped: it goes where its middle is among the others.
    function finishReorder() {
        const id = reordering
        reordering = ""
        const pid = memberOf[id]
        const me = nodeOf(id)
        if (pid === undefined || !me) return
        const inList = e => e.list && e.from === pid && memberOf[e.to] === pid
        const others = edges.filter(e => inList(e) && e.to !== id)
        const middle = me.ny + me.nh / 2
        let at = others.length
        for (let k = 0; k < others.length; k++) {
            const o = nodeOf(others[k].to)
            if (o && middle < o.ny + o.nh / 2) { at = k; break }
        }
        const order = others.slice(0, at).concat([edges.find(e => inList(e) && e.to === id)], others.slice(at))
        let k = 0
        edges = edges.map(e => inList(e) ? order[k++] : e)   // the same places, in the new order
    }
    function setEdgeList(id, on) {
        const e = edgeOf(id)
        if (!e || e.list === on) return
        checkpoint()
        setEdge(id, "list", on)
    }
    // all the edges out of a node: list items, or arrows
    function setChildrenList(id, on) {
        if (!edges.some(e => e.from === id && e.list !== on)) return
        checkpoint()
        edges = edges.map(e => e.from === id ? Object.assign({}, e, { list: on }) : e)
        changed()
    }
    // the chart changed: redraw, and write it a moment later
    function changed() {
        dirty = true
        saveTimer.restart()
        touched()
    }
    function save() {
        saveTimer.stop()
        if (!dirty || resourceId < 0) return
        dirty = false
        controller.saveFlowchart(resourceId, snapshot())
    }
    Timer { id: saveTimer; interval: 600; onTriggered: view.save() }

    // ---- undo / redo: whole snapshots, the chart is small ----
    property var undoStack: []
    property var redoStack: []
    property int historyRevision: 0
    function checkpoint() {
        undoStack.push(JSON.stringify(snapshot()))
        if (undoStack.length > 100) undoStack.shift()
        redoStack = []
        historyRevision++
    }
    function undo() {
        if (undoStack.length === 0) return
        redoStack.push(JSON.stringify(snapshot()))
        apply(JSON.parse(undoStack.pop()))
        historyRevision++
        changed()
    }
    function redo() {
        if (redoStack.length === 0) return
        undoStack.push(JSON.stringify(snapshot()))
        apply(JSON.parse(redoStack.pop()))
        historyRevision++
        changed()
    }

    // ---- changing the chart ----
    readonly property real grid: Theme.canvasDotSpacing / 2  // nodes snap to half the dot spacing
    function snap(v) { return Math.round(v / grid) * grid }
    function newId(prefix) {
        let id
        do { id = prefix + Math.random().toString(36).slice(2, 8) }
        while (indexById[id] !== undefined || edges.some(e => e.id === id))
        return id
    }
    function addNodeAt(wx, wy, from, asNote) {
        checkpoint()
        const id = newId("n")
        const w = asNote ? 240 : 220
        nodeModel.append({ nid: id, title: "", body: "", nx: snap(wx - w / 2), ny: snap(wy - 26),
                           nw: w, nh: 52, tint: "", docPage: 0, note: asNote === true, collapsed: false })
        reindex()
        // from a node whose children are a list, a new one joins the list
        const out = from ? edges.filter(e => e.from === from) : []
        const asListItem = out.length > 0 && out.every(e => e.list)
        if (from) edges = edges.concat([{ id: newId("e"), from: from, to: id, fromSide: "", toSide: "",
                                          label: "", fromArrow: false, toArrow: true, color: "",
                                          list: asListItem }])
        selectNode(id)
        changed()
        // a note is mostly its text; a node is mostly its title
        const field = asNote ? bodyField : titleField
        Qt.callLater(() => { field.forceActiveFocus(); field.selectAll() })
    }
    function setNode(id, role, value) {
        const i = indexById[id]
        if (i === undefined) return
        nodeModel.setProperty(i, role, value)
        changed()
    }
    function removeNodes(ids, undoable) {
        const gone = {}
        for (const id of ids) if (indexById[id] !== undefined) gone[id] = true
        const indexes = Object.keys(gone).map(id => indexById[id]).sort((a, b) => b - a)
        if (indexes.length === 0) return
        if (undoable !== false) checkpoint()
        edges = edges.filter(e => !gone[e.from] && !gone[e.to])
        for (const i of indexes) nodeModel.remove(i)
        reindex()
        selection = ({})
        selectedNode = ""
        if (gone[hoverNode]) hoverNode = ""
        changed()
        syncInspector()
    }
    function removeNode(id) { removeNodes([id]) }
    // a note needs a title or a text: one left empty goes when it is no longer selected
    function pruneEmptyNote(id) {
        const n = nodeOf(id)
        if (n && n.note && n.title.trim() === "" && n.body.trim() === "") removeNodes([id], false)
    }
    // Level: put the tops of the selected nodes on one line, the highest one's
    function levelSelection() {
        const ids = Object.keys(selection)
        if (ids.length < 2) return
        checkpoint()
        let top = Infinity
        for (const id of ids) top = Math.min(top, nodeOf(id).ny)
        for (const id of ids) nodeModel.setProperty(indexById[id], "ny", top)
        changed()
    }
    // where the given nodes are now, to move them all by the same amount
    function positionsOf(ids) {
        const starts = {}
        for (const id of ids) {
            const n = nodeOf(id)
            if (n) starts[id] = { x: n.nx, y: n.ny }
        }
        return starts
    }
    function moveNodes(starts, dx, dy) {
        for (const id in starts) {
            const i = indexById[id]
            if (i === undefined) continue
            nodeModel.setProperty(i, "nx", snap(starts[id].x + dx))
            nodeModel.setProperty(i, "ny", snap(starts[id].y + dy))
        }
        touched()
    }
    function addEdge(from, to) {
        if (from === to || edges.some(e => e.from === from && e.to === to)) return
        checkpoint()
        const id = newId("e")
        edges = edges.concat([{ id: id, from: from, to: to, fromSide: "", toSide: "", label: "",
                                fromArrow: false, toArrow: true, color: "", list: false }])
        changed()
    }
    function setEdge(id, key, value) {
        edges = edges.map(e => {
            if (e.id !== id) return e
            const copy = Object.assign({}, e)
            copy[key] = value
            return copy
        })
        changed()
    }
    function reverseEdge(id) {
        checkpoint()
        edges = edges.map(e => e.id !== id ? e : Object.assign({}, e, {
            from: e.to, to: e.from, fromSide: e.toSide, toSide: e.fromSide,
            fromArrow: e.toArrow, toArrow: e.fromArrow }))
        changed()
    }
    function removeEdge(id) {
        checkpoint()
        edges = edges.filter(e => e.id !== id)
        selectedEdge = ""
        changed()
    }
    function removeSelected() {
        if (selectionCount > 0) removeNodes(Object.keys(selection))
        else if (selectedEdge !== "") removeEdge(selectedEdge)
    }
    // Select these nodes (and no arrow). Ids that are gone or folded away are left out.
    function setSelection(ids) {
        const previous = selectedNode
        const map = {}
        for (const id of ids) if (indexById[id] !== undefined && !hidden[id]) map[id] = true
        const keys = Object.keys(map)
        selection = map
        selectedNode = keys.length === 1 ? keys[0] : ""
        if (keys.length > 0) selectedEdge = ""
        if (previous !== "" && previous !== selectedNode) pruneEmptyNote(previous)
        syncInspector()
        edgeCanvas.requestPaint()
    }
    function selectNode(id) { setSelection([id]) }
    function toggleSelected(id) {
        const keys = Object.keys(selection)
        const at = keys.indexOf(id)
        if (at >= 0) keys.splice(at, 1)
        else keys.push(id)
        setSelection(keys)
    }
    function selectEdge(id) {
        setSelection([])
        selectedEdge = id
        syncInspector()
        edgeCanvas.requestPaint()
    }
    function clearSelection() {
        setSelection([])
        selectedEdge = ""
        syncInspector()
        edgeCanvas.requestPaint()
    }
    onEditingChanged: {
        if (!editing) { clearSelection(); save(); return }
        // the panel on the right comes in: make room when the chart would be under it
        for (let i = 0; i < nodeModel.count; i++) {
            const n = nodeModel.get(i)
            if ((n.nx + n.nw) * zoom + panX > viewWidth) { Qt.callLater(fit, true); return }
        }
    }

    function pasteFromClipboard() {
        const r = controller.pasteFlowchart()
        if (!r.ok) return
        checkpoint()
        apply(r)
        changed()
        editing = true
        fit(true)
    }

    // ---- geometry (world units): where an arrow leaves and enters its nodes ----
    function opposite(side) {
        return side === "left" ? "right" : side === "right" ? "left" : side === "top" ? "bottom" : "top"
    }
    function facing(a, b) {                  // the side of a that faces b: across the wider gap
        const dx = (b.nx + b.nw / 2) - (a.nx + a.nw / 2)
        const dy = (b.ny + b.nh / 2) - (a.ny + a.nh / 2)
        const across = Math.abs(dx) - (a.nw + b.nw) / 2
        const down = Math.abs(dy) - (a.nh + b.nh) / 2
        return across >= down ? (dx >= 0 ? "right" : "left") : (dy >= 0 ? "bottom" : "top")
    }
    function anchor(n, side) {
        switch (side) {
        case "left": return { x: n.nx, y: n.ny + n.nh / 2 }
        case "right": return { x: n.nx + n.nw, y: n.ny + n.nh / 2 }
        case "top": return { x: n.nx + n.nw / 2, y: n.ny }
        default: return { x: n.nx + n.nw / 2, y: n.ny + n.nh }
        }
    }
    function outward(side) {
        return side === "left" ? { x: -1, y: 0 } : side === "right" ? { x: 1, y: 0 }
             : side === "top" ? { x: 0, y: -1 } : { x: 0, y: 1 }
    }
    // a soft S-curve: out of one side, into the other
    function curve(p0, s0, p3, s1) {
        const dist = Math.sqrt((p3.x - p0.x) * (p3.x - p0.x) + (p3.y - p0.y) * (p3.y - p0.y))
        const k = Math.max(28, Math.min(160, dist * 0.42))
        const o0 = outward(s0), o1 = outward(s1)
        return { p0: p0, c1: { x: p0.x + o0.x * k, y: p0.y + o0.y * k },
                 c2: { x: p3.x + o1.x * k, y: p3.y + o1.y * k }, p3: p3 }
    }
    function route(e) {
        const a = nodeOf(e.from), b = nodeOf(e.to)
        if (!a || !b) return null
        const s0 = e.fromSide || facing(a, b)
        const s1 = e.toSide || (e.fromSide ? facing(b, a) : opposite(s0))
        return curve(anchor(a, s0), s0, anchor(b, s1), s1)
    }
    function bezier(r, t) {
        const u = 1 - t
        return { x: u * u * u * r.p0.x + 3 * u * u * t * r.c1.x + 3 * u * t * t * r.c2.x + t * t * t * r.p3.x,
                 y: u * u * u * r.p0.y + 3 * u * u * t * r.c1.y + 3 * u * t * t * r.c2.y + t * t * t * r.p3.y }
    }

    // ---- the view: screen = world * zoom + pan ----
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    readonly property real minZoom: 0.3
    readonly property real maxZoom: 2
    readonly property real viewLeft: 0
    readonly property real viewTop: 86
    readonly property real viewWidth: Math.max(200, width - (editing ? inspector.width + 32 : 0))
    readonly property real viewHeight: Math.max(120, height - viewTop - 70)

    function toWorld(sx, sy) { return { x: (sx - panX) / zoom, y: (sy - panY) / zoom } }
    // the topmost node under a point of the viewport (nodesOnly: not a note, for an arrow's end)
    function nodeAt(sx, sy, except, nodesOnly) {
        const p = toWorld(sx, sy)
        for (let i = nodeModel.count - 1; i >= 0; i--) {
            const n = nodeModel.get(i)
            if (n.nid === except || hidden[n.nid] || (nodesOnly && n.note)) continue
            if (p.x >= n.nx && p.x <= n.nx + n.nw && p.y >= n.ny && p.y <= n.ny + n.nh) return n.nid
        }
        return ""
    }
    // the nodes a rectangle of the viewport touches
    function nodesIn(x0, y0, x1, y1) {
        const a = toWorld(Math.min(x0, x1), Math.min(y0, y1))
        const b = toWorld(Math.max(x0, x1), Math.max(y0, y1))
        const ids = []
        for (let i = 0; i < nodeModel.count; i++) {
            const n = nodeModel.get(i)
            if (hidden[n.nid]) continue
            if (n.nx <= b.x && n.nx + n.nw >= a.x && n.ny <= b.y && n.ny + n.nh >= a.y) ids.push(n.nid)
        }
        return ids
    }
    function edgeAt(sx, sy) {                 // the arrow within a few pixels of a point
        let best = "", bestDist = 8
        for (const e of edges) {
            if (hidden[e.from] || hidden[e.to]) continue
            if (e.list && memberOf[e.to] === e.from) {      // a list item: its tick
                const p = nodeOf(e.from), n = nodeOf(e.to)
                if (!p || !n) continue
                const y = (n.ny + n.nh / 2) * zoom + panY
                const xa = (p.nx + listLine) * zoom + panX, xb = n.nx * zoom + panX
                if (sx >= xa - 4 && sx <= xb + 4 && Math.abs(sy - y) < bestDist) { bestDist = Math.abs(sy - y); best = e.id }
                continue
            }
            const r = route(e)
            if (!r) continue
            for (let i = 0; i <= 32; i++) {
                const p = bezier(r, i / 32)
                const d = Math.hypot(p.x * zoom + panX - sx, p.y * zoom + panY - sy)
                if (d < bestDist) { bestDist = d; best = e.id }
            }
        }
        return best
    }
    function fit(animated) {
        if (nodeModel.count === 0 || width <= 0) {
            const v0 = { zoom: 1, panX: viewWidth / 2, panY: viewTop + viewHeight / 2 }
            if (animated) moveTo(v0)
            else { zoom = v0.zoom; panX = v0.panX; panY = v0.panY }
            return
        }
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
        for (let i = 0; i < nodeModel.count; i++) {
            const n = nodeModel.get(i)
            if (hidden[n.nid]) continue
            x0 = Math.min(x0, n.nx); y0 = Math.min(y0, n.ny)
            x1 = Math.max(x1, n.nx + n.nw); y1 = Math.max(y1, n.ny + n.nh)
        }
        const margin = 60
        const z = Math.max(minZoom, Math.min(1.2, (viewWidth - 2 * margin) / Math.max(1, x1 - x0),
                                             (viewHeight - margin) / Math.max(1, y1 - y0)))
        const v = { zoom: z, panX: viewLeft + (viewWidth - (x1 - x0) * z) / 2 - x0 * z,
                    panY: viewTop + (viewHeight - (y1 - y0) * z) / 2 - y0 * z }
        if (animated) moveTo(v)
        else { zoom = v.zoom; panX = v.panX; panY = v.panY }
    }
    function moveTo(v) {
        flight.stop()
        zoomTo.to = v.zoom; panXTo.to = v.panX; panYTo.to = v.panY
        flight.start()
    }
    function zoomAt(point, factor) {
        flight.stop()
        const next = Math.max(minZoom, Math.min(maxZoom, zoom * factor))
        const real = next / zoom
        panX = point.x - (point.x - panX) * real
        panY = point.y - (point.y - panY) * real
        zoom = next
    }
    readonly property point viewCentre: Qt.point(viewLeft + viewWidth / 2, viewTop + viewHeight / 2)
    ParallelAnimation {
        id: flight
        NumberAnimation { id: zoomTo; target: view; property: "zoom"; duration: 400; easing.type: Easing.OutCubic }
        NumberAnimation { id: panXTo; target: view; property: "panX"; duration: 400; easing.type: Easing.OutCubic }
        NumberAnimation { id: panYTo; target: view; property: "panY"; duration: 400; easing.type: Easing.OutCubic }
    }
    onZoomChanged: { dots.requestPaint(); edgeCanvas.requestPaint() }
    onPanXChanged: { dots.requestPaint(); edgeCanvas.requestPaint() }
    onPanYChanged: { dots.requestPaint(); edgeCanvas.requestPaint() }

    // ---- drawing an arrow from one of a node's dots ----
    function beginLink(id, centroid) {
        const p = viewport.mapFromItem(null, centroid.scenePressPosition.x, centroid.scenePressPosition.y)
        dragStartX = p.x
        dragStartY = p.y
        view.forceActiveFocus()              // out of the fields: Del and Ctrl+Z act on the chart
        linkFrom = id
        linkTarget = ""
        moveLink(centroid.scenePosition)
    }
    function moveLink(scenePoint) {
        const p = viewport.mapFromItem(null, scenePoint.x, scenePoint.y)
        linkX = p.x
        linkY = p.y
        linkTarget = nodeAt(p.x, p.y, linkFrom, true)
        edgeCanvas.requestPaint()
    }
    function finishLink() {
        const from = linkFrom, to = linkTarget
        linkFrom = ""
        linkTarget = ""
        if (from === "") return
        if (to !== "") addEdge(from, to)
        else if (Math.hypot(linkX - dragStartX, linkY - dragStartY) > 30) {  // dropped on the grid: a new node there
            const p = toWorld(linkX, linkY)
            addNodeAt(p.x + 110, p.y, from)
        }
        edgeCanvas.requestPaint()
    }
    property real dragStartX: 0
    property real dragStartY: 0

    // ---- keys ----
    Shortcut {
        sequences: [StandardKey.Delete, "Backspace"]
        enabled: view.visible && view.editing
        onActivated: view.removeSelected()
    }
    Shortcut {
        sequences: [StandardKey.Undo]
        enabled: view.visible && view.editing
        onActivated: view.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Y"]
        enabled: view.visible && view.editing
        onActivated: view.redo()
    }
    Shortcut {
        sequence: "Escape"
        enabled: view.visible && (view.selectionCount > 0 || view.selectedEdge !== "")
        onActivated: view.clearSelection()
    }

    // ------------------------------------------------------------------ the grid and the chart
    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        visible: view.loaded
        onWidthChanged: if (view.loaded && view.nodeModelEmpty) Qt.callLater(view.fit, false)

        // the middle button moves the view around
        DragHandler {
            property real startX: 0
            property real startY: 0
            target: null
            acceptedButtons: Qt.MiddleButton
            cursorShape: Qt.ClosedHandCursor
            onActiveChanged: if (active) { flight.stop(); startX = view.panX; startY = view.panY }
            onTranslationChanged: if (active) {
                view.panX = startX + translation.x
                view.panY = startY + translation.y
            }
        }
        WheelHandler {
            onWheel: (event) => view.zoomAt(point.position, event.angleDelta.y > 0 ? 1.1 : 1 / 1.1)
        }
        // Edit: the left button draws a box on the grid; what it touches is selected (Ctrl: added)
        DragHandler {
            id: boxSelect
            enabled: view.editing
            target: null
            acceptedButtons: Qt.LeftButton
            property var base: []
            property real x0: 0
            property real y0: 0
            property real x1: 0
            property real y1: 0
            onActiveChanged: if (active) {
                view.forceActiveFocus()
                base = (centroid.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) ? Object.keys(view.selection) : []
                x0 = x1 = centroid.pressPosition.x
                y0 = y1 = centroid.pressPosition.y
            }
            onCentroidChanged: if (active) {
                x1 = centroid.position.x
                y1 = centroid.position.y
                view.setSelection(base.concat(view.nodesIn(x0, y0, x1, y1)))
            }
        }
        Rectangle {
            visible: boxSelect.active
            z: 5
            x: Math.min(boxSelect.x0, boxSelect.x1)
            y: Math.min(boxSelect.y0, boxSelect.y1)
            width: Math.abs(boxSelect.x1 - boxSelect.x0)
            height: Math.abs(boxSelect.y1 - boxSelect.y0)
            radius: 4
            color: Qt.alpha(Theme.ringDone, 0.08)
            border.color: Qt.alpha(Theme.ringDone, 0.6)
        }
        // a click on the grid picks an arrow (or nothing); a double-click there adds a node
        TapHandler {
            onTapped: (eventPoint) => {
                const p = eventPoint.position
                if (view.nodeAt(p.x, p.y) !== "") return         // the node handles its own clicks
                // a button on the grid (a fold button) may have taken this click: look after it
                Qt.callLater(() => {
                    if (Date.now() - view.tapTakenAt < 400) return
                    const edge = view.edgeAt(p.x, p.y)
                    if (edge !== "") view.selectEdge(edge)
                    else view.clearSelection()
                })
            }
            onDoubleTapped: (eventPoint) => {
                const p = eventPoint.position
                if (!view.editing || view.nodeAt(p.x, p.y) !== "" || view.edgeAt(p.x, p.y) !== ""
                        || Date.now() - view.tapTakenAt < 400) return
                const w = view.toWorld(p.x, p.y)
                view.addNodeAt(w.x, w.y)
            }
        }

        // a very light dotted grid that moves and zooms with the chart
        Canvas {
            id: dots
            anchors.fill: parent
            renderTarget: Canvas.Image
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = Theme.canvasDot
                let step = Theme.canvasDotSpacing * view.zoom
                while (step < 14) step *= 2                       // zoomed out: fewer dots
                const size = Math.max(1.4, 2 * Math.min(1, view.zoom))
                const ox = ((view.panX % step) + step) % step
                const oy = ((view.panY % step) + step) % step
                for (let y = oy; y < height; y += step) {
                    for (let x = ox; x < width; x += step)
                        ctx.fillRect(x - size / 2, y - size / 2, size, size)
                }
            }
        }

        // the arrows (under the nodes)
        Canvas {
            id: edgeCanvas
            anchors.fill: parent
            renderTarget: Canvas.Image

            function head(ctx, tip, from, size) {
                const angle = Math.atan2(tip.y - from.y, tip.x - from.x)
                ctx.beginPath()
                ctx.moveTo(tip.x, tip.y)
                ctx.lineTo(tip.x - size * Math.cos(angle - 0.45), tip.y - size * Math.sin(angle - 0.45))
                ctx.lineTo(tip.x - size * Math.cos(angle + 0.45), tip.y - size * Math.sin(angle + 0.45))
                ctx.closePath()
                ctx.fill()
            }
            function screen(p) { return { x: p.x * view.zoom + view.panX, y: p.y * view.zoom + view.panY } }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const z = view.zoom
                const size = Math.max(5, 9 * Math.min(1.2, z + 0.15))
                const focus = view.hoverNode !== "" ? view.hoverNode : view.selectedNode
                const labels = []
                const lists = {}                  // node id -> its list's edges
                for (const e of view.edges) {
                    if (view.hidden[e.from] || view.hidden[e.to]) continue
                    if (e.list && view.memberOf[e.to] === e.from) {
                        (lists[e.from] = lists[e.from] || []).push(e)
                        continue
                    }
                    const r = view.route(e)
                    if (!r) continue
                    const selected = e.id === view.selectedEdge
                    const lit = focus !== "" && (e.from === focus || e.to === focus)
                    const tint = e.color !== "" ? Theme.flowchartColor(e.color) : Theme.text
                    ctx.strokeStyle = selected ? Theme.ringDone
                                    : Qt.alpha(tint, lit ? 0.85 : e.color !== "" ? 0.7 : 0.34)
                    ctx.fillStyle = ctx.strokeStyle
                    ctx.lineWidth = selected ? 2.6 : lit ? 2 : 1.5
                    const p0 = screen(r.p0), c1 = screen(r.c1), c2 = screen(r.c2), p3 = screen(r.p3)
                    ctx.beginPath()
                    ctx.moveTo(p0.x, p0.y)
                    ctx.bezierCurveTo(c1.x, c1.y, c2.x, c2.y, p3.x, p3.y)
                    ctx.stroke()
                    if (e.toArrow) head(ctx, p3, c2, size)
                    if (e.fromArrow) head(ctx, p0, c1, size)
                    if (e.label !== "" && z > 0.45) labels.push({ at: screen(view.bezier(r, 0.5)), text: e.label,
                                                                  selected: selected, lit: lit })
                }
                // the lists: a line down from the node's left, with a tick to each item, the last
                // one round the corner
                for (const pid in lists) {
                    const p = view.nodeOf(pid)
                    if (!p) continue
                    const items = lists[pid].map(e => ({ e: e, n: view.nodeOf(e.to) })).filter(it => it.n)
                    items.sort((a, b) => a.n.ny - b.n.ny)
                    if (items.length === 0) continue
                    const lx = p.nx + view.listLine
                    const last = items[items.length - 1]
                    const lastMid = last.n.ny + last.n.nh / 2
                    const corner = Math.min(10, (lastMid - p.ny - p.nh) / 2)
                    const lit = focus === pid
                    const line = (on, selected) => {
                        ctx.strokeStyle = selected ? Theme.ringDone : Qt.alpha(Theme.text, on ? 0.85 : 0.34)
                        ctx.lineWidth = selected ? 2.6 : on ? 2 : 1.5
                    }
                    line(lit, false)
                    ctx.beginPath()
                    let a = screen({ x: lx, y: p.ny + p.nh })
                    ctx.moveTo(a.x, a.y)
                    a = screen({ x: lx, y: lastMid - corner })
                    ctx.lineTo(a.x, a.y)
                    const c = screen({ x: lx, y: lastMid }), b = screen({ x: lx + corner, y: lastMid })
                    ctx.quadraticCurveTo(c.x, c.y, b.x, b.y)
                    a = screen({ x: last.n.nx, y: lastMid })
                    ctx.lineTo(a.x, a.y)
                    ctx.stroke()
                    for (const it of items) {
                        const selected = it.e.id === view.selectedEdge
                        const on = lit || focus === it.n.nid
                        if (it === last && !selected && !on) continue      // drawn with the line
                        line(on, selected)
                        const mid = it.n.ny + it.n.nh / 2
                        const from = screen({ x: lx + (it === last ? corner : 0), y: mid })
                        const to = screen({ x: it.n.nx, y: mid })
                        ctx.beginPath()
                        ctx.moveTo(from.x, from.y)
                        ctx.lineTo(to.x, to.y)
                        ctx.stroke()
                    }
                }
                // the labels on top of every line, on a small pill of the background
                const px = Math.round(Math.max(10, 12 * Math.min(1.2, z)))
                ctx.font = px + "px sans-serif"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                for (const l of labels) {
                    const w = ctx.measureText(l.text).width + 14
                    const h = px + 9
                    ctx.fillStyle = Theme.window
                    ctx.strokeStyle = l.selected ? Theme.ringDone : Theme.hairlineStrong
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.roundedRect(l.at.x - w / 2, l.at.y - h / 2, w, h, h / 2, h / 2)
                    ctx.fill()
                    ctx.stroke()
                    ctx.fillStyle = l.selected || l.lit ? Theme.text : Theme.textMuted
                    ctx.fillText(l.text, l.at.x, l.at.y + 0.5)
                }
                // the arrow being drawn
                if (view.linkFrom !== "") {
                    const a = view.nodeOf(view.linkFrom)
                    if (a) {
                        const b = view.linkTarget !== "" ? view.nodeOf(view.linkTarget) : null
                        const pointer = view.toWorld(view.linkX, view.linkY)
                        const target = b || { nx: pointer.x, ny: pointer.y, nw: 0, nh: 0 }
                        const s0 = view.facing(a, target)
                        const s1 = b ? view.opposite(s0) : view.opposite(view.facing(target, a))
                        const r = view.curve(view.anchor(a, s0), s0, b ? view.anchor(b, s1) : pointer, s1)
                        ctx.strokeStyle = Theme.ringDone
                        ctx.fillStyle = Theme.ringDone
                        ctx.lineWidth = 2
                        const p0 = screen(r.p0), c1 = screen(r.c1), c2 = screen(r.c2), p3 = screen(r.p3)
                        ctx.beginPath()
                        ctx.moveTo(p0.x, p0.y)
                        ctx.bezierCurveTo(c1.x, c1.y, c2.x, c2.y, p3.x, p3.y)
                        ctx.stroke()
                        head(ctx, p3, c2, size)
                    }
                }
            }
        }

        // the nodes, in world units: this item does the moving and zooming
        Item {
            id: world
            x: view.panX
            y: view.panY
            scale: view.zoom
            transformOrigin: Item.TopLeft

            Repeater {
                model: nodeModel
                delegate: Item {
                    id: node
                    required property int index
                    required property string nid
                    required property string title
                    required property string body
                    required property real nx
                    required property real ny
                    required property real nw
                    required property real nh
                    required property string tint
                    required property int docPage
                    required property bool note
                    required property bool collapsed

                    readonly property bool selected: view.selection[nid] === true
                    readonly property bool hasChildren: { view.revision; return view.edges.some(e => e.from === nid) }
                    readonly property bool lifted: moving.active && !moving.linking   // being moved
                    // which of the dots (see below) a point of the node is on, or ""
                    function dotAt(px, py) {
                        const spots = { top: [width / 2, 0], right: [width, height / 2],
                                        bottom: [width / 2, height], left: [0, height / 2] }
                        for (const side in spots) {
                            if (Math.hypot(px - spots[side][0], py - spots[side][1]) <= 12) return side
                        }
                        return ""
                    }
                    readonly property bool hovered: nodeHover.hovered
                    readonly property bool near: nearHover.hovered || hovered || selected || view.linkFrom === nid
                    readonly property bool target: view.linkTarget === nid
                    readonly property color accent: tint !== "" ? Theme.flowchartColor(tint) : Theme.textFaint

                    visible: view.hidden[nid] !== true
                    x: nx
                    y: ny
                    width: nw
                    height: Math.max(note ? 40 : 52, content.implicitHeight + 26)
                    z: selected || lifted ? 2 : 1
                    onHeightChanged: if (Math.abs(height - nh) > 0.5) {
                        nodeModel.setProperty(index, "nh", height)
                        view.touched()
                    }

                    // the dots to draw an arrow from show when the pointer comes near
                    Item {
                        id: nearZone
                        anchors.fill: parent
                        anchors.margins: -16
                        anchors.bottomMargin: -40            // down to the fold button
                        HoverHandler { id: nearHover }
                    }

                    // folded: the cards of what is folded away peek out from under it
                    Repeater {
                        model: node.collapsed && node.hasChildren ? [2, 1] : []
                        Rectangle {
                            required property int modelData
                            x: modelData * 5
                            y: modelData * 5
                            width: node.width
                            height: node.height
                            radius: face.radius
                            color: Qt.darker(Theme.panel, 1.05 + modelData * 0.05)
                            border.color: Theme.hairline
                        }
                    }

                    RectangularShadow {
                        anchors.fill: face
                        radius: face.radius
                        offset.y: node.hovered || node.lifted ? 7 : 3
                        blur: node.hovered || node.lifted ? 18 : 9
                        spread: -1
                        color: Theme.shadow
                        Behavior on offset.y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    RectangularShadow {                  // a soft green glow: selected, or about to be joined
                        visible: node.selected || node.target
                        anchors.fill: face
                        radius: face.radius
                        blur: 16
                        spread: 2
                        color: Qt.alpha(Theme.ringDone, 0.32)
                    }
                    // a node is a raised dark card; a note a lighter one, like paper, with smaller corners
                    readonly property color faceTop: note ? Theme.flowNoteRaised : Theme.panelRaised
                    readonly property color faceBottom: note ? Theme.flowNote : Theme.panel
                    Rectangle {
                        id: face
                        anchors.fill: parent
                        radius: node.note ? 6 : 12
                        gradient: Gradient {
                            GradientStop { position: 0; color: node.tint !== "" ? Qt.tint(node.faceTop, Qt.alpha(node.accent, node.note ? 0.18 : 0.10)) : node.faceTop }
                            GradientStop { position: 1; color: node.tint !== "" ? Qt.tint(node.faceBottom, Qt.alpha(node.accent, node.note ? 0.14 : 0.06)) : node.faceBottom }
                        }
                        border.width: node.selected || node.target ? 1.5 : 1
                        border.color: node.selected || node.target ? Theme.focusRing
                                    : node.tint !== "" ? Qt.alpha(node.accent, node.hovered ? 0.75 : 0.45)
                                    : node.hovered ? Theme.hairlineStrong : Theme.hairline
                        Rectangle {                      // light along the top edge
                            x: parent.radius
                            y: 1
                            width: parent.width - 2 * x
                            height: 1
                            color: Theme.surfaceHighlight
                        }
                    }

                    Column {
                        id: content
                        x: 14
                        y: 13
                        width: parent.width - 28
                        spacing: 6

                        Row {
                            visible: !node.note || node.title !== ""     // a note's title is optional
                            width: parent.width
                            spacing: 8
                            Rectangle {
                                id: swatch
                                visible: node.tint !== ""
                                y: titleText.lineCount > 0 ? (titleText.font.pixelSize * 1.3 - height) / 2 : 0
                                width: 8
                                height: 8
                                radius: 4
                                color: node.accent
                            }
                            Text {
                                id: titleText
                                width: parent.width - (swatch.visible ? swatch.width + parent.spacing : 0)
                                text: node.title !== "" ? node.title : "Untitled"
                                wrapMode: Text.Wrap
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.italic: node.title === ""
                                lineHeight: 1.1
                                color: node.title !== "" ? Theme.text : Theme.textFaint
                            }
                        }
                        // a note always shows its text
                        Text {
                            visible: node.note && node.body !== ""
                            width: parent.width
                            text: node.note ? node.body : ""
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap
                            font.pixelSize: 13
                            lineHeight: 1.15
                            color: Qt.alpha(Theme.text, 0.88)
                        }
                        // more to read (on hover), and the page of the document it is about
                        Row {
                            visible: (!node.note && node.body !== "") || node.docPage > 0
                            spacing: 8
                            IconImage {
                                visible: !node.note && node.body !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                source: Theme.iconDocument
                                sourceSize: Qt.size(12, 12)
                                color: node.hovered ? Theme.textMuted : Theme.textFaint
                            }
                            PillLabel {
                                id: pagePill
                                visible: node.docPage > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "p. " + node.docPage
                                tint: view.attachedTo >= 0 && pageHover.hovered ? Theme.ringDone : Theme.text
                                textColor: view.attachedTo >= 0 && pageHover.hovered ? Theme.text : Theme.textMuted
                                HoverHandler {
                                    id: pageHover
                                    cursorShape: view.attachedTo >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                }
                                ClickHandler {
                                    enabled: view.attachedTo >= 0
                                    onTapped: view.controller.openResourceAtPage(view.attachedTo, node.docPage)
                                }
                            }
                        }
                    }

                    HoverHandler {
                        id: nodeHover
                        cursorShape: view.editing ? (node.lifted ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                                  : Qt.ArrowCursor
                        onHoveredChanged: {
                            if (hovered) view.hoverNode = node.nid
                            else if (view.hoverNode === node.nid) view.hoverNode = ""
                            edgeCanvas.requestPaint()
                        }
                    }
                    // click: select it; Ctrl/Shift+click (Edit): add it to the selection, or take it out
                    ClickHandler {
                        id: nodeClick
                        onTapped: {
                            if (view.editing && (nodeClick.point.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
                                view.toggleSelected(node.nid)
                            else
                                view.selectNode(node.nid)
                        }
                        onDoubleTapped: if (view.editing) {
                            view.selectNode(node.nid)
                            const field = node.note ? bodyField : titleField
                            field.forceActiveFocus()
                            field.selectAll()
                        }
                    }
                    // Edit: drag to move it, with whatever else is selected (it snaps to the grid). A
                    // drag that starts on one of the dots draws an arrow instead (the dots' own
                    // handlers only get the half of a dot that sticks out of the node).
                    DragHandler {
                        id: moving
                        enabled: view.editing
                        target: null
                        // wins from the grid's box selection
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                        property var starts: ({})
                        property bool linking: false
                        onActiveChanged: {
                            if (active) {
                                const press = node.mapFromItem(null, centroid.scenePressPosition.x,
                                                               centroid.scenePressPosition.y)
                                linking = !node.note && node.dotAt(press.x, press.y) !== ""
                                if (linking) {
                                    view.beginLink(node.nid, centroid)
                                    return
                                }
                                view.forceActiveFocus()
                                view.checkpoint()
                                if (!node.selected) view.selectNode(node.nid)
                                // a list item dragged on its own goes to another place in its list
                                if (view.memberOf[node.nid] !== undefined && view.selectionCount <= 1)
                                    view.reordering = node.nid
                                starts = view.positionsOf(view.reordering !== "" ? [node.nid]
                                                                                 : Object.keys(view.selection))
                                view.dragging = true
                            } else if (linking) {
                                linking = false
                                view.finishLink()
                            } else {
                                view.dragging = false
                                if (view.reordering !== "") view.finishReorder()
                                view.changed()
                            }
                        }
                        onCentroidChanged: if (active && linking) {
                            view.moveLink(centroid.scenePosition)
                        } else if (active) {
                            const dx = (centroid.scenePosition.x - centroid.scenePressPosition.x) / view.zoom
                            const dy = (centroid.scenePosition.y - centroid.scenePressPosition.y) / view.zoom
                            view.moveNodes(starts, dx, dy)
                        }
                    }

                    // Edit: a dot on each side; drag from one to another node for an arrow
                    Repeater {
                        model: ["top", "right", "bottom", "left"]
                        Item {
                            id: handle
                            required property string modelData
                            readonly property bool live: linking.active || (moving.linking && moving.active)
                            visible: view.editing && !node.note && !node.lifted && (node.near || live)
                            width: 22
                            height: 22
                            x: modelData === "left" ? -width / 2 : modelData === "right" ? node.width - width / 2
                                                                  : node.width / 2 - width / 2
                            y: modelData === "top" ? -height / 2 : modelData === "bottom" ? node.height - height / 2
                                                                 : node.height / 2 - height / 2
                            z: 3
                            Rectangle {
                                anchors.centerIn: parent
                                width: handleHover.hovered || handle.live ? 12 : 9
                                height: width
                                radius: width / 2
                                color: handleHover.hovered || handle.live ? Theme.ringDone : Theme.panelRaised
                                border.width: 1.5
                                border.color: Theme.ringDone
                                Behavior on width { NumberAnimation { duration: 90 } }
                            }
                            HoverHandler { id: handleHover; cursorShape: Qt.CrossCursor }
                            DragHandler {
                                id: linking
                                target: null
                                grabPermissions: PointerHandler.CanTakeOverFromAnything
                                onActiveChanged: {
                                    if (active) {
                                        view.beginLink(node.nid, centroid)
                                    } else {
                                        view.finishLink()
                                    }
                                }
                                onCentroidChanged: if (active) view.moveLink(centroid.scenePosition)
                            }
                        }
                    }

                    // Under a node with arrows going out: fold away what they lead to (and show it
                    // again). It stays while folded, with how many are hidden.
                    Item {
                        id: fold
                        readonly property int count: { view.revision; return node.hasChildren ? view.descendants(node.nid).length : 0 }
                        visible: node.hasChildren && !node.lifted && (node.near || node.collapsed || foldHover.hovered)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: node.height + 14
                        z: 3
                        width: foldRow.implicitWidth + 18
                        height: 22
                        RectangularShadow {
                            anchors.fill: foldFace
                            radius: foldFace.radius
                            offset.y: 2
                            blur: 6
                            color: Theme.shadow
                        }
                        Rectangle {
                            id: foldFace
                            anchors.fill: parent
                            radius: height / 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: foldHover.hovered ? Qt.lighter(Theme.panelRaised, 1.15) : Theme.panelRaised }
                                GradientStop { position: 1; color: Theme.panel }
                            }
                            border.color: node.collapsed ? Qt.alpha(Theme.ringDone, 0.6)
                                        : foldHover.hovered ? Theme.hairlineStrong : Theme.hairline
                        }
                        Row {
                            id: foldRow
                            anchors.centerIn: parent
                            spacing: 4
                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                source: node.collapsed ? Theme.iconChevronDown : Theme.iconChevronUp
                                sourceSize: Qt.size(12, 12)
                                color: foldHover.hovered || node.collapsed ? Theme.text : Theme.textMuted
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: node.collapsed ? "+" + fold.count : fold.count
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: foldHover.hovered || node.collapsed ? Theme.text : Theme.textMuted
                            }
                        }
                        HoverHandler { id: foldHover; cursorShape: Qt.PointingHandCursor }
                        ClickHandler { onTapped: view.toggleCollapsed(node.nid) }
                        ClickHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: view.openFoldMenu(node.nid, fold)
                        }
                    }
                }
            }
        }

        // The body of the node under the pointer, after a moment: below it (or above it when there
        // is no room), never in the way of the pointer.
        Item {
            id: peek
            // a copy: a row object of the model is not kept up to date in a binding
            readonly property var n: {
                view.revision
                const m = view.peekNode !== "" ? view.nodeOf(view.peekNode) : null
                return m && !m.note && !view.hidden[m.nid]
                       ? { nx: m.nx, ny: m.ny, nw: m.nw, nh: m.nh, title: m.title, body: m.body, tint: m.tint }
                       : null
            }
            readonly property bool wanted: !!n && n.body !== "" && !view.dragging && view.linkFrom === ""
            readonly property real nodeLeft: n ? n.nx * view.zoom + view.panX : 0
            readonly property real nodeTop: n ? n.ny * view.zoom + view.panY : 0
            readonly property real nodeBottom: n ? (n.ny + n.nh) * view.zoom + view.panY : 0
            width: Math.min(380, Math.max(240, n ? n.nw * view.zoom : 0))
            height: peekColumn.implicitHeight + 28
            x: Math.max(12, Math.min(viewport.width - width - 12, nodeLeft))
            y: nodeBottom + 10 + height < viewport.height - 12 ? nodeBottom + 10
                                                               : Math.max(12, nodeTop - height - 10)
            z: 10
            opacity: wanted ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Surface { anchors.fill: parent; elevation: 2; radius: 14 }
            Rectangle {                              // the node's colour along the left edge
                visible: !!peek.n && peek.n.tint !== ""
                x: 0; y: 14
                width: 3
                height: parent.height - 28
                radius: 1.5
                color: peek.n ? Theme.flowchartColor(peek.n.tint) : "transparent"
            }
            Column {
                id: peekColumn
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 6
                Text {
                    width: parent.width
                    text: peek.n ? (peek.n.title || "Untitled") : ""
                    wrapMode: Text.Wrap
                    font.family: Theme.serifFont
                    font.pixelSize: 17
                    color: Theme.text
                }
                Text {
                    width: parent.width
                    text: peek.n ? peek.n.body : ""
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    lineHeight: 1.15
                    color: Theme.textMuted
                }
            }
        }
    }
    // the body shows a moment after the pointer comes to rest on a node, and goes at once
    property string peekNode: ""
    onHoverNodeChanged: {
        if (hoverNode === "") { peekNode = ""; peekTimer.stop() }
        else peekTimer.restart()
    }
    Timer { id: peekTimer; interval: 220; onTriggered: view.peekNode = view.hoverNode }
    readonly property bool nodeModelEmpty: nodeModel.count === 0

    // ------------------------------------------------------------------ top left: the title
    Rectangle {                                  // a soft fade, so the chart never makes it hard to read
        width: view.viewWidth
        height: 110
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.window, 0.9) }
            GradientStop { position: 0.55; color: Qt.alpha(Theme.window, 0.55) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Column {
        x: 22
        y: 14
        spacing: 6
        width: view.viewWidth - 44 - topBar.width
        SectionTitle {
            width: Math.min(implicitWidth, parent.width)
            text: view.title
        }
        Row {
            spacing: 12
            CapsLabel {
                anchors.verticalCenter: parent.verticalCenter
                readonly property int notes: {
                    view.revision
                    let n = 0
                    for (let i = 0; i < nodeModel.count; i++) if (nodeModel.get(i).note) n++
                    return n
                }
                readonly property int nodes: nodeModel.count - notes
                text: nodes + (nodes === 1 ? " node" : " nodes")
                      + (notes > 0 ? "  ·  " + notes + (notes === 1 ? " note" : " notes") : "") + "  ·  "
                      + view.edges.length + (view.edges.length === 1 ? " arrow" : " arrows")
                color: Theme.textFaint
            }
            // the document it is about: click to open it
            Item {
                id: docChip
                visible: view.attachedTo >= 0
                anchors.verticalCenter: parent.verticalCenter
                width: docRow.implicitWidth + 16
                height: 24
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: docHover.hovered ? Qt.alpha(Theme.text, 0.08) : Qt.alpha(Theme.text, 0.04)
                    border.color: Theme.hairline
                }
                Row {
                    id: docRow
                    anchors.centerIn: parent
                    spacing: 6
                    KindTile {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        kind: view.attachedKind
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: view.attachedName
                        font.pixelSize: 12
                        color: Theme.text
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 260)
                    }
                }
                HoverHandler { id: docHover; cursorShape: Qt.PointingHandCursor }
                ClickHandler { onTapped: view.controller.openResourceById(view.attachedTo) }
                AppToolTip { text: "Open the document this flowchart is about"; shown: docHover.hovered }
            }
            // Edit: attach it to a document, or to another one
            AppButton {
                id: attachButton
                visible: view.editing
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                implicitHeight: 24
                text: view.attachedTo >= 0 ? "Change" : "Attach to a document..."
                font.pixelSize: 11
                textColor: Theme.textMuted
                onClicked: {
                    attachMenu.choices = view.controller.documentChoices()
                    attachMenu.popup(attachButton, 0, attachButton.height + 6)
                }
            }
        }
    }
    // right-click on a fold button
    AppMenu {
        id: foldMenu
        property string target: ""
        AppMenuItem {
            text: "Show the next level"
            iconSource: Theme.iconChevronDown
            onTriggered: view.showNextLevel(foldMenu.target)
        }
        AppMenuItem {
            text: "Show everything below"
            iconSource: Theme.iconExpand
            onTriggered: view.showAllBelow(foldMenu.target)
        }
        AppMenuItem {
            text: "Fold everything below"
            iconSource: Theme.iconChevronUp
            onTriggered: view.foldAllBelow(foldMenu.target)
        }
    }
    AppMenu {
        id: attachMenu
        property var choices: []
        AppMenuItem {
            visible: view.attachedTo >= 0
            height: visible ? implicitHeight : 0
            text: "Not attached"
            iconSource: Theme.iconClose
            onTriggered: view.controller.setAttachment(view.resourceId, -1)
        }
        Repeater {
            model: attachMenu.choices
            AppMenuItem {
                required property var modelData
                text: modelData.name
                iconSource: Theme.resourceIcon(modelData.kind)
                tint: modelData.id === view.attachedTo ? Theme.ringDone : Theme.text
                onTriggered: view.controller.setAttachment(view.resourceId, modelData.id)
            }
        }
        AppMenuItem {
            visible: attachMenu.choices.length === 0
            height: visible ? implicitHeight : 0
            enabled: false
            text: "No PDFs or presentations in this workspace"
        }
    }

    // ------------------------------------------------------------------ top right: mode and menu
    Row {
        id: topBar
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 10

        CapsLabel {
            anchors.verticalCenter: parent.verticalCenter
            visible: view.editing
            text: view.dirty ? "Saving..." : "Saved"
            color: Theme.textFaint
        }
        Item {
            width: modeSwitch.width
            height: 34
            InputBlocker {}
            SegmentedSwitch {
                id: modeSwitch
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 32
                leftText: "View"
                rightText: "Edit"
                rightActive: view.editing
                onToggledTo: (right) => view.editing = right
            }
        }
        Item {
            width: 34
            height: 34
            InputBlocker {}
            Well { anchors.fill: parent; radius: height / 2 }
            IconButton {
                id: moreButton
                anchors.centerIn: parent
                compact: true
                implicitHeight: 28
                implicitWidth: 28
                iconSource: Theme.iconSparkles
                active: moreMenu.visible
                onClicked: moreMenu.visible ? moreMenu.close() : moreMenu.popup(moreButton, moreButton.width - moreMenu.width, moreButton.height + 8)
                AppToolTip { text: "Make it with AI, and the file"; shown: moreButton.hovered && !moreMenu.visible }
            }
            AppMenu {
                id: moreMenu
                AppMenuItem {
                    text: "Copy the prompt for an AI"
                    iconSource: Theme.iconCopy
                    onTriggered: view.controller.copyFlowchartPrompt()
                }
                AppMenuItem {
                    text: "Replace with the AI's answer (paste)"
                    iconSource: Theme.iconPaste
                    onTriggered: view.pasteFromClipboard()
                }
                AppMenuSeparator {}
                AppMenuItem {
                    text: "Reveal in file explorer"
                    iconSource: Theme.iconFolder
                    onTriggered: view.controller.revealInExplorer(view.uri)
                }
            }
        }
    }

    // ------------------------------------------------------------------ right: what is selected (Edit)
    Item {
        id: inspector
        visible: view.editing && view.loaded
        anchors.right: parent.right
        anchors.top: topBar.bottom
        anchors.margins: 16
        width: 290
        height: Math.min(view.height - topBar.height - 48, inspectorColumn.implicitHeight + 32)

        InputBlocker {}
        Surface { anchors.fill: parent; elevation: 2; radius: 18 }

        ColumnLayout {
            id: inspectorColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // nothing selected: how it works
            SectionTitle {
                visible: view.selectionCount === 0 && view.selectedEdge === ""
                text: "Editing"
                size: 20
            }
            Repeater {
                model: view.selectionCount === 0 && view.selectedEdge === "" ? [
                    ["Double-click the grid", "a new node"],
                    ["Drag a node", "move it"],
                    ["Drag from a green dot", "an arrow to another node, or a new node"],
                    ["Drag on the grid  ·  Ctrl+click", "select several: move, level or delete them together"],
                    ["Click an arrow", "show it as a list item under its node instead"],
                    ["Right-click a fold button", "show one level at a time"],
                    ["Middle-drag  ·  scroll", "move around  ·  zoom"],
                    ["Del  ·  Ctrl+Z", "remove  ·  undo"]
                ] : []
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: modelData[0]
                        font.pixelSize: 13
                        color: Theme.text
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData[1]
                        font.pixelSize: 12
                        color: Theme.textFaint
                        wrapMode: Text.Wrap
                    }
                }
            }

            // ---- several nodes ----
            SectionTitle {
                visible: view.selectionCount > 1
                text: view.selectionCount + " selected"
                size: 20
            }
            CapsLabel {
                visible: view.selectionCount > 1
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Drag one to move them all"
                color: Theme.textFaint
            }
            RowLayout {
                visible: view.selectionCount > 1
                spacing: 8
                AppButton {
                    id: levelButton
                    compact: true
                    raised: true
                    text: "Level"
                    onClicked: view.levelSelection()
                    AppToolTip { text: "Line up their tops with the highest one"; shown: levelButton.hovered }
                }
                AppButton {
                    compact: true
                    text: "Delete " + view.selectionCount
                    textColor: hovered ? Theme.danger : Theme.textMuted
                    onClicked: view.removeSelected()
                }
            }

            // ---- a node or a note ----
            readonly property bool isNote: { view.revision; const n = view.nodeOf(view.selectedNode); return !!n && n.note }
            readonly property var outgoing: { view.revision; return view.edges.filter(e => e.from === view.selectedNode) }
            readonly property bool edgeIsList: { view.revision; const e = view.edgeOf(view.selectedEdge); return !!e && e.list }
            SectionTitle {
                visible: view.selectedNode !== ""
                text: inspectorColumn.isNote ? "Note" : "Node"
                size: 20
            }
            CapsLabel { visible: view.selectedNode !== ""; text: inspectorColumn.isNote ? "Title (optional)" : "Title" }
            AppTextField {
                id: titleField
                visible: view.selectedNode !== ""
                Layout.fillWidth: true
                placeholderText: inspectorColumn.isNote ? "A heading, if it needs one" : "What is the point?"
                onActiveFocusChanged: if (activeFocus) view.checkpointPending = true
                onTextEdited: view.editNode("title", text)
                Keys.onReturnPressed: bodyField.forceActiveFocus()
                Keys.onEnterPressed: bodyField.forceActiveFocus()
            }
            CapsLabel { visible: view.selectedNode !== ""; text: inspectorColumn.isNote ? "Text" : "Shown on hover" }
            NoteTextArea {
                id: bodyField
                visible: view.selectedNode !== ""
                Layout.fillWidth: true
                Layout.maximumHeight: 260
                lines: 4
                autoGrow: true
                placeholderText: inspectorColumn.isNote ? "Write the note (Markdown works)" : "Explain it (Markdown works)"
                onActiveFocusChanged: if (activeFocus) view.checkpointPending = true
                onTextChanged: if (!view.syncing && activeFocus) view.editNode("body", text)
                onCancelled: focus = false
            }
            RowLayout {
                visible: view.selectedNode !== ""
                Layout.fillWidth: true
                spacing: 8
                CapsLabel { text: "Page" }
                AppTextField {
                    id: pageField
                    implicitWidth: 64
                    implicitHeight: 28
                    font.pixelSize: 12
                    horizontalAlignment: TextInput.AlignHCenter
                    leftPadding: 4
                    rightPadding: 4
                    placeholderText: "-"
                    validator: IntValidator { bottom: 0; top: 99999 }
                    inputMethodHints: Qt.ImhDigitsOnly
                    onActiveFocusChanged: if (activeFocus) view.checkpointPending = true
                    onTextEdited: view.editNode("docPage", parseInt(text) || 0)
                }
                Text {
                    Layout.fillWidth: true
                    text: view.attachedTo >= 0 ? "of " + view.attachedName : "of the attached document"
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    color: Theme.textFaint
                }
            }
            RowLayout {
                visible: view.selectedNode !== "" && inspectorColumn.outgoing.length > 0
                spacing: 10
                CapsLabel { text: "Children as" }
                SegmentedSwitch {
                    leftText: "Arrows"
                    rightText: "List"
                    rightActive: inspectorColumn.outgoing.length > 0 && inspectorColumn.outgoing.every(e => e.list)
                    onToggledTo: (right) => view.setChildrenList(view.selectedNode, right)
                }
            }
            CapsLabel { visible: view.selectedNode !== ""; text: "Colour" }
            Row {
                visible: view.selectedNode !== ""
                spacing: 6
                Repeater {
                    model: [""].concat(Theme.flowchartPresets)
                    Item {
                        id: colourChoice
                        required property string modelData
                        readonly property bool current: {
                            view.revision
                            const n = view.nodeOf(view.selectedNode)
                            return !!n && n.tint === modelData
                        }
                        width: 26
                        height: 26
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            radius: 9
                            color: colourChoice.modelData === "" ? "transparent" : Theme.flowchartColor(colourChoice.modelData)
                            border.width: colourChoice.modelData === "" ? 1.5 : 0
                            border.color: Theme.textFaint
                            Rectangle {                  // "none": a slash
                                visible: colourChoice.modelData === ""
                                anchors.centerIn: parent
                                width: 14
                                height: 1.5
                                rotation: -45
                                color: Theme.textFaint
                            }
                        }
                        Rectangle {
                            visible: colourChoice.current
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 1.5
                            border.color: Theme.text
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        ClickHandler {
                            onTapped: {
                                view.checkpoint()
                                view.setNode(view.selectedNode, "tint", colourChoice.modelData)
                            }
                        }
                    }
                }
            }
            AppButton {
                visible: view.selectedNode !== ""
                Layout.topMargin: 4
                compact: true
                text: inspectorColumn.isNote ? "Delete note" : "Delete node"
                textColor: hovered ? Theme.danger : Theme.textMuted
                onClicked: view.removeNode(view.selectedNode)
            }

            // ---- an arrow ----
            SectionTitle {
                visible: view.selectedEdge !== ""
                text: inspectorColumn.edgeIsList ? "List item" : "Arrow"
                size: 20
            }
            CapsLabel {
                visible: view.selectedEdge !== ""
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: {
                    view.revision
                    const e = view.edgeOf(view.selectedEdge)
                    const a = e ? view.nodeOf(e.from) : null, b = e ? view.nodeOf(e.to) : null
                    return a && b ? (a.title || "Untitled") + "  →  " + (b.title || "Untitled") : ""
                }
                color: Theme.textFaint
            }
            RowLayout {
                visible: view.selectedEdge !== ""
                spacing: 10
                CapsLabel { text: "Shown as" }
                SegmentedSwitch {
                    leftText: "Arrow"
                    rightText: "List item"
                    rightActive: inspectorColumn.edgeIsList
                    onToggledTo: (right) => view.setEdgeList(view.selectedEdge, right)
                }
            }
            CapsLabel { visible: view.selectedEdge !== "" && !inspectorColumn.edgeIsList; text: "Label" }
            AppTextField {
                id: labelField
                visible: view.selectedEdge !== "" && !inspectorColumn.edgeIsList
                Layout.fillWidth: true
                placeholderText: "How do they relate? (optional)"
                onActiveFocusChanged: if (activeFocus) view.checkpointPending = true
                onTextEdited: {
                    if (view.checkpointPending) { view.checkpoint(); view.checkpointPending = false }
                    view.setEdge(view.selectedEdge, "label", text)
                }
            }
            RowLayout {
                visible: view.selectedEdge !== ""
                spacing: 8
                AppButton {
                    visible: !inspectorColumn.edgeIsList
                    compact: true
                    raised: true
                    text: "Reverse"
                    onClicked: view.reverseEdge(view.selectedEdge)
                }
                AppButton {
                    compact: true
                    text: inspectorColumn.edgeIsList ? "Take out of the list" : "Delete arrow"
                    textColor: hovered ? Theme.danger : Theme.textMuted
                    onClicked: view.removeEdge(view.selectedEdge)
                }
            }
        }
    }
    // The inspector's fields follow the selection; typing in them changes the chart (one undo step
    // per field visit).
    property bool syncing: false
    property bool checkpointPending: false
    function syncInspector() {
        syncing = true
        const n = nodeOf(selectedNode)
        titleField.text = n ? n.title : ""
        bodyField.text = n ? n.body : ""
        pageField.text = n && n.docPage > 0 ? String(n.docPage) : ""
        const e = edgeOf(selectedEdge)
        labelField.text = e ? e.label : ""
        syncing = false
    }
    function editNode(role, value) {
        if (syncing || selectedNode === "") return
        if (checkpointPending) { checkpoint(); checkpointPending = false }
        setNode(selectedNode, role, value)
    }

    // ------------------------------------------------------------------ bottom left: the view
    Row {
        visible: view.loaded
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 18
        spacing: 12

        Item {
            width: viewTools.width + 8
            height: 36
            InputBlocker {}
            Well { anchors.fill: parent; radius: height / 2 }
            Row {
                id: viewTools
                anchors.centerIn: parent
                spacing: 2
                IconButton {
                    id: fitButton
                    compact: true
                    implicitHeight: 28
                    iconSource: Theme.iconFit
                    onClicked: view.fit(true)
                    AppToolTip { text: "Fit everything"; shown: fitButton.hovered }
                }
                IconButton {
                    compact: true
                    implicitHeight: 28
                    iconSource: Theme.iconZoomOut
                    onClicked: view.zoomAt(view.viewCentre, 1 / 1.2)
                }
                AppButton {
                    id: zoomLabel
                    compact: true
                    implicitHeight: 28
                    implicitWidth: 56
                    text: Math.round(view.zoom * 100) + "%"
                    font.pixelSize: 12
                    textColor: Theme.textMuted
                    onClicked: view.zoomAt(view.viewCentre, 1 / view.zoom)
                    AppToolTip { text: "Back to 100%"; shown: zoomLabel.hovered }
                }
                IconButton {
                    compact: true
                    implicitHeight: 28
                    iconSource: Theme.iconZoomIn
                    onClicked: view.zoomAt(view.viewCentre, 1.2)
                }
            }
        }
        Item {
            visible: view.editing
            width: historyTools.width + 8
            height: 36
            InputBlocker {}
            Well { anchors.fill: parent; radius: height / 2 }
            Row {
                id: historyTools
                anchors.centerIn: parent
                spacing: 2
                IconButton {
                    id: undoButton
                    compact: true
                    implicitHeight: 28
                    iconSource: Theme.iconUndo
                    enabled: { view.historyRevision; return view.undoStack.length > 0 }
                    onClicked: view.undo()
                    AppToolTip { text: "Undo (Ctrl+Z)"; shown: undoButton.hovered }
                }
                IconButton {
                    id: redoButton
                    compact: true
                    implicitHeight: 28
                    iconSource: Theme.iconRedo
                    enabled: { view.historyRevision; return view.redoStack.length > 0 }
                    onClicked: view.redo()
                    AppToolTip { text: "Redo (Ctrl+Shift+Z)"; shown: redoButton.hovered }
                }
            }
        }
    }

    // ------------------------------------------------------------------ bottom centre: a new node or note (Edit)
    Row {
        visible: view.editing && view.loaded
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -(view.width - view.viewWidth) / 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        spacing: 10
        AppButton {
            implicitHeight: 36
            filled: true
            contentItem: Row {
                spacing: 6
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Theme.iconPlus
                    sourceSize: Qt.size(14, 14)
                    color: Theme.accentText
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "New node"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.accentText
                }
            }
            onClicked: {
                const w = view.toWorld(view.viewCentre.x, view.viewCentre.y)
                // a little to the side of the last one, so a row of new nodes doesn't pile up
                const offset = (nodeModel.count % 5) * view.grid * 2
                view.addNodeAt(w.x + offset, w.y + offset)
            }
        }
        // a free-floating note: no arrows, its text always shows
        AppButton {
            implicitHeight: 36
            raised: true
            contentItem: Row {
                spacing: 6
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Theme.iconDocument
                    sourceSize: Qt.size(14, 14)
                    color: Theme.text
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "New note"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.text
                }
            }
            onClicked: {
                const w = view.toWorld(view.viewCentre.x, view.viewCentre.y)
                const offset = (nodeModel.count % 5) * view.grid * 2
                view.addNodeAt(w.x + offset, w.y + offset, "", true)
            }
        }
    }

    // ------------------------------------------------------------------ empty, or unreadable
    Column {
        visible: view.loaded && nodeModel.count === 0
        x: view.viewLeft + (view.viewWidth - width) / 2
        y: view.viewTop + (view.viewHeight - height) / 2 - 40
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "An empty flowchart"
            font.family: Theme.serifFont
            font.pixelSize: 26
            color: Theme.textMuted
        }
        CapsLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.editing ? "Double-click anywhere for a node, or let an AI make one"
                               : "Switch to Edit to add nodes"
            color: Theme.textFaint
        }
        Row {
            visible: view.editing
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            topPadding: 6
            AppButton {
                raised: true
                compact: true
                text: "1. Copy the prompt"
                onClicked: view.controller.copyFlowchartPrompt()
            }
            AppButton {
                raised: true
                compact: true
                text: "2. Paste the answer"
                onClicked: view.pasteFromClipboard()
            }
        }
    }
    Column {
        visible: view.loadError !== ""
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 80)
        spacing: 12
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Can't show this flowchart"
            font.family: Theme.serifFont
            font.pixelSize: 26
            color: Theme.textMuted
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: view.loadError
            wrapMode: Text.Wrap
            font.pixelSize: 13
            color: Theme.textFaint
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            AppButton { raised: true; compact: true; text: "Try again"; onClicked: view.load() }
            AppButton { compact: true; text: "Reveal in file explorer"; onClicked: view.controller.revealInExplorer(view.uri) }
        }
    }
}
