import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import DailyTodo.Style
import DailyTodo.Controls

// The Library column: the workspace's resources as a two-column grid of cards.
SideColumn {
    id: library

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    title: "Library"
    badge: library.controller.resourceTotal > 0 ? String(library.controller.resourceTotal) : ""

    // Keep the column open while a context menu (of a card or a tag), the tag filter or the sort
    // menu is showing.
    property int openMenus: 0                // tag menus
    property int cardMenuFor: -1             // the card whose menu was opened from here
    readonly property bool cardMenuOpen: actions.menuOpen && actions.menuResourceId === cardMenuFor
    pinned: openMenus > 0 || cardMenuOpen || tagFilter.opened || sortMenu.opened

    // Resources or tags.
    property bool showTags: false

    headerActions: [
        SegmentedSwitch {
            anchors.verticalCenter: parent.verticalCenter
            leftIcon: Theme.iconGrid
            rightIcon: Theme.iconTag
            rightActive: library.showTags
            onToggledTo: (right) => library.showTags = right
        }
    ]
    headerActionsEnd: [
        AppButton {
            anchors.verticalCenter: parent.verticalCenter
            compact: true
            filled: true
            contentItem: Row {
                spacing: 6
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Theme.iconPlus
                    sourceSize: Qt.size(14, 14)
                    color: Theme.accentText
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: library.showTags ? "New tag" : "New resource"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Theme.accentText
                }
            }
            onClicked: library.showTags ? tagDialog.openNew() : library.actions.create()
        }
    ]

    // Space the controls row takes: none while the column is collapsed (or showing tags), so the
    // content moves up instead of leaving a gap; it slides open with the column.
    property real searchSpace: library.revealed && !library.showTags ? Theme.controlHeight + 10 : 0
    Behavior on searchSpace { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // Collapsed, the library shows nothing real: ten empty blocks stand in for the grid. Opening
    // fades them out while the real content fades in. Opening also always starts on resources.
    property real contentOpacity: library.revealed ? 1 : 0
    Behavior on contentOpacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    onRevealedChanged: if (revealed) showTags = false

    readonly property var sortLabels: ({ recent: "Recently used", name: "Alphabetical", added: "Recently added" })
    readonly property var sortShort: ({ recent: "Recent", name: "A-Z", added: "Added" })

    // ---- search (Enter), tag filter (immediately), whitespace, sort ----
    Row {
        id: controls
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.controlHeight
        spacing: 6
        opacity: library.revealed && !library.showTags ? 1 : 0
        enabled: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Name filter: applied when Enter is pressed (an empty field + Enter clears it).
        AppTextField {
            id: search
            width: parent.width - tagFilterButton.width - sortButton.width - 2 * parent.spacing - 14
            placeholderText: "Search by name..."
            onAccepted: library.controller.setResourceQuery(text)
            // emptying the box (Ctrl+A, Backspace ...) shows everything again without Enter
            onTextChanged: if (text === "") library.controller.setResourceQuery("")
        }

        // Tag filter: pick any number; the list updates as soon as a box is ticked or cleared.
        AppButton {
            id: tagFilterButton
            readonly property int selected: library.controller.resourceTagFilter.length
            compact: true
            active: selected > 0 || tagFilter.opened
            implicitHeight: Theme.controlHeight
            contentItem: Row {
                spacing: 6
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Theme.iconTag
                    sourceSize: Qt.size(14, 14)
                    color: tagFilterButton.selected > 0 ? Theme.accentHover : Theme.text
                }
                Text {
                    visible: tagFilterButton.selected > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: tagFilterButton.selected
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.accentHover
                }
            }
            onClicked: tagFilter.opened ? tagFilter.close() : tagFilter.open()

            Popup {
                id: tagFilter
                y: parent.height + 4
                x: parent.width - width
                width: 220
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                background: Surface {
                    elevation: 2
                    radius: 14
                }

                contentItem: Column {
                    spacing: 2

                    Repeater {
                        id: filterRepeater
                        model: library.controller.tags
                        Item {
                            id: tagRow
                            required property int tagId
                            required property string name
                            required property int depth
                            width: tagFilter.availableWidth
                            height: 30

                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: rowHover.hovered ? Qt.alpha(Theme.text, 0.07) : "transparent"
                            }
                            AppCheckBox {
                                id: tagCheck
                                anchors.left: parent.left
                                anchors.leftMargin: 6 + tagRow.depth * 18        // sub-tags sit under their tag
                                anchors.verticalCenter: parent.verticalCenter
                                checked: library.controller.resourceTagFilter.indexOf(tagRow.tagId) >= 0
                                onToggled: library.controller.toggleResourceTag(tagRow.tagId)
                            }
                            Text {
                                anchors.left: tagCheck.right
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: tagRow.name
                                elide: Text.ElideRight
                                font.pixelSize: 13
                                color: Theme.text
                            }
                            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                            ClickHandler { onTapped: library.controller.toggleResourceTag(tagRow.tagId) }
                        }
                    }

                    Text {
                        visible: filterRepeater.count === 0
                        width: tagFilter.availableWidth
                        height: 30
                        leftPadding: 8
                        verticalAlignment: Text.AlignVCenter
                        text: "No tags yet"
                        font.pixelSize: 13
                        color: Theme.textFaint
                    }

                    Text {
                        visible: filterRepeater.count > 0
                        width: tagFilter.availableWidth
                        leftPadding: 8
                        topPadding: 4
                        bottomPadding: 2
                        wrapMode: Text.Wrap
                        text: "A tag also finds what is tagged with its sub-tags."
                        font.pixelSize: 11
                        color: Theme.textFaint
                    }

                    AppButton {
                        visible: tagFilterButton.selected > 0
                        compact: true
                        text: "Clear filter"
                        textColor: Theme.textMuted
                        onClicked: library.controller.clearResourceTagFilter()
                    }
                }
            }
        }

        // whitespace between the filters and the sort option
        Item { width: 14; height: 1 }

        AppButton {
            id: sortButton
            compact: true
            active: sortMenu.opened
            implicitHeight: Theme.controlHeight
            contentItem: Row {
                spacing: 6
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Theme.iconSort
                    sourceSize: Qt.size(14, 14)
                    color: Theme.text
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: library.sortShort[library.controller.resourceSort]
                    font.pixelSize: 12
                    color: Theme.text
                }
            }
            onClicked: sortMenu.opened ? sortMenu.close() : sortMenu.popup(0, height + 4)

            AppMenu {
                id: sortMenu
                x: parent.width - width
                Repeater {
                    model: ["recent", "name", "added"]
                    AppMenuItem {
                        required property string modelData
                        text: library.sortLabels[modelData]
                        highlighted: library.controller.resourceSort === modelData
                        onTriggered: library.controller.setResourceSort(modelData)
                    }
                }
            }
        }
    }
    // ---- tags: pills that wrap onto as many lines as needed ----
    Flickable {
        anchors.top: parent.top
        anchors.topMargin: library.searchSpace
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: library.showTags
        opacity: library.contentOpacity
        enabled: library.revealed
        clip: true
        contentHeight: tagFlow.height
        boundsBehavior: Flickable.StopAtBounds

        // a tree: every tag on its own line, its sub-tags below it and indented
        Column {
            id: tagFlow
            width: parent.width
            spacing: 6

            Repeater {
                id: tagRepeater
                model: library.controller.tags
                Row {
                    id: tagLine
                    required property int tagId
                    required property string name
                    required property int parentId
                    required property int depth
                    required property int childCount
                    spacing: 6
                    leftPadding: depth * 22

                    Text {                                   // the elbow of a sub-tag
                        visible: tagLine.depth > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↳"
                        font.pixelSize: 13
                        color: Theme.textFaint
                    }
                    TagPill {
                        text: tagLine.name
                        menuEnabled: true
                        onMenuOpenChanged: library.openMenus += menuOpen ? 1 : -1
                        onAddChildRequested: tagDialog.openNew(tagLine.tagId)
                        onEditRequested: tagDialog.openFor(tagLine.tagId, tagLine.name, tagLine.parentId)
                        onDeleteRequested: library.controller.deleteTag(tagLine.tagId)
                    }
                    CapsLabel {
                        visible: tagLine.childCount > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: tagLine.childCount + (tagLine.childCount === 1 ? " sub-tag" : " sub-tags")
                        color: Theme.textFaint
                    }
                }
            }
        }

    }

    // ---- resources: two-column grid ----
    Flickable {
        anchors.top: parent.top
        anchors.topMargin: library.searchSpace
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: !library.showTags && resourceRepeater.count > 0
        opacity: library.contentOpacity
        enabled: library.revealed
        clip: true
        contentHeight: resourceGrid.height
        boundsBehavior: Flickable.StopAtBounds

        Grid {
            id: resourceGrid
            width: parent.width
            columns: 2
            readonly property real cellWidth: width / 2
            readonly property real cellHeight: 90

            Repeater {
                id: resourceRepeater
                model: library.controller.resources

                delegate: Item {
                    id: cell
                    required property int resourceId
                    required property string name
                    required property string uri
                    required property string kind
                    required property string title
                    required property bool isPath
                    required property bool missing
                    required property var tagIds

                    width: resourceGrid.cellWidth
                    height: resourceGrid.cellHeight

                    ResourceCard {
                        anchors.fill: parent
                        anchors.margins: 6
                        kind: cell.kind
                        title: cell.title
                        missing: cell.missing
                        menuShown: library.cardMenuOpen && library.cardMenuFor === cell.resourceId
                        onMenuRequested: (position) => {
                            library.cardMenuFor = cell.resourceId
                            library.actions.showMenu(cell.resourceId, this, position.x, position.y)
                        }
                        onClicked: {
                            if (cell.missing) {
                                library.actions.edit(cell.resourceId)
                                return
                            }
                            library.controller.openResourceById(cell.resourceId)
                        }
                    }
                }
            }
        }
    }

    // ---- empty states ----
    Text {
        visible: !library.showTags && resourceRepeater.count === 0
        opacity: library.contentOpacity
        anchors.fill: parent
        anchors.topMargin: library.searchSpace
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        text: library.controller.resourceTotal === 0 ? "No resources yet.\nCreate one to get started."
                                                      : "No resources match."
        font.pixelSize: 18
        color: Theme.textMuted
    }
    Text {
        visible: library.showTags && tagRepeater.count === 0
        opacity: library.contentOpacity
        anchors.fill: parent
        anchors.topMargin: library.searchSpace
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        text: "No tags yet.\nCreate one to get started."
        font.pixelSize: 18
        color: Theme.textMuted
    }
    // ---- collapsed: ten empty blocks (same cells as the grid), fading out as it opens ----
    Grid {
        anchors.top: parent.top
        anchors.topMargin: library.searchSpace
        anchors.left: parent.left
        anchors.right: parent.right
        columns: 2
        opacity: 1 - library.contentOpacity
        visible: opacity > 0

        Repeater {
            model: 10
            Item {
                width: parent.width / 2
                height: 90
                Surface {
                    anchors.fill: parent
                    anchors.margins: 6
                    elevation: 0
                    opacity: 0.6
                }
            }
        }
    }
    TagDialog {
        id: tagDialog
        controller: library.controller
        onCreateClicked: (name, parentId) => library.controller.createTag(name, parentId)
        onSaveClicked: (id, name, parentId) => library.controller.updateTag(id, name, parentId)
    }
}
