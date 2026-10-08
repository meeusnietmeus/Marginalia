import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The "Overview" tab: three columns. The centre one (the timeline) is the focus; Library and
// Notes sit in the periphery, pushed outward and faded until hovered.
Item {
    id: page

    required property var controller
    required property var actions            // the resource menu and dialogs (ResourceActions)

    readonly property real gap: 20
    readonly property real centerWidth: Math.max(320, width * 3 / 7)    // columns split 2/7 : 3/7 : 2/7
    readonly property real sideWidth: Math.max(140, (width - centerWidth) / 2 - gap)

    clip: true

    // Left column: Jump back in (as tall as its rows, at most half the column; always visible)
    // over Library (the rest, peripheral).
    JumpBackIn {
        id: recent
        controller: page.controller
        actions: page.actions
        width: page.sideWidth
        height: Math.min(contentHeight, page.height / 2)
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        anchors.left: parent.left
        anchors.top: parent.top
    }

    LibraryPanel {
        controller: page.controller
        actions: page.actions
        width: page.sideWidth
        anchors.left: parent.left
        anchors.top: recent.bottom
        anchors.bottom: parent.bottom
        z: 1
    }

    BacklogPanel {
        controller: page.controller
        width: page.sideWidth
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        z: 1
    }
    ColumnLayout {
        width: page.centerWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            Layout.leftMargin: 12
            Layout.rightMargin: 6
            SectionTitle {
                text: "Timeline"
                Layout.fillWidth: true
            }
        }

        DayView {
            id: dayView
            controller: page.controller
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
