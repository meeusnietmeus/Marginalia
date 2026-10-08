import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// "Open questions": every question of the workspace that has no answer yet, as an inbox to work
// through.
//   left    the resources that have some, with how many ("All resources" on top), and a filter
//   right   their questions. Two ways to go through them:
//           - List: every question on a card, under its resource and page, answered right there
//           - One by one: a single question in the middle, the answer box ready; answering (or
//             skipping) brings the next one
// "Open at page" shows a question where it was asked (the PDF at its page, the video at its time).
Item {
    id: view

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)
    readonly property var oq: controller.openQuestions

    property bool oneByOne: false
    property int reviewIndex: 0              // which question "one by one" is at

    // Notes are written from the document tabs too, so look again whenever this page comes into view.
    onVisibleChanged: if (visible) view.oq.refresh()
    Component.onCompleted: view.oq.refresh()

    function openAt(resourceId, pageNumber) { controller.openResourceAtPage(resourceId, pageNumber || 0) }
    function sectionParts(section) {          // "<id>|<page label>|<kind>|<name>"
        const parts = section.split("|")
        return { id: parseInt(parts[0]), label: parts[1], kind: parts[2], name: parts.slice(3).join("|") }
    }

    FocusClearTapHandler { hostWindow: view.Window.window }

    // ------------------------------------------------------------------ nothing open
    Column {
        visible: view.oq.total === 0
        anchors.centerIn: parent
        spacing: 14
        Item {                                   // a big green bead with a tick, like a done todo
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64
            height: 64
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.ringDone, 1.15) }
                    GradientStop { position: 1; color: Theme.accentBottom }
                }
                border.color: Qt.darker(Theme.accentBottom, 1.2)
            }
            IconImage {
                anchors.centerIn: parent
                source: Theme.iconSave
                sourceSize: Qt.size(30, 30)
                color: Theme.window
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No open questions"
            font.family: Theme.serifFont
            font.pixelSize: 28
            color: Theme.text
        }
        CapsLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Every question has an answer. Ask one with Q in a document"
            color: Theme.textFaint
        }
    }

    // ------------------------------------------------------------------ left: the resources
    ColumnLayout {
        id: side
        visible: view.oq.total > 0
        x: 22
        y: 14
        width: 300
        height: parent.height - y - 18
        spacing: 10

        SectionTitle {
            text: "Open questions"
            badge: String(view.oq.total)
        }
        CapsLabel {
            text: "In " + resourceList.count + (resourceList.count === 1 ? " resource" : " resources")
            color: Theme.textFaint
        }
        AppTextField {
            id: resourceFilter
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: 32
            placeholderText: "Filter resources..."
            Keys.onEscapePressed: { text = ""; focus = false }
        }

        // "All resources", then each one with its count
        ResourceRow {
            Layout.fillWidth: true
            Layout.topMargin: 4
            allRow: true
            name: "All resources"
            count: view.oq.total
            selected: view.oq.selectedResourceId < 0
            onPicked: view.oq.select(-1)
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            implicitHeight: 1
            color: Theme.hairline
        }
        ListView {
            id: resourceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: view.oq.resources
            ScrollBar.vertical: AppScrollBar {}

            delegate: ResourceRow {
                required property int resourceId
                required name                    // ResourceRow's own, filled in from the model
                required count
                required property string kind
                required property bool missing
                readonly property string filter: resourceFilter.text.trim().toLowerCase()
                width: ListView.view.width
                visible: filter === "" || name.toLowerCase().indexOf(filter) >= 0
                height: visible ? implicitHeight : -resourceList.spacing
                resourceKind: kind
                resourceMissing: missing
                selected: view.oq.selectedResourceId === resourceId
                onPicked: view.oq.select(resourceId)
                onMenuRequested: (item, position) => view.actions.showMenu(resourceId, item, position.x, position.y)
            }
        }
    }

    // one row of the resource list: a raised card, lit when picked
    component ResourceRow: Item {
        id: resourceRow
        property bool allRow: false
        property string name
        property string resourceKind
        property bool resourceMissing: false
        property int count: 0
        property bool selected: false
        signal picked()
        signal menuRequested(Item item, point position)

        implicitHeight: 50
        readonly property bool lit: selected || rowHover.hovered

        Surface {
            anchors.fill: parent
            radius: 14
            elevation: resourceRow.selected ? 1 : 0
            lit: resourceRow.lit
            topColor: resourceRow.selected ? Theme.panelRaised : Qt.alpha(Theme.panelRaised, rowHover.hovered ? 0.8 : 0.45)
            bottomColor: resourceRow.selected ? Theme.panel : Qt.alpha(Theme.panel, rowHover.hovered ? 0.8 : 0.45)
        }
        Rectangle {                              // the picked one: a green mark at its edge
            visible: resourceRow.selected
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - 22
            radius: 1.5
            color: Theme.ringDone
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10
            KindTile {
                visible: !resourceRow.allRow
                kind: resourceRow.resourceKind
                missing: resourceRow.resourceMissing
            }
            Rectangle {                          // "All": a stack of three bars
                visible: resourceRow.allRow
                implicitWidth: 22
                implicitHeight: 22
                radius: 7
                color: Qt.alpha(Theme.text, 0.08)
                border.color: Theme.hairlineStrong
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: 3
                        Rectangle { width: 10; height: 2; radius: 1; color: Theme.textMuted }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: resourceRow.name
                elide: Text.ElideRight
                font.pixelSize: 13
                font.weight: resourceRow.selected ? Font.DemiBold : Font.Normal
                color: Theme.text
            }
            PillLabel {
                text: String(resourceRow.count)
                tint: Theme.warning
                textColor: Theme.warning
            }
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        ClickHandler { onTapped: resourceRow.picked() }
        ClickHandler {
            enabled: !resourceRow.allRow
            acceptedButtons: Qt.RightButton
            onTapped: (eventPoint) => resourceRow.menuRequested(resourceRow, eventPoint.position)
        }
    }

    // ------------------------------------------------------------------ right: the questions
    Item {
        id: main
        visible: view.oq.total > 0
        anchors.left: side.right
        anchors.leftMargin: 40
        anchors.right: parent.right
        anchors.rightMargin: 28
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        readonly property bool single: view.oq.selectedResourceId >= 0
        readonly property real contentWidth: Math.min(width, 820)

        // the heading: what is shown, how many, and how to go through them
        RowLayout {
            id: heading
            x: 0
            y: 14
            width: main.contentWidth
            spacing: 12
            Column {
                Layout.fillWidth: true
                spacing: 2
                SectionTitle {
                    width: parent.width
                    text: main.single ? view.oq.selectedName : "All questions"
                }
                CapsLabel {
                    text: view.oq.shownCount + (view.oq.shownCount === 1 ? " to answer" : " to answer")
                          + (main.single ? "" : "  ·  most first")
                    color: Theme.textFaint
                }
            }
            AppButton {
                visible: main.single && view.oq.selectedCanOpen
                compact: true
                raised: true
                text: "Open"
                onClicked: view.openAt(view.oq.selectedResourceId, 0)
            }
            SegmentedSwitch {
                leftText: "List"
                rightText: "One by one"
                rightActive: view.oneByOne
                onToggledTo: (right) => {
                    view.oneByOne = right
                    view.reviewIndex = 0
                }
            }
        }

        // ---- List: every question on a card, under its resource and page ----
        ListView {
            id: questionList
            visible: !view.oneByOne
            x: 0
            y: heading.y + heading.height + 18
            width: main.contentWidth
            height: main.height - y
            clip: true
            spacing: 10
            bottomMargin: 24
            boundsBehavior: Flickable.StopAtBounds
            model: view.oq.questions
            ScrollBar.vertical: AppScrollBar {}

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
                id: sectionHead
                required property string section
                readonly property var parts: view.sectionParts(section)
                width: ListView.view.width
                height: 44

                Row {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    spacing: 8
                    KindTile {
                        visible: !main.single
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        height: 18
                        kind: sectionHead.parts.kind
                    }
                    Text {
                        visible: !main.single
                        anchors.verticalCenter: parent.verticalCenter
                        text: sectionHead.parts.name
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    CapsLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (main.single ? "" : "·  ") + sectionHead.parts.label
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    x: 0
                    width: parent.width
                    height: 1
                    color: Theme.hairline
                }
            }

            // one question: the question, an answer box, and what can be done
            delegate: Item {
                id: card
                width: ListView.view.width
                required property int noteId
                required property string body
                required property int page
                required property string pageLabel
                required property int resourceId
                property bool editing: false

                function startEdit() {
                    editArea.text = view.controller.toEditText(body)
                    editing = true
                    Qt.callLater(() => editArea.forceActiveFocus())
                }
                function saveEdit() {
                    if (editArea.text.trim() !== "") view.oq.edit(noteId, editArea.text)
                    editing = false
                }
                function answer() {
                    if (answerArea.text.trim() === "") return
                    view.oq.answer(noteId, answerArea.text)
                }

                height: column.implicitHeight + 28

                HoverHandler { id: cardHover }
                QuietCard {
                    anchors.fill: parent
                    radius: 16
                    lit: cardHover.hovered || answerArea.activeFocus || card.editing
                }
                ColumnLayout {
                    id: column
                    x: 16
                    y: 14
                    width: parent.width - 32
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ReferenceText {
                            visible: !card.editing
                            Layout.fillWidth: true
                            source: card.body
                            controller: view.controller
                            font.pixelSize: 14
                            font.bold: true
                            baseColor: Theme.text
                        }
                        NoteTextArea {
                            id: editArea
                            visible: card.editing
                            Layout.fillWidth: true
                            autoGrow: true
                            references: view.controller
                            placeholderText: "Edit the question..."
                            onSubmitted: card.saveEdit()
                            onCancelled: card.editing = false
                        }
                        // shown on hover: go there, edit
                        IconButton {
                            id: goButton
                            Layout.alignment: Qt.AlignTop
                            compact: true
                            opacity: cardHover.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            iconSource: Theme.iconInApp
                            textColor: Theme.textMuted
                            onClicked: view.openAt(card.resourceId, card.page)
                            AppToolTip { text: card.page > 0 ? "Open at " + card.pageLabel.toLowerCase() : "Open"; shown: goButton.hovered }
                        }
                        IconButton {
                            id: editButton
                            Layout.alignment: Qt.AlignTop
                            compact: true
                            opacity: cardHover.hovered && !card.editing ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            iconSource: Theme.iconEdit
                            textColor: Theme.textMuted
                            onClicked: card.startEdit()
                            AppToolTip { text: "Edit"; shown: editButton.hovered }
                        }
                    }

                    // the answer, written right here
                    NoteTextArea {
                        id: answerArea
                        Layout.fillWidth: true
                        // one line until it is used
                        lines: activeFocus || text !== "" ? 3 : 1
                        autoGrow: true
                        references: view.controller
                        placeholderText: "Write an answer... (Ctrl+Enter)"
                        onSubmitted: card.answer()
                        onCancelled: focus = false
                    }
                    AppButton {
                        visible: answerArea.text.trim() !== ""
                        Layout.alignment: Qt.AlignRight
                        compact: true
                        filled: true
                        text: "Answer"
                        onClicked: card.answer()
                    }
                }

                ClickHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (eventPoint) => questionMenu.popup(eventPoint.position)
                }
                CrudMenu {
                    id: questionMenu
                    onEditTriggered: card.startEdit()
                    onDeleteTriggered: view.oq.delete(card.noteId)
                    AppMenuItem {
                        text: card.page > 0 ? "Open at " + card.pageLabel.toLowerCase() : "Open"
                        iconSource: Theme.iconInApp
                        onTriggered: view.openAt(card.resourceId, card.page)
                    }
                }
            }

        }

        // ---- One by one: a single question in the middle ----
        Item {
            id: review
            visible: view.oneByOne
            x: 0
            y: heading.y + heading.height + 18
            width: main.contentWidth
            height: main.height - y - 18

            readonly property int count: view.oq.shownCount
            readonly property int index: Math.min(view.reviewIndex, Math.max(0, count - 1))

            // how far along: "3 of 12" and a thin bar
            Row {
                id: progress
                width: parent.width
                spacing: 12
                CapsLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Question " + (review.index + 1) + " of " + review.count
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 160
                    height: 4
                    radius: 2
                    color: Theme.ringTrack
                    Rectangle {
                        width: parent.width * (review.count > 0 ? (review.index + 1) / review.count : 0)
                        height: parent.height
                        radius: 2
                        color: Theme.ringDone
                        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // the questions side by side; only the current one shows, sliding in
            ListView {
                id: deck
                y: progress.height + 18
                width: parent.width
                height: parent.height - y
                orientation: ListView.Horizontal
                interactive: false
                clip: true
                model: view.oq.questions
                currentIndex: review.index
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: 0
                preferredHighlightEnd: width
                highlightMoveDuration: 260

                delegate: Item {
                    id: slide
                    required property int index
                    required property int noteId
                    required property string body
                    required property int page
                    required property string pageLabel
                    required property int resourceId
                    required property string resourceName
                    required property string kind
                    readonly property bool current: ListView.isCurrentItem
                    width: deck.width
                    height: deck.height

                    function answer() {
                        if (answerBox.text.trim() === "") return
                        view.oq.answer(slide.noteId, answerBox.text)
                        // the answered question leaves the list: the same index is the next one
                    }
                    onCurrentChanged: if (current && view.oneByOne) Qt.callLater(() => answerBox.forceActiveFocus())

                    Surface {
                        id: reviewCard
                        width: parent.width
                        height: cardColumn.implicitHeight + 48
                        radius: 22
                    }
                    ColumnLayout {
                        id: cardColumn
                        x: 28
                        y: 24
                        width: parent.width - 56
                        spacing: 16

                        // where it was asked; click to go there
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                KindTile { anchors.verticalCenter: parent.verticalCenter; kind: slide.kind }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: slide.resourceName
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: Theme.text
                                }
                                CapsLabel {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "·  " + slide.pageLabel
                                }
                            }
                        }
                        ReferenceText {
                            Layout.fillWidth: true
                            source: slide.body
                            controller: view.controller
                            font.family: Theme.serifFont
                            font.pixelSize: 24
                            baseColor: Theme.text
                        }
                        NoteTextArea {
                            id: answerBox
                            Layout.fillWidth: true
                            lines: 4
                            autoGrow: true
                            references: view.controller
                            placeholderText: "Your answer..."
                            onSubmitted: slide.answer()
                            onCancelled: focus = false
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            CapsLabel {
                                Layout.fillWidth: true
                                text: "Ctrl+Enter: answer and go on"
                                color: Theme.textFaint
                            }
                            AppButton {
                                visible: view.oq.selectedCanOpen || !main.single
                                text: slide.page > 0 ? "Open at " + slide.pageLabel.toLowerCase() : "Open"
                                onClicked: view.openAt(slide.resourceId, slide.page)
                            }
                            AppButton {
                                text: "Skip"
                                raised: true
                                enabled: review.count > 1
                                onClicked: view.reviewIndex = (review.index + 1) % review.count
                            }
                            AppButton {
                                text: "Answer"
                                filled: true
                                enabled: answerBox.text.trim() !== ""
                                onClicked: slide.answer()
                            }
                        }
                    }
                }
            }
        }
    }
}
