import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import DailyTodo.Style
import DailyTodo.Controls

// Settings of the active workspace, in sections: its name, its folder (moving it carries the files
// along, after a confirmation that shows what will happen), how its todos are ordered, and
// deleting it (with a confirmation step).
AppDialog {
    id: dialog

    property string workspaceName
    property bool canDelete: true
    property bool confirming: false
    property string resourceFolder          // native path of the workspace's folder, "" = none

    property var controller: null
    property string newFolder: ""             // a folder picked to move the workspace to...
    property var moveInfo: ({})               // ...and what moving there would do (previewFolderRetarget)
    property string timelineSort: "created"   // "created" | "priority" | "tags"
    property string backlogSort: "created"
    property bool doneLast: false

    signal timelineSortPicked(string mode)
    signal backlogSortPicked(string mode)
    signal doneLastToggled(bool on)
    signal openFolderRequested()
    signal saveClicked(string name)
    signal deleteConfirmed()

    readonly property string name: field.text.trim()
    readonly property var sortChoices: [
        { text: "Order created", value: "created" },
        { text: "Priority first", value: "priority" },
        { text: "Group by tag", value: "tags" }
    ]

    function save() {
        if (name === "") return
        if (name !== workspaceName)
            saveClicked(name)
        close()
    }
    function sortIndex(mode) {
        const i = sortChoices.findIndex(c => c.value === mode)
        return i >= 0 ? i : 0
    }

    width: Math.min(parent.width - 40, Math.max(480, parent.width * 0.4))

    onAboutToShow: {
        field.text = workspaceName
        confirming = false
        newFolder = ""
    }
    onResourceFolderChanged: newFolder = ""   // it moved (or the dialog was filled in again)
    onOpened: {
        field.forceActiveFocus()
        field.selectAll()
    }

    FolderDialog {
        id: folderDialog
        title: "New folder for the workspace"
        currentFolder: dialog.resourceFolder !== "" && dialog.controller
                       ? dialog.controller.fileUrl(dialog.resourceFolder) : ""
        onAccepted: {
            dialog.newFolder = dialog.controller.localPath(selectedFolder)
            dialog.moveInfo = dialog.controller.previewFolderRetarget(dialog.newFolder)
        }
    }

    // taller than the window (a small one): the content scrolls
    height: Math.min(implicitHeight, parent.height - 40)

    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: AppScrollBar {}

      ColumnLayout {
        width: scroll.availableWidth
        spacing: 18

        RowLayout {
            DialogTitle {
                text: "Workspace settings"
                Layout.fillWidth: true
            }
            IconButton {
                iconSource: Theme.iconClose
                fallbackText: "×"
                onClicked: dialog.close()
            }
        }

        // ---- name ----
        SettingsSection {
            title: "General"
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 6
                Layout.fillWidth: true
                Text { text: "Name"; font.pixelSize: 13; color: Theme.text }
                RowLayout {
                    spacing: 8
                    AppTextField {
                        id: field
                        placeholderText: "Workspace name"
                        Layout.fillWidth: true
                        onAccepted: dialog.save()
                    }
                    AppButton {
                        text: "Save"
                        filled: true
                        enabled: dialog.name !== "" && dialog.name !== dialog.workspaceName
                        onClicked: dialog.save()
                    }
                }
            }
        }

        // ---- folder ----
        SettingsSection {
            title: "Folder"
            note: "Where the files of this workspace's resources live, and its backups (in .backups)."
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 6
                Layout.fillWidth: true
                Text { text: "Workspace folder"; font.pixelSize: 13; color: Theme.text }
                AppTextField {
                    readOnly: true
                    text: dialog.resourceFolder
                    placeholderText: "None"
                    Layout.fillWidth: true
                    onTextChanged: cursorPosition = 0      // show the start of a long path
                }
                RowLayout {
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    AppButton {
                        text: "Open in File Explorer"
                        enabled: dialog.resourceFolder !== ""
                        onClicked: dialog.openFolderRequested()
                    }
                    AppButton {
                        text: "Retarget..."
                        enabled: dialog.controller !== null
                        onClicked: folderDialog.open()
                    }
                }
            }

            // what moving the folder would do, to confirm
            ColumnLayout {
                visible: dialog.newFolder !== ""
                spacing: 8
                Layout.fillWidth: true
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }
                Label {
                    text: dialog.moveInfo.ok === true
                          ? "Move the workspace folder to " + dialog.newFolder + "? "
                            + dialog.moveInfo.count + (dialog.moveInfo.count === 1 ? " file is" : " files are")
                            + " moved there and their links updated"
                            + (dialog.moveInfo.missing > 0
                               ? " (" + dialog.moveInfo.missing + " link"
                                 + (dialog.moveInfo.missing === 1 ? "" : "s") + " whose file is missing only change)"
                               : "")
                            + "."
                            + (dialog.moveInfo.backups > 0
                               ? " The " + dialog.moveInfo.backups + " backup"
                                 + (dialog.moveInfo.backups === 1 ? "" : "s") + " in .backups move too."
                               : "")
                            + " Resources outside the folder stay where they are."
                          : (dialog.moveInfo.error || "")
                    font.pixelSize: 12
                    color: dialog.moveInfo.ok === true ? Theme.textMuted : Theme.danger
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    AppButton {
                        text: "Cancel"
                        onClicked: dialog.newFolder = ""
                    }
                    AppButton {
                        visible: dialog.moveInfo.ok === true
                        text: "Move"
                        filled: true
                        onClicked: {
                            dialog.controller.retargetWorkspaceFolder(dialog.newFolder)
                            dialog.newFolder = ""
                        }
                    }
                }
            }
        }

        // ---- how the todos are ordered ----
        SettingsSection {
            title: "Todos"
            note: "\"Group by tag\" puts the todos that start with the same tag together, in the order of your tag list."
            Layout.fillWidth: true

            SettingsRow {
                label: "Timeline order"
                AppComboBox {
                    model: dialog.sortChoices
                    currentIndex: dialog.sortIndex(dialog.timelineSort)
                    onActivated: dialog.timelineSortPicked(currentValue)
                }
            }
            SettingsRow {
                label: "Show done todos last"
                hint: "A todo you check moves to the bottom of its day"
                AppCheckBox {
                    checked: dialog.doneLast
                    onToggled: dialog.doneLastToggled(checked)
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }
            SettingsRow {
                label: "Backlog order"
                AppComboBox {
                    model: dialog.sortChoices
                    currentIndex: dialog.sortIndex(dialog.backlogSort)
                    onActivated: dialog.backlogSortPicked(currentValue)
                }
            }
        }

        // ---- danger zone ----
        SettingsSection {
            title: "Danger zone"
            Layout.fillWidth: true

            SettingsRow {
                visible: !dialog.confirming
                label: "Delete this workspace"
                hint: dialog.canDelete ? "Removes the workspace and all of its todos"
                                       : "You can't delete your only workspace"
                AppButton {
                    enabled: dialog.canDelete
                    text: "Delete workspace"
                    textColor: Theme.danger
                    onClicked: dialog.confirming = true
                }
            }
            RowLayout {
                visible: dialog.confirming
                spacing: 8
                Label {
                    text: "This can't be undone."
                    font.pixelSize: 13
                    color: Theme.danger
                    Layout.fillWidth: true
                }
                AppButton {
                    text: "Cancel"
                    onClicked: dialog.confirming = false
                }
                AppButton {
                    text: "Delete"
                    textColor: Theme.danger
                    onClicked: {
                        dialog.deleteConfirmed()
                        dialog.close()
                    }
                }
            }
        }
    }
      }
}
