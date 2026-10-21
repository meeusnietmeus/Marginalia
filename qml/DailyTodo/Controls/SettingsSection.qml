import QtQuick
import QtQuick.Layouts
import DailyTodo.Style

// One section of a settings window: a small uppercase title above a quiet card that holds the
// rows (SettingsRow, or anything else). Everything declared inside goes into the card.
ColumnLayout {
    id: section

    property string title
    property string note                       // a line of explanation under the card
    default property alias content: rows.data

    spacing: 8

    Text {
        visible: section.title !== ""
        text: section.title
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: Theme.labelSpacing
        font.capitalization: Font.AllUppercase
        color: Theme.textMuted
        Layout.leftMargin: 4
    }
    QuietCard {
        Layout.fillWidth: true
        implicitHeight: rows.implicitHeight + 24
        ColumnLayout {
            id: rows
            anchors.fill: parent
            anchors.margins: 14
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            spacing: 12
        }
    }
    Text {
        visible: section.note !== ""
        text: section.note
        font.pixelSize: 11
        color: Theme.textFaint
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.leftMargin: 4
    }
}
