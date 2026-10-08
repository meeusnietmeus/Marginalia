import QtQuick
import QtQuick.Effects
import DailyTodo.Style
import DailyTodo.Controls

// One day's slice of the side ruler: a hairline with tick marks every 12 px (a longer one every
// fifth), and the day's date dial on it. Every day draws its own slice, so nothing is shared between
// delegates: the ListView can create/destroy them freely. The ticks are placed by the slice's
// position in the list (`offset`), so they run on evenly from one day into the next.
//
// The dial is a small raised squircle with the weekday and the date, and an outline around it that
// fills as the day gets done (it fades away once everything is done; a past day with open todos has
// a reddish track). Today's date is red, and its dial glows once when it comes into view.
Item {
    id: slice

    property real headerY: 0            // y of the middle of the day header
    property real offset: 0             // where this slice starts in the whole list (for the ticks)
    property bool isFirst: false        // the ruler starts here
    property bool isLast: false         // the ruler fades out below this day
    property bool isToday: false
    property bool isPast: false
    property string dateIso
    property int done: 0
    property int total: 0

    readonly property real tickStep: 12
    readonly property real dialSize: isToday ? 42 : 36
    readonly property real rulerTop: isFirst ? headerY : 0

    // the hairline and its ticks; after the last day they fade out over Theme.graphFadeLength
    Item {
        id: ruler
        x: Theme.graphX
        y: slice.rulerTop
        width: 10
        height: slice.height - y + 1                  // +1: no gap between slices
        // where the fade starts and how far it runs (ruler coordinates); no fade but on the last day
        readonly property real fadeFrom: slice.isLast ? Math.max(slice.headerY - slice.rulerTop + 24, height - Theme.graphFadeLength) : height
        readonly property real fadeLength: Math.max(1, height - fadeFrom)
        function strength(y) { return y <= fadeFrom ? 1 : Math.max(0, 1 - (y - fadeFrom) / fadeLength) }

        Rectangle {
            width: 1
            height: parent.height
            color: Theme.hairlineStrong
            gradient: slice.isLast ? fade : null
            Gradient {
                id: fade
                GradientStop { position: 0; color: Theme.hairlineStrong }
                GradientStop { position: ruler.fadeFrom / Math.max(1, ruler.height); color: Theme.hairlineStrong }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Repeater {
            id: ticks
            // first tick at the next multiple of tickStep in list coordinates
            readonly property real first: (slice.tickStep - (slice.offset + slice.rulerTop) % slice.tickStep) % slice.tickStep
            model: Math.max(0, Math.ceil((ruler.height - first) / slice.tickStep))
            Rectangle {
                required property int index
                readonly property real listY: slice.offset + slice.rulerTop + ticks.first + index * slice.tickStep
                readonly property bool major: Math.round(listY / slice.tickStep) % 5 === 0
                x: 1
                y: ticks.first + index * slice.tickStep
                width: major ? 7 : 4
                height: 1
                color: major ? Theme.hairlineStrong : Theme.hairline
                opacity: ruler.strength(y)
            }
        }
    }

    // the hairline from the dial to the title
    Rectangle {
        x: Theme.graphX + slice.dialSize / 2 + 4
        y: slice.headerY - 0.5
        width: Math.max(0, Theme.contentX - 8 - x)
        height: 1
        color: Theme.hairlineStrong
    }

    // ---- the date dial ----
    Item {
        id: dial
        x: Theme.graphX - width / 2
        y: slice.headerY - height / 2
        width: slice.dialSize
        height: slice.dialSize

        readonly property real discRadius: disc.width * 0.32
        readonly property date day: {
            const p = slice.dateIso.split("-")
            return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
        }

        // today glows red once, softly
        RectangularShadow {
            id: glow
            visible: slice.isToday
            anchors.fill: disc
            radius: dial.discRadius
            blur: 18
            spread: 2
            color: Qt.alpha(Theme.now, 0.45)
            opacity: 0
            SequentialAnimation {
                running: slice.isToday
                PauseAnimation { duration: 300 }
                NumberAnimation { target: glow; property: "opacity"; to: 1; duration: 450; easing.type: Easing.OutCubic }
                NumberAnimation { target: glow; property: "opacity"; to: 0.25; duration: 1400; easing.type: Easing.InOutSine }
            }
        }
        // the raised squircle
        Surface {
            id: disc
            anchors.fill: parent
            anchors.margins: 5
            radius: dial.discRadius
            topColor: Qt.lighter(Theme.panelRaised, 1.1)
            opacity: slice.isPast ? 0.75 : 1
        }
        Column {
            anchors.centerIn: disc
            spacing: -1
            CapsLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale("en_GB").toString(dial.day, "ddd")
                font.pixelSize: 7
                font.letterSpacing: 0.8
                color: slice.isToday ? Theme.now : Theme.textFaint
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.day.getDate()
                font.pixelSize: slice.isToday ? 14 : 12
                font.weight: Font.DemiBold
                color: slice.isToday ? Theme.now : slice.isPast ? Theme.textMuted : Theme.text
            }
        }
        // how much of the day is done, following the squircle's shape
        ProgressOutline {
            anchors.fill: parent
            thickness: 2.5
            cornerRadius: dial.discRadius + 5
            value: slice.total > 0 ? slice.done / slice.total : 0
            trackColor: slice.isPast && slice.done < slice.total ? Theme.ringMissed : Theme.ringTrack
        }
    }
}
