import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style

// Modal "are you sure?". Call ask(payload, message); confirmed(payload) fires on the confirm
// button, so one dialog can serve many items.
AppDialog {
    id: dialog

    property string title: "Are you sure?"
    property string confirmText: "Delete"
    property bool danger: true
    property var payload: null
    property string message

    signal confirmed(var payload)

    function ask(item, text) {
        payload = item
        message = text
        open()
    }

    width: Math.min(380, parent.width - 40)

    contentItem: ColumnLayout {
        spacing: 14

        DialogTitle {
            text: dialog.title
        }
        Label {
            text: dialog.message
            wrapMode: Text.Wrap
            font.pixelSize: 13
            color: Theme.textMuted
            Layout.fillWidth: true
        }
        RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            AppButton {
                text: "Cancel"
                onClicked: dialog.close()
            }
            AppButton {
                text: dialog.confirmText
                textColor: dialog.danger ? Theme.danger : Theme.accentText
                filled: !dialog.danger
                onClicked: {
                    const item = dialog.payload
                    dialog.close()
                    dialog.confirmed(item)
                }
            }
        }
    }
}