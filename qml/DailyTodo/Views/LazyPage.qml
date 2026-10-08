import QtQuick

// A page that is made when it is first shown and thrown away again some time after it was left
// (5 minutes by default), so a page you visited once doesn't keep its memory for the rest of the
// session. Coming back within that time finds it as it was; later, it is made afresh. Set `shown`
// while it is the visible page.
Loader {
    id: page

    property bool shown: false
    property int unloadAfter: 5 * 60 * 1000          // ms after leaving it
    readonly property bool loaded: status === Loader.Ready
    property double unloadsAt: 0                     // when it will be unloaded (ms since epoch); 0: not counting down

    property bool keep: false
    active: shown || keep

    onShownChanged: {
        if (shown) {
            keep = true
            countdown.stop()
            unloadsAt = 0
        } else if (keep) {
            countdown.restart()
            unloadsAt = Date.now() + unloadAfter
        }
    }

    Timer {
        id: countdown
        interval: page.unloadAfter
        onTriggered: {
            page.keep = false
            page.unloadsAt = 0
        }
    }
}
