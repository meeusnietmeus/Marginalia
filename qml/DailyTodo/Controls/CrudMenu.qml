import QtQuick
import QtQuick.Layouts
import DailyTodo.Style

// The context menu of anything that can be edited and deleted.
//
//   +---------------------------+
//   |  [copy]  [edit]  [delete] |   top section: icon buttons in a row
//   |---------------------------|
//   |  Some other action        |   bottom section: ordinary entries
//   +---------------------------+
//
// Edit and Delete are always in the top section (editTriggered / deleteTriggered). More icon
// buttons go in front of them with `topBefore` or behind them with `topAfter` (MenuIconButtons);
// ordinary entries (AppMenuItem) are simply declared as children and form the bottom section.
// The separator only shows when there is a bottom section.
//
//   CrudMenu {
//       onEditTriggered: ...
//       onDeleteTriggered: ...
//       topBefore: [ MenuIconButton { iconSource: Theme.iconCopy; text: "Copy"; onTriggered: ... } ]
//       AppMenuItem { text: "Move to backlog"; onTriggered: ... }
//   }
AppMenu {
    id: menu

    property bool canEdit: true
    property bool canDelete: true
    property alias topBefore: before.data
    property alias topAfter: after.data

    signal editTriggered()
    signal deleteTriggered()

    // top section
    Item {
        id: top
        readonly property var crudMenu: menu       // how the buttons find the menu (MenuIconButton)
        implicitWidth: toolbar.implicitWidth + 8
        implicitHeight: 36

        RowLayout {
            id: toolbar
            anchors.fill: parent
            anchors.margins: 2
            spacing: 4
            RowLayout { id: before; spacing: 4; Layout.fillWidth: children.length > 0 }
            MenuIconButton {
                visible: menu.canEdit
                text: "Edit"
                iconSource: Theme.iconEdit
                onTriggered: menu.editTriggered()
            }
            MenuIconButton {
                visible: menu.canDelete
                text: "Delete"
                iconSource: Theme.iconTrash
                tint: Theme.danger
                onTriggered: menu.deleteTriggered()
            }
            RowLayout { id: after; spacing: 4; Layout.fillWidth: children.length > 0 }
        }
    }

    // bottom section: whatever the user of this menu declares comes after this separator
    AppMenuSeparator { visible: menu.count > 2 }
}
