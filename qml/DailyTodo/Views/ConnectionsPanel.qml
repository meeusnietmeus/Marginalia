import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The connections of a document, per page instead of as a graph, all of them at all times. A
// switch picks the list:
//   Links      every resource this one mentions, grouped under the page whose note does it (the
//              global notes first); the group of the page being viewed is lit and scrolled to
//   Backlinks  the notes of other resources that mention this one, each with its page
// A row opens the resource (a backlink opens it at the page that mentions this document).
// Give it the tab's notes session; right-click uses `actions` (ResourceActions) like the library.
ColumnLayout {
    id: panel

    property var session: null
    property var controller: null
    property var actions: null
    property int currentPage: 1               // the page being viewed
    property bool back: false                 // showing the backlinks instead of the links

    readonly property var links: session ? session.pageLinks : []
    readonly property var backlinks: session ? session.backlinks : []

    signal pageRequested(int page)

    spacing: 10

    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        spacing: 12
        SectionTitle {
            text: "Connections"
            size: 22
            height: 30
        }
        SegmentedSwitch {
            leftText: "Links (" + panel.links.length + ")"
            rightText: "Backlinks (" + panel.backlinks.length + ")"
            rightActive: panel.back
            onToggledTo: (right) => panel.back = right
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 14
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: AppScrollBar {}

        model: panel.back ? panel.backlinks : panel.links
        section.property: panel.back ? "" : "group"
        section.delegate: CapsLabel {
            required property string section
            readonly property int page: parseInt(section)
            width: list.width - 8
            topPadding: 4
            text: page === 0 ? "Global" : "Page " + page
            color: page === panel.currentPage ? Theme.accent : Theme.textFaint

            HoverHandler { enabled: parent.page > 0; cursorShape: Qt.PointingHandCursor }
            ClickHandler {
                enabled: parent.page > 0
                onTapped: panel.pageRequested(parent.page)
            }
        }

        // the group of the page being viewed comes into view when the page changes
        function showCurrent() {
            if (panel.back) return
            const i = panel.links.findIndex(l => l.page === panel.currentPage)
            if (i >= 0) positionViewAtIndex(i, ListView.Beginning)
        }
        Connections {
            target: panel
            function onCurrentPageChanged() { Qt.callLater(list.showCurrent) }
        }

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.listEnterDuration; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: row
            required property var modelData
            width: list.width - 8
            height: 38

            QuietCard {
                anchors.fill: parent
                lit: hover.hovered || (!panel.back && row.modelData.page === panel.currentPage)
            }
            KindTile {
                id: tile
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                kind: row.modelData.kind
                missing: row.modelData.missing
            }
            Text {
                anchors.left: tile.right
                anchors.leftMargin: 10
                anchors.right: caption.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                elide: Text.ElideRight
                font.pixelSize: 13
                color: row.modelData.missing ? Theme.textFaint : Theme.text
            }
            CapsLabel {
                id: caption
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.back
                text: row.modelData.page > 0 ? "p. " + row.modelData.page : "global"
                color: Theme.textFaint
            }

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            ClickHandler {
                onTapped: panel.back && row.modelData.page > 0
                          ? panel.controller.openResourceAtPage(row.modelData.id, row.modelData.page)
                          : panel.controller.openResourceById(row.modelData.id)
            }
            ClickHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (eventPoint) => panel.actions.showMenu(row.modelData.id, row,
                                                                 eventPoint.position.x, eventPoint.position.y)
            }
            AppToolTip {
                text: row.modelData.name
                shown: hover.hovered
            }
        }

        CapsLabel {
            visible: list.count === 0
            width: list.width - 8
            topPadding: 6
            wrapMode: Text.Wrap
            text: panel.back ? "No other resource mentions this one yet"
                             : "This document doesn't mention other resources yet. Type @ in a note to link one"
            color: Theme.textFaint
        }
    }
}
