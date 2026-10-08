import QtQuick
import QtQuick.Effects
import DailyTodo.Style
import DailyTodo.Controls

// The resources directly connected to one resource: it sits in the middle (a raised green pill),
// the ones it mentions and the ones that mention it around it, joined by arrows
// (from the resource that mentions to the one that is mentioned). Click a neighbour to open it.
Item {
    id: graph

    property string centerName
    property int centerId: -1                // the resource in the middle
    property var connections: []            // [{id, name, kind, missing, outgoing, incoming}]

    signal nodeClicked(int id)
    // right-click on a resource, the one in the middle or a neighbour: its context menu
    // (position in item's coordinates)
    signal menuRequested(int id, Item item, point position)

    readonly property int count: connections.length
    readonly property real nodeHeight: 30
    readonly property real nodeWidth: Math.max(70, Math.min(170, width * 0.5))
    readonly property real centerX: width / 2
    readonly property real centerY: height / 2

    // Centre of neighbour i: evenly around an ellipse that fills the free space.
    function pointOf(i) {
        const radiusX = Math.max(0, (width - nodeWidth) / 2 - 2)
        const radiusY = Math.max(0, (height - nodeHeight) / 2 - 2)
        const angle = -Math.PI / 2 + 2 * Math.PI * i / Math.max(1, count)
        return Qt.point(centerX + radiusX * Math.cos(angle), centerY + radiusY * Math.sin(angle))
    }

    onConnectionsChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    // the arrows, behind the nodes
    Canvas {
        id: canvas
        anchors.fill: parent

        // where the line from the centre of a box towards (dx, dy) leaves the box
        function edgePoint(cx, cy, hw, hh, dx, dy) {
            const t = Math.min(dx === 0 ? Infinity : hw / Math.abs(dx),
                               dy === 0 ? Infinity : hh / Math.abs(dy))
            return Qt.point(cx + dx * t, cy + dy * t)
        }
        function arrowHead(ctx, tip, fromX, fromY) {
            const angle = Math.atan2(tip.y - fromY, tip.x - fromX)
            const size = 8
            ctx.beginPath()
            ctx.moveTo(tip.x, tip.y)
            ctx.lineTo(tip.x - size * Math.cos(angle - 0.4), tip.y - size * Math.sin(angle - 0.4))
            ctx.lineTo(tip.x - size * Math.cos(angle + 0.4), tip.y - size * Math.sin(angle + 0.4))
            ctx.closePath()
            ctx.fill()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Qt.alpha(Theme.textMuted, 0.55)
            ctx.fillStyle = Qt.alpha(Theme.textMuted, 0.8)
            ctx.lineWidth = 1.2
            const hw = graph.nodeWidth / 2
            const hh = graph.nodeHeight / 2
            const centreHw = Math.min(hw + 10, 70)
            for (let i = 0; i < graph.count; i++) {
                const c = graph.connections[i]
                const p = graph.pointOf(i)
                const dx = p.x - graph.centerX
                const dy = p.y - graph.centerY
                if (dx === 0 && dy === 0) continue
                const start = edgePoint(graph.centerX, graph.centerY, centreHw, hh, dx, dy)
                const end = edgePoint(p.x, p.y, hw, hh, -dx, -dy)
                ctx.beginPath()
                ctx.moveTo(start.x, start.y)
                ctx.lineTo(end.x, end.y)
                ctx.stroke()
                if (c.outgoing) arrowHead(ctx, end, start.x, start.y)     // this one mentions it
                if (c.incoming) arrowHead(ctx, start, end.x, end.y)       // it mentions this one
            }
        }
    }

    // the resource itself: a raised green pill
    Item {
        x: graph.centerX - width / 2
        y: graph.centerY - height / 2
        width: Math.min(graph.nodeWidth + 24, 150)
        height: graph.nodeHeight + 4

        RectangularShadow {
            anchors.fill: parent
            radius: height / 2
            offset.y: 3
            blur: 12
            color: Qt.alpha(Theme.ringDone, 0.30)
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.accentTop }
                GradientStop { position: 1; color: Theme.accentBottom }
            }
            border.color: Qt.darker(Theme.accentBottom, 1.25)
            Rectangle {                             // the glint along its top edge
                x: parent.radius
                y: 1
                width: parent.width - 2 * x
                height: 1
                color: Qt.rgba(1, 1, 1, 0.28)
            }
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: graph.centerName
            elide: Text.ElideRight
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: Theme.accentText
        }

        ClickHandler {
            id: centreMenu
            enabled: graph.centerId >= 0
            acceptedButtons: Qt.RightButton
            onTapped: (eventPoint) => graph.menuRequested(graph.centerId, centreMenu.parent, eventPoint.position)
        }
    }

    // the neighbours
    Repeater {
        model: graph.connections

        Item {
            id: node
            required property int index
            required property var modelData
            readonly property point at: graph.pointOf(index)

            x: at.x - width / 2
            y: at.y - height / 2 - (nodeHover.hovered ? 1 : 0)
            width: graph.nodeWidth
            height: graph.nodeHeight

            Surface {
                anchors.fill: parent
                radius: height / 2
                lit: nodeHover.hovered
            }
            Row {
                anchors.fill: parent
                anchors.leftMargin: 5
                anchors.rightMargin: 10
                spacing: 6
                KindTile {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    kind: node.modelData.kind
                    missing: node.modelData.missing
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 26
                    text: node.modelData.name
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    color: node.modelData.missing ? Theme.textFaint : Theme.text
                }
            }

            HoverHandler { id: nodeHover; cursorShape: Qt.PointingHandCursor }
            ClickHandler { onTapped: graph.nodeClicked(node.modelData.id) }
            ClickHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (eventPoint) => graph.menuRequested(node.modelData.id, node, eventPoint.position)
            }
            AppToolTip {
                text: node.modelData.name
                shown: nodeHover.hovered
            }
        }
    }

    CapsLabel {
        visible: graph.count === 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: 30
        width: parent.width - 28
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "No connections yet. Mention a resource with @ in a note to link it."
        color: Theme.textFaint
    }
}
