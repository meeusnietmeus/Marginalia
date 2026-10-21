import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls
import DailyTodo.Views

// App shell: window, toolbar, the day list and the toast. All the real UI lives in the
// DailyTodo.* modules next to this file:
//   Style    - Theme (colours, sizes, icons)
//   Controls - generic styled widgets, reusable in any app
//   Views    - this app's screens and pieces (day list, todo row, add box, ...)
ApplicationWindow {
    id: root

    // Both set from Python (dailytodo/app.py) via setInitialProperties.
    required property var controller
    property string appTitle: "Marginalia"
    // Takes over the window's title bar (Windows only, see window_chrome.py): null or not
    // `active` keeps the normal one.
    property var chrome: null
    readonly property bool customTitleBar: chrome !== null && chrome.active

    width: 900
    height: 780
    minimumWidth: 520
    minimumHeight: 400
    visibility: Window.Maximized
    title: appTitle
    color: Theme.window

    // Palette for any stock control we don't restyle (scrollbar, ...). Values come from Theme.
    palette {
        window: Theme.window
        windowText: Theme.text
        base: Theme.input
        text: Theme.text
        button: Theme.hover
        buttonText: Theme.text
        mid: Theme.checkBorder
        highlight: Theme.accent
        highlightedText: Theme.accentText
        placeholderText: Theme.textFaint
    }

    FocusClearTapHandler { hostWindow: root }

    // ---- navigation state ----
    property string currentView: "overview"   // "overview", "questions", "graph", "search", or "tab" (an entry of `tabs`)
    property int currentTab: -1               // index into `tabs` while currentView === "tab"

    property string settingsFolder: ""        // the workspace settings dialog's view of the setting

    // Open resource tabs, after the fixed pages (Overview, Open questions, Resource graph).
    // kind: "pdf" (a PDF, or with hasDocument false the notes tab of any other resource) | "video" |
    // "flowchart" | "unified" (every note and question of a PDF on one page; a second tab of the
    // same resource).
    ListModel { id: tabs }
    property int nextTabUid: 1                // every tab gets its own uid: indexes shift when one closes

    // ---- recently used (Ctrl+Tab) ----
    // The pages and tabs in the order they were last shown, most recent first, as keys: "overview",
    // "questions", "graph", "search" or "tab:<uid>". Closed tabs drop out when the list is used.
    property var recentViews: ["overview"]
    function viewKey() { return currentView === "tab" ? (currentTab >= 0 && currentTab < tabs.count ? "tab:" + tabs.get(currentTab).uid : "") : currentView }
    function noteVisit() {
        const key = viewKey()
        if (key === "") return
        recentViews = [key].concat(recentViews.filter(k => k !== key))
    }
    onCurrentViewChanged: Qt.callLater(noteVisit)       // (opening a tab sets both: count it once)
    onCurrentTabChanged: Qt.callLater(noteVisit)
    function tabIndexOf(uid) {
        for (let i = 0; i < tabs.count; i++) if (tabs.get(i).uid === uid) return i
        return -1
    }
    // What Ctrl+Tab offers: the recent ones that are still there, leaving out the pages that have
    // unloaded themselves (LazyPage, after a while away).
    function switcherEntries() {
        const pages = {
            overview: { title: "Overview", icon: Theme.iconCalendar },
            questions: { title: "Open questions", icon: Theme.iconInfo, page: questionsPage },
            graph: { title: "Resource graph", icon: Theme.iconLink, page: graphPage },
            search: { title: "Search", icon: Theme.iconSearch }
        }
        const current = viewKey()
        const list = []
        for (const key of recentViews) {
            if (key.startsWith("tab:")) {
                const i = tabIndexOf(parseInt(key.slice(4)))
                if (i < 0) continue
                const tab = tabs.get(i)
                const info = controller.resourceInfo(tab.resourceId)
                list.push({ key: key, title: tab.title, kind: info.kind || "file",
                            caption: tab.kind === "unified" ? "All notes" : (info.kind || "") })
            } else {
                const p = pages[key]
                if (!p || (p.page && !p.page.loaded && key !== current)) continue
                list.push({ key: key, title: p.title, icon: p.icon, caption: "Page" })
            }
        }
        return list
    }
    function cycleViews(delta) {
        if (tabSwitcher.open) tabSwitcher.step(delta)
        else tabSwitcher.start(switcherEntries(), delta < 0, root.activeFocusItem)
    }
    function showView(key) {
        if (key.startsWith("tab:")) {
            const i = tabIndexOf(parseInt(key.slice(4)))
            if (i < 0) return
            currentView = "tab"
            currentTab = i
        } else {
            currentView = key
        }
    }
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: root.cycleViews(1)
    }
    Shortcut {
        // Shift+Tab arrives as Backtab
        sequences: ["Ctrl+Shift+Tab", "Ctrl+Shift+Backtab", "Ctrl+Backtab"]
        onActivated: root.cycleViews(-1)
    }
    onActiveChanged: if (!active) tabSwitcher.cancel()

    // Opens a resource in its own tab, or switches to the tab it is already open in. A PDF shows
    // its pages; any other resource (hasDocument false) is a notes tab, where the page is typed in.
    // `page` > 0 goes to that page (also when the tab is already open); 0 leaves it where it was.
    // A video (a YouTube link) has a page of its own: a preview, a timeline of notes at timestamps.
    function openPdf(resourceId, title, uri, page) { openResourceTab(resourceId, title, uri, page, true, "pdf") }
    function openNotes(resourceId, title, uri, page) { openResourceTab(resourceId, title, uri, page, false, "pdf") }
    function openVideo(resourceId, title, uri, page) { openResourceTab(resourceId, title, uri, page, false, "video") }
    function openFlowchart(resourceId, title, uri) { openResourceTab(resourceId, title, uri, 0, false, "flowchart") }
    function openUnified(resourceId, title) { openResourceTab(resourceId, "Notes: " + title, "", 0, true, "unified") }
    function openResourceTab(resourceId, title, uri, page, hasDocument, kind) {
        const startPage = page || 0
        for (let i = 0; i < tabs.count; i++) {
            // a resource has its document tab and may have a unified view next to it
            if (tabs.get(i).resourceId === resourceId && (tabs.get(i).kind === "unified") === (kind === "unified")) {
                currentView = "tab"
                currentTab = i
                const loader = tabRepeater.itemAt(i)
                if (startPage > 0 && loader && loader.item)
                    loader.item.goToPage(startPage)
                return
            }
        }
        tabs.append({ title: title, kind: kind, uri: uri, resourceId: resourceId,
                      startPage: startPage, hasDocument: hasDocument, uid: nextTabUid++ })
        currentView = "tab"
        currentTab = tabs.count - 1
    }

    // Called from Python when another start of the app hands this one a link (see instance.py).
    function bringToFront() {
        if (root.visibility === Window.Minimized || root.visibility === Window.Hidden)
            root.showNormal()
        root.raise()
        root.requestActivate()
    }

    // A capture from the browser extension (controller.capture): the resource's tab is open, so
    // open its note / question box at that moment, with the cursor in it.
    function openCaptureBox(resourceId, kind, seconds) {
        for (let i = 0; i < tabs.count; i++) {
            if (tabs.get(i).resourceId !== resourceId || tabs.get(i).kind === "unified") continue
            const loader = tabRepeater.itemAt(i)
            if (loader && loader.item) {
                const page = loader.item
                Qt.callLater(() => page.openBox(kind, seconds > 0 ? { time: seconds } : {}))
            }
            return
        }
    }

    function closeTabsOf(resourceId) {
        for (let i = tabs.count - 1; i >= 0; i--) {
            if (tabs.get(i).resourceId === resourceId)
                closeTab(i)
        }
    }

    function closeTab(index) {
        tabs.remove(index)
        if (currentView !== "tab") {
            if (index < currentTab) currentTab--
        } else if (tabs.count === 0) {
            currentView = "overview"
            currentTab = -1
        } else if (index < currentTab) {
            currentTab--
        } else if (index === currentTab) {
            currentTab = Math.min(index, tabs.count - 1)
        }
    }

    // Is this point of the header empty space, which moves the window when it is dragged? Asked by
    // the window chrome for every mouse move over the title bar (x, y in window units). Buttons,
    // tabs and the like (anything `interactive`, or with a `hovered` state) are not.
    // (The answer goes back through chrome.setCaptionResult: a value returned to Python from a QML
    // function does not come through.)
    function captionAt(x, y) {
        const empty = isEmptyHeaderSpace(x, y)
        if (chrome) chrome.setCaptionResult(empty)
        return empty
    }
    // The topmost visible child of an item at a point (its own coordinates), not counting
    // backgrounds (z below 0). (Item.childAt would also find the header's background.)
    function topChildAt(item, px, py) {
        let best = null
        for (let i = 0; i < item.children.length; i++) {
            const c = item.children[i]
            if (!c.visible || c.z < 0) continue
            if (px < c.x || py < c.y || px >= c.x + c.width || py >= c.y + c.height) continue
            if (best === null || c.z >= best.z) best = c
        }
        return best
    }
    function isEmptyHeaderSpace(x, y) {
        const bar = root.header
        if (!bar || y < 0 || y >= bar.height) return false
        let item = bar
        let px = x - bar.x
        let py = y - bar.y
        while (true) {
            const child = topChildAt(item, px, py)
            if (!child) return true
            px -= child.x
            py -= child.y
            item = child
            if (item.interactive === true || item.hovered !== undefined) return false
        }
    }
    // Where the maximize button is: Windows shows its snap layouts over it.
    function reportChromeGeometry() {
        if (!customTitleBar || !root.header) return
        const button = root.header.maximizeButton
        const p = button.mapToItem(null, 0, 0)
        chrome.setMaxButtonRect(p.x, p.y, button.width, button.height)
        chrome.setHeaderHeight(root.header.height)
    }
    onWidthChanged: Qt.callLater(reportChromeGeometry)
    onVisibilityChanged: Qt.callLater(reportChromeGeometry)
    onCustomTitleBarChanged: Qt.callLater(reportChromeGeometry)

    header: AppHeader {
        customTitleBar: root.customTitleBar
        maximized: root.visibility === Window.Maximized
        maxHovered: root.chrome ? root.chrome.maxHovered : false
        maxPressed: root.chrome ? root.chrome.maxPressed : false
        onMinimizeRequested: root.showMinimized()
        onCloseRequested: root.close()
        workspaces: root.controller.workspaces
        currentWorkspaceId: root.controller.currentWorkspaceId
        tabs: tabs
        currentView: root.currentView
        // whether the pages that unload themselves are loaded, and until when (for their tooltips)
        pageStates: ({
            questions: { loaded: questionsPage.loaded, unloadsAt: questionsPage.unloadsAt },
            graph: { loaded: graphPage.loaded, unloadsAt: graphPage.unloadsAt }
        })
        currentTab: root.currentTab
        onWorkspaceSelected: (id) => root.controller.setWorkspace(id)
        onCreateWorkspaceRequested: newWorkspace.open()
        onViewRequested: (kind) => root.currentView = kind    // "overview" | "questions" | "graph" | "search"
        onTabClicked: (index) => { root.currentView = "tab"; root.currentTab = index }
        onTabCloseClicked: (index) => root.closeTab(index)
        onWorkspaceSettingsRequested: workspaceSettings.open()
        onGlobalSettingsRequested: settings.open()

        FocusClearTapHandler { hostWindow: root }
    }

    // A page is made the first time it is shown (not at startup) and then stays loaded, so
    // switching tabs never loses a page's state.
    // The calm background (Theme.backdrop: "ambient" or "dots"), behind every page.
    Backdrop { anchors.fill: parent }

    StackLayout {
        id: pages
        anchors.fill: parent
        anchors.topMargin: 10                // a little air under the navbar, on every page
        currentIndex: root.currentView === "overview" ? 0
                    : root.currentView === "questions" ? 1
                    : root.currentView === "graph" ? 2
                    : root.currentView === "search" ? 3 : 4 + root.currentTab

        OverviewPage { controller: root.controller; actions: resourceActions }
        // Made when first opened, unloaded 5 minutes after they were left (the Overview stays).
        LazyPage {
            id: questionsPage
            shown: root.currentView === "questions"
            sourceComponent: OpenQuestionsPage { controller: root.controller; actions: resourceActions }
        }
        LazyPage {
            id: graphPage
            property int tagToShow: -2           // asked for before the page was made
            shown: root.currentView === "graph"
            onLoaded: if (tagToShow > -2) { item.showTag(tagToShow); tagToShow = -2 }
            sourceComponent: ResourceGraphPage { controller: root.controller; actions: resourceActions }
        }

        SearchPage { controller: root.controller; actions: resourceActions }

        Repeater {
            id: tabRepeater
            model: tabs
            Loader {
                required property string title
                required property string kind
                required property string uri
                required property int resourceId
                required property int startPage
                required property bool hasDocument
                sourceComponent: kind === "video" ? videoTab : kind === "unified" ? unifiedTab
                               : kind === "flowchart" ? flowchartTab : pdfViewerTab
                onLoaded: {
                    item.title = kind === "unified" ? title.replace(/^Notes: /, "") : title
                    if (kind === "unified") {
                        item.resourceId = resourceId
                        return
                    }
                    if (kind === "pdf")
                        item.hasDocument = hasDocument      // first: the uri of a web link is no PDF to load
                    item.uri = uri
                    item.startPage = startPage
                    item.resourceId = resourceId            // last: setting it starts loading the notes
                }
            }
        }
    }

    Component {
        id: pdfViewerTab
        PdfViewerPage {
            controller: root.controller
            actions: resourceActions
            onUnifiedRequested: root.openUnified(resourceId, title)
        }
    }

    Component {
        id: unifiedTab
        UnifiedNotesPage { controller: root.controller; actions: resourceActions }
    }

    Component {
        id: videoTab
        VideoPage { controller: root.controller; actions: resourceActions }
    }

    Component {
        id: flowchartTab
        FlowchartPage { controller: root.controller; actions: resourceActions }
    }

    // A capture about a page that is no resource yet: make it first (the link and its title filled
    // in), then carry on with the capture.
    ResourceDialog {
        id: captureDialog
        controller: root.controller
        property string kind: "note"
        property int seconds: 0
        function ask(link, title, captureKind, captureSeconds) {
            kind = captureKind
            seconds = captureSeconds
            openWithLink(link, title)
            // only here: which workspace it goes in, the open one unless another is picked
            chooseWorkspace = true
            workspaceId = root.controller.currentWorkspaceId
        }
        property string created: ""          // the link of the resource just made from here
        onCreateRequested: (uri, name, tagIds, moveFile) => {
            // another workspace was picked: open it, and make the resource there
            if (workspaceId >= 0 && workspaceId !== root.controller.currentWorkspaceId)
                root.controller.setWorkspace(workspaceId)
            if (root.controller.addResource(uri, name, tagIds, moveFile) !== "")
                created = uri
        }
        // Carry on once the dialog has fully closed: closing hands the keyboard back to whatever
        // had it before, which would take it from the note box again.
        onClosed: {
            if (created === "") return
            const link = created
            created = ""
            root.controller.capture(kind, link, seconds)
        }
    }

    // A resource's context menu and its edit / delete dialogs, the same wherever it is shown.
    ResourceActions {
        id: resourceActions
        controller: root.controller
        // a renamed resource: its open tab shows the new name
        onEdited: (resourceId, name) => {
            for (let i = 0; i < tabs.count; i++) {
                if (tabs.get(i).resourceId !== resourceId) continue
                const shown = tabs.get(i).kind === "unified" ? "Notes: " + name : name
                tabs.setProperty(i, "title", shown)
                const loader = tabRepeater.itemAt(i)
                if (loader && loader.item) loader.item.title = name
            }
        }
    }

    NewWorkspaceDialog {
        id: newWorkspace
        controller: root.controller
        onCreateClicked: (name, folder) => root.controller.createWorkspace(name, folder)
    }

    WorkspaceSettingsDialog {
        id: workspaceSettings
        workspaceName: {
            const w = root.controller.workspaces.find(w => w.id === root.controller.currentWorkspaceId)
            return w ? w.name : ""
        }
        canDelete: root.controller.workspaces.length > 1
        controller: root.controller
        resourceFolder: root.settingsFolder
        timelineSort: root.controller.timelineSort
        backlogSort: root.controller.backlogSort
        doneLast: root.controller.doneLast
        onTimelineSortPicked: (mode) => root.controller.setTimelineSort(mode)
        onBacklogSortPicked: (mode) => root.controller.setBacklogSort(mode)
        onDoneLastToggled: (on) => root.controller.setDoneLast(on)
        onOpenFolderRequested: root.controller.openResource(root.settingsFolder)
        onAboutToShow: root.settingsFolder = root.controller.defaultResourceFolder()
        onSaveClicked: (name) => root.controller.renameWorkspace(name)
        onDeleteConfirmed: root.controller.deleteWorkspace()
    }

    SettingsDialog {
        id: settings
        showExport: root.controller.canBackup
        pdfScrollSpeed: root.controller.pdfScrollSpeed
        onPdfScrollSpeedPicked: (speed) => root.controller.setPdfScrollSpeed(speed)
        onExportClicked: root.controller.exportBackup()
    }
    // ---- "Deleted ... Undo" toasts (bottom right, newest at the bottom) ----
    ListModel { id: undoToasts }

    function removeUndoToast(token) {
        for (let i = 0; i < undoToasts.count; i++) {
            if (undoToasts.get(i).token === token) { undoToasts.remove(i); return }
        }
    }

    Column {
        id: undoHost
        z: 20
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20
        spacing: 10

        Repeater {
            model: undoToasts
            UndoToast {
                required property int token
                required property string text
                message: text
                onUndone: root.controller.undo(token)
                onExpired: root.controller.expireUndo(token)
                onRemoved: root.removeUndoToast(token)
            }
        }
    }

    TabSwitcher {
        id: tabSwitcher
        z: 30
        anchors.fill: parent
        onChosen: (key) => {
            root.showView(key)
            root.contentItem.forceActiveFocus()          // out of whatever field had the keyboard
        }
    }

    AppToast {
        id: toast
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        maximumWidth: root.width - 40
    }

    // Local files can disappear while the app is open: re-check them when the window is focused again.
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive)
                root.controller.refreshResources()
        }
    }

    Connections {
        target: root.controller
        function onNotify(message) { toast.show(message) }
        function onPdfRequested(resourceId, name, uri, page) { root.openPdf(resourceId, name, uri, page) }
        function onNotesRequested(resourceId, name, uri, page) { root.openNotes(resourceId, name, uri, page) }
        function onVideoRequested(resourceId, name, uri, page) { root.openVideo(resourceId, name, uri, page) }
        function onFlowchartRequested(resourceId, name, uri) { root.openFlowchart(resourceId, name, uri) }
        function onCaptureReady(resourceId, kind, seconds) { root.openCaptureBox(resourceId, kind, seconds) }
        // a tag clicked in a todo or a note: the Resource graph, at that tag
        function onTagRequested(tagId) {
            root.currentView = "graph"
            if (graphPage.item) graphPage.item.showTag(tagId)
            else graphPage.tagToShow = tagId
        }
        function onCaptureNeedsResource(link, title, kind, seconds) { captureDialog.ask(link, title, kind, seconds) }
        // its notes went with it: the tab could only show errors now
        function onResourceRemoved(resourceId) { root.closeTabsOf(resourceId) }
        function onWorkspaceFolderChanged() { root.settingsFolder = root.controller.defaultResourceFolder() }
        // its PDF is being replaced: a tab would keep the old file locked
        function onResourceTabsShouldClose(resourceId) { root.closeTabsOf(resourceId) }
        function onUndoOffered(token, message) {
            // at most four at once: the oldest one becomes final
            if (undoToasts.count >= 4) {
                root.controller.expireUndo(undoToasts.get(0).token)
                undoToasts.remove(0)
            }
            undoToasts.append({ token: token, text: message })
        }
    }
}
