import QtQuick
import QtQuick.Layouts
import DailyTodo.Style

// One setting: its name (and a line of explanation) on the left, the control on the right. The
// controls are declared inside, e.g.  SettingsRow { label: "Sort"; AppComboBox { ... } }
RowLayout {
    id: row

    property string label
    property string hint
    property bool wide: false                  // the control gets the whole width under the label
    default property alias control: slot.data

    Layout.fillWidth: true
    spacing: 16

    ColumnLayout {
        spacing: 2
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Text {
            text: row.label
            font.pixelSize: 13
            color: Theme.text
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text {
            visible: row.hint !== ""
            text: row.hint
            font.pixelSize: 11
            color: Theme.textFaint
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
    RowLayout {
        id: slot
        spacing: 8
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
    }
}
