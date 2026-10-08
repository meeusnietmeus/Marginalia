import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// Popup menu in the app style. Fill it with AppMenuItems. It is as wide as its widest visible
// entry (at least `minimumWidth`), unless a width is set explicitly.
Menu {
    id: menu

    property real minimumWidth: 148

    padding: 6
    background: Surface {
        implicitWidth: menu.minimumWidth
        elevation: 2
        radius: 14
    }
    // grows in from where it was opened
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 140; easing.type: Easing.OutCubic }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 80 } }

    // The style's own sizing leaves the width at the minimum, which clips long entries.
    function fit() {
        let widest = 0
        for (let i = 0; i < count; i++) {
            const item = itemAt(i)
            if (item && item.visible)
                widest = Math.max(widest, item.implicitWidth)
        }
        implicitWidth = Math.max(minimumWidth, widest + leftPadding + rightPadding)
    }
    onAboutToShow: fit()
}
