import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Effects
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// "Knowledge graph": every resource of the workspace, in the region of its tag (a sub-tag's region
// inside its tag's), and the links between them (a note of one mentions the other).
//   top left      the title and what is in it
//   top right     the legend: every tag, with a filter; click one to go to its region
//   bottom left   fit / zoom out / zoom / zoom in, and whether every link is drawn
//   bottom centre find a resource by name
// Drag to move around, scroll to zoom, click a resource to open it, right-click it for its menu.
// Hovering a resource lights up its links and neighbours; nothing else fades.
Item {
    id: page

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)
    readonly property var graph: controller.knowledgeGraph

    // the view: screen = world * zoom + pan
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    readonly property real minZoom: 0.08
    readonly property real maxZoom: 2.5

    property int focusTag: -2                    // the tag picked in the legend (-2: none, -1: untagged)
    property int hoverId: -1                     // the resource under the pointer
    property int foundId: -1                     // the resource just found with the search bar
    property bool allLinks: true                 // false: a resource's links only show on hover

    function tint(color) { return color < 0 ? Theme.textMuted : Theme.areaColor(color) }

    // the part of the page the graph is fitted into: left of the legend, below the title and above
    // the controls at the bottom
    readonly property real viewWidth: Math.max(200, width - legend.width - 36)
    readonly property real viewTop: 76
    readonly property real viewHeight: Math.max(120, height - viewTop - 76)

    property var nodeById: ({})
    property var regionByTag: ({})
    function index() {
        const nodes = {}
        for (const n of graph.nodes) nodes[n.id] = n
        nodeById = nodes
        const regions = {}
        for (const r of graph.regions) regions[r.tag] = r
        regionByTag = regions
    }

    // everything next to the hovered resource (and itself)
    property var hoverSet: ({})
    onHoverIdChanged: {
        const set = {}
        if (hoverId >= 0) {
            set[hoverId] = true
            for (const e of graph.edges) {
                if (e.a === hoverId) set[e.b] = true
                else if (e.b === hoverId) set[e.a] = true
            }
        }
        hoverSet = set
        canvas.requestPaint()
    }

    // ---- moving the view ----
    // Show the world rectangle (x, y, w, h) as large as fits, centred in the free part of the page.
    function viewFor(x, y, w, h, margin, most) {
        const z = Math.max(minZoom, Math.min(most, (viewWidth - 2 * margin) / Math.max(1, w),
                                                   (viewHeight - margin) / Math.max(1, h)))
        return { zoom: z, panX: (viewWidth - w * z) / 2 - x * z,
                 panY: viewTop + (viewHeight - h * z) / 2 - y * z }
    }
    function fit(animated) {
        if (graph.worldWidth <= 0 || width <= 0) { zoom = 1; panX = 0; panY = 0; return }
        const v = viewFor(0, 0, graph.worldWidth, graph.worldHeight, 40, 1.2)
        if (animated) moveTo(v)
        else { zoom = v.zoom; panX = v.panX; panY = v.panY }
    }
    function moveTo(v) {
        flight.stop()
        zoomTo.to = v.zoom; panXTo.to = v.panX; panYTo.to = v.panY
        flight.start()
    }
    function goToRegion(tag) {
        const r = regionByTag[tag]
        if (r) moveTo(viewFor(r.x, r.y, r.width, r.height, 60, 1.4))
    }
    function goToResource(id) {
        const n = nodeById[id]
        if (!n) return
        const z = Math.max(zoom, 1.1)
        moveTo({ zoom: z, panX: viewWidth / 2 - n.x * z, panY: viewTop + viewHeight / 2 - n.y * z })
        foundId = id
        foundTimer.restart()
    }
    // Show one tag: pick it in the legend and go to its region (a tag without a region of its own,
    // nothing tagged with it, is only picked). Asked for before the graph is built, it waits.
    property int pendingTag: -2
    function showTag(tag) {
        if (!graph.built) { pendingTag = tag; return }
        pendingTag = -2
        focusTag = tag
        if (regionByTag[tag]) goToRegion(tag)
        else fit(true)
    }

    function zoomAt(point, factor) {
        flight.stop()
        const next = Math.max(minZoom, Math.min(maxZoom, zoom * factor))
        const real = next / zoom
        panX = point.x - (point.x - panX) * real
        panY = point.y - (point.y - panY) * real
        zoom = next
    }

    ParallelAnimation {
        id: flight
        NumberAnimation { id: zoomTo; target: page; property: "zoom"; duration: 450; easing.type: Easing.OutCubic }
        NumberAnimation { id: panXTo; target: page; property: "panX"; duration: 450; easing.type: Easing.OutCubic }
        NumberAnimation { id: panYTo; target: page; property: "panY"; duration: 450; easing.type: Easing.OutCubic }
    }
    Timer { id: foundTimer; interval: 2600; onTriggered: page.foundId = -1 }

    onVisibleChanged: if (visible) graph.rebuild()
    onZoomChanged: canvas.requestPaint()
    onPanXChanged: canvas.requestPaint()
    onPanYChanged: canvas.requestPaint()
    onAllLinksChanged: canvas.requestPaint()
    onFocusTagChanged: canvas.requestPaint()
    Component.onCompleted: { index(); graph.rebuild(); Qt.callLater(fit, false) }

    Connections {
        target: page.controller
        function onCurrentWorkspaceIdChanged() { page.graph.rebuild() }
    }
    Connections {
        target: page.graph
        function onChanged() {
            page.index()
            page.hoverId = -1
            if (page.focusTag >= 0 && page.regionByTag[page.focusTag] === undefined
                    && !page.graph.areas.some(a => a.tag === page.focusTag))
                page.focusTag = -2
            // the picked tag stays in view through a rebuild; otherwise everything is shown
            if (page.focusTag > -2 && page.regionByTag[page.focusTag]) page.goToRegion(page.focusTag)
            else page.fit(false)
            canvas.requestPaint()
            if (page.pendingTag > -2) Qt.callLater(page.showTag, page.pendingTag)
        }
    }

    // ------------------------------------------------------------------ the picture
    Item {
        id: viewport
        anchors.fill: parent
        clip: true
        onWidthChanged: Qt.callLater(page.fit, false)
        onHeightChanged: Qt.callLater(page.fit, false)

        DragHandler {
            property real startX: 0
            property real startY: 0
            target: null
            onActiveChanged: if (active) { flight.stop(); startX = page.panX; startY = page.panY }
            onTranslationChanged: if (active) {
                page.panX = startX + translation.x
                page.panY = startY + translation.y
            }
        }
        WheelHandler {
            onWheel: (event) => page.zoomAt(point.position, event.angleDelta.y > 0 ? 1.15 : 1 / 1.15)
        }

        // the regions: a soft panel per tag, in its family's colour, its name at the top
        Repeater {
            model: page.graph.regions
            Rectangle {
                id: region
                required property var modelData
                readonly property color tint: page.tint(modelData.color)
                readonly property bool focused: page.focusTag === modelData.tag
                readonly property real s: Math.min(1, page.zoom + 0.25)   // shrinks less than the world
                x: modelData.x * page.zoom + page.panX
                y: modelData.y * page.zoom + page.panY
                width: modelData.width * page.zoom
                height: modelData.height * page.zoom
                radius: Math.min(22 * page.zoom, 22)
                color: Qt.alpha(region.tint, modelData.depth === 0 ? 0.045 : 0.06)
                border.color: Qt.alpha(region.tint, focused ? 0.75 : modelData.depth === 0 ? 0.26 : 0.18)
                border.width: focused ? 1.5 : 1
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Row {
                    visible: page.zoom > 0.18
                    x: 14 * page.zoom
                    y: 13 * page.zoom
                    spacing: 7 * region.s
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8 * region.s
                        height: width
                        radius: width / 2
                        color: region.tint
                        visible: region.modelData.tag >= 0
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: region.modelData.name
                        font.family: region.modelData.depth === 0 ? Theme.serifFont : font.family
                        font.pixelSize: Math.max(9, (region.modelData.depth === 0 ? 20 : 13) * page.zoom)
                        font.weight: region.modelData.depth === 0 ? Font.Normal : Font.DemiBold
                        font.letterSpacing: region.modelData.depth === 0 ? 0 : Theme.labelSpacing * 0.6
                        font.capitalization: region.modelData.depth === 0 ? Font.MixedCase : Font.AllUppercase
                        color: region.modelData.depth === 0 ? Theme.text : Qt.lighter(region.tint, 1.15)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: region.modelData.size
                        font.pixelSize: Math.max(8, 11 * page.zoom)
                        color: Theme.textFaint
                    }
                }
            }
        }

        // the links: soft curves; the ones of the hovered resource in its colour
        Canvas {
            id: canvas
            anchors.fill: parent
            renderTarget: Canvas.Image

            function arrow(ctx, tipX, tipY, fromX, fromY, size) {
                const angle = Math.atan2(tipY - fromY, tipX - fromX)
                ctx.beginPath()
                ctx.moveTo(tipX, tipY)
                ctx.lineTo(tipX - size * Math.cos(angle - 0.42), tipY - size * Math.sin(angle - 0.42))
                ctx.lineTo(tipX - size * Math.cos(angle + 0.42), tipY - size * Math.sin(angle + 0.42))
                ctx.closePath()
                ctx.fill()
            }
            // how far along the line from a pill's centre towards (dx, dy) its edge is
            function leave(dx, dy, hw, hh) {
                return Math.min(dx === 0 ? Infinity : hw / Math.abs(dx), dy === 0 ? Infinity : hh / Math.abs(dy))
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const z = page.zoom
                const hh = 15 * z
                const size = Math.max(4, 8 * Math.min(1, z + 0.2))
                for (const e of page.graph.edges) {
                    const a = page.nodeById[e.a], b = page.nodeById[e.b]
                    if (!a || !b) continue
                    const lit = page.hoverId >= 0 && (e.a === page.hoverId || e.b === page.hoverId)
                    if (!lit && !page.allLinks) continue
                    const focused = page.focusTag > -2 && (a.region === page.focusTag || b.region === page.focusTag)
                    const hovered = lit ? page.nodeById[page.hoverId] : null
                    ctx.strokeStyle = lit ? Qt.alpha(page.tint(hovered.color), 0.95)
                                          : Qt.alpha(Theme.text, focused ? 0.34 : 0.17)
                    ctx.fillStyle = ctx.strokeStyle
                    ctx.lineWidth = lit ? 2 : 1.1
                    const ax = a.x * z + page.panX, ay = a.y * z + page.panY
                    const bx = b.x * z + page.panX, by = b.y * z + page.panY
                    const dx = bx - ax, dy = by - ay
                    if (dx === 0 && dy === 0) continue
                    // each pill is as wide as its name needs (a.width, in layout units)
                    const ta = leave(dx, dy, a.width / 2 * z, hh), tb = leave(-dx, -dy, b.width / 2 * z, hh)
                    if (ta + tb >= 1) continue                 // the pills touch: nothing to draw
                    const sx = ax + dx * ta, sy = ay + dy * ta
                    const ex = bx - dx * tb, ey = by - dy * tb
                    // a gentle bend, always to the same side, so crossing links stay apart
                    const len = Math.sqrt((ex - sx) * (ex - sx) + (ey - sy) * (ey - sy))
                    const bend = Math.min(40 * z, len * 0.12)
                    const cx = (sx + ex) / 2 - (ey - sy) / len * bend
                    const cy = (sy + ey) / 2 + (ex - sx) / len * bend
                    ctx.beginPath()
                    ctx.moveTo(sx, sy)
                    ctx.quadraticCurveTo(cx, cy, ex, ey)
                    ctx.stroke()
                    if (e.a_to_b) arrow(ctx, ex, ey, cx, cy, size)
                    if (e.b_to_a) arrow(ctx, sx, sy, cx, cy, size)
                }
            }
        }

        // under the hovered (or found) resource: a soft glow in its colour
        RectangularShadow {
            readonly property var n: page.hoverId >= 0 ? page.nodeById[page.hoverId]
                                   : page.foundId >= 0 ? page.nodeById[page.foundId] : null
            visible: n !== null && n !== undefined
            x: n ? n.x * page.zoom + page.panX - width / 2 : 0
            y: n ? n.y * page.zoom + page.panY - height / 2 + 3 : 0
            width: n ? n.width * page.zoom : 0
            height: 30 * page.zoom
            radius: height / 2
            blur: 18
            spread: 2
            color: n ? Qt.alpha(page.tint(n.color), 0.55) : "transparent"
        }

        // the resources: small raised pills with their kind's tile
        Repeater {
            model: page.graph.nodes
            Item {
                id: node
                required property var modelData
                readonly property color tint: page.tint(modelData.color)
                readonly property bool hovered: page.hoverId === modelData.id
                readonly property bool neighbour: !hovered && page.hoverSet[modelData.id] === true
                readonly property bool found: page.foundId === modelData.id
                // a tag picked in the legend: what has it stands out, the rest steps back a little
                readonly property bool picked: page.focusTag === -2
                    || (page.focusTag === -1 ? modelData.tags.length === 0
                                             : page.focusTag >= 0 && page.focusName !== ""
                                               && modelData.tags.indexOf(page.focusName) >= 0)
                readonly property bool small: page.zoom < 0.42

                width: modelData.width * page.zoom
                height: 30 * page.zoom
                x: modelData.x * page.zoom + page.panX - width / 2
                y: modelData.y * page.zoom + page.panY - height / 2
                z: hovered || found ? 2 : 1
                scale: hovered ? 1.06 : 1
                opacity: picked ? 1 : 0.4
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.panelRaised }
                        GradientStop { position: 1; color: Theme.panel }
                    }
                    border.width: node.hovered || node.found ? 1.5 : 1
                    border.color: node.hovered || node.found ? node.tint
                                : node.neighbour ? Qt.alpha(node.tint, 0.8)
                                : Qt.alpha(node.tint, 0.35)
                    Rectangle {                          // light along the top edge
                        visible: !node.small
                        x: parent.radius
                        y: 1
                        width: parent.width - 2 * x
                        height: 1
                        color: Theme.surfaceHighlight
                    }
                }
                KindTile {
                    visible: !node.small
                    anchors.verticalCenter: parent.verticalCenter
                    x: 5 * page.zoom
                    width: 20 * page.zoom
                    height: width
                    kind: node.modelData.kind
                    missing: node.modelData.missing
                }
                Rectangle {                              // zoomed far out: just a dot
                    visible: node.small
                    anchors.centerIn: parent
                    width: Math.max(4, parent.height * 0.45)
                    height: width
                    radius: width / 2
                    color: node.tint
                }
                Text {
                    visible: !node.small
                    anchors.fill: parent
                    anchors.leftMargin: 31 * page.zoom
                    anchors.rightMargin: 10 * page.zoom
                    verticalAlignment: Text.AlignVCenter
                    text: node.modelData.label        // at most 80 characters, then an ellipsis
                    elide: Text.ElideRight
                    font.pixelSize: Math.max(7, 14 * page.zoom)
                    font.weight: Font.DemiBold
                    font.strikeout: node.modelData.missing
                    color: node.modelData.missing ? Theme.textFaint : Theme.text
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered) page.hoverId = node.modelData.id
                        else if (page.hoverId === node.modelData.id) page.hoverId = -1
                    }
                }
                ClickHandler { onTapped: page.controller.openResourceById(node.modelData.id) }
                ClickHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (eventPoint) => page.actions.showMenu(node.modelData.id, node,
                                                                    eventPoint.position.x, eventPoint.position.y)
                }
            }
        }

        // one tooltip for whichever resource is under the pointer
        AppToolTip {
            readonly property var hovered: page.hoverId >= 0 ? page.nodeById[page.hoverId] : null
            parent: viewport
            x: hovered ? hovered.x * page.zoom + page.panX - width / 2 : 0
            y: hovered ? hovered.y * page.zoom + page.panY + 22 * page.zoom : 0
            text: hovered ? hovered.name + (hovered.tags.length > 0 ? "\n" + hovered.tags.join(", ") : "")
                            + (hovered.degree > 0 ? "\n" + hovered.degree + (hovered.degree === 1 ? " link" : " links") : "")
                          : ""
            shown: hovered !== null && hovered !== undefined
        }
    }

    readonly property string focusName: {
        for (const a of graph.areas) if (a.tag === focusTag) return a.name
        return ""
    }

    // ------------------------------------------------------------------ top left: the title
    // A soft fade behind it, so the graph moving underneath never makes it hard to read.
    Rectangle {
        width: page.viewWidth
        height: 120
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.window, 0.9) }
            GradientStop { position: 0.55; color: Qt.alpha(Theme.window, 0.6) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    Column {
        x: 22
        y: 14
        spacing: 2
        SectionTitle { text: "Knowledge graph" }
        CapsLabel {
            text: page.graph.nodes.length + (page.graph.nodes.length === 1 ? " resource" : " resources")
                  + "  ·  " + page.graph.edges.length + (page.graph.edges.length === 1 ? " link" : " links")
                  + "  ·  " + page.graph.areas.length + (page.graph.areas.length === 1 ? " tag" : " tags")
            color: Theme.textFaint
        }
    }

    // nothing to draw
    Column {
        visible: page.graph.built && !page.graph.loading && page.graph.nodes.length === 0
        anchors.centerIn: parent
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No resources yet"
            font.family: Theme.serifFont
            font.pixelSize: 26
            color: Theme.textMuted
        }
        CapsLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Add some in the library: they show up here, by tag"
            color: Theme.textFaint
        }
    }

    // ------------------------------------------------------------------ top right: the legend
    Item {
        id: legend
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        width: 270
        height: Math.min(parent.height - 32 - 70, legendColumn.implicitHeight + 28)

        InputBlocker {}
        Surface {
            anchors.fill: parent
            elevation: 2
            radius: 18
        }
        ColumnLayout {
            id: legendColumn
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            SectionTitle {
                text: "Tags"
                badge: page.graph.areas.length > 0 ? String(page.graph.areas.length) : ""
                size: 20
            }
            AppTextField {
                id: tagFilter
                visible: page.graph.areas.length > 0
                Layout.fillWidth: true
                implicitHeight: 30
                placeholderText: "Filter tags..."
                Keys.onEscapePressed: { text = ""; focus = false }
            }
            ListView {
                id: tagList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                Layout.minimumHeight: Math.min(contentHeight, 60)
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: AppScrollBar {}
                // matching tags (by name or by the tag above), and "Untagged" when there is such a region
                model: {
                    const q = tagFilter.text.trim().toLowerCase()
                    const rows = page.graph.areas.filter(a => q === "" || a.path.toLowerCase().indexOf(q) >= 0)
                    const untagged = page.regionByTag[-1]
                    if (untagged && (q === "" || "untagged".indexOf(q) >= 0))
                        rows.push({ tag: -1, name: "Untagged", path: "Untagged", depth: 0, color: -1, count: untagged.size })
                    return rows
                }

                delegate: Item {
                    id: tagRow
                    required property var modelData
                    readonly property bool selected: page.focusTag === modelData.tag
                    readonly property bool filtering: tagFilter.text.trim() !== ""
                    width: ListView.view.width
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: tagRow.selected ? Qt.alpha(page.tint(tagRow.modelData.color), 0.16)
                             : rowHover.hovered ? Qt.alpha(Theme.text, 0.07) : "transparent"
                        border.color: tagRow.selected ? Qt.alpha(page.tint(tagRow.modelData.color), 0.45) : "transparent"
                    }
                    Rectangle {                          // the colour: a dot, a ring for a sub-tag
                        id: swatch
                        x: 10 + (tagRow.filtering ? 0 : tagRow.modelData.depth * 16)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 5
                        color: tagRow.modelData.depth === 0 ? page.tint(tagRow.modelData.color) : "transparent"
                        border.width: tagRow.modelData.depth === 0 ? 0 : 2
                        border.color: page.tint(tagRow.modelData.color)
                    }
                    Text {
                        anchors.left: swatch.right
                        anchors.leftMargin: 9
                        anchors.right: count.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        // filtered, a sub-tag shows the tag above it too
                        text: tagRow.filtering ? tagRow.modelData.path : tagRow.modelData.name
                        elide: Text.ElideLeft
                        font.pixelSize: 13
                        font.italic: tagRow.modelData.tag === -1
                        color: tagRow.modelData.count > 0 ? Theme.text : Theme.textFaint
                    }
                    CapsLabel {
                        id: count
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: tagRow.modelData.count
                        color: Theme.textFaint
                    }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    ClickHandler {
                        onTapped: {
                            if (tagRow.selected) {
                                page.focusTag = -2
                            } else {
                                page.focusTag = tagRow.modelData.tag
                                page.goToRegion(tagRow.modelData.tag)
                            }
                        }
                    }
                }
            }
            CapsLabel {
                visible: page.graph.areas.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Tag resources in the library to group them here"
                color: Theme.textFaint
            }
            CapsLabel {
                visible: tagList.count === 0 && tagFilter.text.trim() !== ""
                text: "No tag matches"
                color: Theme.textFaint
            }
            CapsLabel {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: page.focusTag > -2 ? "Click it again to show everything"
                                         : "Click a tag to go to it"
                color: Theme.textFaint
                font.letterSpacing: 0.8
            }
        }
    }

    // ------------------------------------------------------------------ bottom left: the view
    Row {
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
                    onClicked: page.fit(true)
                    AppToolTip { text: "Fit everything"; shown: fitButton.hovered }
                }
                IconButton {
                    compact: true
                    implicitHeight: 28
                    iconSource: Theme.iconZoomOut
                    onClicked: page.zoomAt(Qt.point(page.viewWidth / 2, page.viewTop + page.viewHeight / 2), 1 / 1.3)
                }
                AppButton {
                    id: zoomLabel
                    compact: true
                    implicitHeight: 28
                    implicitWidth: 56
                    text: Math.round(page.zoom * 100) + "%"
                    font.pixelSize: 12
                    textColor: Theme.textMuted
                    onClicked: page.zoomAt(Qt.point(page.viewWidth / 2, page.viewTop + page.viewHeight / 2), 1 / page.zoom)
                    AppToolTip { text: "Back to 100%"; shown: zoomLabel.hovered }
                }
                IconButton {
                    compact: true
                    implicitHeight: 28
                    iconSource: Theme.iconZoomIn
                    onClicked: page.zoomAt(Qt.point(page.viewWidth / 2, page.viewTop + page.viewHeight / 2), 1.3)
                }
            }
        }
        Item {
            width: 36
            height: 36
            InputBlocker {}
            Well { anchors.fill: parent; radius: height / 2 }
            IconButton {
                id: linksButton
                anchors.centerIn: parent
                compact: true
                implicitHeight: 28
                implicitWidth: 28
                iconSource: Theme.iconLink
                active: page.allLinks
                onClicked: page.allLinks = !page.allLinks
                AppToolTip {
                    text: page.allLinks ? "Every link is drawn: click to only draw them on hover"
                                        : "Links show on hover: click to draw every link"
                    shown: linksButton.hovered
                }
            }
        }
    }

    // ------------------------------------------------------------------ bottom centre: find
    Item {
        id: finder
        readonly property string query: findField.text.trim().toLowerCase()
        readonly property var matches: {
            if (query === "") return []
            const hits = page.graph.nodes.filter(n => n.name.toLowerCase().indexOf(query) >= 0)
            hits.sort((a, b) => a.name.toLowerCase().indexOf(query) - b.name.toLowerCase().indexOf(query)
                                || a.name.localeCompare(b.name))
            return hits.slice(0, 6)
        }
        property int current: 0
        onQueryChanged: current = 0
        function choose(i) {
            const n = matches[i]
            if (!n) return
            page.goToResource(n.id)
        }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: Math.min(440, page.width - 2 * 270)          // clear of the controls on the left
        height: 46

        // the matches, above the bar
        Item {
            visible: findField.activeFocus && finder.matches.length > 0
            anchors.bottom: parent.top
            anchors.bottomMargin: 8
            width: parent.width
            height: resultColumn.implicitHeight + 12
            InputBlocker {}
            Surface { anchors.fill: parent; elevation: 2; radius: 16 }
            Column {
                id: resultColumn
                x: 6
                y: 6
                width: parent.width - 12
                Repeater {
                    model: finder.matches
                    Item {
                        id: result
                        required property var modelData
                        required property int index
                        width: resultColumn.width
                        height: 34
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: result.index === finder.current ? Qt.alpha(Theme.text, 0.08)
                                 : resultHover.hovered ? Qt.alpha(Theme.text, 0.05) : "transparent"
                        }
                        KindTile {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 20
                            kind: result.modelData.kind
                            missing: result.modelData.missing
                        }
                        Text {
                            x: 36
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - regionLabel.width - 18
                            text: result.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            color: Theme.text
                        }
                        CapsLabel {
                            id: regionLabel
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.regionByTag[result.modelData.region] ? page.regionByTag[result.modelData.region].name : ""
                            color: page.tint(result.modelData.color)
                        }
                        HoverHandler { id: resultHover; cursorShape: Qt.PointingHandCursor }
                        ClickHandler { onTapped: finder.choose(result.index) }
                    }
                }
            }
        }

        InputBlocker {}
        Surface {
            anchors.fill: parent
            elevation: 2
            radius: height / 2
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 8
            spacing: 8
            IconImage {
                source: Theme.iconSearch
                sourceSize: Qt.size(16, 16)
                color: Theme.textMuted
            }
            AppTextField {
                id: findField
                Layout.fillWidth: true
                implicitHeight: 30
                placeholderText: "Find a resource..."
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Down) {
                        finder.current = Math.min(finder.matches.length - 1, finder.current + 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        finder.current = Math.max(0, finder.current - 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        finder.choose(finder.current)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        text = ""
                        focus = false
                        event.accepted = true
                    }
                }
            }
            CapsLabel {
                visible: finder.query !== ""
                text: finder.matches.length === 0 ? "None" : finder.matches.length + (finder.matches.length === 6 ? "+" : "")
                color: finder.matches.length === 0 ? Theme.danger : Theme.textFaint
            }
        }
    }

    // ------------------------------------------------------------------ building a big graph takes a moment
    Item {
        anchors.fill: parent
        visible: page.graph.loading
        InputBlocker {}                              // nothing to click while it builds
        Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.window, 0.6) }
        Column {
            anchors.centerIn: parent
            spacing: 12
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: parent.visible
                palette.dark: Theme.textMuted
            }
            CapsLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Building the graph..."
            }
        }
    }
}
