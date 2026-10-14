import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Effects
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// A flowchart resource in its own tab: nodes (a title, and a body that shows on hover) joined by
// arrows, on a dotted grid. The chart lives in its .canvas file (JSON Canvas, see
// core/flowchart.py); every change is written back to it a moment later.
//   View  drag the grid to move around, scroll to zoom, hover a node to read its body
//   Edit  the same, and: double-click the grid for a new node, drag a node to move it, drag from
//         one of the dots on its sides to another node for an arrow (or to empty space for a new
//         node), click a node or arrow to change it on the right; Del removes, Ctrl+Z undoes
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
    // nid, title, body, nx, ny, nw, nh (world units), tint (a colour key), docPage (0: none)
    ListModel { id: nodeModel }
    property var edges: []                   // { id, from, to, fromSide, toSide, label, fromArrow, toArrow, color }
    property var indexById: ({})
    property int revision: 0                 // bumped on every change: bindings on positions re-read
    property bool loaded: false
    property string loadError: ""
    property bool editing: false
    property bool dirty: false

    property string selectedNode: ""
    property string selectedEdge: ""
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
                         height: n.nh, color: n.tint, page: n.docPage })
        }
        return { nodes: nodes, edges: edges.map(e => Object.assign({}, e)) }
    }
    function apply(data) {
        nodeModel.clear()
        for (const n of data.nodes)
            nodeModel.append({ nid: n.id, title: n.title, body: n.body || "", nx: n.x, ny: n.y,
                               nw: n.width, nh: n.height, tint: n.color || "", docPage: n.page || 0 })
        edges = data.edges.map(e => ({ id: e.id, from: e.from, to: e.to, fromSide: e.fromSide || "",
                                       toSide: e.toSide || "", label: e.label || "",
                                       fromArrow: e.fromArrow === true, toArrow: e.toArrow !== false,
                                       color: e.color || "" }))
        reindex()
        if (indexById[selectedNode] === undefined) selectedNode = ""
        if (!edges.some(e => e.id === selectedEdge)) selectedEdge = ""
        touched()
        syncInspector()
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
        revision++
        edgeCanvas.requestPaint()
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
    function addNodeAt(wx, wy, from) {
        checkpoint()
        const id = newId("n")
        nodeModel.append({ nid: id, title: "", body: "", nx: snap(wx - 110), ny: snap(wy - 26),
                           nw: 220, nh: 52, tint: "", docPage: 0 })
        reindex()
        if (from) edges = edges.concat([{ id: newId("e"), from: from, to: id, fromSide: "", toSide: "",
                                          label: "", fromArrow: false, toArrow: true, color: "" }])
        selectNode(id)
        changed()
        Qt.callLater(() => { titleField.forceActiveFocus(); titleField.selectAll() })
    }
    function setNode(id, role, value) {
        const i = indexById[id]
        if (i === undefined) return
        nodeModel.setProperty(i, role, value)
        changed()
    }
    function removeNode(id) {
        const i = indexById[id]
        if (i === undefined) return
        checkpoint()
        edges = edges.filter(e => e.from !== id && e.to !== id)
        nodeModel.remove(i)
        reindex()
        selectedNode = ""
        hoverNode = ""
        changed()
    }
    function addEdge(from, to) {
        if (from === to || edges.some(e => e.from === from && e.to === to)) return
        checkpoint()
        const id = newId("e")
        edges = edges.concat([{ id: id, from: from, to: to, fromSide: "", toSide: "", label: "",
                                fromArrow: false, toArrow: true, color: "" }])
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
        if (selectedNode !== "") removeNode(selectedNode)
        else if (selectedEdge !== "") removeEdge(selectedEdge)
    }
    function selectNode(id) {
        selectedEdge = ""
        selectedNode = id
        syncInspector()
    }
    function selectEdge(id) {
        selectedNode = ""
        selectedEdge = id
        syncInspector()
    }
    function clearSelection() {
        selectedNode = ""
        selectedEdge = ""
        syncInspector()
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
    function nodeAt(sx, sy, except) {         // the topmost node under a point of the viewport
        const p = toWorld(sx, sy)
        for (let i = nodeModel.count - 1; i >= 0; i--) {
            const n = nodeModel.get(i)
            if (n.nid !== except && p.x >= n.nx && p.x <= n.nx + n.nw && p.y >= n.ny && p.y <= n.ny + n.nh)
                return n.nid
        }
        return ""
    }
    function edgeAt(sx, sy) {                 // the arrow within a few pixels of a point
        let best = "", bestDist = 8
        for (const e of edges) {
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
        linkTarget = nodeAt(p.x, p.y, linkFrom)
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
        enabled: view.visible && (view.selectedNode !== "" || view.selectedEdge !== "")
        onActivated: view.clearSelection()
    }

    // ------------------------------------------------------------------ the grid and the chart
    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        visible: view.loaded
        onWidthChanged: if (view.loaded && view.nodeModelEmpty) Qt.callLater(view.fit, false)

        DragHandler {
            property real startX: 0
            property real startY: 0
            target: null
            onActiveChanged: if (active) { flight.stop(); startX = view.panX; startY = view.panY }
            onTranslationChanged: if (active) {
                view.panX = startX + translation.x
                view.panY = startY + translation.y
            }
        }
        WheelHandler {
            onWheel: (event) => view.zoomAt(point.position, event.angleDelta.y > 0 ? 1.1 : 1 / 1.1)
        }
        // a click on the grid picks an arrow (or nothing); a double-click there adds a node
        TapHandler {
            onTapped: (eventPoint) => {
                const p = eventPoint.position
                if (view.nodeAt(p.x, p.y) !== "") return         // the node handles its own clicks
                const edge = view.edgeAt(p.x, p.y)
                if (edge !== "") view.selectEdge(edge)
                else view.clearSelection()
            }
            onDoubleTapped: (eventPoint) => {
                const p = eventPoint.position
                if (!view.editing || view.nodeAt(p.x, p.y) !== "" || view.edgeAt(p.x, p.y) !== "") return
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
                for (const e of view.edges) {
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

                    readonly property bool selected: view.selectedNode === nid
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

                    x: nx
                    y: ny
                    width: nw
                    height: Math.max(52, content.implicitHeight + 26)
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
                        HoverHandler { id: nearHover }
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
                    Rectangle {
                        id: face
                        anchors.fill: parent
                        radius: 12
                        gradient: Gradient {
                            GradientStop { position: 0; color: node.tint !== "" ? Qt.tint(Theme.panelRaised, Qt.alpha(node.accent, 0.10)) : Theme.panelRaised }
                            GradientStop { position: 1; color: node.tint !== "" ? Qt.tint(Theme.panel, Qt.alpha(node.accent, 0.06)) : Theme.panel }
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
                        // more to read (on hover), and the page of the document it is about
                        Row {
                            visible: node.body !== "" || node.docPage > 0
                            spacing: 8
                            IconImage {
                                visible: node.body !== ""
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
                    ClickHandler {
                        onTapped: view.selectNode(node.nid)
                        onDoubleTapped: if (view.editing) {
                            view.selectNode(node.nid)
                            titleField.forceActiveFocus()
                            titleField.selectAll()
                        }
                    }
                    // Edit: drag to move it (it snaps to the grid). A drag that starts on one of
                    // the dots draws an arrow instead (the dots' own handlers only get the half of
                    // a dot that sticks out of the node).
                    DragHandler {
                        id: moving
                        enabled: view.editing
                        target: null
                        // wins from the grid's DragHandler (which would move the view instead)
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                        property real startX: 0
                        property real startY: 0
                        property bool linking: false
                        onActiveChanged: {
                            if (active) {
                                const press = node.mapFromItem(null, centroid.scenePressPosition.x,
                                                               centroid.scenePressPosition.y)
                                linking = node.dotAt(press.x, press.y) !== ""
                                if (linking) {
                                    view.beginLink(node.nid, centroid)
                                    return
                                }
                                view.forceActiveFocus()
                                view.checkpoint()
                                startX = node.nx
                                startY = node.ny
                                view.selectNode(node.nid)
                                view.dragging = true
                            } else if (linking) {
                                linking = false
                                view.finishLink()
                            } else {
                                view.dragging = false
                                view.changed()
                            }
                        }
                        onCentroidChanged: if (active && linking) {
                            view.moveLink(centroid.scenePosition)
                        } else if (active) {
                            const dx = (centroid.scenePosition.x - centroid.scenePressPosition.x) / view.zoom
                            const dy = (centroid.scenePosition.y - centroid.scenePressPosition.y) / view.zoom
                            nodeModel.setProperty(node.index, "nx", view.snap(startX + dx))
                            nodeModel.setProperty(node.index, "ny", view.snap(startY + dy))
                            view.touched()
                        }
                    }

                    // Edit: a dot on each side; drag from one to another node for an arrow
                    Repeater {
                        model: ["top", "right", "bottom", "left"]
                        Item {
                            id: handle
                            required property string modelData
                            readonly property bool live: linking.active || (moving.linking && moving.active)
                            visible: view.editing && !node.lifted && (node.near || live)
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
                return m ? { nx: m.nx, ny: m.ny, nw: m.nw, nh: m.nh, title: m.title, body: m.body,
                             tint: m.tint } : null
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
                text: nodeModel.count + (nodeModel.count === 1 ? " node" : " nodes") + "  ·  "
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
                visible: view.selectedNode === "" && view.selectedEdge === ""
                text: "Editing"
                size: 20
            }
            Repeater {
                model: view.selectedNode === "" && view.selectedEdge === "" ? [
                    ["Double-click the grid", "a new node"],
                    ["Drag a node", "move it"],
                    ["Drag from a green dot", "an arrow to another node, or a new node"],
                    ["Click a node or arrow", "change it here"],
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

            // ---- a node ----
            SectionTitle {
                visible: view.selectedNode !== ""
                text: "Node"
                size: 20
            }
            CapsLabel { visible: view.selectedNode !== ""; text: "Title" }
            AppTextField {
                id: titleField
                visible: view.selectedNode !== ""
                Layout.fillWidth: true
                placeholderText: "What is the point?"
                onActiveFocusChanged: if (activeFocus) view.checkpointPending = true
                onTextEdited: view.editNode("title", text)
                Keys.onReturnPressed: bodyField.forceActiveFocus()
                Keys.onEnterPressed: bodyField.forceActiveFocus()
            }
            CapsLabel { visible: view.selectedNode !== ""; text: "Shown on hover" }
            NoteTextArea {
                id: bodyField
                visible: view.selectedNode !== ""
                Layout.fillWidth: true
                Layout.maximumHeight: 260
                lines: 4
                autoGrow: true
                placeholderText: "Explain it (Markdown works)"
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
                text: "Delete node"
                textColor: hovered ? Theme.danger : Theme.textMuted
                onClicked: view.removeNode(view.selectedNode)
            }

            // ---- an arrow ----
            SectionTitle {
                visible: view.selectedEdge !== ""
                text: "Arrow"
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
            CapsLabel { visible: view.selectedEdge !== ""; text: "Label" }
            AppTextField {
                id: labelField
                visible: view.selectedEdge !== ""
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
                    compact: true
                    raised: true
                    text: "Reverse"
                    onClicked: view.reverseEdge(view.selectedEdge)
                }
                AppButton {
                    compact: true
                    text: "Delete arrow"
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

    // ------------------------------------------------------------------ bottom centre: a new node (Edit)
    AppButton {
        visible: view.editing && view.loaded
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -(view.width - view.viewWidth) / 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
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
