import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import DailyTodo.Style

// Small round checkbox. Open, it is a little hole sunk into the surface; checked, a raised green
// bead with a dark tick, which pops as it fills. Open and `inProgress`: the hole has an amber rim
// and its left half is filled, half way to done.
CheckBox {
    id: control

    implicitWidth: 24
    implicitHeight: 24
    padding: 0
    hoverEnabled: true

    property bool inProgress: false

    contentItem: Item {}   // no text, indicator only

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    indicator: Item {
        id: dot
        readonly property real s: Theme.checkSize + 2
        x: (control.width - width) / 2
        y: (control.height - height) / 2
        width: s
        height: s

        // the pop when it gets checked
        Connections {
            target: control
            function onToggled() { if (control.checked) pop.restart() }
        }
        SequentialAnimation {
            id: pop
            NumberAnimation { target: dot; property: "scale"; to: 1.25; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: dot; property: "scale"; to: 1; duration: 160; easing.type: Easing.OutBack }
        }

        // open: the hole
        Rectangle {
            visible: !control.checked
            anchors.fill: parent
            radius: width / 2
            color: control.hovered ? Qt.lighter(Theme.well, 1.25) : Theme.well
            border.color: control.inProgress ? Qt.alpha(Theme.inProgress, control.hovered ? 1 : 0.8)
                        : control.hovered ? Theme.textMuted : Theme.hairlineStrong
            border.width: control.inProgress ? 1.5 : 1
            // in progress: the left half filled
            Item {
                visible: control.inProgress
                x: 3
                y: 3
                width: (parent.width - 6) / 2
                height: parent.height - 6
                clip: true
                Rectangle {
                    width: parent.height
                    height: parent.height
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Theme.inProgress, 1.1) }
                        GradientStop { position: 1; color: Qt.darker(Theme.inProgress, 1.2) }
                    }
                }
            }
            Rectangle {                         // shade inside its top half (same circle)
                anchors.fill: parent
                anchors.margins: 1
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.4) }
                    GradientStop { position: 0.5; color: "transparent" }
                }
            }
        }

        // checked: the bead
        RectangularShadow {
            visible: control.checked
            anchors.fill: bead
            radius: width / 2
            offset.y: 1
            blur: 4
            color: Qt.alpha(Theme.ringDone, 0.45)
        }
        Rectangle {
            id: bead
            visible: control.checked
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(Theme.ringDone, 1.18) }
                GradientStop { position: 1; color: Theme.accentBottom }
            }
            border.color: Qt.darker(Theme.accentBottom, 1.2)
            Rectangle {                         // the glint
                x: parent.width * 0.28
                y: 2
                width: parent.width * 0.44
                height: 2
                radius: 1
                color: Qt.rgba(1, 1, 1, 0.35)
            }
            // A Shape rather than a Canvas: every todo row has a checkbox, and a Canvas brings its
            // own JS painting context and offscreen image per instance.
            Shape {
                id: tick
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.window
                    strokeWidth: 1.9
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: tick.width * 0.29
                    startY: tick.height * 0.53
                    PathLine { x: tick.width * 0.44; y: tick.height * 0.68 }
                    PathLine { x: tick.width * 0.72; y: tick.height * 0.37 }
                }
            }
        }
    }
}
