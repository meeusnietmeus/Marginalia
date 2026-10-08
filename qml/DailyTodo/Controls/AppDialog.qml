import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// The frame of every modal dialog: centred over the window with the page dimmed behind it, on a
// floating Surface, fading and growing in a little as it opens. Give it a width and a contentItem
// (usually starting with a DialogTitle).
Popup {
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    padding: 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Surface {
        elevation: 2
        radius: 18
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 90 } }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
}
