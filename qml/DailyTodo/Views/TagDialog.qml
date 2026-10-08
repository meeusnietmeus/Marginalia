import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Modal for a new tag or for editing one: its name and which tag it sits below (a sub-tag).
AppDialog {
    id: dialog

    required property var controller

    property int tagId: -1                   // -1: creating a new tag
    property int parentId: -1                // the tag it is a sub-tag of, -1: top level
    property var choices: []                 // where it may go: [{id, name, depth, path}]
    readonly property bool editing: tagId >= 0
    readonly property string parentPath: {
        for (const c of choices) if (c.id === parentId) return c.path
        return ""
    }

    signal createClicked(string name, int parentId)
    signal saveClicked(int id, string name, int parentId)

    readonly property string name: field.text.trim()

    function openNew(parent) {
        tagId = -1
        parentId = parent === undefined ? -1 : parent
        choices = controller.tagParentChoices(-1)
        field.text = ""
        open()
    }

    function openFor(id, currentName, currentParent) {
        tagId = id
        parentId = currentParent
        choices = controller.tagParentChoices(id)
        field.text = currentName
        open()
    }

    function submit() {
        if (name === "") return
        if (editing) saveClicked(tagId, name, parentId)
        else createClicked(name, parentId)
        close()
    }

    width: Math.min(360, parent.width - 40)

    onOpened: {
        field.forceActiveFocus()
        field.selectAll()
    }

    contentItem: ColumnLayout {
        spacing: 16

        DialogTitle {
            text: dialog.editing ? "Edit tag" : (dialog.parentId >= 0 ? "New sub-tag" : "New tag")
        }

        AppTextField {
            id: field
            placeholderText: "Tag name"
            Layout.fillWidth: true
            onAccepted: dialog.submit()
        }

        // which tag this one sits below
        ColumnLayout {
            spacing: 6
            Layout.fillWidth: true
            Label { text: "Sub-tag of"; font.pixelSize: 12; color: Theme.textMuted }
            AppButton {
                id: parentButton
                Layout.fillWidth: true
                text: dialog.parentId >= 0 ? dialog.parentPath : "None (a top-level tag)"
                onClicked: parentMenu.popup(0, height + 4)

                AppMenu {
                    id: parentMenu
                    AppMenuItem {
                        text: "None (a top-level tag)"
                        highlighted: dialog.parentId < 0
                        onTriggered: dialog.parentId = -1
                    }
                    Repeater {
                        model: dialog.choices
                        AppMenuItem {
                            required property var modelData
                            text: "    ".repeat(modelData.depth) + (modelData.depth > 0 ? "↳ " : "") + modelData.name
                            highlighted: dialog.parentId === modelData.id
                            onTriggered: dialog.parentId = modelData.id
                        }
                    }
                }
            }
        }

        RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            AppButton {
                text: "Cancel"
                onClicked: dialog.close()
            }
            AppButton {
                text: dialog.editing ? "Save" : "Create"
                filled: true
                enabled: dialog.name !== ""
                onClicked: dialog.submit()
            }
        }
    }
}