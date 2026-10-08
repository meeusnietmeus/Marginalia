import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// Text field in an inset well (see Well), with a green ring while typing.
TextField {
    id: control

    implicitHeight: Theme.controlHeight
    leftPadding: 14
    rightPadding: 14
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    font.pixelSize: 14
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.accent
    selectedTextColor: Theme.accentText
    selectByMouse: true

    background: Well {
        radius: height / 2
        focused: control.activeFocus
    }
}
