import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// "Search": type a term and press Enter to find it in the text of every note, question and answer
// of the workspace. Matches are listed per resource (the one with most first), each marked as a
// note, a question or an answer, with the page it is on and a button that opens the resource there.
// A plain "contains" search for now (no fuzzy matching); it only runs on Enter.
Item {
    id: view

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    property string searched: ""             // the term the list below is for ("": no search yet)
    property int total: 0
    property var rows: []                    // group headings and matches, flattened for the list

    function runSearch() {
        const term = field.text.trim()
        searched = term
        if (term === "") {
            rows = []
            total = 0
            return
        }
        const result = controller.searchNotes(term)
        const flat = []
        for (const g of result.groups) {
            flat.push({ type: "group", resourceId: g.resourceId, name: g.name, kind: g.kind,
                        missing: g.missing, count: g.items.length })
            for (const item of g.items)
                flat.push({ type: "item", resourceId: g.resourceId, item: item })
        }
        rows = flat
        total = result.total
        list.positionViewAtBeginning()
    }
    // notes are written elsewhere: look again when the page comes back into view
    onVisibleChanged: if (visible && searched !== "") runSearch()

    function open(resourceId, page) { controller.openResourceAtPage(resourceId, page) }

    FocusClearTapHandler { hostWindow: view.Window.window }

    Shortcut {
        sequences: [StandardKey.Find]
        enabled: view.visible
        onActivated: {
            field.forceActiveFocus()
            field.selectAll()
        }
    }

    // ------------------------------------------------------------------ the search box
    ColumnLayout {
        id: top
        anchors.top: parent.top
        anchors.topMargin: view.searched === "" && view.rows.length === 0 ? Math.max(24, view.height * 0.28) : 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(680, parent.width - 48)
        spacing: 10
        Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Text {
            visible: view.searched === "" && view.rows.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: "Search"
            font.family: Theme.serifFont
            font.pixelSize: 34
            color: Theme.textMuted
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 48

            AppTextField {
                id: field
                anchors.fill: parent
                implicitHeight: 48
                font.pixelSize: 16
                leftPadding: 44
                placeholderText: "Search every note, question and answer..."
                onAccepted: view.runSearch()
                Keys.onEscapePressed: { text = ""; view.searched = ""; view.rows = []; view.total = 0; focus = false }
            }
            IconImage {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                source: Theme.iconSearch
                sourceSize: Qt.size(18, 18)
                color: field.activeFocus ? Theme.accent : Theme.textFaint
            }
        }

        CapsLabel {
            Layout.alignment: Qt.AlignHCenter
            text: view.searched === "" ? "Press Enter to search"
                : view.total === 0 ? "No match for \"" + view.searched + "\""
                : view.total + (view.total === 1 ? " match" : " matches") + " in "
                  + groupCount + (groupCount === 1 ? " resource" : " resources")
            color: Theme.textFaint
            readonly property int groupCount: view.rows.filter(r => r.type === "group").length
        }
    }

    // ------------------------------------------------------------------ the matches
    ListView {
        id: list
        anchors.top: top.bottom
        anchors.topMargin: 12
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(780, parent.width - 48) + 16        // the scroll bar goes in the extra room
        visible: view.rows.length > 0
        clip: true
        model: view.rows
        spacing: 0
        bottomMargin: 24
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: AppScrollBar {}

        delegate: Item {
            id: row
            required property var modelData
            readonly property bool isGroup: modelData.type === "group"
            width: ListView.view.width - 16
            height: isGroup ? 58 : card.height + 8

            // ---- a resource heading ----
            RowLayout {
                visible: row.isGroup
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                spacing: 10

                KindTile {
                    kind: row.modelData.kind || ""
                    missing: row.modelData.missing === true
                }
                Text {
                    text: row.modelData.name || ""
                    font.family: Theme.serifFont
                    font.pixelSize: 17
                    color: Theme.text
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                PillLabel {
                    text: (row.modelData.count || 0) + ((row.modelData.count || 0) === 1 ? " MATCH" : " MATCHES")
                }
                AppButton {
                    compact: true
                    text: "Open"
                    onClicked: view.open(row.modelData.resourceId, 0)
                }
            }

            // ---- one match ----
            Item {
                id: card
                visible: !row.isGroup
                width: parent.width
                height: cardColumn.implicitHeight + 24

                HoverHandler { id: cardHover }
                QuietCard {
                    anchors.fill: parent
                    radius: 14
                    lit: cardHover.hovered
                }
                ColumnLayout {
                    id: cardColumn
                    x: 16
                    y: 12
                    width: parent.width - 32
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        PillLabel {
                            text: (row.modelData.item ? row.modelData.item.kind : "").toUpperCase()
                            tint: !row.modelData.item ? Theme.text
                                : row.modelData.item.kind === "question" ? Theme.accent
                                : row.modelData.item.kind === "answer" ? Theme.info : Theme.text
                        }
                        PillLabel {
                            visible: !!row.modelData.item && row.modelData.item.kind === "question"
                            text: row.modelData.item && row.modelData.item.answered ? "ANSWERED" : "OPEN"
                            tint: row.modelData.item && row.modelData.item.answered ? Theme.ringDone : Theme.warning
                        }
                        CapsLabel {
                            text: row.modelData.item ? row.modelData.item.pageLabel : ""
                            color: Theme.textFaint
                        }
                        Item { Layout.fillWidth: true }
                        AppButton {
                            compact: true
                            text: row.modelData.item && row.modelData.item.page > 0 ? "Go to page" : "Open"
                            onClicked: view.open(row.modelData.resourceId, row.modelData.item.page)
                        }
                    }

                    // an answer says which question it answers
                    Text {
                        visible: !!row.modelData.item && row.modelData.item.kind === "answer"
                                 && row.modelData.item.question !== ""
                        Layout.fillWidth: true
                        text: row.modelData.item ? "Re: " + row.modelData.item.question.replace(/\s+/g, " ") : ""
                        font.pixelSize: 12
                        font.italic: true
                        color: Theme.textFaint
                        elide: Text.ElideRight
                    }

                    ReferenceText {
                        Layout.fillWidth: true
                        controller: view.controller
                        source: row.modelData.item ? row.modelData.item.body : ""
                        font.pixelSize: 14
                        font.weight: row.modelData.item && row.modelData.item.kind === "question" ? Font.DemiBold : Font.Normal
                        baseColor: Theme.text
                    }
                }
            }
        }
    }
}
