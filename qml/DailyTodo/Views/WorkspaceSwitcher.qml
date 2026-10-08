import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Button showing the current workspace name + a chevrons icon; clicking lists all workspaces.
AppButton {
    id: control

    property var workspaces: []            // [{id, name}]
    property int currentId: -1
    readonly property string current: {
        const w = workspaces.find(w => w.id === currentId)
        return w ? w.name : ""
    }

    signal workspaceSelected(int id)
    signal createRequested()

    leftPadding: compact ? 12 : 14
    rightPadding: compact ? 8 : 10
    raised: true

    onClicked: menu.open()

    contentItem: RowLayout {
        spacing: 6
        Text {
            text: control.current
            font.pixelSize: control.compact ? 13 : 14
            font.bold: true
            color: control.textColor
            elide: Text.ElideRight
            Layout.maximumWidth: 160
        }
        IconImage {
            source: Theme.iconChevronsUpDown
            sourceSize: Qt.size(Theme.iconSize, Theme.iconSize)
            color: Theme.textMuted
        }
    }

    AppMenu {
        id: menu
        y: control.height + 4

        // Not a Repeater: when its model changes, a Repeater inside a Menu appends the new items
        // after the static ones below. Instantiator + insertItem keeps them at the top.
        Instantiator {
            model: control.workspaces
            delegate: AppMenuItem {
                required property var modelData
                text: modelData.name
                highlighted: modelData.id === control.currentId
                onTriggered: control.workspaceSelected(modelData.id)
            }
            onObjectAdded: (index, object) => menu.insertItem(index, object)
            onObjectRemoved: (index, object) => menu.removeItem(object)
        }

        // "Create new" is an action, not a workspace: set apart by a divider and accent colour.
        MenuSeparator {
            padding: 4
            topPadding: 4
            bottomPadding: 4
            contentItem: Rectangle {
                implicitHeight: 1
                color: Theme.hairline
            }
        }
        MenuItem {
            id: createItem
            text: "+  Create new"
            implicitWidth: 140
            implicitHeight: 34
            leftPadding: 14
            rightPadding: 14
            topPadding: 0
            bottomPadding: 0
            onTriggered: control.createRequested()

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            contentItem: Text {
                text: createItem.text
                font.pixelSize: 13
                color: Theme.accentHover
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 9
                color: createItem.down ? Qt.alpha(Theme.text, 0.12)
                     : createItem.highlighted ? Qt.alpha(Theme.text, 0.07) : "transparent"
            }
        }
    }
}
