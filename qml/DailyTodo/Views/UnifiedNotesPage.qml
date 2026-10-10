import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The unified view of a PDF / presentation: every note and question written about it on one page,
// in reading order (what belongs to no page first, then page by page, a question followed by its
// answers).
//   search   type to jump to the first note or question that contains the text; Enter / Shift+Enter
//            (or the arrows) step through the others. Ctrl+F focuses the field.
//   filter   all / notes / questions / unanswered questions
//   go to    a page heading and every card open the document at that page; the top button goes back
//            to where it was left
// Read-only: notes are written and edited in the document's own tab.
Item {
    id: view

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    // Set by the tab that hosts this page.
    property string title
    property int resourceId: -1

    property string filter: "all"            // all | notes | questions | unanswered
    property var rows: []                    // page headings and threads (controller.unifiedNotes)
    property int noteCount: 0
    property int questionCount: 0
    property int unansweredCount: 0

    property string query: ""
    property var matches: []                 // indexes (into rows) of the threads that contain the query
    property int matchPos: -1                // which of the matches is the current one
    readonly property int currentRow: matchPos >= 0 && matchPos < matches.length ? matches[matchPos] : -1

    function refresh() {
        if (resourceId < 0) return
        const r = controller.unifiedNotes(resourceId, filter)
        rows = r.rows
        noteCount = r.notes
        questionCount = r.questions
        unansweredCount = r.unanswered
        findMatches(false)
    }
    // Notes are written in the document's tab: look again whenever this page comes into view.
    onResourceIdChanged: refresh()
    onFilterChanged: refresh()
    onVisibleChanged: if (visible) refresh()

    function findMatches(jump) {
        const term = query.trim().toLowerCase()
        const found = []
        if (term !== "") {
            for (let i = 0; i < rows.length; i++) {
                const r = rows[i]
                if (r.kind !== "thread") continue
                const hay = (r.text + " " + r.quote + " " + r.answers.map(a => a.text).join(" ")).toLowerCase()
                if (hay.indexOf(term) >= 0) found.push(i)
            }
        }
        const before = currentRow
        matches = found
        // stay on the same card when the list is rebuilt, else start at the first match
        const keep = found.indexOf(before)
        matchPos = found.length === 0 ? -1 : keep >= 0 && !jump ? keep : 0
        if (jump) scrollToMatch()
    }
    function step(delta) {
        if (matches.length === 0) return
        matchPos = (matchPos + delta + matches.length) % matches.length
        scrollToMatch()
    }
    function scrollToMatch() {
        if (currentRow < 0) return
        list.positionViewAtIndex(currentRow, ListView.Center)
        // cards differ in height, so the first jump over many of them can land short: once more
        Qt.callLater(() => list.positionViewAtIndex(view.currentRow, ListView.Center))
    }
    function openAt(page) { controller.openResourceAtPage(resourceId, page) }

    FocusClearTapHandler { hostWindow: view.Window.window }

    Shortcut {
        sequences: [StandardKey.Find]
        enabled: view.visible
        onActivated: {
            searchField.forceActiveFocus()
            searchField.selectAll()
        }
    }

    // ------------------------------------------------------------------ top bar
    ColumnLayout {
        id: bar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8
        width: Math.min(780, parent.width - 48)
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Unified view"
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: Theme.text
                }
                Text {
                    text: view.title
                    font.pixelSize: 13
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            AppButton {
                text: "Back to document"
                raised: true
                onClicked: view.openAt(0)
            }
        }

        // search, with the way through the matches
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            AppTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search notes and questions  (Ctrl+F)"
                onTextChanged: {
                    view.query = text
                    view.findMatches(true)
                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        view.step((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        text = ""
                        view.Window.window.contentItem.forceActiveFocus()
                        event.accepted = true
                    }
                }
            }
            Text {
                visible: view.query.trim() !== ""
                text: view.matches.length === 0 ? "No match" : (view.matchPos + 1) + " / " + view.matches.length
                font.pixelSize: 12
                color: view.matches.length === 0 ? Theme.textFaint : Theme.textMuted
                Layout.minimumWidth: 52
                horizontalAlignment: Text.AlignRight
            }
            IconButton {
                iconSource: Theme.iconChevronUp
                fallbackText: "↑"
                enabled: view.matches.length > 1
                onClicked: view.step(-1)
            }
            IconButton {
                iconSource: Theme.iconChevronDown
                fallbackText: "↓"
                enabled: view.matches.length > 1
                onClicked: view.step(1)
            }
        }

        // what to show
        Row {
            spacing: 6
            Repeater {
                model: [
                    { key: "all", text: "All", count: view.noteCount + view.questionCount },
                    { key: "notes", text: "Notes", count: view.noteCount },
                    { key: "questions", text: "Questions", count: view.questionCount },
                    { key: "unanswered", text: "Unanswered", count: view.unansweredCount }
                ]
                AppButton {
                    required property var modelData
                    compact: true
                    text: modelData.text + "  " + modelData.count
                    active: view.filter === modelData.key
                    onClicked: view.filter = modelData.key
                }
            }
        }
    }

    // ------------------------------------------------------------------ nothing to show
    Text {
        visible: view.rows.length === 0
        anchors.centerIn: parent
        text: view.filter === "all" ? "Nothing written about this yet.\nNotes and questions you add in the document show up here."
                                    : "Nothing matches this filter."
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 14
        color: Theme.textFaint
    }

    // ------------------------------------------------------------------ the list
    ListView {
        id: list
        anchors.top: bar.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(780, parent.width - 48) + 16        // the scroll bar goes in the extra room
        clip: true
        spacing: 0
        model: view.rows
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 24
        ScrollBar.vertical: AppScrollBar {}

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool isPage: modelData.kind === "page"
            readonly property bool isMatch: view.matches.indexOf(index) >= 0
            readonly property bool isCurrent: index === view.currentRow

            width: ListView.view.width - 16
            height: isPage ? pageHeading.height : card.height + 10

            // ---- a page heading ----
            RowLayout {
                id: pageHeading
                visible: row.isPage
                width: parent.width
                height: row.isPage ? 56 : 0
                spacing: 10

                Text {
                    text: row.modelData.label || ""
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: Theme.text
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 10
                }
                PillLabel {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 10
                    text: {
                        const n = row.modelData.notes || 0, q = row.modelData.questions || 0
                        const parts = []
                        if (n > 0) parts.push(n + (n === 1 ? " NOTE" : " NOTES"))
                        if (q > 0) parts.push(q + (q === 1 ? " QUESTION" : " QUESTIONS"))
                        return parts.join("  ·  ")
                    }
                }
                Item { Layout.fillWidth: true }
                AppButton {
                    visible: (row.modelData.page || 0) > 0
                    compact: true
                    text: "Go to page"
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 6
                    onClicked: view.openAt(row.modelData.page)
                }
            }

            // ---- a note, or a question with its answers ----
            Item {
                id: card
                visible: !row.isPage
                width: parent.width
                height: row.isPage ? 0 : cardColumn.implicitHeight + 28

                HoverHandler { id: cardHover }
                QuietCard {
                    anchors.fill: parent
                    radius: 14
                    lit: cardHover.hovered || row.isCurrent
                    border.color: row.isCurrent ? Theme.accent
                                : row.isMatch ? Qt.alpha(Theme.accent, 0.5)
                                : lit ? Theme.hairlineStrong : Theme.hairline
                    border.width: row.isCurrent ? 2 : 1
                }
                ColumnLayout {
                    id: cardColumn
                    x: 16
                    y: 14
                    width: parent.width - 32
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        PillLabel {
                            text: row.modelData.isQuestion ? "QUESTION" : "NOTE"
                            tint: row.modelData.isQuestion ? Theme.accent : Theme.text
                        }
                        PillLabel {
                            visible: row.modelData.isQuestion === true
                            text: row.modelData.answered ? "ANSWERED" : "OPEN"
                            tint: row.modelData.answered ? Theme.ringDone : Theme.warning
                        }
                        Item { Layout.fillWidth: true }
                        IconButton {
                            visible: !row.isPage && (row.modelData.page || 0) > 0
                            opacity: cardHover.hovered ? 1 : 0
                            iconSource: Theme.iconExternal
                            fallbackText: "↗"
                            compact: true
                            onClicked: view.openAt(row.modelData.page)
                            AppToolTip {
                                text: "Open at this page"
                                shown: parent.hovered
                            }
                        }
                    }

                    QuoteLine {
                        visible: (row.modelData.quote || "") !== ""
                        Layout.fillWidth: true
                        text: row.modelData.quote || ""
                        barColor: Theme.highlightBar(row.modelData.quoteColor || "yellow")
                    }

                    ReferenceText {
                        Layout.fillWidth: true
                        controller: view.controller
                        source: row.modelData.body || ""
                        font.pixelSize: 14
                        font.weight: row.modelData.isQuestion ? Font.DemiBold : Font.Normal
                        baseColor: Theme.text
                    }

                    // the answers, indented under a bar
                    Repeater {
                        model: row.modelData.answers || []
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            spacing: 10
                            Rectangle {
                                Layout.fillHeight: true
                                width: 2
                                radius: 1
                                color: Qt.alpha(Theme.ringDone, 0.6)
                            }
                            ReferenceText {
                                Layout.fillWidth: true
                                controller: view.controller
                                source: modelData.body
                                font.pixelSize: 13
                                baseColor: Theme.textMuted
                            }
                        }
                    }
                }
            }
        }
    }
}
