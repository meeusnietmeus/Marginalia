import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Layouts
import QtQuick.Dialogs
import DailyTodo.Style
import DailyTodo.Controls

// Import many files as resources in one go. Drop files or folders on it (or choose them), check the
// list, name them if the file name isn't good enough, give them all the same tags and import.
// A folder brings the files in it; files that already are resources are shown dimmed and skipped.
AppDialog {
    id: dialog

    required property var controller

    property var selectedTags: []               // tag ids, for every file
    property bool moveFile: true                // bring files from elsewhere into the workspace folder
    property string workspaceFolder: ""
    property int importable: 0                  // rows that will be imported (not duplicates)
    property int outside: 0                     // of those, files that lie outside the workspace folder

    readonly property bool hasRows: rows.count > 0

    ListModel { id: rows }

    // ---- the list ----
    function listedPaths() {
        const paths = []
        for (let i = 0; i < rows.count; i++) paths.push(rows.get(i).path)
        return paths
    }
    function addPaths(paths) {
        const found = controller.previewImport(paths, listedPaths())
        for (const item of found)
            rows.append({ path: item.path, name: item.name, kind: item.kind, folder: item.folder,
                          duplicate: item.duplicate })
        recount()
        if (found.length === 0)
            controller.notify("Nothing to import there")
    }
    function recount() {
        let n = 0, out = 0
        for (let i = 0; i < rows.count; i++) {
            const r = rows.get(i)
            if (r.duplicate) continue
            n++
            if (workspaceFolder !== "" && !controller.isInWorkspaceFolder(r.path)) out++
        }
        importable = n
        outside = out
    }
    function toggleTag(id) {
        const i = selectedTags.indexOf(id)
        selectedTags = i >= 0 ? selectedTags.filter(t => t !== id) : selectedTags.concat([id])
    }
    function doImport() {
        const items = []
        for (let i = 0; i < rows.count; i++) {
            const r = rows.get(i)
            if (!r.duplicate) items.push({ path: r.path, name: r.name })
        }
        controller.importResources(items, selectedTags, moveFile && outside > 0)
        close()
    }

    // Opens empty, or with files already given (dropped on the library).
    function openWith(paths) {
        rows.clear()
        selectedTags = []
        moveFile = true
        workspaceFolder = controller.defaultResourceFolder()
        importable = 0
        outside = 0
        open()
        if (paths && paths.length > 0) addPaths(paths)
    }
    function openPicker() {
        openWith([])
        filePicker.open()
    }

    width: Math.min(parent.width - 40, Math.max(540, parent.width * 0.4))
    height: Math.min(parent.height - 40, 680)

    FileDialog {
        id: filePicker
        title: "Choose files to import"
        fileMode: FileDialog.OpenFiles
        currentFolder: dialog.controller.fileUrl(dialog.controller.downloadsFolder())
        onAccepted: dialog.addPaths(selectedFiles.map(u => u.toString()))
    }
    FolderDialog {
        id: folderPicker
        title: "Choose a folder to import"
        currentFolder: dialog.controller.fileUrl(dialog.controller.downloadsFolder())
        onAccepted: dialog.addPaths([selectedFolder.toString()])
    }

    contentItem: ColumnLayout {
        spacing: 14

        RowLayout {
            DialogTitle {
                text: "Import files"
                Layout.fillWidth: true
            }
            IconButton {
                iconSource: Theme.iconClose
                fallbackText: "×"
                onClicked: dialog.close()
            }
        }

        // ---- nothing chosen yet: a place to drop things ----
        Rectangle {
            id: dropZone
            visible: !dialog.hasRows
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: drop.containsDrag ? Qt.alpha(Theme.accent, 0.1) : Theme.well
            border.width: 1.5
            border.color: drop.containsDrag ? Theme.accent : Theme.hairlineStrong
            Behavior on color { ColorAnimation { duration: 120 } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                IconImage {
                    Layout.alignment: Qt.AlignHCenter
                    source: Theme.iconDownload
                    sourceSize: Qt.size(34, 34)
                    color: drop.containsDrag ? Theme.accent : Theme.textMuted
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Drop files or folders here"
                    font.family: Theme.serifFont
                    font.pixelSize: 20
                    color: Theme.text
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "A folder brings every file inside it"
                    font.pixelSize: 12
                    color: Theme.textFaint
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    spacing: 8
                    AppButton {
                        text: "Choose files..."
                        filled: true
                        onClicked: filePicker.open()
                    }
                    AppButton {
                        text: "Choose a folder..."
                        onClicked: folderPicker.open()
                    }
                }
            }
        }

        // ---- the list ----
        RowLayout {
            visible: dialog.hasRows
            spacing: 10
            Layout.fillWidth: true
            Text {
                text: dialog.importable + (dialog.importable === 1 ? " file" : " files") + " to import"
                      + (rows.count > dialog.importable ? " · " + (rows.count - dialog.importable) + " already in the library" : "")
                font.pixelSize: 13
                color: Theme.text
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            AppButton { compact: true; text: "Add files..."; onClicked: filePicker.open() }
            AppButton { compact: true; text: "Add a folder..."; onClicked: folderPicker.open() }
            AppButton {
                compact: true
                text: "Clear"
                textColor: Theme.textMuted
                onClicked: { rows.clear(); dialog.recount() }
            }
        }

        ListView {
            id: list
            visible: dialog.hasRows
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: rows
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: AppScrollBar {}

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.listEnterDuration; easing.type: Easing.OutCubic }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.listExitDuration; easing.type: Easing.OutCubic }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.listMoveDuration; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                id: row
                required property int index
                required property string path
                required property string name
                required property string kind
                required property string folder
                required property bool duplicate

                width: list.width - 10
                height: 52
                opacity: duplicate ? 0.5 : 1

                QuietCard { anchors.fill: parent; lit: nameField.activeFocus }

                KindTile {
                    id: tile
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    kind: row.kind
                }
                ColumnLayout {
                    anchors.left: tile.right
                    anchors.leftMargin: 10
                    anchors.right: remove.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    TextInput {
                        id: nameField
                        Layout.fillWidth: true
                        text: row.name
                        readOnly: row.duplicate
                        font.pixelSize: 13
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentText
                        selectByMouse: true
                        clip: true
                        onTextEdited: rows.setProperty(row.index, "name", text)
                        // an empty name would be refused: go back to the suggestion
                        onActiveFocusChanged: if (!activeFocus && text.trim() === "") text = controller.suggestName(row.path)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.duplicate ? "Already in the library, skipped" : row.folder
                        elide: Text.ElideMiddle
                        font.pixelSize: 11
                        color: row.duplicate ? Theme.warning : Theme.textFaint
                    }
                }
                RowActionButton {
                    id: remove
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    iconSource: Theme.iconClose
                    fallbackText: "×"
                    tint: Theme.danger
                    onClicked: { rows.remove(row.index); dialog.recount() }
                    AppToolTip { text: "Leave this one out"; shown: remove.hovered }
                }
            }
        }

        // ---- for all of them ----
        ColumnLayout {
            visible: dialog.hasRows
            spacing: 8
            Layout.fillWidth: true
            Text { text: "Tags for all of them"; font.pixelSize: 12; color: Theme.textMuted }
            TagPicker {
                Layout.fillWidth: true
                controller: dialog.controller
                selected: dialog.selectedTags
                onToggleRequested: (tagId) => dialog.toggleTag(tagId)
            }
        }
        RowLayout {
            visible: dialog.hasRows && dialog.outside > 0
            spacing: 8
            Layout.fillWidth: true
            AppCheckBox {
                checked: dialog.moveFile
                onToggled: dialog.moveFile = checked
            }
            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Label {
                    text: "Move " + dialog.outside + (dialog.outside === 1 ? " file" : " files") + " to the workspace folder"
                    font.pixelSize: 13
                    color: Theme.text
                }
                Label {
                    text: dialog.workspaceFolder
                    elide: Text.ElideMiddle
                    font.pixelSize: 11
                    color: Theme.textFaint
                    Layout.fillWidth: true
                }
            }
            ClickHandler { onTapped: dialog.moveFile = !dialog.moveFile }
        }

        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            AppButton {
                text: "Cancel"
                onClicked: dialog.close()
            }
            AppButton {
                visible: dialog.hasRows
                text: dialog.importable === 0 ? "Import" : "Import " + dialog.importable + (dialog.importable === 1 ? " file" : " files")
                filled: true
                enabled: dialog.importable > 0
                onClicked: dialog.doImport()
            }
        }
    }

    // files dropped anywhere on the window of the dialog are added to the list
    DropArea {
        id: drop
        parent: dialog.contentItem
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (event) => { if (event.hasUrls) dialog.addPaths(event.urls.map(u => u.toString())) }
    }
}
