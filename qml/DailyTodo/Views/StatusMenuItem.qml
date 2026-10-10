import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// One status to pick in a resource's menu: its glyph, its name, and a tick on the current one.
MenuItem {
    id: control

    property string status: "unopened"
    property bool current: false

    implicitWidth: Math.max(190, row.implicitWidth + leftPadding + rightPadding)
    implicitHeight: 34
    leftPadding: 14
    rightPadding: 14
    topPadding: 0
    bottomPadding: 0

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    contentItem: Item {
        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            StatusDot {
                anchors.verticalCenter: parent.verticalCenter
                status: control.status
                size: 14
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                font.pixelSize: 13
                color: control.current ? Theme.text : Theme.textMuted
                font.weight: control.current ? Font.DemiBold : Font.Normal
            }
        }
        Text {
            visible: control.current
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "✓"
            font.pixelSize: 13
            color: Theme.statusColor(control.status)
        }
    }

    background: Rectangle {
        radius: 9
        color: control.down ? Qt.alpha(Theme.text, 0.12)
             : control.highlighted ? Qt.alpha(Theme.text, 0.07) : "transparent"
    }
}
