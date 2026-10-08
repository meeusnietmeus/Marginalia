import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Top of the left column, always fully visible: the resources opened last, to pick up where you
// left off. How many (1 to 10) is chosen in the heading. Each row says when it was opened and, for
// a PDF, the page it was left on; clicking it opens it again (a PDF at that page), right-clicking
// gives the same menu as a card in the library. Its height follows the rows (see
// `contentHeight`); given less, the rows scroll.
Item {
    id: panel

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    readonly property real headerHeight: 58
    readonly property real rowHeight: 48
    readonly property real rowSpacing: 8
    // the height it would like: the heading and every row
    readonly property real contentHeight: headerHeight + Math.max(1, list.count) * (rowHeight + rowSpacing) + 6

    property int menuFor: -1                 // the row whose menu was opened from here

    clip: true

    SectionTitle {
        id: heading
        x: 12
        height: 56
        text: "Jump back in"
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: heading.verticalCenter
        spacing: 8
        CapsLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: "Show"
            color: Theme.textFaint
        }
        NumberField {
            anchors.verticalCenter: parent.verticalCenter
            from: 1
            to: 10
            value: panel.controller.recentCount
            onValueModified: (value) => panel.controller.setRecentCount(value)
        }
    }

    ListView {
        id: list
        x: 12
        y: panel.headerHeight
        width: parent.width - 24
        height: parent.height - y
        spacing: panel.rowSpacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: panel.controller.recentResources
        ScrollBar.vertical: AppScrollBar {}

        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: panel.rowHeight

            readonly property bool lit: hover.hovered
                || (panel.actions.menuOpen && panel.actions.menuResourceId === modelData.id
                    && panel.menuFor === modelData.id)

            Surface {
                anchors.fill: parent
                y: row.lit ? -1 : 0
                lit: row.lit
                radius: 12
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                KindTile { kind: row.modelData.kind }
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        width: parent.width
                        text: row.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    CapsLabel {
                        text: "Opened " + row.modelData.when
                        color: Theme.textFaint
                    }
                }
                PillLabel {
                    visible: row.modelData.page > 0
                    text: "p. " + row.modelData.page
                    tint: Theme.ringDone
                    textColor: Theme.ringDone
                }
            }
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            ClickHandler { onTapped: panel.controller.openResourceById(row.modelData.id) }
            ClickHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (eventPoint) => {
                    panel.menuFor = row.modelData.id
                    panel.actions.showMenu(row.modelData.id, row, eventPoint.position.x, eventPoint.position.y)
                }
            }
        }

        CapsLabel {
            visible: list.count === 0
            topPadding: 8
            text: "What you open shows up here"
            color: Theme.textFaint
        }
    }
}
