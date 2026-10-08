import QtQuick
import QtQuick.Shapes
import DailyTodo.Style

// An outline around a squircle (a rounded square) that fills clockwise from the top centre: a faint
// track, and a coloured stroke for `value` (0..1). It sweeps in from zero the first time it is
// shown and glides when the value changes. `hideWhenFull`: once full, the coloured stroke fades
// away (a finished day needs no green ring).
Item {
    id: outline

    property real value: 0
    property real thickness: 2.5
    property real cornerRadius: width * 0.34
    property color color: Theme.ringDone
    property color trackColor: Theme.ringTrack
    property bool hideWhenFull: true

    implicitWidth: 18
    implicitHeight: 18

    property real shown: 0                     // the drawn value: follows `value`, animated
    Component.onCompleted: shown = Qt.binding(() => Math.max(0, Math.min(1, outline.value)))
    Behavior on shown { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

    // the path, inset by half the stroke so it stays inside the item
    readonly property real inset: thickness / 2
    readonly property real side: Math.min(width, height) - thickness
    readonly property real radius: Math.max(0, Math.min(side / 2, cornerRadius - inset))
    // PathRectangle starts at the end of the top-left corner and runs clockwise: shift the start
    // to the middle of the top edge
    readonly property real perimeter: 4 * (side - 2 * radius) + 2 * Math.PI * radius
    readonly property real topCentre: perimeter > 0 ? (side / 2 - radius) / perimeter : 0

    // A full outline fades out once it has filled up (only the green: the track stays).
    property real fade: hideWhenFull && value >= 1 ? 0 : 1
    Behavior on fade {
        SequentialAnimation {
            PauseAnimation { duration: outline.fade > 0.5 ? 550 : 0 }   // let it fill up first
            NumberAnimation { duration: 400 }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: outline.trackColor
            strokeWidth: outline.thickness
            fillColor: "transparent"
            PathRectangle {
                x: outline.inset; y: outline.inset
                width: outline.side; height: outline.side
                radius: outline.radius
            }
        }
        ShapePath {
            strokeColor: outline.shown > 0.001 ? Qt.alpha(outline.color, outline.fade) : "transparent"
            strokeWidth: outline.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            trim.start: 0
            trim.end: outline.shown
            trim.offset: outline.topCentre
            PathRectangle {
                x: outline.inset; y: outline.inset
                width: outline.side; height: outline.side
                radius: outline.radius
            }
        }
    }
}
