import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// One todo: checkbox, text (right-click: Copy / Edit), inline editor and row actions.
// Doesn't talk to the backend itself; it only emits signals.
RowLayout {
    id: row

    property var todo: ({ id: -1, text: "", done: false })
    property bool muted: false             // e.g. a past day: dimmer text
    property bool canMoveToToday: false
    property bool moveHighlighted: false   // light the move button up (hovering "move all to today")
    property bool reserveMoveSlot: false   // keep the move button's space free even when it is hidden
    property alias moveButton: moveButton
    property bool editing: false
    property bool inBacklog: false         // a todo without a date: the menu offers the opposite move
    readonly property bool menuOpen: todoMenu.visible || (pickerLoader.item !== null && pickerLoader.item.opened)
    property var controller: null          // for rendering and picking @resources / !tags
    property string editOriginal: ""

    signal moveToBacklogRequested()
    signal moveToDayRequested(string iso)  // the user picked a day on the calendar
    signal doneToggled(bool done)
    signal edited(string text)             // only emitted when the text actually changed
    signal copyRequested()
    signal moveToTodayRequested()
    signal deleteRequested()

    Layout.fillWidth: true
    spacing: 4

    function startEdit() {
        editing = true
        // the edit form shows @{Name} instead of the stored @{id|Name}
        editOriginal = controller ? controller.toEditText(todo.text) : todo.text
        editField.text = editOriginal
        Qt.callLater(function () {
            editField.forceActiveFocus()
            editField.selectAll()
        })
    }
    function commitEdit() {
        const t = editField.text.trim()
        const changed = t.length > 0 && t !== editOriginal
        editing = false
        if (changed)
            row.edited(t)
    }
    function cancelEdit() {
        editing = false
    }
    function askForDay() {
        if (pickerLoader.item) {
            const range = controller.timelineRange()
            pickerLoader.item.ask(null, range.min, range.max)
        } else {
            pickerLoader.active = true
        }
    }

    AppCheckBox {
        checked: row.todo.done
        onToggled: row.doneToggled(checked)
    }

    // ---- normal view ----
    ReferenceText {
        visible: !row.editing
        Layout.fillWidth: true
        controller: row.controller
        source: row.todo.text
        font.pixelSize: 14
        font.strikeout: row.todo.done
        baseColor: row.todo.done ? Theme.textDone
                 : row.muted ? Theme.textMuted : Theme.text

        ClickHandler {
            acceptedButtons: Qt.RightButton
            onTapped: (eventPoint) => todoMenu.popup(eventPoint.position)
        }
        CrudMenu {
            id: todoMenu
            onEditTriggered: row.startEdit()
            onDeleteTriggered: row.deleteRequested()
            topBefore: [
                MenuIconButton {
                    text: "Copy"
                    iconSource: Theme.iconCopy
                    onTriggered: row.copyRequested()
                }
            ]

            // A backlog todo can only go to the timeline; a dated one to the backlog or another day.
            AppMenuItem {
                visible: !row.inBacklog
                height: visible ? implicitHeight : 0
                text: "Move to backlog"
                iconSource: Theme.iconInbox
                onTriggered: row.moveToBacklogRequested()
            }
            AppMenuItem {
                text: row.inBacklog ? "Move to timeline..." : "Move to..."
                iconSource: Theme.iconCalendar
                onTriggered: row.askForDay()
            }
        }
    }

    // The calendar for "Move to...", created the first time it is needed.
    Loader {
        id: pickerLoader
        active: false
        visible: false                     // takes no room in the row; the calendar is a popup
        sourceComponent: DatePicker {
            title: "Move to which day?"
            onPicked: (payload, iso) => row.moveToDayRequested(iso)
        }
        onLoaded: {
            const range = row.controller.timelineRange()
            item.ask(null, range.min, range.max)
        }
    }

    // ---- edit view (Enter = save, Esc = cancel) ----
    // Multiline and growable: Enter saves, Shift+Enter starts a new line, Esc cancels.
    NoteTextArea {
        id: editField
        visible: row.editing
        Layout.fillWidth: true
        lines: 1
        autoGrow: true
        enterSubmits: true
        references: row.controller
        onSubmitted: row.commitEdit()
        onCancelled: row.cancelEdit()
    }
    IconButton {
        visible: row.editing
        filled: true
        iconSource: Theme.iconSave
        fallbackText: "✓"
        onClicked: row.commitEdit()
    }
    IconButton {
        visible: row.editing
        iconSource: Theme.iconCancel
        fallbackText: "✕"
        onClicked: row.cancelEdit()
    }

    // ---- row actions ----
    // Missed todo -> move it to today (yellow on hover)
    Item {
        visible: !row.editing && row.reserveMoveSlot && !row.canMoveToToday
        implicitWidth: 24
        implicitHeight: 24
    }
    RowActionButton {
        id: moveButton
        visible: !row.editing && row.canMoveToToday
        forceLit: row.moveHighlighted
        baseColor: Theme.window
        iconSource: Theme.iconMoveToToday
        fallbackText: "→"
        tint: Theme.warning
        onClicked: row.moveToTodayRequested()

        AppToolTip {
            text: "Move to today"
            shown: moveButton.hovered
        }
    }
}
