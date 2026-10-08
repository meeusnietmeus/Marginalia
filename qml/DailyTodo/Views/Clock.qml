pragma Singleton
import QtQuick

// App-wide wall clock for UI that depends on the time of day. Ticks every 30 s.
QtObject {
    id: clock

    property date now: new Date()

    // Between midnight and 4 a.m. the calendar day is easy to mix up with "late yesterday".
    readonly property bool lateNight: now.getHours() < 4

    readonly property Timer ticker: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: clock.now = new Date()
    }
}
