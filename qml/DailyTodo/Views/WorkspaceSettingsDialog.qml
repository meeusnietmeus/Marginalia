import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Modal for the active workspace: rename it or delete it (with a confirmation step).
AppDialog {
    id: dialog

    property string workspaceName
    property bool canDelete: true
    property bool confirming: false
    property string resourceFolder          // native path of the workspace's folder, "" = none

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

    width: Math.min(380, parent.width - 40)

    onAboutToShow: {
        field.text = workspaceName
        confirming = false
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
