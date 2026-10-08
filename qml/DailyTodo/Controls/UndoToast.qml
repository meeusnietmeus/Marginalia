import QtQuick
import QtQuick.Controls.impl  // IconImage
import DailyTodo.Style

// A toast for something that was just deleted: the message, an Undo button, and a thin bar that
// drains while the offer lasts. Hovering pauses the countdown. Stack them in a column.
//
// undone()   Undo was clicked
// expired()  the time ran out (the deletion is final)
// removed()  the toast has faded out; the host can drop it now
Item {
    id: toast

    property string message
    property int duration: 6000                 // ms the offer lasts

    signal undone()
    signal expired()
    signal removed()

    property real remaining: 1                  // 1 -> 0 while the offer lasts
    property bool closing: false

    function dismiss(undo) {
        if (closing) return
        closing = true
        countdown.stop()
        if (undo) undone()
        else expired()
        exit.start()
    }

    implicitWidth: 340
    implicitHeight: 48
    width: implicitWidth
    height: implicitHeight

    // slide in from the right, fade out
    opacity: 0
    transform: Translate { id: slide; x: 36 }
    Component.onCompleted: enter.start()
    ParallelAnimation {
        id: enter
        NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: slide; property: "x"; to: 0; duration: 220; easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
        id: exit
        ParallelAnimation {
            NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 160 }
            NumberAnimation { target: slide; property: "x"; to: 24; duration: 160; easing.type: Easing.InCubic }
        }
        ScriptAction { script: toast.removed() }
    }

    NumberAnimation {
        id: countdown
        target: toast
        property: "remaining"
        from: 1
        to: 0
        duration: toast.duration
        running: !toast.closing
        paused: hover.hovered
        onFinished: toast.dismiss(false)
    }

    // soft shadow
    Rectangle {
        anchors.fill: card
        anchors.margins: -1
        anchors.topMargin: 2
        anchors.bottomMargin: -3
        radius: card.radius + 1
        color: "#000000"
        opacity: 0.35
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.cardRadius
        color: Theme.toast
        border.color: Theme.menuBorder
        clip: true

        InputBlocker {}                         // floats over the page: nothing under it reacts

        Text {
            id: label
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: undoButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: toast.message
            elide: Text.ElideRight
            font.pixelSize: 13
            color: Theme.text
        }

        // Undo
        Rectangle {
            id: undoButton
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: undoRow.implicitWidth + 20
            height: 30
            radius: Theme.controlRadius
            color: undoTap.pressed ? Qt.alpha(Theme.accentHover, 0.3)
                 : undoHover.hovered ? Qt.alpha(Theme.accentHover, 0.18) : "transparent"

            Row {
                id: undoRow
                anchors.centerIn: parent
                spacing: 6
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Theme.iconUndo
                    sourceSize: Qt.size(15, 15)
                    color: Theme.accentHover
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Undo"
                    font.pixelSize: 13
                    font.bold: true
                    color: Theme.accentHover
                }
            }
            HoverHandler { id: undoHover; cursorShape: Qt.PointingHandCursor }
            ClickHandler { id: undoTap; onTapped: toast.dismiss(true) }
        }

        // time left
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            height: 3
            width: parent.width * toast.remaining
            color: Theme.accent
            opacity: 0.75
        }
    }

    HoverHandler { id: hover }
}