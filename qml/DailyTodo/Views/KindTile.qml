import QtQuick
import QtQuick.Controls.impl  // IconImage
import QtQuick.Effects
import DailyTodo.Style

// A small raised tile in a resource kind's colour with its icon in white (a red one with a warning
// sign for a file that has disappeared).
Item {
    id: tile

    property string kind
    property bool missing: false
    readonly property color color: missing ? Theme.danger : Theme.resourceColor(kind)

    implicitWidth: 22
    implicitHeight: 22

    RectangularShadow {
        anchors.fill: face
        radius: face.radius
        offset.y: 1
        blur: 4
        color: Qt.alpha(tile.color, 0.45)
    }
    Rectangle {
        id: face
        anchors.fill: parent
        radius: width * 0.32
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(tile.color, 1.25) }
            GradientStop { position: 1; color: Qt.darker(tile.color, 1.1) }
        }
        border.color: Qt.darker(tile.color, 1.35)
        Rectangle {                         // the glint along its top edge
            x: parent.width * 0.22
            y: 1
            width: parent.width - 2 * x
            height: 1
            color: Qt.rgba(1, 1, 1, 0.35)
        }
        IconImage {
            anchors.centerIn: parent
            readonly property int size: Math.round(tile.width * 0.6)
            width: size
            height: size
            sourceSize: Qt.size(size, size)
            source: tile.missing ? Theme.iconWarning : Theme.resourceIcon(tile.kind)
            color: "white"
        }
    }
}
