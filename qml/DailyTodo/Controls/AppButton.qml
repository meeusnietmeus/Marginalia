import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import DailyTodo.Style

// Pill-shaped text button. Plain by default: a soft wash on hover. `active` (the selected nav link,
// an open filter) and `raised` stand it up as a small raised pill; `filled` makes it the green
// primary action, raised as well. Pressing a raised button pushes it down a little.
Button {
    id: control

    property bool filled: false
    property bool compact: false         // slightly smaller, for dense bars (nav bar)
    property bool active: false          // shown as selected (e.g. the current nav link)
    property bool raised: filled || active
    property color textColor: filled ? Theme.accentText : Theme.text

    hoverEnabled: true
    implicitHeight: compact ? 28 : Theme.controlHeight
    leftPadding: compact ? 12 : 16
    rightPadding: compact ? 12 : 16
    topPadding: 0
    bottomPadding: 0
    font.pixelSize: compact ? 12 : 13
    opacity: enabled ? 1 : 0.45

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.textColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Item {
        implicitHeight: control.implicitHeight

        RectangularShadow {
            visible: control.raised
            anchors.fill: face
            radius: face.radius
            offset.y: control.down ? 1 : 2
            blur: control.down ? 3 : 6
            color: Theme.shadow
        }
        Rectangle {
            id: face
            anchors.fill: parent
            anchors.topMargin: control.raised && control.down ? 1 : 0
            radius: height / 2
            gradient: !control.raised ? null : control.filled ? green : neutral
            color: control.down ? Qt.alpha(Theme.text, 0.12)
                 : control.hovered ? Qt.alpha(Theme.text, 0.07) : "transparent"
            border.color: !control.raised ? "transparent"
                        : control.filled ? Qt.darker(Theme.accentBottom, 1.25) : Theme.hairlineStrong

            Gradient {
                id: green
                GradientStop { position: 0; color: control.hovered ? Qt.lighter(Theme.accentTop, 1.08) : Theme.accentTop }
                GradientStop { position: 1; color: Theme.accentBottom }
            }
            Gradient {
                id: neutral
                GradientStop { position: 0; color: control.hovered ? Qt.lighter(Theme.panelRaised, 1.12) : Qt.lighter(Theme.panelRaised, 1.06) }
                GradientStop { position: 1; color: Theme.panel }
            }
            // light along the top edge
            Rectangle {
                visible: control.raised
                x: parent.radius * 0.7
                y: 1
                width: parent.width - 2 * x
                height: 1
                color: control.filled ? Qt.rgba(1, 1, 1, 0.25) : Theme.surfaceHighlight
            }
        }
    }
}
