import QtQuick
import QtQuick.Controls.impl  // IconImage
import DailyTodo.Style
import DailyTodo.Controls

// Ctrl+Tab: the pages and tabs, most recently used first. Hold Ctrl and press Tab to walk down the
// list (Shift+Tab: up); letting go of Ctrl goes to the one picked. A quick Ctrl+Tab goes straight
// back to the page before, without the list ever showing; it only appears when Ctrl is held a
// moment. Esc (or a click outside it) stays where you are. The window's Shortcuts call start() and
// step(); this item takes the keyboard while it is open, to see Ctrl being let go.
//   entries: [{ key, title, caption, kind (a resource kind, for its tile) or icon }]
Item {
    id: switcher

    property var entries: []
    property int index: 0
    property bool open: false
    property bool revealed: false            // the list is showing (Ctrl was held a moment)
    property var returnFocus: null           // what had the keyboard before

    signal chosen(string key)

    function start(list, backwards, focusItem) {
        if (list.length < 2) return
        entries = list
        index = backwards ? list.length - 1 : 1
        returnFocus = focusItem
        open = true
        revealed = false
        revealTimer.restart()
        keys.forceActiveFocus()
    }
    function step(delta) {
        if (!open) return
        index = (index + delta + entries.length) % entries.length
    }
    function commit() {
        if (!open) return
        close()
        chosen(entries[index].key)
    }
    function cancel() {
        if (!open) return
        close()
        if (returnFocus) returnFocus.forceActiveFocus()
    }
    function close() {
        open = false
        revealed = false
        revealTimer.stop()
    }

    visible: open                            // (an invisible item can't have the keyboard)
    Timer { id: revealTimer; interval: 160; onTriggered: switcher.revealed = switcher.open }

    Item {
        id: keys
        Keys.onReleased: (event) => {
            if (event.key === Qt.Key_Control) { switcher.commit(); event.accepted = true }
        }
        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Escape: switcher.cancel(); break
            case Qt.Key_Return:
            case Qt.Key_Enter: switcher.commit(); break
            case Qt.Key_Tab:                     // (the window's Shortcut gets these first, when it can)
            case Qt.Key_Down: switcher.step(1); break
            case Qt.Key_Backtab:
            case Qt.Key_Up: switcher.step(-1); break
            default: return
            }
            event.accepted = true
        }
        // the keyboard went elsewhere (another window, a click): leave things as they are
        onActiveFocusChanged: if (!activeFocus && switcher.open) switcher.close()
    }

    // a click outside the list stays put
    MouseArea {
        anchors.fill: parent
        enabled: switcher.revealed
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: switcher.cancel()
    }

    Item {
        id: panel
        anchors.centerIn: parent
        width: 440
        height: column.implicitHeight + 24
        opacity: switcher.revealed ? 1 : 0
        scale: switcher.revealed ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 110 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        InputBlocker {}
        Surface { anchors.fill: parent; elevation: 2; radius: 18 }

        Column {
            id: column
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 2

            CapsLabel {
                leftPadding: 10
                bottomPadding: 6
                topPadding: 2
                text: "Recently used  ·  Tab: next  ·  Shift+Tab: back"
                color: Theme.textFaint
            }
            Repeater {
                model: switcher.entries
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: index === switcher.index
                    width: column.width
                    height: 40

                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: row.current ? Qt.alpha(Theme.text, 0.09)
                             : rowHover.hovered ? Qt.alpha(Theme.text, 0.05) : "transparent"
                        border.color: row.current ? Theme.hairlineStrong : "transparent"
                    }
                    // a resource's coloured tile, or the icon of a page
                    KindTile {
                        visible: row.modelData.kind !== undefined
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        kind: row.modelData.kind || ""
                    }
                    IconImage {
                        visible: row.modelData.kind === undefined
                        x: 13
                        anchors.verticalCenter: parent.verticalCenter
                        source: row.modelData.icon || ""
                        sourceSize: Qt.size(16, 16)
                        color: row.current ? Theme.text : Theme.textMuted
                    }
                    Text {
                        x: 44
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - caption.width - 24
                        text: row.modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        font.weight: row.current ? Font.DemiBold : Font.Normal
                        color: row.current ? Theme.text : Theme.textMuted
                    }
                    CapsLabel {
                        id: caption
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.caption || ""
                        color: Theme.textFaint
                    }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    ClickHandler {
                        onTapped: {
                            switcher.index = row.index
                            switcher.commit()
                        }
                    }
                }
            }
        }
    }
}
