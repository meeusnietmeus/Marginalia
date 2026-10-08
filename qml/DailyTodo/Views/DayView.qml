import QtQuick
import QtQuick.Controls
import DailyTodo.Style
import DailyTodo.Controls

// The scrolling list of days, plus the layer the floating "add todo" boxes live in.
Item {
    id: view

    required property var controller           // TodoController (Python), provides `days`

    readonly property var hostWindow: Window.window

    // Scrolls just far enough that `item` (e.g. an add box) is fully inside the viewport.
    function revealItem(item) {
        const bottom = item.mapToItem(dayList, 0, item.height).y
        const overflow = bottom + 12 - dayList.height
        if (overflow > 0) {
            revealAnim.to = dayList.contentY + overflow
            revealAnim.restart()
        }
    }

    ListView {
        id: dayList
        anchors.fill: parent
        clip: true
        model: view.controller ? view.controller.days : null
        topMargin: 12
        bottomMargin: 68                       // room for the graph line to fade out after the last day
        boundsBehavior: Flickable.StopAtBounds

        // The ListView swallows clicks before the window-level handler can see them.
        FocusClearTapHandler { hostWindow: view.hostWindow }

        // Mouse-wheel scrolling at Qt's default distance (~68 px per notch with the usual 3 lines
        // per notch), but eased instead of jumping. Touchpads already deliver smooth pixel deltas,
        // so those are applied directly.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const minY = dayList.originY - dayList.topMargin
                const maxY = Math.max(minY, dayList.originY + dayList.contentHeight
                                            - dayList.height + dayList.bottomMargin)
                revealAnim.stop()
                dayList.cancelFlick()
                if (event.pixelDelta.y !== 0) {
                    wheelAnim.stop()
                    dayList.contentY = Math.max(minY, Math.min(maxY,
                        dayList.contentY - event.pixelDelta.y * Theme.scrollSpeed))
                    dayList.returnToBounds()  // the list's height is an estimate until its days exist
                    return
                }
                const dy = event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * (68 / 3)
                         * Theme.scrollSpeed
                const from = wheelAnim.running ? wheelAnim.to : dayList.contentY
                wheelAnim.stop()
                wheelAnim.to = Math.max(minY, Math.min(maxY, from - dy))
                wheelAnim.start()
            }
        }

        NumberAnimation {
            id: wheelAnim
            target: dayList
            property: "contentY"
            duration: 160
            easing.type: Easing.OutCubic
            onFinished: dayList.returnToBounds()
        }

        NumberAnimation {
            id: revealAnim
            target: dayList
            property: "contentY"
            duration: 150
            easing.type: Easing.OutCubic
        }

        delegate: DayDelegate {
            controller: view.controller
            listView: dayList
            overlay: overlayLayer
            onRevealRequested: (item) => view.revealItem(item)
        }
    }

    // Layer for the floating add boxes. It lies exactly over the list (and clips like it), but
    // is a SIBLING of the list, not a child: the frosted glass samples the list, and an effect
    // that samples a tree it sits in would end up sampling itself.
    Item {
        id: overlayLayer
        anchors.fill: dayList
        clip: true
        z: 5
    }
}
