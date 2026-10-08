import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// Short message that fades in, then out again after `duration` ms. Call show("...").
// Anchor it yourself (usually bottom-centre of the window) and set maximumWidth.
Rectangle {
    id: toast

    property int duration: 4000
    property real maximumWidth: 400

    function show(message) {
        label.text = message
        toast.opacity = 1
        hideTimer.restart()
    }

    width: Math.min(label.implicitWidth + 32, maximumWidth)
    height: label.implicitHeight + 20
    radius: Theme.cardRadius
    color: Theme.toast
    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    InputBlocker {}                             // floats over the page: nothing under it reacts

    Label {
        id: label
        anchors.centerIn: parent
        width: parent.width - 32
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        color: Theme.text
        font.pixelSize: 13
    }

    Timer {
        id: hideTimer
        interval: toast.duration
        onTriggered: toast.opacity = 0
    }
}
