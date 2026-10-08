import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// The heading of a section ("Timeline", "Library", "Notes"...): the title in the serif, with an
// optional count in a pill after it. While `loading` stays true for a moment, the title pulses.
Item {
    id: heading

    property string text
    property string badge                    // a count next to the title ("8"); empty: none
    property int size: 24
    property bool loading: false

    readonly property int pulseDelay: 150    // ms of loading before the title starts pulsing
    property bool pulsing: false
    property real pulsePhase: 0              // 0..1, animated while pulsing

    // (from the parts, not the row: the row's width follows this item's)
    implicitWidth: label.implicitWidth + (pill.visible ? pill.implicitWidth + row.spacing : 0)
    implicitHeight: label.implicitHeight
    width: implicitWidth
    height: implicitHeight

    onLoadingChanged: {
        if (loading) delayTimer.restart()
        else {
            delayTimer.stop()
            pulsing = false
        }
    }
    Timer {
        id: delayTimer
        interval: heading.pulseDelay
        onTriggered: heading.pulsing = heading.loading
    }
    SequentialAnimation {
        running: heading.pulsing
        loops: Animation.Infinite
        NumberAnimation { target: heading; property: "pulsePhase"; to: 1; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { target: heading; property: "pulsePhase"; to: 0; duration: 650; easing.type: Easing.InOutSine }
        onStopped: heading.pulsePhase = 0
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, heading.width)
        spacing: 10

        Label {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, heading.width - (pill.visible ? pill.width + row.spacing : 0))
            text: heading.text
            elide: Text.ElideRight
            font.family: Theme.serifFont
            font.pixelSize: heading.size
            color: Theme.text
            opacity: heading.pulsing ? 1 - 0.7 * heading.pulsePhase : 1
        }
        PillLabel {
            id: pill
            visible: heading.badge !== ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 2
            text: heading.badge
        }
    }
}
