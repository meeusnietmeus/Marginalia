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

        NoteTextArea {
            id: noteInput
            Layout.fillWidth: true
            references: box.controller
            placeholderText: box.kind === "question" ? "Ask a question..." : "Write a note..."
            onCancelled: box.cancelled()
            onSubmitted: box.submitted()
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
