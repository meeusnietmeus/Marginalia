import QtQuick
import DailyTodo.Style

// How far along a resource is, as a small round glyph in the status's own colour:
//   unopened     an empty faint ring        opened    a ring with a dot
//   in_progress  a half-filled ring         finished  a filled disc with a tick
Item {
    id: dot

    property string status: "unopened"
    property real size: 12
    readonly property color tint: Theme.statusColor(status)

    implicitWidth: size
    implicitHeight: size

    Rectangle {                                          // the ring
        anchors.fill: parent
        radius: width / 2
        color: dot.status === "finished" ? dot.tint : "transparent"
        border.width: Math.max(1, dot.size / 9)
        border.color: dot.tint
    }
    Item {                                               // in progress: the left half is filled
        visible: dot.status === "in_progress"
        width: dot.size / 2
        height: dot.size
        clip: true
        Rectangle {
            width: dot.size
            height: dot.size
            radius: width / 2
            color: dot.tint
        }
    }
    Rectangle {                                          // opened: a dot in the middle
        visible: dot.status === "opened"
        anchors.centerIn: parent
        width: dot.size * 0.34
        height: width
        radius: width / 2
        color: dot.tint
    }
    Text {                                               // finished: a tick
        visible: dot.status === "finished" && dot.size >= 9
        anchors.centerIn: parent
        text: "✓"
        font.pixelSize: dot.size * 0.78
        font.bold: true
        color: Theme.window
    }
}
