import QtQuick
import QtQuick.Controls
import DailyTodo.Style
import DailyTodo.Controls

// Multiline text box for notes, questions, answers and todos. Enter starts a new line, Ctrl+Enter
// submits, Esc cancels, and Tab never types a tab character.
//   autoGrow     starts at `lines` lines and gets taller as the text needs more room
//   enterSubmits Enter submits instead (Shift+Enter starts a new line), like a todo input
//   references   give it the controller to turn on the @ / ! activators (see ReferencePicker)
TextArea {
    id: area

    property int lines: 3
    property bool autoGrow: false
    property bool enterSubmits: false
    property var references: null

    signal submitted()
    signal cancelled()
    signal tabPressed()

    readonly property real minHeight: lines * font.pixelSize * 1.5 + 16
    implicitHeight: autoGrow ? Math.max(minHeight, contentHeight + topPadding + bottomPadding)
                             : minHeight
    wrapMode: TextEdit.Wrap
    font.pixelSize: 13
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.accent
    selectedTextColor: Theme.accentText
    selectByMouse: true
    topPadding: 8
    bottomPadding: 8
    leftPadding: 12
    rightPadding: 12

    background: Well {
        radius: 12
        focused: area.activeFocus
    }

    ReferencePicker {
        id: picker
        target: area
        controller: area.references
        available: area.references !== null
    }

    // Typing the second `*` of `**` adds the closing `**` and leaves the cursor between the pairs.
    // Only when nothing is selected and the `**` isn't already followed by `*`.
    function autoCloseBold(event) {
        if (event.text !== "*" || area.selectionStart !== area.selectionEnd)
            return false
        const at = area.cursorPosition
        if (at < 1 || area.getText(at - 1, at) !== "*" || area.getText(Math.max(0, at - 2), at - 1) === "*"
                || area.getText(at, at + 1) === "*")
            return false
        area.insert(at, "***")
        area.cursorPosition = at + 1
        return true
    }

    // One handler for every key (Qt calls the specific Keys.onEscapePressed-style handlers before
    // Keys.onPressed, which would run before the @ / ! list gets its say).
    Keys.onPressed: (event) => {
        if (picker.handleKey(event)) {            // choosing in the @ / ! list comes first
            event.accepted = true
            return
        }
        if (autoCloseBold(event)) {
            event.accepted = true
            return
        }
        switch (event.key) {
        case Qt.Key_Escape:
            area.cancelled()
            event.accepted = true
            break
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            area.tabPressed()                      // never types a tab character
            event.accepted = true
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if ((event.modifiers & Qt.ControlModifier)
                    || (area.enterSubmits && !(event.modifiers & Qt.ShiftModifier))) {
                area.submitted()
                event.accepted = true
            }
            break
        }
    }
}
