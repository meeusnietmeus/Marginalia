import QtQuick
import QtQuick.Controls.impl  // IconImage: draws an icon tinted with a colour
import DailyTodo.Style

// Round icon-only button. Give it an SVG/PNG via iconSource; the icon is tinted
// with textColor. If the file doesn't exist yet, fallbackText is shown instead.
AppButton {
    id: control

    property url iconSource
    property string fallbackText: ""
    property int iconSize: Theme.iconSize

    implicitWidth: compact ? 28 : Theme.controlHeight
    leftPadding: 0
    rightPadding: 0

    contentItem: Item {
        IconImage {
            id: icon
            anchors.centerIn: parent
            source: control.iconSource
            width: control.iconSize
            height: control.iconSize
            sourceSize: Qt.size(control.iconSize, control.iconSize)
            color: control.textColor
        }
        // The text is only set when it is needed: laying out a symbol the UI font lacks (✓, ✕)
        // loads a fallback font, which costs many megabytes even if the text is never shown.
        Text {
            readonly property bool needed: icon.status === Image.Error || icon.status === Image.Null
            anchors.centerIn: parent
            visible: needed
            text: needed ? control.fallbackText : ""
            font.pixelSize: 16
            font.bold: true
            color: control.textColor
        }
    }
}
