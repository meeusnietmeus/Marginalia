import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The floating box a note or a question is written in (PDF, presentation and video tabs). Its edge
// and its "NEW NOTE" / "NEW QUESTION" pill take the colour of what is being written. Whatever the
// page needs in the header row (a local/global switch, the page or the timestamp) goes in it after
// the pill; the highlighted passage the entry is about, if any, sits above the text.
// Ctrl+Enter: submitted, Esc: cancelled.
GlassPanel {
    id: box

    property var controller: null
    property string kind: "note"              // note | question
    property bool editing: false              // editing an entry instead of writing a new one
    property string quote: ""                 // shown above the text when not empty
    property string quoteColor: "yellow"
    property string hint: "Ctrl+Enter: save  |  Esc: cancel"
    default property alias headerItems: header.data
    property alias input: noteInput

    readonly property color accent: kind === "question" ? Theme.warning : Theme.accentHover

    signal submitted()
    signal cancelled()

    // Whether the pointer is over the box: the page behind it must not take the wheel then.
    readonly property bool hovered: boxHover.hovered
    HoverHandler { id: boxHover }

    height: column.implicitHeight + 24
    edgeColor: Qt.alpha(accent, 0.55)
    edgeWidth: 1.5

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            id: header
            spacing: 8

            PillLabel {
                text: (box.editing ? "Edit " : "New ") + box.kind
                tint: box.accent
                textColor: box.accent
            }
        }

        QuoteLine {
            visible: box.quote !== ""
            Layout.fillWidth: true
            text: box.quote
            barColor: Theme.highlightBar(box.quoteColor)
        }

        // The box keeps its height: longer text scrolls inside it (wheel or scroll bar), and the
        // view follows the cursor.
        Item {
            Layout.fillWidth: true
            implicitHeight: noteInput.minHeight

            Well {
                anchors.fill: parent
                radius: 12
                focused: noteInput.activeFocus
            }
            Flickable {
                id: inputFlick
                anchors.fill: parent
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                clip: true
                contentWidth: width
                contentHeight: noteInput.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: AppScrollBar {}

                function followCursor(r) {
                    if (r.y < contentY) contentY = Math.max(0, r.y - noteInput.topPadding)
                    else if (r.y + r.height > contentY + height)
                        contentY = r.y + r.height + noteInput.bottomPadding - height
                }

                NoteTextArea {
                    id: noteInput
                    width: inputFlick.width
                    autoGrow: true
                    background: null              // the Well behind the Flickable is the face
                    references: box.controller
                    placeholderText: box.kind === "question" ? "Ask a question..." : "Write a note..."
                    onCancelled: box.cancelled()
                    onSubmitted: box.submitted()
                    onCursorRectangleChanged: inputFlick.followCursor(cursorRectangle)
                }
            }
        }

        // key hints under the text box (the header row has little room)
        CapsLabel {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: box.hint
            color: Theme.textFaint
            font.letterSpacing: 0.6
        }
    }
}
