import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import DailyTodo.Style
import DailyTodo.Controls

// Modal for the active workspace: rename it, move its folder (the files go along, after a
// confirmation showing what will happen), choose how its todos are ordered, or delete it (with a
// confirmation step).
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

    function save() {
        if (name === "") return
        if (name !== workspaceName)
            saveClicked(name)
        close()
    }

    width: Math.min(parent.width - 40, Math.max(460, parent.width * 0.4))

    onAboutToShow: {
        field.text = workspaceName
        confirming = false
        newFolder = ""
    }
    onResourceFolderChanged: newFolder = ""   // it moved (or the dialog was filled in again)

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
    onOpened: {
        field.forceActiveFocus()
        field.selectAll()
    }

    contentItem: ColumnLayout {
        spacing: 16

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

        ColumnLayout {
            spacing: 6
            Label { text: "Name"; font.pixelSize: 12; color: Theme.textMuted }
            AppTextField {
                id: field
                placeholderText: "Workspace name"
                Layout.fillWidth: true
                onAccepted: dialog.save()
            }
        }

        RowLayout {
            Item { Layout.fillWidth: true }
            AppButton {
                text: "Save"
                filled: true
                enabled: dialog.name !== "" && dialog.name !== dialog.workspaceName
                onClicked: dialog.save()
            }
        }

        // ---- the workspace's folder: chosen when it was made, it can only be opened ----
        ColumnLayout {
            spacing: 6
            Layout.fillWidth: true
            Label { text: "Workspace folder"; font.pixelSize: 12; color: Theme.textMuted }
            RowLayout {
                spacing: 8
                AppTextField {
                    readOnly: true
                    text: dialog.resourceFolder
                    placeholderText: "None"
                    Layout.fillWidth: true
                    onTextChanged: cursorPosition = 0      // show the start of a long path
                }
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

            // what moving the folder would do, to confirm
            ColumnLayout {
                visible: dialog.newFolder !== ""
                spacing: 8
                Layout.fillWidth: true
                Label {
                    text: dialog.moveInfo.ok === true
                          ? "Move the workspace folder to " + dialog.newFolder + "? "
                            + dialog.moveInfo.count + (dialog.moveInfo.count === 1 ? " file is" : " files are")
                            + " moved there and their links updated"
                            + (dialog.moveInfo.missing > 0
                               ? " (" + dialog.moveInfo.missing + " link"
                                 + (dialog.moveInfo.missing === 1 ? "" : "s") + " whose file is missing only change)"
                               : "")
                            + ". Resources outside the folder stay where they are."
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
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.menuBorder }

        // ---- how the todos are ordered ----
        component SortPicker: RowLayout {
            id: picker
            property string current
            signal picked(string mode)
            spacing: 6
            Repeater {
                model: [{ mode: "created", text: "Created" },
                        { mode: "priority", text: "Priority first" },
                        { mode: "tags", text: "By tag" }]
                AppButton {
                    required property var modelData
                    compact: true
                    text: modelData.text
                    active: picker.current === modelData.mode
                    onClicked: picker.picked(modelData.mode)
                }
            }
        }
        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Label { text: "Timeline order"; font.pixelSize: 12; color: Theme.textMuted }
            SortPicker {
                current: dialog.timelineSort
                onPicked: (mode) => dialog.timelineSortPicked(mode)
            }
            RowLayout {
                spacing: 8
                AppCheckBox {
                    checked: dialog.doneLast
                    onToggled: dialog.doneLastToggled(checked)
                }
                Label {
                    text: "Show done todos last"
                    font.pixelSize: 13
                    color: Theme.text
                    ClickHandler { onTapped: dialog.doneLastToggled(!dialog.doneLast) }
                }
            }
            Label {
                Layout.topMargin: 6
                text: "Backlog order"
                font.pixelSize: 12
                color: Theme.textMuted
            }
            SortPicker {
                current: dialog.backlogSort
                onPicked: (mode) => dialog.backlogSortPicked(mode)
            }
            Label {
                text: "\"By tag\" groups the todos that start with the same tag, in the order of your tag list."
                font.pixelSize: 11
                color: Theme.textFaint
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.menuBorder }

        // ---- danger zone ----
        ColumnLayout {
            spacing: 10
            Layout.fillWidth: true

            Label {
                text: dialog.canDelete
                      ? "Delete this workspace and all of its todos."
                      : "You can't delete your only workspace."
                font.pixelSize: 12
                color: Theme.textMuted
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            AppButton {
                visible: !dialog.confirming
                enabled: dialog.canDelete
                text: "Delete workspace"
                textColor: Theme.danger
                onClicked: dialog.confirming = true
            }
            RowLayout {
                visible: dialog.confirming
                spacing: 8
                Label {
                    text: "This can't be undone."
                    font.pixelSize: 12
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
