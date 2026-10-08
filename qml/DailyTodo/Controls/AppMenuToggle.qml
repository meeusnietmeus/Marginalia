import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import DailyTodo.Style

// A menu entry that switches something on or off (a todo's priority, whether it is in progress):
// its icon in the setting's own colour while it is on, its name, and a small switch at the end
// that shows the state at a glance. Triggering it means "flip it": act on `switched(!active)`.
MenuItem {
    id: control

    property url iconSource
    property color tint: Theme.accentHover      // the colour of the setting when it is on
    property bool active: false

    signal switched(bool active)
    onTriggered: switched(!active)

    implicitWidth: Math.max(190, row.implicitWidth + leftPadding + rightPadding)
    implicitHeight: 34
    leftPadding: 14
    rightPadding: 12
    topPadding: 0
    bottomPadding: 0

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    contentItem: Item {
        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                source: control.iconSource
                sourceSize: Qt.size(Theme.iconSize, Theme.iconSize)
                color: control.active ? control.tint : Theme.textMuted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                font.pixelSize: 13
                color: Theme.text
            }
        }

        // the switch: a small inset track, its knob to the right (and lit) when on
        Rectangle {
            id: track
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 16
            radius: 8
            color: control.active ? Qt.alpha(control.tint, 0.3) : Theme.well
            border.color: control.active ? Qt.alpha(control.tint, 0.6) : Theme.hairlineStrong
            Behavior on color { ColorAnimation { duration: 140 } }

            Rectangle {
                x: control.active ? parent.width - width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                gradient: Gradient {
                    GradientStop { position: 0; color: control.active ? Qt.lighter(control.tint, 1.15) : Theme.textMuted }
                    GradientStop { position: 1; color: control.active ? Qt.darker(control.tint, 1.15) : Qt.darker(Theme.textMuted, 1.3) }
                }
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
    }

    background: Rectangle {
        radius: 9
        color: control.down ? Qt.alpha(Theme.text, 0.12)
             : control.highlighted ? Qt.alpha(Theme.text, 0.07) : "transparent"
    }
}
