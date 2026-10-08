import QtQuick
import QtQuick.Controls.impl  // IconImage
import QtQuick.Effects
import DailyTodo.Style
import DailyTodo.Controls

// A tag as a small raised chip. With `selectable` it toggles (used when picking tags for a
// resource): selected, it turns green and shows a tick.
Item {
    id: pill

    property string text
    property bool selectable: false
    property bool selected: false
    property bool menuEnabled: false          // right-click: Edit / Delete
    readonly property bool menuOpen: menu.visible

    signal toggled()
    signal addChildRequested()
    signal editRequested()
    signal deleteRequested()

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 26

    RectangularShadow {
        anchors.fill: face
        radius: face.radius
        offset.y: 1
        blur: hover.hovered ? 6 : 3
        color: Theme.shadow
    }
    Rectangle {
        id: face
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            GradientStop {
                position: 0
                color: pill.selected ? Qt.tint(Theme.panelRaised, Qt.alpha(Theme.ringDone, 0.35))
                                     : Qt.lighter(Theme.panelRaised, hover.hovered ? 1.14 : 1.06)
            }
            GradientStop {
                position: 1
                color: pill.selected ? Qt.tint(Theme.panel, Qt.alpha(Theme.ringDone, 0.25)) : Theme.panel
            }
        }
        border.color: pill.selected ? Qt.alpha(Theme.ringDone, 0.6) : Theme.hairlineStrong
        Rectangle {                              // light along the top edge
            x: parent.radius * 0.7
            y: 1
            width: parent.width - 2 * x
            height: 1
            color: Theme.surfaceHighlight
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        IconImage {
            visible: pill.selected
            anchors.verticalCenter: parent.verticalCenter
            source: Theme.iconSave
            sourceSize: Qt.size(12, 12)
            color: Theme.ringDone
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            font.pixelSize: 12
            color: pill.selected ? Theme.text : Theme.textMuted
        }
    }

    HoverHandler { id: hover; cursorShape: pill.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    ClickHandler { enabled: pill.selectable; onTapped: pill.toggled() }

    ClickHandler {
        enabled: pill.menuEnabled
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint) => menu.popup(eventPoint.position)
    }
    CrudMenu {
        id: menu
        onEditTriggered: pill.editRequested()
        onDeleteTriggered: pill.deleteRequested()
        AppMenuItem {
            text: "Add sub-tag"
            iconSource: Theme.iconAdd
            onTriggered: pill.addChildRequested()
        }
    }
}
