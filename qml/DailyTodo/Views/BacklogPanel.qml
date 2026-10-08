import QtQuick
import QtQuick.Controls
import DailyTodo.Style
import DailyTodo.Controls

// The Backlog column: todos without a date. Same rows as the timeline (TodoRow), plus a box at the
// top to jot new ones down. "Move to timeline" asks for a day with a date picker.
SideColumn {
    id: backlog

    required property var controller

    title: "Backlog"
    badge: list.count > 0 ? String(list.count) : ""
    alignRight: true

    // Keep the column open while a menu or the date picker is showing, or while typing here.
    property int openMenus: 0
    property int editing: 0
    pinned: openMenus > 0 || editing > 0 || addInput.activeFocus

    // The box slides open with the column; collapsed, the list moves up instead of leaving a gap.
    property real addSpace: backlog.revealed ? addInput.height + 10 : 0
    Behavior on addSpace { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    NoteTextArea {
        id: addInput
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        lines: 1
        autoGrow: true
        enterSubmits: true
        references: backlog.controller
        placeholderText: "Add to backlog..."
        opacity: backlog.revealed ? 1 : 0
        enabled: backlog.revealed
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        onSubmitted: {
            if (text.trim() === "") return
            backlog.controller.addBacklogTodo(text)
            text = ""
        }
        onCancelled: {
            text = ""
            focus = false
        }
    }

    ListView {
        id: list
        anchors.top: parent.top
        anchors.topMargin: backlog.addSpace
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: backlog.controller.backlog

        // a click on the list (or its empty part) leaves the "add to backlog" box
        FocusClearTapHandler { hostWindow: backlog.Window.window }

        delegate: Item {
            id: item
            required property int todoId
            required property string text
            required property bool done

            width: ListView.view.width
            height: row.implicitHeight + 14

            // each todo on a quiet card that lights its edge on hover
            QuietCard {
                anchors.fill: parent
                lit: cardHover.hovered || row.editing
                HoverHandler { id: cardHover }
            }

            TodoRow {
                id: row
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                controller: backlog.controller
                inBacklog: true
                todo: ({ id: item.todoId, text: item.text, done: item.done })

                onDoneToggled: (done) => backlog.controller.setDone(item.todoId, done)
                onEdited: (text) => backlog.controller.editTodo(item.todoId, text)
                onCopyRequested: backlog.controller.copyText(backlog.controller.toEditText(item.text))
                onDeleteRequested: backlog.controller.deleteTodo(item.todoId)
                onMoveToDayRequested: (iso) => backlog.controller.moveToTimeline(item.todoId, iso)
                onMenuOpenChanged: backlog.openMenus += menuOpen ? 1 : -1
                onEditingChanged: backlog.editing += editing ? 1 : -1
            }
            // Scrolled out of the list (or removed) mid-edit: the counts must not keep the
            // column pinned open forever.
            Component.onDestruction: {
                if (row.menuOpen) backlog.openMenus--
                if (row.editing) backlog.editing--
            }
        }
    }

    Text {
        visible: list.count === 0 && backlog.revealed
        anchors.fill: list
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        text: "Nothing in the backlog.\nJot a todo down above."
        font.pixelSize: 18
        color: Theme.textMuted
    }
}
