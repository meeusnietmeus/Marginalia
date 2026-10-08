import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// Slim, rounded scroll bar: faint at rest, solid while scrolling or hovered, hidden when there is
// nothing to scroll. Use it as `ScrollBar.vertical: AppScrollBar {}`.
ScrollBar {
    id: bar

    policy: ScrollBar.AsNeeded
    minimumSize: 0.08
    padding: 3
    interactive: true
    hoverEnabled: true

    contentItem: Rectangle {
        visible: bar.size < 1.0          // nothing to scroll: no handle
        implicitWidth: bar.vertical ? 7 : 64
        implicitHeight: bar.vertical ? 64 : 7
        radius: 3.5
        color: bar.pressed ? Theme.textMuted : Theme.checkBorder
        opacity: bar.pressed || bar.hovered ? 1 : bar.active ? 0.85 : 0.35
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    background: Item {}
}
