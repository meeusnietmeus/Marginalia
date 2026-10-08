import QtQuick
import QtQuick.Effects
import DailyTodo.Style
import DailyTodo.Controls

// The video as a ruler, from 0:00 to a little past its last moment: a bead at every moment that
// has notes, where it falls in the video. The app doesn't know how long the video is, so the
// ruler's right end is broken off (an axis break, then a few fading dashes). A moment with a
// question still open is amber. Hover a bead to see its time; click it: picked(index).
Item {
    id: scrubber

    property var moments: []                 // the session's timeline groups ({time, label, entries})
    property int current: -1                 // the time that is lit up (-1: none)

    signal picked(int index)

    readonly property real pad: 14
    readonly property real breakWidth: 44     // the broken-off end, right of the ruler proper
    readonly property real rulerWidth: width - 2 * pad - breakWidth
    readonly property real lineY: 24
    readonly property int lastTime: moments.length > 0 ? moments[moments.length - 1].time : 0
    readonly property real span: Math.max(60, lastTime * 1.06)
    function xOf(seconds) { return pad + rulerWidth * seconds / span }
    function hasOpenQuestion(group) {
        for (const e of group.entries)
            if (e.isQuestion && !e.answered) return true
        return false
    }

    implicitHeight: 56

    // the hairline and its ticks: one per 1/40 of the ruler, a longer one every fifth
    Rectangle {
        x: scrubber.pad
        y: scrubber.lineY
        width: scrubber.rulerWidth + 6
        height: 1
        color: Theme.hairlineStrong
    }
    // the broken-off end: "//" across the line, then the line trailing off
    Repeater {
        model: 2
        Rectangle {
            required property int index
            x: scrubber.pad + scrubber.rulerWidth + 10 + index * 5
            y: scrubber.lineY - 6
            width: 1.2
            height: 13
            rotation: 28
            antialiasing: true
            color: Theme.textMuted
        }
    }
    Repeater {
        model: 3
        Rectangle {
            required property int index
            x: scrubber.pad + scrubber.rulerWidth + 22 + index * 8
            y: scrubber.lineY
            width: 4
            height: 1
            color: Theme.hairlineStrong
            opacity: 0.8 - index * 0.3
        }
    }
    Repeater {
        model: 41
        Rectangle {
            required property int index
            readonly property bool major: index % 5 === 0
            x: scrubber.pad + scrubber.rulerWidth * index / 40
            y: scrubber.lineY + 3
            width: 1
            height: major ? 7 : 4
            color: major ? Theme.hairlineStrong : Theme.hairline
        }
    }
    CapsLabel {
        x: scrubber.pad
        y: scrubber.lineY + 14
        text: "0:00"
        color: Theme.textFaint
    }
    CapsLabel {
        visible: scrubber.moments.length > 0
        x: Math.min(scrubber.pad + scrubber.rulerWidth - width, scrubber.xOf(scrubber.lastTime) - width / 2)
        y: scrubber.lineY + 14
        text: scrubber.moments.length > 0 ? scrubber.moments[scrubber.moments.length - 1].label : ""
        color: Theme.textFaint
    }

    // the moments
    Repeater {
        model: scrubber.moments
        Item {
            id: bead
            required property int index
            required property var modelData
            readonly property bool lit: scrubber.current === modelData.time
            readonly property bool open: scrubber.hasOpenQuestion(modelData)
            readonly property color tint: open ? Theme.warning : Theme.ringDone
            readonly property real size: lit ? 14 : hover.hovered ? 13 : 10

            x: scrubber.xOf(modelData.time) - 10
            y: scrubber.lineY - 10
            width: 20
            height: 20
            z: lit || hover.hovered ? 2 : 1

            RectangularShadow {
                anchors.centerIn: parent
                width: bead.size
                height: bead.size
                radius: width / 2
                blur: bead.lit ? 10 : 4
                offset.y: 1
                color: Qt.alpha(bead.tint, bead.lit ? 0.7 : 0.4)
            }
            Rectangle {
                anchors.centerIn: parent
                width: bead.size
                height: bead.size
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(bead.tint, 1.2) }
                    GradientStop { position: 1; color: Qt.darker(bead.tint, 1.25) }
                }
                border.color: Qt.darker(bead.tint, 1.5)
                Behavior on width { NumberAnimation { duration: 120 } }
                Behavior on height { NumberAnimation { duration: 120 } }
            }

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            ClickHandler { onTapped: scrubber.picked(bead.index) }
            AppToolTip {
                text: bead.modelData.label + (bead.open ? "  ·  open question" : "")
                shown: hover.hovered
            }
        }
    }
}
