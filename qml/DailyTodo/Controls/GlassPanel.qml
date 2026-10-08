import QtQuick
import QtQuick.Effects
import DailyTodo.Style

// The background of a box that floats over the page while you type in it (the "add a todo" box,
// the note box of a document): raised well above the page (a soft, wide shadow), light along its
// top edge. With a `backdrop` it is frosted glass over it; without one, a solid raised face.
Item {
    id: panel

    property real radius: Theme.cardRadius + 4
    property Item backdrop: null             // what the glass blurs (must not contain the panel)
    property var backdropTracking: []        // see FrostedGlass.trackedValues
    property color edgeColor: Theme.hairlineStrong
    property real edgeWidth: 1

    // it floats over the page: nothing under it reacts to the pointer
    InputBlocker {}

    RectangularShadow {
        anchors.fill: parent
        radius: panel.radius
        offset.y: 10
        blur: 28
        spread: -4
        color: Theme.shadow
    }

    FrostedGlass {
        visible: panel.backdrop !== null
        anchors.fill: parent
        sourceItem: panel.backdrop
        trackedValues: panel.backdropTracking
        radius: panel.radius
        blur: Theme.glassBlur
        tint: Theme.glassTint
    }
    Rectangle {                                   // no backdrop: a solid face
        visible: panel.backdrop === null
        anchors.fill: parent
        radius: panel.radius
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.panelRaised }
            GradientStop { position: 1; color: Theme.panel }
        }
    }
    Rectangle {                                   // the edge
        anchors.fill: parent
        radius: panel.radius
        color: "transparent"
        border.color: panel.edgeColor
        border.width: panel.edgeWidth
    }
    Rectangle {                                   // light along the top edge
        x: panel.radius
        y: panel.edgeWidth
        width: parent.width - 2 * x
        height: 1
        color: Theme.surfaceHighlight
    }
}
