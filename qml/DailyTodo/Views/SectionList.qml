import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// A titled list. Its height comes from the layout it sits in, never from its content. While
// `loading` stays true for a moment, the title pulses. With `emptyText`, an empty list says so.
ColumnLayout {
    id: section

    property string title
    property string badge
    property bool loading: false
    property string emptyText: ""
    property alias model: list.model
    property alias delegate: list.delegate
    readonly property alias count: list.count

    spacing: 10

    SectionTitle {
        visible: section.title !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 14
        text: section.title
        badge: section.badge
        size: 22
        loading: section.loading
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 14
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: AppScrollBar {}

        CapsLabel {
            visible: list.count === 0 && section.emptyText !== "" && !section.loading
            width: list.width - 8
            topPadding: 6
            wrapMode: Text.Wrap
            text: section.emptyText
            color: Theme.textFaint
        }
    }
}
