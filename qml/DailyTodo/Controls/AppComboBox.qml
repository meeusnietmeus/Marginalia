import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import DailyTodo.Style

// A dropdown in the app style: an inset pill showing the current choice with a chevron, and a
// floating list of the choices under it. Give it `model` as a list of { text, value } (or plain
// strings) and read / set `currentValue`; `activated` fires when the user picks one.
ComboBox {
    id: control

    textRole: "text"
    valueRole: "value"

    implicitWidth: 170
    implicitHeight: 30
    leftPadding: 14
    rightPadding: 34
    topPadding: 0
    bottomPadding: 0
    hoverEnabled: true
    font.pixelSize: 13

    background: Well {
        radius: height / 2
        focused: control.activeFocus || control.popup.visible
    }
    contentItem: Text {
        text: control.displayText
        font: control.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: IconImage {
        x: control.width - width - 12
        y: (control.height - height) / 2
        source: Theme.iconChevronDown
        sourceSize: Qt.size(14, 14)
        color: control.hovered || control.popup.visible ? Theme.text : Theme.textMuted
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }

    delegate: ItemDelegate {
        id: option
        required property var modelData
        required property int index
        width: control.popup.width - control.popup.leftPadding - control.popup.rightPadding
        height: 34
        leftPadding: 12
        rightPadding: 12
        topPadding: 0
        bottomPadding: 0
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: typeof option.modelData === "object" ? option.modelData[control.textRole] : option.modelData
            font.pixelSize: 13
            font.bold: option.index === control.currentIndex
            color: Theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 9
            color: option.highlighted ? Qt.alpha(Theme.text, 0.07) : "transparent"
        }
    }

    popup: Popup {
        y: control.height + 6
        width: control.width
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110 }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 140; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 80 } }

        background: Surface {
            elevation: 2
            radius: 14
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            interactive: false
        }
    }
}
