import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Modal for a new tag or for editing one: its name, which tag it sits below (a sub-tag) and, for a
// top-level tag, its colour (the graph and the tag lists use it; a sub-tag shares its top tag's).
AppDialog {
    id: dialog

    required property var controller

    property int tagId: -1                   // -1: creating a new tag
    property int parentId: -1                // the tag it is a sub-tag of, -1: top level
    property int color: 0                    // a top-level tag's colour (an index of Theme.areaColors)
    property var choices: []                 // where it may go: [{id, name, depth, path}]
    readonly property bool editing: tagId >= 0
    readonly property string parentPath: {
        for (const c of choices) if (c.id === parentId) return c.path
        return ""
    }

    signal createClicked(string name, int parentId, int color)
    signal saveClicked(int id, string name, int parentId, int color)

    readonly property string name: field.text.trim()

    function openNew(parent) {
        tagId = -1
        parentId = parent === undefined ? -1 : parent
        choices = controller.tagParentChoices(-1)
        color = controller.suggestTagColor()
        field.text = ""
        open()
    }

    function openFor(id, currentName, currentParent) {
        tagId = id
        parentId = currentParent
        choices = controller.tagParentChoices(id)
        color = controller.tagColor(id)
        field.text = currentName
        open()
    }

    function submit() {
        if (name === "") return
        if (editing) saveClicked(tagId, name, parentId, color)
        else createClicked(name, parentId, color)
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

        // the colour of a top-level tag
        ColumnLayout {
            visible: dialog.parentId < 0
            spacing: 6
            Layout.fillWidth: true
            Label { text: "Colour"; font.pixelSize: 12; color: Theme.textMuted }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: Theme.areaColors.length
                    Rectangle {
                        id: swatch
                        required property int index
                        width: 24
                        height: 24
                        radius: 12
                        color: Theme.areaColor(index)
                        border.width: dialog.color === index ? 2 : 0
                        border.color: Theme.text
                        scale: swatchHover.hovered ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: dialog.color = swatch.index }
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