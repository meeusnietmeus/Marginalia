import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// Tooltip in the style of the menus. Put it inside the item it describes and bind `shown` to
// that item's hover state; it appears after a short delay and goes away at once.
ToolTip {
    id: tip

    property bool shown: false

    visible: shown
    delay: 450
    timeout: -1
    padding: 8
    leftPadding: 10
    rightPadding: 10

    property real maxTextWidth: 320        // longer text wraps

    contentItem: Text {
        text: tip.text
        width: Math.min(implicitWidth, tip.maxTextWidth)
        wrapMode: Text.Wrap
        font.pixelSize: 12
        color: Theme.text
    }
    background: Surface {
        elevation: 2
        radius: 9
    }

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 60 } }
}
