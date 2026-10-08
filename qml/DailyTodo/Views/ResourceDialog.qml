import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Dialogs
import QtQml.Models  // Instantiator
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Modal for creating a resource, or fixing one whose file has gone missing.
// A resource is EITHER a link OR a file, never both: the two modes below are exclusive and
// switching clears the other one.
AppDialog {
    id: dialog

    required property var controller

    property int resourceId: -1               // -1: creating a new one
    property string mode: "link"              // "link" | "file"
    property string path: ""
    readonly property bool editing: resourceId >= 0
    property var selectedTags: []             // tag ids

    // Which workspace the new resource goes in can be chosen (only when asked: the capture from the
    // browser). Its tags are that workspace's; choosing another one starts the tags over.
    property bool chooseWorkspace: false
    property int workspaceId: -1              // the chosen one (-1: the open workspace)
    onWorkspaceIdChanged: selectedTags = []
    readonly property string workspaceName: {
        for (const w of controller.workspaces) if (w.id === workspaceId) return w.name
        return ""
    }

    // The name starts as a suggestion taken from the link / file name, and follows it until the
    // user edits it.
    property bool nameEdited: false

    // A file picked outside the workspace's folder can be moved into it (see the checkbox).
    property string workspaceFolder: ""
    property bool moveFile: true
    readonly property bool offerMove: !editing && mode === "file" && path !== ""
                                      && workspaceFolder !== "" && !controller.isInWorkspaceFolder(path)

    signal createRequested(string uri, string name, var tagIds, bool moveFile)
    signal updateRequested(int id, string uri, string name, var tagIds)

    // State of the web page title lookup: "idle" | "loading" | "failed" (message in lookupError).
    property string lookupState: "idle"
    property string lookupError: ""

    // Works from the fields themselves, not from the `uri` binding: when this runs from a
    // text/path change handler, that binding may not have updated yet (the name would lag
    // one change behind).
    function reseedName() {
        if (nameEdited) return
        const current = mode === "link" ? linkField.text.trim() : path
        nameField.text = current === "" ? "" : controller.suggestName(current)
    }

    function toggleTag(id) {
        const i = selectedTags.indexOf(id)
        selectedTags = i >= 0 ? selectedTags.filter(t => t !== id) : selectedTags.concat([id])
    }

    readonly property bool pathMissing: mode === "file" && path !== "" && !controller.pathExists(path)
    readonly property string linkText: linkField.text.trim()
    readonly property string uri: mode === "link" ? linkText : path
    readonly property bool valid: (mode === "link" ? /^[A-Za-z][A-Za-z0-9+.\-]+:\S+$/.test(linkText)
                                                   : path !== "" && !pathMissing)
                                  && nameField.text.trim() !== ""

    // Open for a new resource.
    function openNew() {
        resourceId = -1
        chooseWorkspace = false
        workspaceId = -1
        mode = "link"
        nameEdited = false
        lookupState = "idle"
        path = ""
        workspaceFolder = controller.defaultResourceFolder()
        moveFile = true
        linkField.text = ""
        nameField.text = ""
        selectedTags = []
        open()
    }

    // Open for a new resource with this link already filled in, named `name` when it is given
    // (else its title is looked up at once).
    function openWithLink(link, name) {
        openNew()
        linkField.text = link
        if (name) {
            nameField.text = name
            nameEdited = true
        } else if (/^https?:\/\//i.test(link)) {
            lookupState = "loading"
            controller.fetchTitle(link)
        }
    }

    // Open for an existing resource (used when its file is missing).
    function openFor(id, uri, isPath, tagIds, name) {
        resourceId = id
        lookupState = "idle"
        nameEdited = true
        nameField.text = name
        selectedTags = tagIds ? Array.from(tagIds) : []
        mode = isPath ? "file" : "link"
        path = isPath ? uri : ""
        linkField.text = isPath ? "" : uri
        open()
    }

    function submit() {
        if (!valid) return
        if (editing) updateRequested(resourceId, uri, nameField.text.trim(), selectedTags)
        else createRequested(uri, nameField.text.trim(), selectedTags, offerMove && moveFile)
        close()
    }

    width: Math.min(420, parent.width - 40)

    onOpened: if (mode === "link") linkField.forceActiveFocus()
    onPathChanged: reseedName()

    // For web links, replace the suggestion with the page's title once it has been looked up
    // (unless the user already typed a name).
    // Looks the link up shortly after typing stops (also tells the user when the link is broken).
    Timer {
        id: titleTimer
        interval: 700
        onTriggered: {
            if (dialog.mode === "link" && /^https?:\/\//i.test(dialog.linkText)) {
                dialog.lookupState = "loading"
                dialog.controller.fetchTitle(dialog.linkText)
            }
        }
    }
    Connections {
        target: dialog.controller
        function onTitleLookup(url, title, error) {
            if (dialog.mode !== "link" || url !== dialog.linkText) return   // outdated answer
            dialog.lookupError = error
            dialog.lookupState = error !== "" ? "failed" : "idle"
            if (title !== "" && !dialog.nameEdited)
                nameField.text = title
        }
    }

    FileDialog {
        id: fileDialog
        title: "Choose a file"
        onAccepted: dialog.path = dialog.controller.localPath(selectedFile)
    }

    contentItem: ColumnLayout {
        spacing: 16

        RowLayout {
            DialogTitle {
                text: dialog.editing ? "Edit resource" : "New resource"
                Layout.fillWidth: true
            }
            IconButton {
                iconSource: Theme.iconClose
                fallbackText: "×"
                onClicked: dialog.close()
            }
        }

        // Where it goes (capture from the browser only): the open workspace unless another is picked.
        RowLayout {
            visible: dialog.chooseWorkspace && dialog.controller.workspaces.length > 1
            spacing: 10
            Label { text: "Save in"; font.pixelSize: 12; color: Theme.textMuted }
            AppButton {
                id: workspaceButton
                compact: true
                raised: true
                active: workspaceMenu.visible
                text: dialog.workspaceName + "  ↕"
                onClicked: workspaceMenu.visible ? workspaceMenu.close() : workspaceMenu.open()
                AppMenu {
                    id: workspaceMenu
                    y: parent.height + 6
                    Instantiator {
                        model: dialog.controller.workspaces
                        delegate: AppMenuItem {
                            required property var modelData
                            text: modelData.name
                            iconSource: modelData.id === dialog.workspaceId ? Theme.iconSave : ""
                            onTriggered: dialog.workspaceId = modelData.id
                        }
                        onObjectAdded: (index, object) => workspaceMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => workspaceMenu.removeItem(object)
                    }
                }
            }
            CapsLabel {
                visible: dialog.workspaceId !== dialog.controller.currentWorkspaceId
                text: "Opens that workspace"
                color: Theme.textFaint
            }
        }

        // Link or file: pick one.
        SegmentedSwitch {
            leftText: "Link"
            rightText: "File"
            implicitHeight: 30
            rightActive: dialog.mode === "file"
            onToggledTo: (file) => {
                if (file === (dialog.mode === "file")) return
                if (file) {
                    // the link's title lookup (and its error message) no longer applies
                    dialog.mode = "file"; dialog.lookupState = "idle"; linkField.text = ""
                } else {
                    dialog.mode = "link"; dialog.path = ""; linkField.forceActiveFocus()
                }
            }
        }

        AppTextField {
            id: linkField
            visible: dialog.mode === "link"
            placeholderText: "https://example.com  or  obsidian://open?vault=..."
            Layout.fillWidth: true
            onAccepted: dialog.submit()
            onTextChanged: {
                if (dialog.mode !== "link") return
                dialog.lookupState = "idle"
                dialog.reseedName()
                // Only while the dialog is showing: not when it is being filled in for editing.
                if (dialog.opened) titleTimer.restart()
            }
        }

        RowLayout {
            visible: dialog.mode === "file"
            spacing: 8
            Layout.fillWidth: true

            Well {
                Layout.fillWidth: true
                implicitHeight: Theme.controlHeight
                radius: height / 2

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    text: dialog.path !== "" ? dialog.path : "No file chosen"
                    elide: Text.ElideMiddle
                    font.pixelSize: 14
                    color: dialog.path !== "" ? Theme.text : Theme.textFaint
                }
            }
            AppButton {
                filled: true
                contentItem: Row {
                    spacing: 6
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        source: Theme.iconFolder
                        sourceSize: Qt.size(Theme.iconSize, Theme.iconSize)
                        color: Theme.accentText
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Browse"
                        font.pixelSize: 13
                        color: Theme.accentText
                    }
                }
                onClicked: {
                    // start in the workspace's default folder (a client-side setting), if it has one
                    const folder = dialog.controller.defaultResourceFolder()
                    if (folder !== "")
                        fileDialog.currentFolder = dialog.controller.fileUrl(folder)
                    fileDialog.open()
                }
            }
        }

        // A file from somewhere else: offer to bring it into the workspace's folder.
        RowLayout {
            visible: dialog.offerMove
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
                    text: "Move the file to the workspace folder"
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

        // The file isn't where the resource says it is.
        RowLayout {
            visible: dialog.pathMissing
            spacing: 8
            Layout.fillWidth: true
            IconImage {
                source: Theme.iconWarning
                sourceSize: Qt.size(Theme.iconSize, Theme.iconSize)
                color: Theme.danger
            }
            Label {
                text: "This path is no longer valid: the file doesn't exist here anymore. Choose its new location."
                wrapMode: Text.Wrap
                font.pixelSize: 12
                color: Theme.danger
                Layout.fillWidth: true
            }
        }

        // Tags of this workspace: pick any number (TagPicker: chips, type to find or make one).
        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true

            Label { text: "Tags"; font.pixelSize: 12; color: Theme.textMuted }
            TagPicker {
                Layout.fillWidth: true
                controller: dialog.controller
                workspaceId: dialog.chooseWorkspace ? dialog.workspaceId : -1
                selected: dialog.selectedTags
                onToggleRequested: (tagId) => dialog.toggleTag(tagId)
            }
        }

        ColumnLayout {
            spacing: 6
            Layout.fillWidth: true

            RowLayout {
                spacing: 8
                Layout.fillWidth: true
                Label { text: "Name"; font.pixelSize: 12; color: Theme.textMuted }
                Item { Layout.fillWidth: true }

                // Progress / failure of the page title lookup.
                BusyIndicator {
                    visible: dialog.lookupState === "loading"
                    running: visible
                    implicitWidth: 16
                    implicitHeight: 16
                    palette.dark: Theme.textMuted
                }
                Label {
                    visible: dialog.lookupState === "loading"
                    text: "Looking up title..."
                    font.pixelSize: 12
                    color: Theme.textMuted
                }
                IconImage {
                    visible: dialog.lookupState === "failed"
                    source: Theme.iconWarning
                    sourceSize: Qt.size(14, 14)
                    color: Theme.danger
                }
                Label {
                    visible: dialog.lookupState === "failed"
                    text: dialog.lookupError
                    font.pixelSize: 12
                    color: Theme.danger
                }
            }
            AppTextField {
                id: nameField
                placeholderText: "Name (required)"
                Layout.fillWidth: true
                // Typing makes the name the user's own, from then on nothing overwrites it, not
                // even clearing the field (the suggestion would just refill it, e.g. "View").
                onTextEdited: dialog.nameEdited = true
                onAccepted: dialog.submit()
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
                enabled: dialog.valid
                onClicked: dialog.submit()
            }
        }
    }
}
