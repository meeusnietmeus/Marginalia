import QtQuick
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Floating "add a todo" box: frosted glass raised above the list (a soft shadow under it, light on
// its top edge), holding the same inset field as every other text box. It stays while it has focus or text and
// emits dismissed when it loses focus while empty. Position it yourself.
Rectangle {
    id: box

    property bool open: false
    property var controller: null          // enables the @ (resources) and ! (tags) activators
    property alias text: input.text
    property Item backdrop: null           // what the glass blurs (must not contain the box)
    property var backdropTracking: []      // see FrostedGlass.trackedValues

    readonly property Item windowContent: Window.contentItem

    signal submitted(string text)
    signal dismissed()

    function focusInput() {
        input.forceActiveFocus()
    }
    function submit() {
        const t = input.text.trim()
        if (t.length === 0)
            return
        box.submitted(t)
        input.text = ""
        input.forceActiveFocus()
    }

    height: addRow.implicitHeight + 16
    radius: Theme.cardRadius + 4
    color: "transparent"                   // the glass paints the background

    opacity: open ? 1 : 0
    visible: open || opacity > 0
    Behavior on opacity { NumberAnimation { duration: 120 } }

    GlassPanel {
        anchors.fill: parent
        radius: box.radius
        backdrop: box.backdrop
        backdropTracking: box.backdropTracking
    }

    RowLayout {
        id: addRow
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // Multiline and growable. Enter adds the todo, Shift+Enter starts a new line; @ picks a
        // resource and ! a tag (see ReferencePicker).
        NoteTextArea {
            id: input
            Layout.fillWidth: true
            lines: 1
            autoGrow: true
            enterSubmits: true
            references: box.controller
            placeholderText: "Add a todo..."
            onSubmitted: box.submit()
            // Esc = cancel: clear the text and close the box (don't rely on the focus change,
            // which doesn't always fire when the box was already empty)
            onCancelled: {
                text = ""
                box.windowContent.forceActiveFocus()
                box.dismissed()
            }
            onActiveFocusChanged: {
                if (!activeFocus && text.length === 0)
                    box.dismissed()
            }
            onVisibleChanged: {
                if (!visible && activeFocus)
                    box.windowContent.forceActiveFocus()
            }
        }
        IconButton {
            filled: true
            iconSource: Theme.iconAdd
            fallbackText: "+"
            enabled: input.text.trim().length > 0
            onClicked: box.submit()
        }
    }
}
