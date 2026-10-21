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

        // Quick but soft: entries fade in with a small rise, fade out in place, and the rest glide
        // into their new spots instead of jumping.
        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.listEnterDuration; easing.type: Easing.OutCubic }
                NumberAnimation { property: "y"; from: ViewTransition.destination.y + Theme.listEnterRise; duration: Theme.listEnterDuration; easing.type: Easing.OutCubic }
            }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.listExitDuration; easing.type: Easing.OutCubic }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Theme.listMoveDuration; easing.type: Easing.OutCubic }
        }

        CapsLabel {
            visible: list.count === 0 && section.emptyText !== ""
            width: list.width - 8
            topPadding: 6
            wrapMode: Text.Wrap
            text: section.emptyText
            color: Theme.textFaint
        }
    }
}
