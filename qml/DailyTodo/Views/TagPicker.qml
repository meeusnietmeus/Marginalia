import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import DailyTodo.Style
import DailyTodo.Controls

// Choosing the tags of a resource, however many tags the workspace has. The chosen ones are small
// chips in the field (× to take one off); the field takes typing, and a list drops down under it:
// the tags in their tree (a sub-tag under its tag), narrowed down by what is typed, with a check
// at the chosen ones. Up / Down and Enter pick from it, Backspace in the empty field takes the last
// chip off, and a name that matches no tag can be made into one right there.
//
// It doesn't keep the choice itself: give it `selected` (tag ids) and act on toggleRequested(id).
Item {
    id: picker

    required property var controller
    property var selected: []                 // tag ids
    property int workspaceId: -1              // whose tags (-1: the open workspace's)

    signal toggleRequested(int tagId)

    readonly property string query: input.text.trim()
    property var allTags: []                  // every tag, in tree order: {id, name, depth, path, family}
    function reload() {
        allTags = workspaceId < 0 ? controller.tagParentChoices(-1) : controller.tagChoicesIn(workspaceId)
    }
    onWorkspaceIdChanged: reload()

    // what the list shows: the tags that match, and "Create ..." when none is called that exactly
    readonly property var rows: {
        const q = query.toLowerCase()
        const found = allTags.filter(t => q === "" || t.path.toLowerCase().indexOf(q) >= 0)
        if (q !== "" && !allTags.some(t => t.name.toLowerCase() === q))
            found.push({ id: -1, name: query, depth: 0, path: query, family: -1, create: true })
        return found
    }
    property int current: 0
    onQueryChanged: current = 0

    function choose(i) {
        const row = rows[i]
        if (!row) return
        if (row.create) {
            const id = workspaceId < 0 ? controller.createTag(row.name, -1)
                                       : controller.createTagIn(workspaceId, row.name)
            if (id < 0) return
            reload()
            toggleRequested(id)
        } else {
            toggleRequested(row.id)
        }
        input.text = ""
        input.forceActiveFocus()
    }
    function tint(family) { return family < 0 ? Theme.textMuted : Theme.areaColor(family) }

    implicitHeight: Math.max(40, chips.implicitHeight + 12)

    // tags made, renamed or moved elsewhere (the tag view) while this is open
    Connections {
        target: picker.controller.tags
        function onModelReset() { picker.reload() }
        function onRowsInserted() { picker.reload() }
        function onRowsRemoved() { picker.reload() }
        function onDataChanged() { picker.reload() }
    }
    Component.onCompleted: reload()

    // ---- the field: the chosen tags, then room to type ----
    Well {
        anchors.fill: parent
        radius: 14
        focused: input.activeFocus
    }
    Flow {
        id: chips
        x: 6
        y: 6
        width: parent.width - 12
        spacing: 6

        Repeater {
            // the chosen ones, in tree order
            model: picker.allTags.filter(t => picker.selected.indexOf(t.id) >= 0)
            Rectangle {
                id: chip
                required property var modelData
                readonly property int tagId: modelData.id
                readonly property string name: modelData.name
                readonly property string path: modelData.path
                readonly property int depth: modelData.depth
                readonly property int family: modelData.family
                readonly property color tint: picker.tint(family)
                width: chipRow.implicitWidth + 12
                height: 28
                radius: height / 2
                color: Qt.alpha(tint, 0.16)
                border.color: Qt.alpha(tint, 0.5)

                Row {
                    id: chipRow
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 3.5
                        color: chip.tint
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // a sub-tag: its tag above it, faint, in front
                        text: chip.depth > 0
                              ? "<font color=\"" + Theme.textFaint + "\">"
                                + chip.path.slice(0, chip.path.length - chip.name.length) + "</font>" + chip.name
                              : chip.name
                        textFormat: Text.StyledText
                        font.pixelSize: 12
                        color: Theme.text
                    }
                    AppButton {
                        anchors.verticalCenter: parent.verticalCenter
                        compact: true
                        implicitHeight: 20
                        implicitWidth: 20
                        leftPadding: 0
                        rightPadding: 0
                        text: "×"
                        font.pixelSize: 14
                        textColor: Theme.textMuted
                        onClicked: picker.toggleRequested(chip.tagId)
                    }
                }
            }
        }

        Item {
            width: 116
            height: 28
            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: 13
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentText
                selectByMouse: true
                clip: true
                onActiveFocusChanged: {
                    if (activeFocus) { picker.reload(); dropdown.open() }
                    else Qt.callLater(() => { if (!input.activeFocus) dropdown.close() })   // Tab away
                }
                onTextChanged: if (activeFocus && !dropdown.opened) dropdown.open()

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Down) {
                        if (!dropdown.opened) dropdown.open()
                        picker.current = Math.min(picker.rows.length - 1, picker.current + 1)
                        list.positionViewAtIndex(picker.current, ListView.Contain)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        picker.current = Math.max(0, picker.current - 1)
                        list.positionViewAtIndex(picker.current, ListView.Contain)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (dropdown.opened && picker.rows.length > 0) {
                            picker.choose(picker.current)
                            event.accepted = true      // not the dialog's "Create"
                        }
                    } else if (event.key === Qt.Key_Backspace && text === "" && picker.selected.length > 0) {
                        picker.toggleRequested(picker.selected[picker.selected.length - 1])
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape && (text !== "" || dropdown.opened)) {
                        text = ""
                        dropdown.close()
                        event.accepted = true          // not the dialog's: it stays open
                    }
                }
            }
            Text {
                visible: input.text === ""
                anchors.fill: input
                verticalAlignment: Text.AlignVCenter
                text: picker.selected.length === 0 ? "Add tags..." : "Add another..."
                font.pixelSize: 13
                color: Theme.textFaint
            }
            HoverHandler { cursorShape: Qt.IBeamCursor }
        }
    }
    // a click anywhere in the field is a click in the text
    ClickHandler {
        onTapped: input.forceActiveFocus()
    }

    // ---- the list under the field ----
    Popup {
        id: dropdown
        y: picker.height + 6
        width: picker.width
        height: Math.min(264, list.contentHeight + 12)
        padding: 6
        closePolicy: Popup.CloseOnPressOutsideParent
        focus: false                                   // the typing stays in the field

        background: Surface {
            elevation: 2
            radius: 14
        }

        contentItem: ListView {
            id: list
            clip: true
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds
            model: picker.rows
            ScrollBar.vertical: AppScrollBar {}

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool chosen: !modelData.create && picker.selected.indexOf(modelData.id) >= 0
                readonly property bool filtering: picker.query !== ""
                readonly property color tint: picker.tint(modelData.family)
                width: ListView.view.width
                height: 32

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: row.index === picker.current ? Qt.alpha(Theme.text, 0.08)
                         : rowHover.hovered ? Qt.alpha(Theme.text, 0.05) : "transparent"
                }
                // the colour: a dot for a tag, a ring for a sub-tag, a plus for a new one
                Rectangle {
                    id: swatch
                    visible: !row.modelData.create
                    x: 10 + (row.filtering ? 0 : row.modelData.depth * 16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 4.5
                    color: row.modelData.depth === 0 ? row.tint : "transparent"
                    border.width: row.modelData.depth === 0 ? 0 : 2
                    border.color: row.tint
                }
                IconImage {
                    visible: row.modelData.create === true
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    source: Theme.iconPlus
                    sourceSize: Qt.size(14, 14)
                    color: Theme.accentHover
                }
                Text {
                    anchors.left: swatch.right
                    anchors.leftMargin: 9
                    anchors.right: check.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.create ? "Create tag “" + row.modelData.name + "”"
                        : row.filtering ? row.modelData.path : row.modelData.name
                    elide: Text.ElideLeft
                    font.pixelSize: 13
                    font.weight: row.chosen ? Font.DemiBold : Font.Normal
                    color: row.modelData.create ? Theme.accentHover : Theme.text
                }
                IconImage {
                    id: check
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.chosen
                    source: Theme.iconSave
                    sourceSize: Qt.size(14, 14)
                    color: Theme.ringDone
                }
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                ClickHandler { onTapped: picker.choose(row.index) }
            }
        }
    }
}
