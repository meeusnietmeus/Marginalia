import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import DailyTodo.Style
import DailyTodo.Controls

// Navigation bar: workspace switcher, the fixed views, then the open tabs; settings on the right.
// It is also the window's title bar when the window has none of its own (customTitleBar): the
// empty parts move the window, and the window buttons sit at the far right.
ToolBar {
    id: header

    property var workspaces: []
    property int currentWorkspaceId: -1
    property var tabs                  // ListModel with `title` per open tab
    property string currentView: "overview"
    // {questions: {loaded, unloadsAt}, graph: {...}}: the pages that unload themselves (LazyPage)
    property var pageStates: ({})
    property int currentTab: -1

    property bool customTitleBar: false         // draw the minimize / maximize / close buttons
    property bool maximized: false
    property bool maxHovered: false
    property bool maxPressed: false
    readonly property Item maximizeButton: windowControls.maximizeButton

    signal minimizeRequested()
    signal closeRequested()
    signal workspaceSelected(int id)
    signal createWorkspaceRequested()
    signal viewRequested(string kind)
    signal tabClicked(int index)
    signal tabCloseClicked(int index)
    signal workspaceSettingsRequested()
    signal globalSettingsRequested()

    implicitHeight: 28 + 18

    // a bar lying a little above the page: light on its top edge, a hairline and a soft shadow below
    background: Item {
        RectangularShadow {
            anchors.fill: bar
            offset.y: 2
            blur: 12
            color: Qt.rgba(0, 0, 0, 0.35)
        }
        Rectangle {
            id: bar
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(Theme.toolbar, 1.07) }
                GradientStop { position: 1; color: Theme.toolbar }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.hairline
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.topMargin: 9
        anchors.bottomMargin: 9
        anchors.leftMargin: 12
        anchors.rightMargin: 12 + (header.customTitleBar ? windowControls.width : 0)
        spacing: 4

        WorkspaceSwitcher {
            Layout.rightMargin: 10
            workspaces: header.workspaces
            currentId: header.currentWorkspaceId
            compact: true
            onWorkspaceSelected: (id) => header.workspaceSelected(id)
            onCreateRequested: header.createWorkspaceRequested()
        }
        // The fixed pages: tabs in an inset track, the current one raised out of it.
        Item {
            readonly property bool interactive: true          // not part of the movable title bar
            implicitWidth: pages.implicitWidth + 6
            implicitHeight: 32
            Well { anchors.fill: parent; radius: height / 2 }
            Row {
                id: pages
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: [{ kind: "overview", text: "Overview" },
                            { kind: "questions", text: "Open questions" },
                            { kind: "graph", text: "Knowledge graph" }]
                    AppButton {
                        id: pageButton
                        required property var modelData
                        readonly property var pageState: header.pageStates[modelData.kind]
                        text: modelData.text
                        compact: true
                        implicitHeight: 26
                        active: header.currentView === modelData.kind
                        textColor: active ? Theme.text : Theme.textMuted
                        onClicked: header.viewRequested(modelData.kind)

                        // a page that unloads itself says whether it is loaded (and for how long)
                        AppToolTip {
                            shown: pageButton.hovered && pageButton.pageState !== undefined
                            text: {
                                pageButton.hovered                  // the time left, as of now
                                const s = pageButton.pageState
                                if (!s) return ""
                                if (!s.loaded) return "Unloaded: it loads when you open it"
                                if (pageButton.active || s.unloadsAt <= 0)
                                    return "Loaded: unloads 5 min after you leave it"
                                const minutes = Math.max(1, Math.ceil((s.unloadsAt - Date.now()) / 60000))
                                return "Loaded: unloads in " + minutes + " min"
                            }
                        }
                    }
                }
            }
        }

        ListView {
            id: tabStrip
            orientation: ListView.Horizontal
            model: header.tabs
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Layout.leftMargin: 20
            Layout.fillWidth: true
            Layout.fillHeight: true

            delegate: Item {
                id: tab
                required property int index
                required property string title
                readonly property bool current: header.currentView === "tab" && index === header.currentTab
                readonly property bool interactive: true      // not part of the movable title bar

                width: Math.min(240, tabRow.implicitWidth + 14)
                height: ListView.view.height

                // the current tab stands up as a raised chip; the others only show a wash on hover
                Surface {
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: tab.current
                    radius: height / 2
                    lit: tabArea.hovered
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: !tab.current
                    radius: height / 2
                    color: tabArea.hovered ? Qt.alpha(Theme.text, 0.07) : "transparent"
                }

                HoverHandler { id: tabArea; cursorShape: Qt.PointingHandCursor }
                ClickHandler { onTapped: header.tabClicked(tab.index) }
                // middle click closes the tab, like in a browser
                ClickHandler {
                    acceptedButtons: Qt.MiddleButton
                    onTapped: header.tabCloseClicked(tab.index)
                }

                RowLayout {
                    id: tabRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 4

                    Text {
                        text: tab.title
                        font.pixelSize: 12
                        color: tab.current ? Theme.text : Theme.textMuted
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    IconButton {
                        iconSource: Theme.iconClose
                        iconSize: 12
                        compact: true
                        implicitWidth: 20
                        implicitHeight: 20
                        textColor: Theme.textMuted
                        onClicked: header.tabCloseClicked(tab.index)
                    }
                }
            }
        }

        IconButton {
            iconSource: Theme.iconSettings
            fallbackText: "*"
            compact: true
            onClicked: settingsMenu.open()

            AppMenu {
                id: settingsMenu
                width: 190
                x: parent.width - width
                y: parent.height + 4

                AppMenuItem {
                    text: "Workspace settings"
                    onTriggered: header.workspaceSettingsRequested()
                }
                AppMenuItem {
                    text: "Global settings"
                    onTriggered: header.globalSettingsRequested()
                }
            }
        }
    }

    WindowControls {
        id: windowControls
        visible: header.customTitleBar
        anchors.right: parent.right
        anchors.top: parent.top
        height: header.height
        maximized: header.maximized
        maxHovered: header.maxHovered
        maxPressed: header.maxPressed
        onMinimizeClicked: header.minimizeRequested()
        onCloseClicked: header.closeRequested()
    }
}