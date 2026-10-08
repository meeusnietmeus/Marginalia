import QtQuick
import DailyTodo.Style

// A CapsLabel in a soft pill ("THIS WEEK", "8"): a tag on a card, or a count next to a title.
Rectangle {
    id: pill

    property alias text: label.text
    property alias textColor: label.color
    property color tint: Theme.text            // the pill is a faint wash of this colour

    implicitWidth: label.implicitWidth + 16
    implicitHeight: 20
    radius: height / 2
    color: Qt.alpha(tint, 0.08)
    border.color: Qt.alpha(tint, 0.10)

    CapsLabel {
        id: label
        anchors.centerIn: parent
        color: Theme.textMuted
    }
}
