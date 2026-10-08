import QtQuick
import QtQuick.Effects
import DailyTodo.Style

// A raised surface: a soft top-to-bottom gradient, a hairline edge, light catching its top edge,
// and a soft shadow under it. Use it as the background of cards, menus and dialogs.
//   elevation 0: flat (no shadow), 1: resting on the page (cards), 2: floating (menus, dialogs)
//   lit: hovered or selected: the edge brightens and a resting surface rises a little
Item {
    id: surface

    property real radius: Theme.cardRadius
    property int elevation: 1
    property bool lit: false
    property color topColor: Theme.panelRaised
    property color bottomColor: Theme.panel
    property color edgeColor: lit ? Theme.hairlineStrong : Theme.hairline
    property alias face: face                    // to clip or decorate the face itself

    RectangularShadow {
        visible: surface.elevation > 0
        anchors.fill: face
        radius: surface.radius
        offset.y: surface.elevation > 1 ? 12 : surface.lit ? 6 : 3
        blur: surface.elevation > 1 ? 32 : surface.lit ? 16 : 8
        spread: surface.elevation > 1 ? -4 : -1
        color: Theme.shadow
        Behavior on offset.y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on blur { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: surface.radius
        gradient: Gradient {
            GradientStop { position: 0; color: surface.topColor }
            GradientStop { position: 1; color: surface.bottomColor }
        }
        border.color: surface.edgeColor

        // light along the top edge
        Rectangle {
            x: Math.min(surface.radius * 0.7, parent.width / 2)
            y: 1
            width: parent.width - 2 * x
            height: 1
            color: Theme.surfaceHighlight
        }
    }
}
