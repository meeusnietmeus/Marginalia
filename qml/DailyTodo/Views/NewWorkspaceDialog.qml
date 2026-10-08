import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Modal asking for the name of a new workspace and its folder. The folder is required (the files of
// the workspace's resources live there) and can't be changed afterwards.
AppDialog {
    id: dialog

    required property var controller

    property string folder: ""                // native path

    signal createClicked(string name, string folder)

    readonly property string name: field.text.trim()
    readonly property bool valid: name !== "" && folder !== ""

    function submit() {
        if (!valid) return
        createClicked(name, folder)
        close()
    }

    width: Math.min(400, parent.width - 40)

    onAboutToShow: {
        field.text = ""
        folder = ""
    }
    onOpened: field.forceActiveFocus()

    FolderDialog {
        id: folderDialog
        title: "Folder for the workspace"
        currentFolder: dialog.folder !== "" ? dialog.controller.fileUrl(dialog.folder) : ""
        onAccepted: dialog.folder = dialog.controller.localPath(selectedFolder)
    }

    contentItem: ColumnLayout {
        spacing: 16

        DialogTitle {
            text: "New workspace"
        }

        AppTextField {
            id: field
            placeholderText: "Workspace name"
            Layout.fillWidth: true
            onAccepted: dialog.submit()
        }

        ColumnLayout {
            spacing: 6
            Layout.fillWidth: true
            Label { text: "Folder (required)"; font.pixelSize: 12; color: Theme.textMuted }
            RowLayout {
                spacing: 8
                AppTextField {
                    readOnly: true
                    text: dialog.folder
                    placeholderText: "Choose where its files live"
                    Layout.fillWidth: true
                    onTextChanged: cursorPosition = 0      // show the start of a long path
                }
                AppButton { text: "Browse"; onClicked: folderDialog.open() }
            }
            Label {
                text: "New files can be moved here when you add them. It can't be changed later."
                wrapMode: Text.Wrap
                font.pixelSize: 11
                color: Theme.textFaint
                Layout.fillWidth: true
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
                text: "Create"
                filled: true
                enabled: dialog.valid
                onClicked: dialog.submit()
            }
        }
    }
}