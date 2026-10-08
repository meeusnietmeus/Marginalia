import QtQuick
import DailyTodo.Style
import DailyTodo.Controls

// What can be done to a resource, wherever it is shown: its context menu (Edit, Delete, Open link /
// Reveal in file explorer) and the dialogs those open. One of these lives in the window (Main.qml)
// and is handed to everything that shows resources: the library, "Jump back in", and the
// Connections of a resource's own tab. So the menu is the same everywhere, and there is one
// edit dialog and one "delete?" dialog for the whole app.
//
//   actions.showMenu(resourceId, item, x, y)   right-click on a resource (x, y in item's coordinates)
//   actions.create()                           the "New resource" dialog
//   actions.edit(resourceId)                   the edit dialog (also: a file that went missing)
Item {
    id: actions

    required property var controller

    // the resource the menu is open for (-1: none), e.g. to keep its card lit meanwhile
    readonly property int menuResourceId: menu.visible ? menu.info.id : -1
    readonly property bool menuOpen: menu.visible

    signal edited(int resourceId, string name)    // renamed / changed: open tabs show the new name

    function showMenu(resourceId, item, x, y) {
        const info = controller.resourceInfo(resourceId)
        if (info.id === undefined) return
        menu.info = info
        menu.popup(item, x, y)
    }
    function create() { dialog.openNew() }
    function edit(resourceId) {
        const r = controller.resourceInfo(resourceId)
        if (r.id !== undefined) dialog.openFor(r.id, r.uri, r.isPath, r.tagIds, r.name)
    }
    function remove(resourceId) {
        const r = controller.resourceInfo(resourceId)
        if (r.id !== undefined) confirmDelete.ask(r.id, controller.deleteResourceWarning(r.id, r.name))
    }

    CrudMenu {
        id: menu
        property var info: ({ id: -1, uri: "", isPath: false })
        onEditTriggered: actions.edit(menu.info.id)
        onDeleteTriggered: actions.remove(menu.info.id)

        // a link opens in its program, a file can be shown in the file explorer
        AppMenuItem {
            visible: !menu.info.isPath
            height: visible ? implicitHeight : 0
            text: "Open link"
            iconSource: Theme.iconExternal
            onTriggered: {
                actions.controller.openResource(menu.info.uri)
                actions.controller.touchResource(menu.info.id)
            }
        }
        AppMenuItem {
            visible: menu.info.isPath
            height: visible ? implicitHeight : 0
            text: "Reveal in file explorer"
            iconSource: Theme.iconFolder
            onTriggered: actions.controller.revealInExplorer(menu.info.uri)
        }
    }

    ResourceDialog {
        id: dialog
        controller: actions.controller
        onCreateRequested: (uri, name, tagIds, moveFile) =>
            actions.controller.addResource(uri, name, tagIds, moveFile)
        onUpdateRequested: (id, uri, name, tagIds) => {
            actions.controller.updateResource(id, uri, name, tagIds)
            actions.edited(id, name)
        }
    }

    ConfirmDialog {
        id: confirmDelete
        title: "Delete resource?"
        onConfirmed: (id) => actions.controller.deleteResource(id)
    }
}
