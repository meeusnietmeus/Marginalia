import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl    // IconImage (tinted icon)
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// "Today   2 OF 4 DONE": the day's name in serif, and how far along it is as a small uppercase
// label (the date itself is on the day's dial on the ruler). Today is set in bold.
RowLayout {
    id: header

    property string title                 // "Yesterday" / "Today" / "Tomorrow" / weekday name
    property string dateIso               // "2026-10-02"
    property string dateLabel             // "2 Oct"
    property bool isToday: false
    property bool isPast: false
    property bool showLateNightWarning: false
    property bool showMoveAll: false
    property int done: 0
    property int total: 0
    readonly property bool moveAllHovered: moveAllHover.hovered
    property alias moveAllLabel: moveAllLabel

    signal moveAllRequested()

    spacing: 10

    Label {
        id: titleLabel
        text: header.title
        font.family: Theme.serifFont
        font.pixelSize: 17
        font.bold: header.isToday
        color: header.isPast ? Theme.textFaint : Theme.text
    }
    CapsLabel {
        visible: header.total > 0
        text: header.done === header.total ? "all done" : header.done + " of " + header.total + " done"
        color: header.done === header.total ? Theme.ringDone : header.isPast ? Theme.textFaint : Theme.textMuted
        Layout.alignment: Qt.AlignVCenter
        Layout.topMargin: 2
    }
    // Late at night "Today" is easy to mix up with "late yesterday": show a red clock.
    IconImage {
        visible: header.showLateNightWarning
        source: Theme.iconClockAlert
        sourceSize: Qt.size(15, 15)
        Layout.preferredWidth: 15
        Layout.preferredHeight: 15
        Layout.leftMargin: 3
        color: Theme.danger

        HoverHandler { id: lateHover }
        AppToolTip {
            text: "It's getting late, you're starting to blend days!"
            shown: lateHover.hovered
        }
    }
    // Past day with missed todos: send them all to today. The day delegate draws the line
    // that runs from here down to the todos' move buttons.
    CapsLabel {
        id: moveAllLabel
        visible: header.showMoveAll
        text: "Move all to today"
        color: moveAllHover.hovered ? Theme.warning : Theme.textMuted
        Layout.leftMargin: 8
        Layout.topMargin: 2

        HoverHandler { id: moveAllHover; cursorShape: Qt.PointingHandCursor }
        ClickHandler { onTapped: header.moveAllRequested() }
    }
    Item { Layout.fillWidth: true }
}
