import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Layouts
import QtQuick.Pdf
import QtQuick.Shapes
import QtQuick.Effects
import DailyTodo.Style
import DailyTodo.Controls

// A PDF in its own tab: three columns split 2/7 : 3/7 : 2/7.
//   left   - Global Notes / Global Q&A (top, nearly all the height), page + zoom indicator (bottom)
//   centre - the PDF itself: our own page list (PdfPageImage per page) with large gaps
//   right  - Notes and Q&A for the page being viewed
// Press N to write a note and Q to ask a question; the switch in the box makes it local (this
// page) or global (no page). A question without an answer shows a box to type the answer in.
Item {
    id: view

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    // Set by the tab that hosts this page.
    property string title
    property string uri                      // absolute path of the PDF
    property int resourceId: -1
    // False for a resource that is not a PDF (a web link, a Word file...): there are no pages to
    // scroll, so this is a notes tab where the page of a note is typed in.
    property bool hasDocument: true

    property int selectionPage: -1           // the page (0-based) whose text selection is the live one
    // A text box (note, answer, page field...) has the keyboard: copy/paste belong to it.
    readonly property bool textBoxFocused: {
        const item = Window.window ? Window.window.activeFocusItem : null
        return item !== null && typeof item.selectAll === "function"
    }

    // ---- highlights ----
    // Every highlight of this PDF ({ id, page, text, rects }): the pages draw their own.
    readonly property var highlightList: session ? session.highlights : []
    property int glowHighlight: -1           // the highlight to pulse (its note is being hovered)
    property string lastHighlightColor: "yellow"   // new highlights get the colour picked last
    // The text selected on a page once the mouse is released: { page (1-based), text, rects }.
    // Highlighting, noting or copying act on it. null when nothing is selected.
    property var activeSelection: null

    // The selection is dropped (every page clears its own when it is no longer the live one).
    function clearSelection() {
        activeSelection = null
        selectionPage = -2
    }
    // Highlight the selected passage for good. Returns the highlight's id, or -1.
    function highlightSelection() {
        const s = activeSelection
        if (!s || !session) return -1
        const id = session.addHighlight(s.page, s.text, s.rects, lastHighlightColor)
        if (id >= 0) clearSelection()
        return id
    }
    // Highlight the selection and start a note/question about it.
    function noteOnSelection(kind) {
        const s = activeSelection
        const id = highlightSelection()
        if (id >= 0) openBox(kind, { highlightId: id, quote: s.text, page: s.page,
                                      quoteColor: lastHighlightColor })
    }
    // The bounding box of every polygon of a selection, as [x, y, w, h] in PDF points. (QML cannot
    // read the points of a polygon, so Python does the measuring.)
    function rectsOf(geometry) {
        return session ? session.boundingRects(geometry) : []
    }
    property int currentPage: 1              // 1-based: the page near the top of the viewport
    readonly property int pageCount: doc.pageCount
    readonly property int maxPage: hasDocument ? Math.max(1, doc.pageCount) : 99999
    property real zoom: 1                    // 1 = page fits the column
    property bool dark: false                // invert the pages (see shaders/invert.frag)
    property bool noteBoxOpen: false
    property string boxKind: "note"          // what the floating box is writing: note | question
    property int editingNoteId: -1           // >= 0: the box edits that entry instead of adding one
    property bool boxGlobal: false           // new note/question: global (no page) instead of local
    property int boxHighlightId: -1          // >= 0: the new note/question is about this highlight
    property string boxQuote: ""
    property string boxQuoteColor: "yellow"
    property int boxPage: 0                  // the page a highlight-bound note will live on
    // The box asks which page a new local note is for (a resource without pages to scroll).
    readonly property bool askForPage: !hasDocument && editingNoteId < 0 && !boxGlobal
                                       && boxHighlightId < 0
    property bool wide: false                // give the PDF column more room (3/5 of the page)

    readonly property real columnGap: 20
    readonly property real centerWidth: Math.max(320, width * (wide ? 0.6 : 0.46))
    readonly property real sideWidth: Math.max(140, (width - centerWidth) / 2 - columnGap)
    readonly property real pageGap: 48       // empty space between two pages
    readonly property real pageMargin: 22    // room for the sheet's shadow
    readonly property real minZoom: 0.5
    readonly property real maxZoom: 4

    // The notes of this PDF; asks the database for a page's notes only once scrolling settles.
    property var session: null

    // A presentation shows its PDF, and what is written in it besides the slides (speaker notes
    // and comments, per slide; read-only: they belong to the .pptx).
    property var slideAnnotations: []
    readonly property bool isPresentation: resourceId >= 0 && controller.isPresentation(resourceId)
    readonly property var slideInfo: {
        for (const a of slideAnnotations) {
            if (a.slide === currentPage) return a
        }
        return null
    }
    onResourceIdChanged: {
        if (resourceId >= 0 && session === null) {
            session = controller.createNotesSession(resourceId)
            session.loadNow(currentPage)
            slideAnnotations = controller.presentationAnnotations(resourceId)
        }
        resumeIfReady()
    }
    onCurrentPageChanged: if (session) session.setPage(currentPage)
    Component.onDestruction: {
        saveProgress()
        if (session) session.dispose()
    }

    // "Continue where you left off": the page this PDF was closed on is stored in the client-side
    // database. Jump back to it once, as soon as the document is loaded and we know which it is.
    property bool resumed: false
    property int startPage: 0                // > 0: opened to show this page, whatever was saved
    function resumeIfReady() {
        if (resumed || resourceId < 0) return
        if (hasDocument && doc.status !== PdfDocument.Ready) return
        resumed = true
        const page = startPage > 0 ? startPage : controller.lastPdfPage(resourceId)
        if (!hasDocument) currentPage = Math.max(1, page)       // nothing to scroll: just the page
        else if (page > 1) Qt.callLater(() => goToPage(page))
    }
    // Written when the tab is closed (or the app quits). Never before the jump above has
    // happened, or a tab closed while still loading would overwrite the saved page with 1.
    function saveProgress() {
        if (resumed && resourceId >= 0 && (!hasDocument || doc.status === PdfDocument.Ready))
            controller.savePdfPage(resourceId, currentPage)
    }
    Connections {
        target: Qt.application
        function onAboutToQuit() { view.saveProgress() }
    }
    // An old .ppt is read by PowerPoint in the background: its notes arrive a moment after the tab.
    Connections {
        target: view.controller
        function onPresentationAnnotationsReady(id) {
            if (id === view.resourceId)
                view.slideAnnotations = view.controller.presentationAnnotations(id)
        }
    }
    PresentationInfoDialog { id: presentationInfo; controller: view.controller }

    function updateCurrentPage() {
        if (doc.pageCount === 0) return
        // The page at 30% of the viewport height: stable after jumping to a page (it sits at the
        // top), and it changes about when the next page has come well into view.
        let i = pages.indexAt(pages.contentX + pages.width / 2, pages.contentY + pages.height * 0.3)
        if (pages.atYEnd) i = doc.pageCount - 1     // the last page may never reach the middle
        if (i >= 0) currentPage = i + 1
    }

    function goToPage(page) {
        if (!hasDocument) {                      // no pages to scroll: only the page number changes
            currentPage = Math.max(1, Math.min(maxPage, page))
            return
        }
        const p = Math.max(1, Math.min(doc.pageCount, page))
        pages.positionViewAtIndex(p - 1, ListView.Beginning)
        updateCurrentPage()
    }

    // Zoom by `factor`, keeping the point under (mx, my) (viewport coordinates) where it is.
    function zoomBy(factor, mx, my) {
        const next = Math.max(minZoom, Math.min(maxZoom, zoom * factor))
        if (next === zoom) return
        const fx = (pages.contentX - pages.originX + mx) / pages.contentWidth
        const fy = (pages.contentY - pages.originY + my) / pages.contentHeight
        zoom = next
        Qt.callLater(function () {        // after the pages have been laid out at the new size
            pages.contentX = pages.originX + fx * pages.contentWidth - mx
            pages.contentY = pages.originY + fy * pages.contentHeight - my
            pages.returnToBounds()
            updateCurrentPage()
        })
    }

    // ---- Autoscroll: hold the middle button, move the pointer away from the marker to scroll
    // (faster the further away); releasing the button stops it.
    property bool autoScrolling: false
    property point autoOrigin: Qt.point(0, 0)
    property point autoPointer: Qt.point(0, 0)

    function startAutoScroll(p) {
        autoOrigin = p
        autoPointer = p
        autoScrolling = true
    }
    function stopAutoScroll() { autoScrolling = false }

    function autoSpeed(distance) {       // pixels per tick; a small dead zone around the marker
        const beyond = Math.abs(distance) - 12
        return beyond > 0 ? Math.sign(distance) * beyond * 0.12 : 0
    }

    Timer {
        interval: 16
        repeat: true
        running: view.autoScrolling
        onTriggered: {
            const minY = pages.originY
            const maxY = pages.originY + Math.max(0, pages.contentHeight - pages.height)
            pages.contentY = Math.max(minY, Math.min(maxY,
                pages.contentY + view.autoSpeed(view.autoPointer.y - view.autoOrigin.y)))
            const maxX = pages.originX + Math.max(0, pages.contentWidth - pages.width)
            pages.contentX = Math.max(pages.originX, Math.min(maxX,
                pages.contentX + view.autoSpeed(view.autoPointer.x - view.autoOrigin.x)))
        }
    }

    // Open the floating box. kind: "note" | "question".
    // opts: { editId, text } to edit an existing entry.
    function openBox(kind, opts) {
        if (session === null) return
        const o = opts || {}
        boxKind = kind
        editingNoteId = o.editId !== undefined ? o.editId : -1
        boxGlobal = false
        boxHighlightId = o.highlightId !== undefined ? o.highlightId : -1
        boxQuote = o.quote || ""
        boxQuoteColor = o.quoteColor || "yellow"
        boxPageField.text = String(currentPage)
        boxPage = o.page || 0
        noteBoxOpen = true
        noteBox.input.text = o.text || ""
        Qt.callLater(function () { noteBox.input.forceActiveFocus() })
    }

    function closeNoteBox() {
        noteBoxOpen = false
        editingNoteId = -1
        view.forceActiveFocus()
    }

    function saveNote() {
        const text = noteBox.input.text
        if (text.trim() === "") return
        if (askForPage) {                       // the typed page becomes the page being viewed
            const typed = parseInt(boxPageField.text)
            if (typed >= 1) currentPage = Math.min(typed, maxPage)
        }
        if (editingNoteId >= 0) session.editNote(editingNoteId, text)
        else if (boxHighlightId >= 0 && boxKind === "question") session.addQuestionTo(text, boxHighlightId)
        else if (boxHighlightId >= 0) session.addNoteTo(text, boxHighlightId)
        else if (boxKind === "question") session.addQuestion(text, boxGlobal)
        else session.addNote(text, boxGlobal)
        closeNoteBox()
    }

    // Plain letters never reach these while a text field has focus (it keeps them for typing).
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
    // H highlights the selected text for good
    Shortcut {
        sequence: "H"
        enabled: view.visible && !view.noteBoxOpen && view.activeSelection !== null
        onActivated: view.highlightSelection()
    }

    // ------------------------------------------------------------------ search (Ctrl+F)
    // Looks through the whole document. Every match is marked on its page, the current one is
    // outlined; Enter / Shift+Enter (or the arrows) go to the next / previous match, Esc closes.
    property bool searchOpen: false
    property string searchText: ""
    property var currentMatchRects: []              // where the current match is, on its page
    property int searchCount: 0                      // matches (the model's count does not notify)

    PdfSearchModel {
        id: searchModel
        document: view.hasDocument ? doc : null
        searchString: view.searchOpen ? view.searchText : ""
        onCurrentResultChanged: { view.showSearchResult(); searchTick.restart() }
        // a new search starts at its first match
        onSearchStringChanged: if (searchString !== "") currentResult = 0
        onRowsInserted: { view.searchCount = rowCount(); searchTick.restart() }
        onRowsRemoved: { view.searchCount = rowCount(); searchTick.restart() }
        onModelReset: { view.searchCount = rowCount(); searchTick.restart() }
    }
    // The pages ask the model where the matches are a moment after it has settled (it finds them
    // page by page, and the outlines of a page are only there after its rows are).
    property int searchRevision: 0
    Timer {
        id: searchTick
        interval: 120
        onTriggered: {
            view.currentMatchRects = view.searchCount > 0 ? view.rectsOf(searchModel.currentResultBoundingPolygons) : []
            view.searchRevision++
        }
    }

    function openSearch() {
        if (!hasDocument) return
        searchOpen = true
        Qt.callLater(function () {
            searchField.forceActiveFocus()
            searchField.selectAll()
        })
    }
    function closeSearch() {
        searchOpen = false
        view.forceActiveFocus()
    }
    function searchNext(step) {
        const n = view.searchCount
        if (n === 0) return
        searchModel.currentResult = (searchModel.currentResult + step + n) % n
        showSearchResult()
    }
    // Scroll so that the current match is in view (a third of the way down the viewport).
    function showSearchResult() {
        if (!searchOpen || searchCount === 0) return
        const link = searchModel.currentResultLink
        const index = link.page
        pages.positionViewAtIndex(index, ListView.Beginning)
        const item = pages.itemAtIndex(index)
        if (!item) return
        const points = doc.pagePointSize(index)
        const scale = (pages.contentWidth - 2 * pageMargin) / points.width
        const y = item.y + pageGap / 2 + link.location.y * scale
        const maxY = pages.originY + Math.max(0, pages.contentHeight - pages.height)
        pages.contentY = Math.max(pages.originY, Math.min(maxY, y - pages.height * 0.3))
        if (zoom > 1) {
            const x = pageMargin + link.location.x * scale
            pages.contentX = Math.max(pages.originX, Math.min(pages.originX + pages.contentWidth - pages.width,
                                                              x - pages.width / 2))
        }
        updateCurrentPage()
    }

    Shortcut {
        sequence: "Ctrl+F"
        enabled: view.visible && view.hasDocument
        onActivated: view.openSearch()
    }
    Shortcut {
        sequence: "F3"
        enabled: view.visible && view.searchOpen
        onActivated: view.searchNext(1)
    }
    Shortcut {
        sequence: "Shift+F3"
        enabled: view.visible && view.searchOpen
        onActivated: view.searchNext(-1)
    }

    // ------------------------------------------------ list entries (shared by local and global)
    // Right-click on an entry: Edit / Delete / move between global and local. One pair of menus
    // serves every entry; `entry` is the delegate that opened it (it has noteId and edit()).
    function showEntryMenu(entry, position) {
        const menu = entry.isGlobal ? globalMenu : localMenu
        const p = entry.mapToItem(view, position.x, position.y)
        menu.entry = entry
        menu.popup(p.x, p.y)
    }

    CrudMenu {
        id: localMenu
        property Item entry
        // answers can't be tied to a highlight (only the note or question itself)
        readonly property bool linkable: entry !== null && entry.canLink
        readonly property bool canUseSelection: view.activeSelection !== null
                                                && view.activeSelection.page === view.currentPage
        onEditTriggered: entry.edit()
        onDeleteTriggered: view.session.deleteNote(entry.noteId)
        AppMenuItem {
            text: "Move to global"
            onTriggered: view.session.moveToGlobal(localMenu.entry.noteId)
        }
        AppMenuItem {
            visible: localMenu.linkable && localMenu.entry.highlightId < 0 && localMenu.canUseSelection
            height: visible ? implicitHeight : 0
            text: "Link to selected text"
            onTriggered: {
                const id = view.highlightSelection()
                if (id >= 0) view.session.linkNote(localMenu.entry.noteId, id)
            }
        }
        AppMenuItem {
            visible: localMenu.linkable && localMenu.entry.highlightId >= 0
            height: visible ? implicitHeight : 0
            text: "Unlink from highlight"
            onTriggered: view.session.unlinkNote(localMenu.entry.noteId)
        }
    }

    // Left-click on a highlight: pick its colour from a row of swatches.
    function showColorPopover(highlight, item, position) {
        const p = item.mapToItem(view, position.x, position.y)
        colorPopover.highlightId = highlight.id
        colorPopover.openAt(p.x, p.y, highlight.color)
    }
    ColorPopover {
        id: colorPopover
        parent: view
        property int highlightId: -1
        onPicked: (color) => {
            // new highlights get the colour picked last, but never "transparent": a new highlight
            // that you can't see would only be confusing
            if (color !== "none") view.lastHighlightColor = color
            view.session.setHighlightColor(highlightId, color)
        }
    }

    // Right-click on a highlight in the PDF.
    function showHighlightMenu(highlight, item, position) {
        const p = item.mapToItem(view, position.x, position.y)
        highlightMenu.highlight = highlight
        highlightMenu.popup(p.x, p.y)
    }
    CrudMenu {
        id: highlightMenu
        property var highlight: ({ id: -1, page: 0, text: "", color: "yellow" })
        canEdit: false
        onDeleteTriggered: view.session.deleteHighlight(highlight.id)
        topBefore: [
            MenuIconButton {
                text: "Copy"
                iconSource: Theme.iconCopy
                onTriggered: view.controller.copyText(highlightMenu.highlight.text)
            }
        ]
        AppMenuItem {
            text: "Add note"
            onTriggered: view.openBox("note", { highlightId: highlightMenu.highlight.id,
                                               quote: highlightMenu.highlight.text,
                                               quoteColor: highlightMenu.highlight.color,
                                               page: highlightMenu.highlight.page })
        }
        AppMenuItem {
            text: "Add question"
            onTriggered: view.openBox("question", { highlightId: highlightMenu.highlight.id,
                                                   quote: highlightMenu.highlight.text,
                                                   quoteColor: highlightMenu.highlight.color,
                                                   page: highlightMenu.highlight.page })
        }
    }
    CrudMenu {
        id: globalMenu
        property Item entry
        onEditTriggered: entry.edit()
        onDeleteTriggered: view.session.deleteNote(entry.noteId)
        AppMenuItem {
            text: "To local (this page)"
            onTriggered: view.session.moveToPage(globalMenu.entry.noteId, view.currentPage)
        }
        AppMenuItem {
            text: "To local: choose a page..."
            onTriggered: pagePrompt.ask(globalMenu.entry.noteId)
        }
    }

    // One entry of any of the lists: a note, or a question or one of its answers (EntryCard).
    // Hovering one that is tied to a highlight makes that highlight pulse in the PDF.
    Component {
        id: entryDelegate

        EntryCard {
            id: entry
            required isGlobal
            required highlightId
            required quote
            required quoteColor
            width: ListView.view.width
            controller: view.controller
            onEditRequested: view.openBox(isQuestion ? "question" : "note",
                                          { editId: noteId, text: view.controller.toEditText(body) })
            onAnswerSubmitted: (text) => view.session.addAnswer(noteId, text)
            onAnswerEdited: (text) => view.session.editNote(noteId, text)
            onMenuRequested: (position) => view.showEntryMenu(entry, position)
            onHoveredChanged: if (highlightId >= 0) view.glowHighlight = hovered ? highlightId : -1
            Component.onDestruction: if (view.glowHighlight === highlightId) view.glowHighlight = -1
        }
    }
    // Asks for the page a global note / question should become local to.
    AppDialog {
        id: pagePrompt
        property int noteId: -1

        function ask(id) {
            noteId = id
            pageInput.text = view.currentPage
            open()
        }
        function confirm() {
            if (!pageInput.acceptableInput) return
            view.session.moveToPage(noteId, parseInt(pageInput.text))
            close()
        }

        width: 300
        onOpened: {
            pageInput.forceActiveFocus()
            pageInput.selectAll()
        }

        contentItem: ColumnLayout {
            spacing: 14

            DialogTitle { text: "Move to which page?" }
            AppTextField {
                id: pageInput
                Layout.fillWidth: true
                placeholderText: view.hasDocument ? "1 - " + view.pageCount : "page"
                validator: IntValidator { bottom: 1; top: view.maxPage }
                inputMethodHints: Qt.ImhDigitsOnly
                onAccepted: pagePrompt.confirm()
            }
            RowLayout {
                spacing: 8
                Item { Layout.fillWidth: true }
                AppButton {
                    text: "Cancel"
                    onClicked: pagePrompt.close()
                }
                AppButton {
                    text: "Move"
                    filled: true
                    enabled: pageInput.acceptableInput
                    onClicked: pagePrompt.confirm()
                }
            }
        }
    }
    PdfDocument {
        id: doc
        source: view.hasDocument && view.uri !== "" ? view.controller.fileUrl(view.uri) : ""
        onStatusChanged: view.resumeIfReady()
    }


    // ------------------------------------------------------------------ left column
    ColumnLayout {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: view.sideWidth
        spacing: 14

        // Top part: global notes and global Q&A share one list; the switch picks which it shows.
        GlobalNotes {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            session: view.session
            delegate: entryDelegate
        }

        // The resources this one is connected to (it mentions them, or they mention it).
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            spacing: 6

            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                text: "Connections"
                badge: view.session && view.session.connections.length > 0
                       ? String(view.session.connections.length) : ""
                size: 22
            }
            ResourceGraph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 14
                centerName: view.title
                centerId: view.resourceId
                onMenuRequested: (id, item, position) => view.actions.showMenu(id, item, position.x, position.y)
                connections: view.session ? view.session.connections : []
                onNodeClicked: (id) => view.controller.openResourceById(id)
            }
        }

        // Bottom part: "PAGE 5 OF 21" (the number is an input; scroll it to change page), then the
        // view controls: zoom level and wide mode together in an inset track, dark mode in one of
        // its own, and export as a plain icon. A Flow, so they wrap when the column is narrow.
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            spacing: 18

            Row {
                height: 34
                spacing: 8
                CapsLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Page"
                }
                AppTextField {
                    id: pageField
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    implicitHeight: 28
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: TextInput.AlignHCenter
                    leftPadding: 4
                    rightPadding: 4
                    validator: IntValidator { bottom: 1; top: view.maxPage }
                    inputMethodHints: Qt.ImhDigitsOnly
                    text: view.currentPage
                    onAccepted: {
                        view.goToPage(parseInt(text))
                        focus = false
                    }
                    onActiveFocusChanged: {
                        if (!activeFocus) text = view.currentPage
                        else selectAll()
                    }
                    Connections {
                        target: view
                        function onCurrentPageChanged() {
                            if (!pageField.activeFocus) pageField.text = view.currentPage
                        }
                    }
                    // Wheel down = next page, wheel up = previous page.
                    WheelHandler {
                        onWheel: (event) => view.goToPage(view.currentPage + (event.angleDelta.y < 0 ? 1 : -1))
                    }
                }
                CapsLabel {
                    visible: view.hasDocument
                    anchors.verticalCenter: parent.verticalCenter
                    text: "of " + view.pageCount
                }
            }

            // zoom level (click it: back to 100%) and wide mode
            Item {
                visible: view.hasDocument
                width: zoomTools.width + 8
                height: 34
                Well { anchors.fill: parent; radius: height / 2 }
                Row {
                    id: zoomTools
                    anchors.centerIn: parent
                    spacing: 2
                    AppButton {
                        compact: true
                        implicitHeight: 26
                        text: Math.round(view.zoom * 100) + "%"
                        font.pixelSize: 12
                        textColor: Theme.textMuted
                        onClicked: view.zoomBy(1 / view.zoom, pages.width / 2, pages.height / 2)
                    }
                    IconButton {
                        compact: true
                        implicitHeight: 26
                        iconSource: view.wide ? Theme.iconShrink : Theme.iconExpand
                        active: view.wide
                        onClicked: view.wide = !view.wide
                    }
                }
            }

            // dark mode
            Item {
                visible: view.hasDocument
                width: 34
                height: 34
                Well { anchors.fill: parent; radius: height / 2 }
                IconButton {
                    anchors.centerIn: parent
                    compact: true
                    implicitHeight: 26
                    implicitWidth: 26
                    iconSource: Theme.iconMoon
                    active: view.dark
                    onClicked: view.dark = !view.dark
                }
            }

            // Export what was written about this PDF: a plain icon.
            IconButton {
                id: exportButton
                height: 34
                compact: true
                iconSource: Theme.iconExport
                textColor: exportButton.hovered || exportMenu.visible ? Theme.text : Theme.textMuted
                onClicked: exportMenu.visible ? exportMenu.close() : exportMenu.open()

                AppToolTip {
                    text: "Export"
                    shown: exportButton.hovered && !exportMenu.visible
                }
                // opens upwards: the buttons sit at the bottom of the column
                AppMenu {
                    id: exportMenu
                    x: 0
                    y: -height - 8
                    AppMenuItem {
                        enabled: false
                        text: "Unified page view (coming soon)"
                        iconSource: Theme.iconGrid
                        tint: Theme.textFaint
                    }
                    AppMenuItem {
                        visible: view.isPresentation
                        height: visible ? implicitHeight : 0
                        text: "Presentation info..."
                        iconSource: Theme.iconInfo
                        onTriggered: presentationInfo.show(view.resourceId)
                    }
                    AppMenuItem {
                        text: "To Markdown"
                        iconSource: Theme.iconDocument
                        onTriggered: view.controller.exportPdfMarkdown(view.resourceId, view.title)
                    }
                }
            }
        }
    }
    // ----------------------------------------------------------------- centre column
    // The PDF stands in front of the side columns: a raised panel behind it, throwing a wide
    // shadow onto them, and drawn above them (the side columns are at z 0).
    Item {
        id: stage
        visible: view.hasDocument
        z: 1
        width: view.centerWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        RectangularShadow {
            anchors.fill: parent
            blur: 56
            spread: 4
            color: Qt.rgba(0, 0, 0, 0.55)
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.panelRaised }
                GradientStop { position: 0.5; color: Theme.panel }
                GradientStop { position: 1; color: Theme.panelRaised }
            }
            // light edges, like the top edge of a Surface
            Rectangle { width: 1; height: parent.height; color: Theme.hairlineStrong }
            Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: Theme.hairlineStrong }
        }
    }
    ListView {
        id: pages
        visible: view.hasDocument
        z: 2
        width: view.centerWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        clip: true                                   // zoomed pages never leave the column
        model: doc.pageCount
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        contentWidth: width * view.zoom
        onContentYChanged: view.updateCurrentPage()
        onHeightChanged: view.updateCurrentPage()

        ScrollBar.vertical: AppScrollBar { z: 6 }
        ScrollBar.horizontal: AppScrollBar { z: 6 }      // only appears when zoomed in

        delegate: Item {
            id: pageItem
            required property int index
            readonly property size points: doc.pagePointSize(index)

            width: pages.contentWidth
            height: paper.height + view.pageGap

            // The sheet lies on the desk: a soft shadow under it.
            RectangularShadow {
                anchors.fill: paper
                radius: 3
                offset.y: 6
                blur: 22
                spread: -2
                color: Qt.rgba(0, 0, 0, 0.5)
            }

            // White paper under the (transparent) page rendering. In dark mode the whole sheet
            // is inverted by a shader.
            Item {
                id: paper
                x: view.pageMargin
                y: view.pageGap / 2
                width: pageItem.width - 2 * view.pageMargin
                height: pageItem.points.width > 0
                        ? width * pageItem.points.height / pageItem.points.width : width * 1.4

                layer.enabled: view.dark
                layer.effect: ShaderEffect {
                    fragmentShader: Qt.resolvedUrl("shaders/invert.frag.qsb")
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: "white"
                }
                PdfPageImage {
                    anchors.fill: parent
                    z: 1
                    document: doc
                    currentFrame: pageItem.index
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                }
            }

            // ---- text selection and highlights ----
            // Left-drag over the page selects text (it no longer pans the page: use the wheel,
            // the scroll bars or the middle button). Sits over the paper, in its coordinates, and
            // outside the paper's layer so dark mode doesn't invert the handlers' geometry.
            Item {
                id: selectionLayer
                x: paper.x
                y: paper.y
                width: paper.width
                height: paper.height
                // pixels per PDF point
                readonly property real pageScale: pageItem.points.width > 0
                                                  ? width / pageItem.points.width : 1
                // the permanent highlights of this page
                readonly property var pageHighlights:
                    view.highlightList.filter(h => h.page === pageItem.index + 1)

                function highlightAt(position) {
                    const px = position.x / pageScale
                    const py = position.y / pageScale
                    for (const h of pageHighlights)
                        for (const r of h.rects)
                            if (px >= r[0] && px <= r[0] + r[2] && py >= r[1] && py <= r[1] + r[3])
                                return h
                    return null
                }

                PdfSelection {
                    id: selection
                    document: doc
                    page: pageItem.index
                    from: Qt.point(selectDrag.centroid.pressPosition.x / selectionLayer.pageScale,
                                   selectDrag.centroid.pressPosition.y / selectionLayer.pageScale)
                    to: Qt.point(selectDrag.centroid.position.x / selectionLayer.pageScale,
                                 selectDrag.centroid.position.y / selectionLayer.pageScale)
                    hold: !selectDrag.active && !selectTap.pressed
                }

                // Once the mouse is released with text selected, the viewer knows what is selected
                // (the toolbar below, "H", and the note menus work on it).
                function syncSelection() {
                    if (selection.text !== "" && selection.hold) {
                        view.activeSelection = {
                            page: pageItem.index + 1,
                            text: selection.text.replace(/\s+/g, " ").trim(),
                            rects: view.rectsOf(selection.geometry)
                        }
                    } else if (selection.text === "" && view.selectionPage === pageItem.index) {
                        view.activeSelection = null
                    }
                }
                Connections {
                    target: selection
                    function onTextChanged() { selectionLayer.syncSelection() }
                    function onHoldChanged() { selectionLayer.syncSelection() }
                }

                // Everything below is drawn OVER the page image (z > 1), see-through, like the
                // search matches. Under it would look nicer (black text on the marker), but a page
                // that paints its own opaque background (slides exported from PowerPoint) would
                // hide it completely. Being inside the paper it is inverted with it in dark mode.
                // The transient selection:
                Shape {
                    parent: paper
                    anchors.fill: parent
                    z: 1.5
                    ShapePath {
                        strokeWidth: 0
                        fillColor: Qt.alpha(Theme.selection, 0.35)
                        scale: Qt.size(selectionLayer.pageScale, selectionLayer.pageScale)
                        PathMultiline { paths: selection.geometry }
                    }
                }
                // The permanent highlights. One whose note is hovered pulses and glows.
                Item {
                    parent: paper
                    anchors.fill: parent
                    z: 1.4
                    Repeater {
                        model: selectionLayer.pageHighlights
                        delegate: Item {
                            id: marker
                            required property var modelData
                            readonly property bool glowing: view.glowHighlight === modelData.id
                            property real pulse: 0
                            anchors.fill: parent

                            SequentialAnimation on pulse {
                                running: marker.glowing
                                loops: Animation.Infinite
                                NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0.15; duration: 500; easing.type: Easing.InOutSine }
                            }
                            onGlowingChanged: if (!glowing) pulse = 0

                            Repeater {
                                model: marker.modelData.rects
                                delegate: Item {
                                    required property var modelData
                                    x: modelData[0] * selectionLayer.pageScale
                                    y: modelData[1] * selectionLayer.pageScale
                                    width: modelData[2] * selectionLayer.pageScale
                                    height: modelData[3] * selectionLayer.pageScale

                                    Rectangle {          // the glow around the marker
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        radius: 5
                                        color: Qt.alpha("#ff9a1f", 0.45 * marker.pulse)
                                        border.width: 2
                                        border.color: Qt.alpha("#ff9a1f", marker.pulse)
                                        visible: marker.glowing
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        // a transparent highlight has no marker at all (its halo still shows)
                                        color: marker.modelData.color === "none" ? "transparent"
                                             : Qt.alpha(Theme.highlightColor(marker.modelData.color),
                                                        0.4 + 0.3 * marker.pulse)
                                    }
                                }
                            }
                        }
                    }
                }

                // The search matches: every one marked, the current one outlined and stronger.
                // (Measured as plain rectangles by Python, like the highlights.) Drawn over the
                // page like the highlights, and above them.
                Item {
                    id: matchLayer
                    parent: paper
                    anchors.fill: parent
                    z: 2
                    property var rects: []
                    function refresh() {
                        rects = view.searchOpen && view.searchCount > 0
                                ? view.rectsOf(searchModel.boundingPolygonsOnPage(pageItem.index)) : []
                    }
                    Connections {
                        target: searchModel
                        function onCurrentPageBoundingPolygonsChanged() { matchLayer.refresh() }
                        function onSearchStringChanged() { matchLayer.refresh() }
                    }
                    Connections {
                        target: view
                        function onSearchOpenChanged() { matchLayer.refresh() }
                        function onSearchCountChanged() { matchLayer.refresh() }
                        function onSearchRevisionChanged() { matchLayer.refresh() }
                    }
                    Component.onCompleted: refresh()

                    Repeater {
                        model: matchLayer.rects
                        Rectangle {
                            required property var modelData
                            x: modelData[0] * selectionLayer.pageScale
                            y: modelData[1] * selectionLayer.pageScale
                            width: modelData[2] * selectionLayer.pageScale
                            height: modelData[3] * selectionLayer.pageScale
                            radius: 2
                            color: Qt.alpha("#ffd23f", 0.42)
                        }
                    }
                    Repeater {                               // the current match
                        model: view.searchOpen && searchModel.currentPage === pageItem.index
                               ? view.currentMatchRects : []
                        Rectangle {
                            required property var modelData
                            x: modelData[0] * selectionLayer.pageScale - 2
                            y: modelData[1] * selectionLayer.pageScale - 2
                            width: modelData[2] * selectionLayer.pageScale + 4
                            height: modelData[3] * selectionLayer.pageScale + 4
                            radius: 3
                            color: Qt.alpha("#ff9a1f", 0.32)
                            border.width: 2
                            border.color: "#ff7a1a"
                        }
                    }
                }
                DragHandler {
                    id: selectDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
                    onActiveChanged: if (active) {
                        view.selectionPage = pageItem.index
                        view.activeSelection = null
                    }
                }
                TapHandler {
                    id: selectTap
                    acceptedButtons: Qt.LeftButton
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
                    onPressedChanged: if (pressed) {
                        view.selectionPage = pageItem.index
                        view.activeSelection = null
                    }
                    // a click (not a drag) on a highlight: choose its colour
                    onTapped: (eventPoint) => {
                        const hit = selectionLayer.highlightAt(eventPoint.position)
                        if (hit) view.showColorPopover(hit, selectionLayer, eventPoint.position)
                    }
                }
                // Right-click on a highlight: copy it, add a note or question, remove it.
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (eventPoint) => {
                        const hit = selectionLayer.highlightAt(eventPoint.position)
                        if (hit) view.showHighlightMenu(hit, selectionLayer, eventPoint.position)
                    }
                }

                // only one page keeps a selection, so Ctrl+C is never ambiguous
                Connections {
                    target: view
                    function onSelectionPageChanged() {
                        if (view.selectionPage !== pageItem.index) selection.clear()
                    }
                }
                // Ctrl+C copies the selection, unless a text box has the keyboard (it copies its own)
                Shortcut {
                    sequences: [StandardKey.Copy]
                    enabled: view.visible && selection.text !== "" && !view.textBoxFocused
                    onActivated: view.controller.copyText(selection.text)
                }
            }

            // What to do with the selected text, right under it: highlight it, write a note or a
            // question about it (which highlights it too), or copy it.
            Item {
                id: toolbar
                readonly property var sel: view.activeSelection
                readonly property bool mine: sel !== null && sel.page === pageItem.index + 1
                readonly property var last: mine && sel.rects.length > 0 ? sel.rects[sel.rects.length - 1] : null
                visible: mine && last !== null
                z: 5
                x: last ? Math.max(paper.x, Math.min(paper.x + last[0] * selectionLayer.pageScale,
                                                     pageItem.width - width - 8)) : 0
                y: last ? paper.y + (last[1] + last[3]) * selectionLayer.pageScale + 6 : 0
                width: toolbarRow.implicitWidth + 10
                height: 38

                Surface {
                    anchors.fill: parent
                    elevation: 2
                    radius: height / 2
                }
                InputBlocker {}                             // clicks here are not clicks on the page

                Row {
                    id: toolbarRow
                    anchors.centerIn: parent
                    spacing: 2
                    AppButton {
                        compact: true
                        text: "Highlight"
                        filled: true
                        onClicked: view.highlightSelection()
                    }
                    AppButton {
                        compact: true
                        text: "Note"
                        onClicked: view.noteOnSelection("note")
                    }
                    AppButton {
                        compact: true
                        text: "Question"
                        onClicked: view.noteOnSelection("question")
                    }
                    AppButton {
                        compact: true
                        text: "Copy"
                        onClicked: {
                            view.controller.copyText(toolbar.sel.text)
                            view.clearSelection()
                        }
                    }
                }
            }
        }
    }

    // Pointer input for the PDF column, in viewport coordinates (a sibling above the list so the
    // coordinates do not scroll with the content). The handlers are passive: normal scrolling and
    // dragging still reach the list.
    Item {
        id: inputLayer
        visible: view.hasDocument
        anchors.fill: pages
        z: 5

        // Ctrl + wheel zooms.
        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: (event) => view.zoomBy(event.angleDelta.y > 0 ? 1.1 : 1 / 1.1,
                                            point.position.x, point.position.y)
        }

        // The plain wheel scrolls the pages: Qt's default distance (~68 px per notch with the
        // usual 3 lines per notch) times the PDF scroll speed from the settings, eased instead
        // of jumping. Touchpads already send smooth pixel deltas, which are applied directly.
        WheelHandler {
            acceptedModifiers: Qt.NoModifier
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const speed = view.controller.pdfScrollSpeed
                const minY = pages.originY
                const maxY = Math.max(minY, pages.originY + pages.contentHeight - pages.height)
                pages.cancelFlick()
                if (event.pixelDelta.y !== 0) {
                    wheelAnim.stop()
                    pages.contentY = Math.max(minY, Math.min(maxY,
                        pages.contentY - event.pixelDelta.y * speed))
                    return
                }
                const dy = event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * (68 / 3) * speed
                const from = wheelAnim.running ? wheelAnim.to : pages.contentY
                wheelAnim.stop()
                wheelAnim.to = Math.max(minY, Math.min(maxY, from - dy))
                wheelAnim.start()
            }
        }
        NumberAnimation {
            id: wheelAnim
            target: pages
            property: "contentY"
            duration: 160
            easing.type: Easing.OutCubic
        }

        // Middle button held = autoscrolling. WithinBounds keeps `pressed` true while the pointer
        // moves (the default policy would call it a drag and cancel the press).
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            gesturePolicy: TapHandler.WithinBounds
            onPressedChanged: {
                if (pressed) view.startAutoScroll(point.position)
                else view.stopAutoScroll()
            }
            onPointChanged: if (pressed) view.autoPointer = point.position
        }
        HoverHandler {
            acceptedButtons: Qt.MiddleButton
            cursorShape: view.autoScrolling ? Qt.SizeAllCursor : Qt.ArrowCursor
        }

        // Marker where the autoscroll started.
        Surface {
            visible: view.autoScrolling
            x: view.autoOrigin.x - width / 2
            y: view.autoOrigin.y - height / 2
            width: 26
            height: 26
            radius: 13
            elevation: 2
            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: Theme.text
            }
        }
    }

    // ----------------------------------------------- centre column of a resource without pages
    // A web link or a Word file has nothing to scroll here, so the middle shows what it is, a button
    // to open it, and the pages that have notes (click one to see them).
    Item {
        id: notesOnly
        visible: !view.hasDocument
        width: view.centerWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        readonly property bool isLink: /^[A-Za-z][A-Za-z0-9+.\-]+:\S+$/.test(view.uri)

        Surface {
            anchors.fill: notesOnlyColumn
            anchors.margins: -28
            radius: 22
        }
        ColumnLayout {
            id: notesOnlyColumn
            anchors.centerIn: parent
            width: Math.min(parent.width - 96, 520)
            spacing: 14

            Text {
                text: view.title
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: Theme.serifFont
                font.pixelSize: 26
                color: Theme.text
            }
            CapsLabel {
                text: view.uri
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                font.capitalization: Font.MixedCase
                font.letterSpacing: 0.4
                color: Theme.textFaint
            }
            AppButton {
                text: notesOnly.isLink ? "Open link" : "Open file"
                filled: true
                Layout.alignment: Qt.AlignHCenter
                onClicked: view.controller.openResource(view.uri)
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: 1
                color: Theme.hairline
            }
            Text {
                text: "This resource has no pages to scroll. Type a page number below to see the "
                      + "notes of that page; a new note asks for its page."
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.pixelSize: 13
                color: Theme.textMuted
            }
            CapsLabel {
                visible: noted.count > 0
                text: "Pages with notes"
                Layout.topMargin: 4
                Layout.alignment: Qt.AlignHCenter
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    id: noted
                    model: view.session ? view.session.notedPages : []
                    delegate: AppButton {
                        required property var modelData
                        compact: true
                        text: "p. " + modelData.page + "  (" + modelData.count + ")"
                        active: modelData.page === view.currentPage
                        onClicked: view.goToPage(modelData.page)
                    }
                }
            }
        }
    }

    Text {
        visible: doc.status === PdfDocument.Error
        anchors.centerIn: pages
        width: pages.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "This PDF couldn't be opened."
        font.family: Theme.serifFont
        font.pixelSize: 20
        color: Theme.danger
    }

    // ----------------------------------------------------------------- right column
    ColumnLayout {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 12
        width: view.sideWidth
        spacing: 14

        // Notes of the page being viewed (add them with the N key).
        SectionList {
            title: "Notes"
            badge: "p. " + view.currentPage
            loading: view.session ? view.session.loading : false
            model: view.session ? view.session.notes : null
            delegate: entryDelegate
            emptyText: "Press N to write a note on this page"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
        }

        // Questions of the page (Q key), each followed by its answers.
        SectionList {
            title: "Q&A"
            loading: view.session ? view.session.loading : false
            model: view.session ? view.session.questions : null
            delegate: entryDelegate
            emptyText: "Press Q to ask a question about this page"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
        }

        // The speaker notes and comments of the slide (presentations only).
        ColumnLayout {
            visible: view.isPresentation
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            spacing: 10

            SectionTitle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                text: "Slide notes"
                size: 22
            }
            Flickable {
                id: slideFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 14
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: slideColumn.height
                ScrollBar.vertical: AppScrollBar {}

                CapsLabel {
                    visible: view.slideInfo === null
                    width: slideFlick.width - 10
                    topPadding: 6
                    wrapMode: Text.Wrap
                    text: "No speaker notes or comments on this slide"
                    color: Theme.textFaint
                }
                Column {
                    id: slideColumn
                    width: slideFlick.width - 10
                    spacing: 6

                    // the speaker notes, on a card like the notes above
                    Item {
                        visible: view.slideInfo !== null && view.slideInfo.notes !== ""
                        width: parent.width
                        height: speakerNotes.implicitHeight + 20
                        QuietCard { anchors.fill: parent }
                        ReferenceText {
                            id: speakerNotes
                            x: 12
                            y: 10
                            width: parent.width - 24
                            source: view.slideInfo ? view.slideInfo.notes : ""
                            controller: view.controller
                            font.pixelSize: 13
                            baseColor: Theme.text
                        }
                    }
                    // the comments; a reply hangs off the comment before it, like an answer
                    Repeater {
                        model: view.slideInfo ? view.slideInfo.comments : []
                        Item {
                            id: comment
                            required property var modelData
                            width: slideColumn.width
                            height: commentColumn.implicitHeight + (modelData.isReply ? 8 : 20)

                            QuietCard {
                                visible: !comment.modelData.isReply
                                anchors.fill: parent
                            }
                            Rectangle {
                                visible: comment.modelData.isReply
                                x: 12
                                y: 2
                                width: 2
                                height: parent.height - 4
                                radius: 1
                                color: Qt.alpha(Theme.info, 0.6)
                            }
                            Column {
                                id: commentColumn
                                x: comment.modelData.isReply ? 34 : 12
                                y: comment.modelData.isReply ? 4 : 10
                                width: parent.width - x - 12
                                spacing: 4
                                CapsLabel {
                                    width: parent.width
                                    text: comment.modelData.author !== "" ? comment.modelData.author : "Comment"
                                    elide: Text.ElideRight
                                    color: Theme.info
                                }
                                ReferenceText {
                                    width: parent.width
                                    source: comment.modelData.text
                                    controller: view.controller
                                    font.pixelSize: 13
                                    baseColor: Theme.text
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ search bar (Ctrl+F)
    Item {
        id: searchBar
        visible: view.searchOpen
        z: 11
        width: Math.min(480, view.centerWidth - 24)
        height: 46
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12

        InputBlocker {}
        Surface {
            anchors.fill: parent
            elevation: 2
            radius: height / 2
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 8
            spacing: 6

            IconImage {
                source: Theme.iconSearch
                sourceSize: Qt.size(16, 16)
                color: Theme.textMuted
            }
            AppTextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 30
                placeholderText: "Search the whole document"
                onTextChanged: view.searchText = text
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        view.searchNext((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        view.closeSearch()
                        event.accepted = true
                    }
                }
            }
            // "3 / 17" (the first match is the current one), or that there is none
            CapsLabel {
                text: view.searchText === "" ? ""
                      : view.searchCount === 0 ? "No results"
                      : (searchModel.currentResult + 1) + " / " + view.searchCount
                color: view.searchText !== "" && view.searchCount === 0 ? Theme.danger : Theme.textMuted
            }
            IconButton {
                compact: true
                iconSource: Theme.iconChevronUp
                enabled: view.searchCount > 0
                onClicked: { view.searchNext(-1); searchField.forceActiveFocus() }
            }
            IconButton {
                compact: true
                iconSource: Theme.iconChevronDown
                enabled: view.searchCount > 0
                onClicked: { view.searchNext(1); searchField.forceActiveFocus() }
            }
            IconButton {
                compact: true
                iconSource: Theme.iconClose
                fallbackText: "×"
                onClicked: view.closeSearch()
            }
        }
    }

    // ------------------------------------------- floating box (N: note, Q: question, answers)
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
        quote: view.editingNoteId < 0 && view.boxHighlightId >= 0 ? view.boxQuote : ""
        quoteColor: view.boxQuoteColor
        hint: view.askForPage ? "Tab: from the page to the text  |  Ctrl+Enter: save  |  Esc: cancel"
                              : "Ctrl+Enter: save  |  Esc: cancel"
        onCancelled: view.closeNoteBox()
        onSubmitted: view.saveNote()

        // Local (this page) or global (no page): click to choose.
        SegmentedSwitch {
            visible: view.editingNoteId < 0 && view.boxHighlightId < 0
            leftText: "Local"
            rightText: "Global"
            rightActive: view.boxGlobal
            onToggledTo: (right) => {
                view.boxGlobal = right
                // a click takes the focus away: give it back so typing and Tab keep working
                Qt.callLater(function () { noteBox.input.forceActiveFocus() })
            }
        }
        // A resource without pages: the page of a new local note is typed in here.
        CapsLabel {
            visible: view.askForPage
            text: "Page"
        }
        AppTextField {
            id: boxPageField
            visible: view.askForPage
            implicitWidth: 60
            implicitHeight: 26
            font.pixelSize: 12
            horizontalAlignment: TextInput.AlignHCenter
            leftPadding: 4
            rightPadding: 4
            placeholderText: "page"
            validator: IntValidator { bottom: 1; top: view.maxPage }
            inputMethodHints: Qt.ImhDigitsOnly
            onAccepted: noteBox.input.forceActiveFocus()
            Keys.onTabPressed: noteBox.input.forceActiveFocus()
            onActiveFocusChanged: if (activeFocus) selectAll()
        }
        CapsLabel {
            visible: !view.askForPage
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: view.editingNoteId >= 0 || view.boxGlobal ? ""
                : "Page " + (view.boxHighlightId >= 0 ? view.boxPage : view.currentPage)
        }
        Item { visible: view.askForPage; Layout.fillWidth: true }
    }
}
