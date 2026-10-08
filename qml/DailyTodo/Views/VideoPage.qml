import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// A video (a YouTube link) in its own tab. The video is watched in the browser; this is where what
// you think of it is kept, in three columns like a PDF's tab:
//   left   - the video (its picture and name; click it to watch) and its connections
//   centre - its moments: a ruler of the whole video with a bead per moment, and under it every
//            moment in order on a timeline like the Overview's, with what was written at it; each
//            moment can be watched from (the video opens at that time) or added to
//   right  - the notes and Q&A about the whole video (global)
// Press N to write a note and Q to ask a question: the box asks for the timestamp first (Tab moves
// on to the text), and the entry shows up at its moment.
Item {
    id: view

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    // Set by the tab that hosts this page.
    property string title
    property string uri
    property int resourceId: -1
    property int startPage: 0                // > 0: opened to show the notes at this timestamp

    property var session: null
    onResourceIdChanged: {
        if (resourceId >= 0 && session === null) {
            session = controller.createNotesSession(resourceId)
            session.loadNow(1)
            if (startPage > 0) Qt.callLater(() => goToPage(startPage))
        }
    }
    Component.onDestruction: if (session) session.dispose()

    readonly property var moments: session ? session.timeline : []

    // ---- the preview picture ----
    property url thumbnail: ""
    property string thumbnailError: ""
    onUriChanged: if (uri !== "") thumbnail = controller.thumbnailFor(uri)
    Connections {
        target: view.controller
        function onThumbnailReady(link, fileUrl, error) {
            if (link !== view.uri) return
            view.thumbnail = fileUrl
            view.thumbnailError = error
        }
    }

    // ---- the floating box ----
    property bool noteBoxOpen: false
    property string boxKind: "note"          // note | question
    property int editingNoteId: -1           // >= 0: the box edits that entry instead of adding one
    property bool boxGlobal: false           // new note/question: global (no timestamp)
    property int lastTime: 0                 // the timestamp used last: the next box starts with it
    readonly property bool askForTime: editingNoteId < 0 && !boxGlobal
    readonly property int typedTime: controller.timestampOf(boxTime.text)

    // Open the box. kind: "note" | "question"; opts: { editId, text } to edit an entry,
    // { time } to start at that moment, { global: true } for a global one.
    function openBox(kind, opts) {
        if (session === null) return
        const o = opts || {}
        boxKind = kind
        editingNoteId = o.editId !== undefined ? o.editId : -1
        boxGlobal = o.global === true
        const time = o.time !== undefined ? o.time : lastTime
        boxTime.text = time > 0 ? controller.timestampLabel(time) : ""
        noteBoxOpen = true
        noteBox.input.text = o.text || ""
        Qt.callLater(function () {
            // a time that is given is right: straight on to the text
            if (view.askForTime && o.time === undefined) { boxTime.forceActiveFocus(); boxTime.selectAll() }
            else noteBox.input.forceActiveFocus()
        })
    }
    function closeNoteBox() {
        noteBoxOpen = false
        editingNoteId = -1
        view.forceActiveFocus()
    }
    function saveNote() {
        const text = noteBox.input.text
        if (text.trim() === "") return
        if (editingNoteId >= 0) {
            session.editNote(editingNoteId, text)
        } else {
            if (!boxGlobal) {
                if (typedTime < 0) { boxTime.forceActiveFocus(); boxTime.selectAll(); return }
                lastTime = typedTime
                session.setPage(typedTime)            // the position the note is saved at
            }
            if (boxKind === "question") session.addQuestion(text, boxGlobal)
            else session.addNote(text, boxGlobal)
            if (!boxGlobal) Qt.callLater(() => goToPage(lastTime))
        }
        closeNoteBox()
    }

    Shortcut {
        sequence: "N"
        enabled: view.visible && !view.noteBoxOpen
        onActivated: view.openBox("note")
    }
    Shortcut {
        sequence: "Q"
        enabled: view.visible && !view.noteBoxOpen
        onActivated: view.openBox("question")
    }

    // ---- the moments ----
    property int markedTime: -1               // the moment that was jumped to (lit up for a while)
    Timer { id: markTimer; interval: 2600; onTriggered: view.markedTime = -1 }

    // Scroll to a timestamp (or the nearest moment before it) and light it up.
    function goToPage(seconds) {
        let target = -1
        for (let i = 0; i < moments.length; i++) {
            if (moments[i].time <= seconds) target = i
        }
        if (target < 0 && moments.length > 0) target = 0
        if (target >= 0) showMoment(target)
    }
    function showMoment(index) {
        markedTime = moments[index].time
        markTimer.restart()
        momentList.positionViewAtIndex(index, ListView.Beginning)
    }
    function watchAt(seconds) { controller.openVideoAt(uri, seconds) }

    // "12 notes · 2 questions" for one moment (answers don't count)
    function summary(group) {
        let notes = 0, questions = 0
        for (const e of group.entries) {
            if (e.isQuestion) questions++
            else if (e.parentId <= 0) notes++
        }
        const parts = []
        if (notes > 0) parts.push(notes + (notes === 1 ? " note" : " notes"))
        if (questions > 0) parts.push(questions + (questions === 1 ? " question" : " questions"))
        return parts.join("  ·  ")
    }
    // "4 min later", "1 h 5 min later"
    function gapLabel(seconds) {
        const minutes = Math.round(seconds / 60)
        if (minutes < 60) return minutes + " min later"
        const h = Math.floor(minutes / 60), m = minutes % 60
        return h + " h" + (m > 0 ? " " + m + " min" : "") + " later"
    }

    // ---- menus (right-click on an entry) ----
    function showEntryMenu(entry, position, isGlobal) {
        const menu = isGlobal ? globalMenu : localMenu
        const p = entry.mapToItem(view, position.x, position.y)
        menu.entry = entry
        menu.popup(p.x, p.y)
    }
    CrudMenu {
        id: localMenu
        property Item entry
        onEditTriggered: entry.edit()
        onDeleteTriggered: view.session.deleteNote(entry.noteId)
        AppMenuItem {
            text: "Change timestamp..."
            onTriggered: timePrompt.ask(localMenu.entry.noteId, true)
        }
        AppMenuItem {
            text: "Move to global"
            onTriggered: view.session.moveToGlobal(localMenu.entry.noteId)
        }
    }
    CrudMenu {
        id: globalMenu
        property Item entry
        onEditTriggered: entry.edit()
        onDeleteTriggered: view.session.deleteNote(entry.noteId)
        AppMenuItem {
            text: "Pin to a moment..."
            onTriggered: timePrompt.ask(globalMenu.entry.noteId, false)
        }
    }

    // Asks for the timestamp an entry should move to.
    AppDialog {
        id: timePrompt
        property int noteId: -1
        property bool moving: true
        readonly property int typed: view.controller.timestampOf(timeInput.text)

        function ask(id, changing) {
            noteId = id
            moving = changing
            timeInput.text = ""
            open()
        }
        function confirm() {
            if (typed < 0) return
            view.session.moveToPage(noteId, typed)
            view.lastTime = typed
            close()
            Qt.callLater(() => view.goToPage(typed))
        }

        width: 340
        onOpened: timeInput.forceActiveFocus()

        contentItem: ColumnLayout {
            spacing: 14
            DialogTitle { text: timePrompt.moving ? "Move to which moment?" : "Pin to which moment?" }
            RowLayout {
                spacing: 10
                AppTextField {
                    id: timeInput
                    Layout.fillWidth: true
                    placeholderText: "1:05   1h2m3s   105"
                    onAccepted: timePrompt.confirm()
                }
                CapsLabel {
                    text: timePrompt.typed >= 0 ? "= " + view.controller.timestampLabel(timePrompt.typed) : ""
                }
            }
            RowLayout {
                spacing: 8
                Item { Layout.fillWidth: true }
                AppButton { text: "Cancel"; onClicked: timePrompt.close() }
                AppButton {
                    text: "Move"
                    filled: true
                    enabled: timePrompt.typed >= 0
                    onClicked: timePrompt.confirm()
                }
            }
        }
    }


    readonly property real columnGap: 20
    readonly property real centerWidth: Math.max(360, width * 0.46)
    readonly property real sideWidth: Math.max(160, (width - centerWidth) / 2 - columnGap)

    // ------------------------------------------------------------------ left column
    ColumnLayout {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 12
        anchors.leftMargin: 18
        width: view.sideWidth - 6
        spacing: 36

        VideoCard {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.preferredHeight: implicitHeight
            title: view.title
            uri: view.uri
            thumbnail: view.thumbnail
            thumbnailError: view.thumbnailError
            onWatchRequested: view.watchAt(0)
        }

        // the resources this one is connected to (it mentions them, or they mention it)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: "Connections"
                badge: view.session && view.session.connections.length > 0
                       ? String(view.session.connections.length) : ""
                size: 22
            }
            ResourceGraph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                centerName: view.title
                centerId: view.resourceId
                onMenuRequested: (id, item, position) => view.actions.showMenu(id, item, position.x, position.y)
                connections: view.session ? view.session.connections : []
                onNodeClicked: (id) => view.controller.openResourceById(id)
            }
        }
    }

    // ----------------------------------------------------------------- centre column: moments
    ColumnLayout {
        id: centre
        width: view.centerWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 12
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            SectionTitle {
                text: "Moments"
                badge: view.moments.length > 0 ? String(view.moments.length) : ""
                Layout.fillWidth: true
            }
            CapsLabel {
                visible: view.moments.length > 0
                text: "In the order of the video"
                color: Theme.textFaint
            }
        }

        MomentScrubber {
            Layout.fillWidth: true
            Layout.topMargin: 4
            moments: view.moments
            current: view.markedTime
            onPicked: (index) => view.showMoment(index)
        }

        ListView {
            id: momentList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: view.moments
            bottomMargin: view.noteBoxOpen ? noteBox.height + 32 : 24
            topMargin: 10
            ScrollBar.vertical: AppScrollBar {}

            // the timeline's gutter: the ruler runs down at rulerX, the times sit on it
            readonly property real rulerX: 44
            readonly property real contentX: 96

            delegate: Item {
                id: moment
                required property int index
                required property var modelData
                readonly property bool lit: view.markedTime === modelData.time
                readonly property bool first: index === 0
                readonly property bool last: index === view.moments.length - 1
                readonly property real gapHeight: modelData.longGap ? 44 : 0
                readonly property real headerY: gapHeight + 14       // middle of the time dial

                width: ListView.view.width
                height: entries.y + entries.height + 26

                // the ruler: solid, but dotted across a long stretch of the video
                Rectangle {
                    visible: !moment.first
                    x: momentList.rulerX
                    width: 1
                    height: moment.gapHeight > 0 ? 0 : moment.headerY
                    color: Theme.hairlineStrong
                }
                Repeater {
                    model: moment.gapHeight > 0 ? Math.floor(moment.headerY / 7) : 0
                    Rectangle {
                        required property int index
                        x: momentList.rulerX - 1
                        y: index * 7 + 2
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Theme.hairlineStrong
                    }
                }
                CapsLabel {
                    visible: moment.gapHeight > 0
                    x: momentList.rulerX + 16
                    y: moment.gapHeight / 2 - height / 2 + 2
                    text: moment.first || moment.gapHeight === 0 ? ""
                          : view.gapLabel(moment.modelData.time - view.moments[moment.index - 1].time)
                    color: Theme.textFaint
                }
                Rectangle {
                    visible: !moment.last
                    x: momentList.rulerX
                    y: moment.headerY
                    width: 1
                    height: moment.height - y
                    color: Theme.hairlineStrong
                }

                // the time dial, on the ruler: a small raised pill (green while lit up)
                AppButton {
                    id: dial
                    x: momentList.rulerX - width / 2
                    y: moment.headerY - height / 2
                    compact: true
                    implicitHeight: 28
                    leftPadding: 10
                    rightPadding: 10
                    raised: true
                    filled: moment.lit
                    text: moment.modelData.label
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.serifFont
                    onClicked: view.watchAt(moment.modelData.time)
                    AppToolTip {
                        text: "Watch from " + moment.modelData.label
                        shown: dial.hovered
                    }
                }
                // a hairline from the dial to the summary
                Rectangle {
                    x: dial.x + dial.width + 4
                    y: moment.headerY
                    width: Math.max(0, momentList.contentX - 8 - x)
                    height: 1
                    color: Theme.hairlineStrong
                }

                // what is there, and what to do here
                RowLayout {
                    x: momentList.contentX
                    width: moment.width - x - 8
                    y: moment.headerY - height / 2
                    spacing: 4
                    CapsLabel {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: view.summary(moment.modelData)
                        color: moment.lit ? Theme.ringDone : Theme.textMuted
                    }
                    IconButton {
                        id: watchHere
                        compact: true
                        iconSource: Theme.iconPlay
                        iconSize: 13
                        textColor: Theme.textMuted
                        onClicked: view.watchAt(moment.modelData.time)
                        AppToolTip { text: "Watch from here"; shown: watchHere.hovered }
                    }
                    IconButton {
                        id: addHere
                        compact: true
                        iconSource: Theme.iconPlus
                        textColor: Theme.textMuted
                        onClicked: view.openBox("note", { time: moment.modelData.time })
                        AppToolTip { text: "Note at " + moment.modelData.label; shown: addHere.hovered }
                    }
                }

                // everything written at this moment
                Column {
                    id: entries
                    x: momentList.contentX
                    y: moment.headerY + 22
                    width: moment.width - x - 8
                    spacing: 6

                    Repeater {
                        model: moment.modelData.entries
                        EntryCard {
                            id: entry
                            required property var modelData
                            width: entries.width
                            controller: view.controller
                            noteId: modelData.noteId
                            body: modelData.body
                            isQuestion: modelData.isQuestion
                            answered: modelData.answered
                            parentId: modelData.parentId
                            marked: moment.lit
                            onEditRequested: view.openBox(isQuestion ? "question" : "note",
                                                          { editId: noteId, text: view.controller.toEditText(body) })
                            onAnswerSubmitted: (text) => view.session.addAnswer(noteId, text)
                            onAnswerEdited: (text) => view.session.editNote(noteId, text)
                            onMenuRequested: (position) => view.showEntryMenu(entry, position, false)
                        }
                    }
                }
            }

            // nothing written at a moment yet
            Column {
                visible: view.moments.length === 0
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 420)
                spacing: 12
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "No moments yet"
                    font.family: Theme.serifFont
                    font.pixelSize: 24
                    color: Theme.textMuted
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "While you watch, press N to note something at a moment of the video, or Q to "
                          + "ask a question about it. Every moment shows up here, in order."
                    font.pixelSize: 13
                    color: Theme.textFaint
                }
            }
        }
    }

    // ----------------------------------------------------------------- right column: global
    GlobalNotes {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 12
        anchors.topMargin: 18
        width: view.sideWidth
        session: view.session
        emptyNotes: "Notes about the whole video, not one moment: choose Global in the box"
        emptyQuestions: "Questions about the whole video: choose Global in the box"
        delegate: EntryCard {
            id: globalEntry
            width: ListView.view.width
            controller: view.controller
            onEditRequested: view.openBox(isQuestion ? "question" : "note",
                                          { editId: noteId, text: view.controller.toEditText(body) })
            onAnswerSubmitted: (text) => view.session.addAnswer(noteId, text)
            onAnswerEdited: (text) => view.session.editNote(noteId, text)
            onMenuRequested: (position) => view.showEntryMenu(globalEntry, position, true)
        }
    }

    // ------------------------------------------- floating box (N: note, Q: question)
    NoteBox {
        id: noteBox
        visible: view.noteBoxOpen
        z: 10
        width: view.centerWidth - 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        controller: view.controller
        kind: view.boxKind
        editing: view.editingNoteId >= 0
        hint: view.askForTime ? "Tab: on to the text  |  Ctrl+Enter: save  |  Esc: cancel"
                              : "Ctrl+Enter: save  |  Esc: cancel"
        onCancelled: view.closeNoteBox()
        onSubmitted: view.saveNote()

        // at a moment, or global (about the whole video)
        SegmentedSwitch {
            visible: view.editingNoteId < 0
            leftText: "Moment"
            rightText: "Global"
            rightActive: view.boxGlobal
            onToggledTo: (right) => {
                view.boxGlobal = right
                // a click takes the focus away: give it back
                Qt.callLater(function () {
                    if (view.askForTime) { boxTime.forceActiveFocus(); boxTime.selectAll() }
                    else noteBox.input.forceActiveFocus()
                })
            }
        }
        CapsLabel {
            visible: view.askForTime
            text: "At"
        }
        AppTextField {
            id: boxTime
            visible: view.askForTime
            implicitWidth: 84
            implicitHeight: 26
            font.pixelSize: 13
            font.bold: true
            horizontalAlignment: TextInput.AlignHCenter
            leftPadding: 4
            rightPadding: 4
            placeholderText: "0:00"
            onAccepted: noteBox.input.forceActiveFocus()
            Keys.onTabPressed: noteBox.input.forceActiveFocus()
            Keys.onEscapePressed: view.closeNoteBox()
            onActiveFocusChanged: if (activeFocus) selectAll()
        }
        CapsLabel {                                     // what was understood: 105 -> 1:05
            visible: view.askForTime
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: boxTime.text.trim() === "" ? "type 1:05, 105 or 1h2m3s"
                  : view.typedTime >= 0 ? "= " + view.controller.timestampLabel(view.typedTime)
                                        : "not a timestamp"
            color: boxTime.text.trim() !== "" && view.typedTime < 0 ? Theme.danger : Theme.textFaint
        }
        Item { visible: !view.askForTime; Layout.fillWidth: true }
    }
}
