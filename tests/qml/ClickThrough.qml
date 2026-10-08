import QtQuick
import QtQuick.Controls
import DailyTodo.Controls

// A card that counts its clicks (like a resource card in the library), under two things that float
// over it: a popup with a clickable row (like the tag filter) and a plain floating box with a
// clickable row (like the note box). Clicking either row, or the box's empty part, must not reach
// the card. See test_click_through.py.
Window {
    id: win
    width: 600
    height: 400
    visible: true

    property int cardClicks: 0
    property int popupRowClicks: 0
    property int boxRowClicks: 0

    Rectangle {
        anchors.fill: parent
        color: "tan"
        ClickHandler { onTapped: win.cardClicks++ }
    }

    Popup {
        id: pop
        x: 20; y: 20; width: 200; height: 150    // row at (30..210, 30..60)
        padding: 10
        closePolicy: Popup.NoAutoClose
        contentItem: Item {
            Rectangle {
                width: parent.width; height: 30
                ClickHandler { onTapped: win.popupRowClicks++ }
            }
        }
    }

    Rectangle {
        x: 300; y: 20; width: 200; height: 150    // row at (310..490, 30..60), empty below it
        InputBlocker {}
        Rectangle {
            x: 10; y: 10; width: 180; height: 30
            ClickHandler { onTapped: win.boxRowClicks++ }
        }
    }

    Component.onCompleted: pop.open()
}
