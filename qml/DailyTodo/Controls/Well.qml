import QtQuick
import QtQuick.Effects
import DailyTodo.Style

// An inset field: sunk a little into the surface (a shade along its inside top edge), with a soft
// green ring while it has the focus. The background of every text field.
Item {
    id: well

    property bool focused: false
    property real radius: 12

    // the focus ring's glow
    RectangularShadow {
        anchors.fill: parent
        radius: well.radius
        blur: 10
        spread: 1
        color: Qt.alpha(Theme.ringDone, 0.28)
        opacity: well.focused ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
        anchors.fill: parent
        radius: well.radius
        color: Theme.well
        border.color: well.focused ? Theme.focusRing : Theme.hairline
        border.width: well.focused ? 1.5 : 1

        // Shade along the inside top edge. It covers the whole field (same corners, so nothing pokes
        // out at the rounded ends) and fades out after its first 8 px.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, well.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.32) }
                GradientStop { position: Math.min(0.5, 8 / Math.max(1, well.height)); color: "transparent" }
            }
        }
    }
}
