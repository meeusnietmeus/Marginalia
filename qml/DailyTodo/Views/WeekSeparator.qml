import QtQuick
import DailyTodo.Style

// "NEXT WEEK |||||||||||||||" divider: a pill with the week's name, then a ruler, a hairline with
// a tick every 8 px and a longer one every 40. Collapses to zero height when label is empty.
Item {
    id: separator

    property string label

    height: visible ? 40 : 0
    visible: label !== ""

    PillLabel {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        text: separator.label
    }

    Item {
        id: ruler
        anchors.left: pill.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 9
        clip: true

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.hairlineStrong
        }
        Row {
            anchors.bottom: parent.bottom
            spacing: 7
            Repeater {
                model: Math.max(0, Math.ceil(ruler.width / 8))
                Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width: 1
                    height: index % 5 === 0 ? 9 : 4
                    color: index % 5 === 0 ? Theme.hairlineStrong : Theme.hairline
                }
            }
        }
    }
}
