import QtQuick
import QtQuick.Controls
import DailyTodo.Style
import DailyTodo.Controls

// "Activators" for a text box: typing `@` or `!` (at the start of a word) inserts `@{}` / `!{}`,
// puts the cursor between the braces and pops up a list of the best matches (at most five) for
// what is typed there: resources for `@`, tags for `!`. Up / Down choose, Enter (or a click)
// replaces `@{typed}` with `@{Chosen name}`, Esc closes the list.
//
// A black box for any TextArea / TextField (it only uses text, cursorPosition, insert, remove and
// positionToRectangle). The text box passes its key presses to handleKey():
//
//     Keys.onPressed: (event) => { if (picker.handleKey(event)) event.accepted = true }
//
// The controller must offer searchReferences(activator, query) -> [{id, name}].
Item {
    id: picker

    property Item target
    property var controller
    property bool available: true

    property bool active: false              // an `@{...}` / `!{...}` is being filled in
    property int start: -1                   // index of the activator character
    property string activator: "@"
    property var results: []
    property int current: 0

    // ---- what the text box calls -----------------------------------------------------------

    // Returns true when the key was used up here.
    function handleKey(event) {
        if (!available || !target || !controller)
            return false

        if (active) {
            switch (event.key) {
            case Qt.Key_Up:
                if (results.length > 0) current = (current + results.length - 1) % results.length
                return true
            case Qt.Key_Down:
                if (results.length > 0) current = (current + 1) % results.length
                return true
            case Qt.Key_Tab:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (event.modifiers & Qt.ControlModifier) {   // Ctrl+Enter: not for us
                    close()
                    return false
                }
                if (results.length > 0) accept(current)
                else close()                                  // nothing to pick: next Enter submits
                return true
            case Qt.Key_Escape:
                close()
                return true
            }
            return false
        }

        if ((event.text === "@" || event.text === "!") && atWordStart())
            return trigger(event.text)
        return false
    }

    // ---- internals --------------------------------------------------------------------------

    // The text as it is right now. target.text can lag behind when cursorPositionChanged fires
    // first (typing a character moves the cursor before the text property updates).
    function readText() { return target.getText(0, target.length) }

    // Only at the start of a word, so "me@example.com" and "Hello!" are typed normally.
    function atWordStart() {
        const pos = target.selectionStart
        return pos === 0 || /[\s(\[]/.test(readText().charAt(pos - 1))
    }

    function trigger(symbol) {
        if (target.selectionStart !== target.selectionEnd)
            target.remove(target.selectionStart, target.selectionEnd)   // typing replaces a selection
        const pos = target.cursorPosition
        target.insert(pos, symbol + "{}")
        target.cursorPosition = pos + 2                                 // between the braces
        start = pos
        activator = symbol
        active = true
        refresh()
        return true
    }

    // Re-read what is between the braces and search; close when the user moved away.
    function refresh() {
        if (!active) return
        const t = readText()
        const end = t.indexOf("}", start + 2)
        const cursor = target.cursorPosition
        if (t.charAt(start) !== activator || t.charAt(start + 1) !== "{" || end < 0
                || cursor < start + 2 || cursor > end) {
            close()
            return
        }
        const query = t.substring(start + 2, end)
        results = controller.searchReferences(activator, query)
        if (activator === "@" && query.trim().toLowerCase() === "new")
            results = [{ id: -1, name: "New resource...", create: true }].concat(results)
        current = Math.min(current, Math.max(0, results.length - 1))
    }

    function accept(index) {
        const choice = results[index]
        if (!choice) { close(); return }
        if (choice.create) { startCreate(); return }
        const end = readText().indexOf("}", start + 2)
        const from = start
        close()
        const inserted = activator + "{" + choice.name + "}"
        target.remove(from, end + 1)
        target.insert(from, inserted)
        target.cursorPosition = from + inserted.length
        target.forceActiveFocus()
    }

    // ---- "@{new}": make a resource right here ----
    // The `@{new}` stays in the text while the dialog is open (an empty add-todo box would close);
    // it becomes `@{Name of the new resource}`, or disappears when nothing gets created.
    property int createAt: -1

    function startCreate() {
        createAt = start
        close()
        if (dialogLoader.item) dialogLoader.item.openNew()
        else dialogLoader.active = true                // onLoaded opens it
    }

    // Swap the `@{new}` that was typed for what should be there ("" removes it).
    function replaceNew(reference) {
        const from = createAt
        createAt = -1
        if (!target || from < 0) return
        const typed = readText().indexOf("@{new}", from)
        if (typed < 0) return
        target.remove(typed, typed + 6)
        target.insert(typed, reference)
        target.cursorPosition = typed + reference.length
        target.forceActiveFocus()
    }

    Loader {
        id: dialogLoader
        active: false
        visible: false
        sourceComponent: ResourceDialog {
            controller: picker.controller
            onCreateRequested: (uri, name, tagIds, moveFile) => {
                const made = picker.controller.addResource(uri, name, tagIds, moveFile)
                picker.replaceNew(made !== "" ? "@{" + made + "}" : "")
            }
            onClosed: if (picker.createAt >= 0) picker.replaceNew("")     // cancelled
        }
        onLoaded: item.openNew()
    }

    function close() {
        active = false
        results = []
        current = 0
    }

    onActiveChanged: active ? popup.open() : popup.close()

    Connections {
        target: picker.target
        function onTextChanged() { picker.refresh() }
        function onCursorPositionChanged() { picker.refresh() }
        function onActiveFocusChanged() { if (!picker.target.activeFocus) picker.close() }
    }

    Popup {
        id: popup

        // Just under the cursor.
        readonly property rect cursorRect: {
            picker.target.text; picker.target.cursorPosition; picker.target.width   // re-evaluate
            return picker.active ? picker.target.positionToRectangle(picker.target.cursorPosition)
                                 : Qt.rect(0, 0, 0, 0)
        }

        parent: picker.target
        x: Math.max(0, Math.min(cursorRect.x, picker.target.width - width))
        y: cursorRect.y + cursorRect.height + 4
        width: 260
        padding: 4
        focus: false                                 // typing carries on in the text box
        closePolicy: Popup.NoAutoClose

        background: Surface {
            elevation: 2
            radius: 12
        }

        contentItem: Column {
            spacing: 2

            Repeater {
                model: picker.results

                Rectangle {
                    id: option
                    required property int index
                    required property var modelData
                    width: popup.availableWidth
                    height: 30
                    radius: 9
                    color: option.index === picker.current ? Qt.alpha(Theme.text, 0.08) : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: option.modelData.create === true ? "+" : picker.activator
                            font.pixelSize: 13
                            font.bold: true
                            color: picker.activator === "@" ? Theme.resourceWeb : Theme.accentHover
                        }
                        Text {
                            id: optionName
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width - 28)
                            text: option.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            color: Theme.text
                        }
                        Text {                                  // where a sub-tag sits: "Maths"
                            visible: text !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - 28 - optionName.width - 8)
                            text: option.modelData.hint === undefined ? "" : option.modelData.hint
                            elide: Text.ElideRight
                            font.pixelSize: 11
                            color: Theme.textFaint
                        }
                    }
                    HoverHandler { onHoveredChanged: if (hovered) picker.current = option.index }
                    ClickHandler { onTapped: picker.accept(option.index) }
                }
            }

            Text {
                visible: picker.results.length === 0
                width: popup.availableWidth
                height: 30
                leftPadding: 10
                verticalAlignment: Text.AlignVCenter
                text: picker.activator === "@" ? "No matching resource" : "No matching tag"
                font.pixelSize: 13
                color: Theme.textFaint
            }
        }
    }
}
