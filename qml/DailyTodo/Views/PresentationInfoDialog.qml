import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// What is going on with a presentation: where its PDF is, where the notes and comments come from,
// what was found. For when something doesn't show up.
AppDialog {
    id: dialog

    required property var controller
    property int resourceId: -1
    property string info: ""

    function show(id) {
        resourceId = id
        info = controller.presentationDebugInfo(id)
        open()
    }

    width: Math.min(720, parent.width - 40)
    height: Math.min(520, parent.height - 40)

    contentItem: ColumnLayout {
        spacing: 12

        RowLayout {
            DialogTitle {
                text: "Presentation info"
                Layout.fillWidth: true
            }
            IconButton {
                iconSource: Theme.iconClose
                fallbackText: "×"
                onClicked: dialog.close()
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            TextArea {
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: dialog.info
                font.family: "Consolas"
                font.pixelSize: 12
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentText
                padding: 12
                background: Well { radius: 12 }
            }
        }

        RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            AppButton { text: "Refresh"; onClicked: dialog.info = dialog.controller.presentationDebugInfo(dialog.resourceId) }
            AppButton { text: "Copy"; onClicked: dialog.controller.copyText(dialog.info) }
            AppButton { text: "Close"; filled: true; onClicked: dialog.close() }
        }
    }
}