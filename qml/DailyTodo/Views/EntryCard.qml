import QtQuick
import DailyTodo.Style
import DailyTodo.Controls

// One entry of a notes list, for every page that has them (PDF, presentation, video): a plain note
// or a question (bold) on a quiet card, or one of a question's answers (no card: indented, hanging
// off the question by a thin line). A note or question about a highlighted passage shows the
// passage above its text. A question without an answer shows a box to type the answer in; an
// answer is edited in place. Notes and questions are edited by whoever hosts the card (edit() asks
// for it with editRequested). Right-click asks for the context menu: menuRequested.
//
// In a delegate, mark the optional roles you need as required (`required highlightId`) so the
// model fills them in.
Item {
    id: card

    required property var controller
    required property int noteId
    required property string body
    required property bool isQuestion
    required property bool answered
    required property int parentId
    property bool isGlobal: false
    property int highlightId: -1               // >= 0: about this highlighted passage
    property string quote: ""                  // ... which reads like this
    property string quoteColor: "yellow"
    property bool marked: false                // lit up (e.g. the entry that was jumped to)

    readonly property bool isAnswer: !isQuestion && parentId > 0       // (ids start at 1)
    readonly property bool needsAnswer: isQuestion && !answered
    // only a local note or question can be tied to a highlight (an answer belongs to its question)
    readonly property bool canLink: !isAnswer && !isGlobal
    readonly property bool hovered: hover.hovered
    readonly property real indent: isAnswer ? 22 : 0
    property bool editing: false               // an answer being edited in place

    signal editRequested()
    signal answerSubmitted(string text)
    signal answerEdited(string text)
    signal menuRequested(point position)

    function edit() {
        if (isAnswer) startEdit()
        else editRequested()
    }
    function startEdit() {
        editArea.text = controller.toEditText(body)
        editing = true
        Qt.callLater(function () { editArea.forceActiveFocus() })
    }
    function saveEdit() {
        if (editArea.text.trim() !== "")
            card.answerEdited(editArea.text)
        editing = false
    }

    readonly property real pad: isAnswer ? 6 : 10
    height: content.y + (editing ? editArea.height : label.implicitHeight) + pad
            + (needsAnswer ? answerArea.height + 10 : 0)

    HoverHandler { id: hover }

    QuietCard {
        visible: !card.isAnswer
        anchors.fill: parent
        lit: card.hovered || card.editing || answerArea.activeFocus
        border.color: card.marked ? Qt.alpha(Theme.ringDone, 0.6) : lit ? Theme.hairlineStrong : Theme.hairline
        Rectangle {                             // marks the entry that was jumped to
            visible: card.marked
            anchors.fill: parent
            radius: parent.radius
            color: Qt.alpha(Theme.ringDone, 0.10)
        }
    }
    Rectangle {                                 // an answer hangs off its question by a thin line
        visible: card.isAnswer
        x: 12
        y: 2
        width: 2
        height: parent.height - 4
        radius: 1
        color: Qt.alpha(Theme.info, 0.6)
    }

    QuoteLine {
        id: quoteLine
        visible: card.quote !== ""
        x: 12
        y: 10
        width: parent.width - 24
        text: card.quote
        barColor: Theme.highlightBar(card.quoteColor)
    }

    Item {
        id: content
        x: 12 + card.indent
        y: quoteLine.visible ? quoteLine.y + quoteLine.height + 8 : card.pad
        width: parent.width - x - 12
    }
    ReferenceText {
        id: label
        visible: !card.editing
        x: content.x
        y: content.y
        width: content.width
        source: card.body
        controller: card.controller
        font.pixelSize: 13
        font.bold: card.isQuestion
        baseColor: card.isAnswer ? Qt.lighter(Theme.textMuted, 1.15) : Theme.text
    }
    NoteTextArea {                              // editing an answer (Ctrl+Enter saves, Esc cancels)
        id: editArea
        autoGrow: true
        visible: card.editing
        x: content.x
        y: content.y - 2
        width: content.width
        placeholderText: "Edit the answer..."
        references: card.controller
        onSubmitted: card.saveEdit()
        onCancelled: card.editing = false
    }

    // not answered yet: type the answer right here
    Rectangle {
        visible: card.needsAnswer
        x: 12
        y: answerArea.y
        width: 2
        height: answerArea.height
        radius: 1
        color: Qt.alpha(Theme.info, 0.6)
    }
    NoteTextArea {
        id: answerArea
        autoGrow: true
        visible: card.needsAnswer
        x: 22
        y: label.y + label.height + 10
        width: parent.width - x - 10
        placeholderText: "Write an answer... (Ctrl+Enter)"
        references: card.controller
        onSubmitted: {
            if (text.trim() === "") return
            card.answerSubmitted(text)
            text = ""
        }
        onCancelled: focus = false
    }

    ClickHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint) => card.menuRequested(eventPoint.position)
    }
}
