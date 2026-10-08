import QtQuick
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The empty strip under a todo (or under "Nothing planned"). While `live`, hovering it
// reports pointerHovered (the day then shows the add-arrow on the graph) and clicking it
// emits tapped (the day opens its add box).
// The hit area reaches left over the graph gutter, so the arrow itself can be reached
// and clicked without leaving the zone.
Item {
    id: gap

    property bool live: true
    // How far the hit area extends to the left of the strip.
    property real reachLeft: Theme.contentX - Theme.graphX + Theme.arrowSize / 2 + 4

    signal pointerHovered(bool hovered)
    signal tapped()

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.todoGap

    Item {
        x: -gap.reachLeft
        width: gap.width - x
        height: gap.height
        HoverHandler {
            enabled: gap.live
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: gap.pointerHovered(hovered)
        }
        ClickHandler {
            enabled: gap.live
            onTapped: gap.tapped()
        }
    }
}
