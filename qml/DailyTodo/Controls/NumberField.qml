import QtQuick
import QtQuick.Controls
import DailyTodo.Style

// A small whole number to choose, in an inset pill: [ −  4  + ]. Type it, click − / +, or scroll
// the wheel over it. `valueModified` fires with the new value (from..to) when the user changes it;
// the owner sets `value` back (it doesn't keep its own copy).
Item {
    id: field

    property int value: 0
    property int from: 0
    property int to: 99

    signal valueModified(int value)

    function change(next) {
        next = Math.max(from, Math.min(to, next))
        if (next !== value) valueModified(next)
        input.text = String(value)          // a refused or unchanged value goes back to the real one
    }

    implicitWidth: 86
    implicitHeight: 28

    Well {
        anchors.fill: parent
        radius: height / 2
        focused: input.activeFocus
    }

    AppButton {
        id: minus
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        compact: true
        implicitHeight: 24
        implicitWidth: 24
        leftPadding: 0
        rightPadding: 0
        text: "−"
        font.pixelSize: 15
        textColor: Theme.textMuted
        enabled: field.value > field.from
        onClicked: field.change(field.value - 1)
    }
    TextInput {
        id: input
        anchors.left: minus.right
        anchors.right: plus.left
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: TextInput.AlignHCenter
        text: String(field.value)
        font.pixelSize: 12
        font.bold: true
        color: Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentText
        selectByMouse: true
        validator: IntValidator { bottom: field.from; top: field.to }
        inputMethodHints: Qt.ImhDigitsOnly
        onEditingFinished: field.change(parseInt(text) || field.value)
        onActiveFocusChanged: if (activeFocus) selectAll()
    }
    AppButton {
        id: plus
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        compact: true
        implicitHeight: 24
        implicitWidth: 24
        leftPadding: 0
        rightPadding: 0
        text: "+"
        font.pixelSize: 15
        textColor: Theme.textMuted
        enabled: field.value < field.to
        onClicked: field.change(field.value + 1)
    }

    Connections {
        target: field
        function onValueChanged() { if (!input.activeFocus) input.text = String(field.value) }
    }
    WheelHandler {
        onWheel: (event) => field.change(field.value + (event.angleDelta.y > 0 ? 1 : -1))
    }
}
