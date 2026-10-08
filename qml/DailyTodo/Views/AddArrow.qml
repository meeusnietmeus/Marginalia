import QtQuick
import QtQuick.Controls.impl    // IconImage (tinted icon)
import DailyTodo.Style
import DailyTodo.Controls

// The green "add here" marker sitting on the graph line. A window-coloured disc behind it
// hides the line underneath. Positions itself on the graph; set centerY.
Item {
    id: arrow

    property bool shown: false
    property real centerY: 0

    width: Theme.arrowSize + 6
    height: width
    x: Theme.graphX - width / 2
    y: centerY - height / 2
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 100 } }

    Surface {
        anchors.fill: parent
        radius: width / 2
        topColor: Theme.accentTop
        bottomColor: Theme.accentBottom
        edgeColor: Qt.darker(Theme.accentBottom, 1.25)
    }
    IconImage {
        anchors.centerIn: parent
        source: Theme.iconPlus
        sourceSize: Qt.size(Theme.arrowSize - 2, Theme.arrowSize - 2)
        color: Theme.accentText
    }
}
