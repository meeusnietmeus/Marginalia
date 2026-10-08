import QtQuick
import QtQuick.Controls.impl  // IconImage
import QtQuick.Effects
import DailyTodo.Style

// A two-way switch: an inset track holding a left and a right label (text, or an icon when
// leftIcon / rightIcon is set). The active side sits on a raised pill, which slides across when the
// switch flips.
Item {
    id: sw

    property string leftText
    property string rightText
    property url leftIcon                  // set these instead of the texts for an icon switch
    property url rightIcon
    property bool rightActive: false

    signal toggledTo(bool right)      // the user picked a side

    readonly property bool useIcons: leftIcon.toString() !== "" || rightIcon.toString() !== ""
    readonly property real segmentWidth: useIcons ? 34
        : Math.max(leftLabel.implicitWidth, rightLabel.implicitWidth) + 24
    readonly property real inset: 3

    implicitWidth: 2 * segmentWidth + 2 * inset
    implicitHeight: 26

    // track
    Well {
        anchors.fill: parent
        radius: height / 2
    }

    // active side
    Item {
        x: sw.inset + (sw.rightActive ? sw.segmentWidth : 0)
        y: sw.inset
        width: sw.segmentWidth
        height: parent.height - 2 * sw.inset
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        RectangularShadow {
            anchors.fill: thumb
            radius: thumb.radius
            offset.y: 1
            blur: 4
            color: Theme.shadow
        }
        Rectangle {
            id: thumb
            anchors.fill: parent
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(Theme.panelRaised, 1.12) }
                GradientStop { position: 1; color: Theme.panel }
            }
            border.color: Theme.hairlineStrong
        }
    }

    Row {
        x: sw.inset
        y: sw.inset
        height: parent.height - 2 * sw.inset

        Item {
            width: sw.segmentWidth
            height: parent.height
            Text {
                id: leftLabel
                visible: !sw.useIcons
                anchors.centerIn: parent
                text: sw.leftText
                font.pixelSize: 12
                font.bold: !sw.rightActive
                color: sw.rightActive ? Theme.textMuted : Theme.text
            }
            IconImage {
                visible: sw.useIcons
                anchors.centerIn: parent
                source: sw.leftIcon
                sourceSize: Qt.size(14, 14)
                color: sw.rightActive ? Theme.textMuted : Theme.text
            }
        }
        Item {
            width: sw.segmentWidth
            height: parent.height
            Text {
                id: rightLabel
                visible: !sw.useIcons
                anchors.centerIn: parent
                text: sw.rightText
                font.pixelSize: 12
                font.bold: sw.rightActive
                color: sw.rightActive ? Theme.text : Theme.textMuted
            }
            IconImage {
                visible: sw.useIcons
                anchors.centerIn: parent
                source: sw.rightIcon
                sourceSize: Qt.size(14, 14)
                color: sw.rightActive ? Theme.text : Theme.textMuted
            }
        }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    ClickHandler {
        onTapped: (eventPoint) => sw.toggledTo(eventPoint.position.x > sw.width / 2)
    }
}