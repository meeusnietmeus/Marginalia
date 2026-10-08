import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// Thin line between two groups of menu entries.
MenuSeparator {
    topPadding: 5
    bottomPadding: 5
    leftPadding: 8
    rightPadding: 8
    contentItem: Rectangle {
        implicitHeight: 1
        color: Theme.hairline
    }
}
