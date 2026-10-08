import QtQuick
import DailyTodo.Style

// Small icon button for per-row actions (delete, move to today, ...). Muted at rest;
// on hover the icon takes `tint` and a soft wash of the same colour appears behind it.
IconButton {
    id: control

    property color tint: Theme.text
    property bool forceLit: false          // lit up as if hovered (e.g. by a related control)
    property color baseColor: "transparent"  // opaque base lets the button mask a line behind it
    readonly property bool lit: hovered || forceLit

    implicitWidth: 24
    implicitHeight: 24
    iconSize: 15
    textColor: control.lit ? control.tint : Theme.textMuted

    background: Rectangle {
        radius: Theme.controlRadius
        color: control.baseColor
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Qt.alpha(control.tint, control.down ? 0.26 : control.lit ? 0.15 : 0)
        }
    }
}
