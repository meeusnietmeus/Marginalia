import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import DailyTodo.Style

// Menu entry for AppMenu: flat, rounded highlight, pointer cursor. Optionally with an icon, and
// a colour for both icon and text (e.g. red for a destructive entry).
MenuItem {
    id: control

    property url iconSource
    property color tint: Theme.text

    implicitWidth: Math.max(140, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: 34
    leftPadding: 14
    rightPadding: 14
    topPadding: 0
    bottomPadding: 0

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    contentItem: Row {
        spacing: 10

        IconImage {
            visible: control.iconSource.toString() !== ""
            anchors.verticalCenter: parent.verticalCenter
            source: control.iconSource
            sourceSize: Qt.size(Theme.iconSize, Theme.iconSize)
            color: control.tint
        }
        Text {
            text: control.text
            font.pixelSize: 13
            color: control.tint
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: 9
        color: control.down ? Qt.alpha(Theme.text, 0.12)
             : control.highlighted ? Qt.alpha(Theme.text, 0.07) : "transparent"
    }
}
