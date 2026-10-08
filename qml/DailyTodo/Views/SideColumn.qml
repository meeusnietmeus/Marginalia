import QtQuick
import QtQuick.Controls
import DailyTodo.Style
import DailyTodo.Controls

// A peripheral column (Library / Backlog). At rest its content is pushed outward, partly out of
// view, and fades out towards the outer edge. Hovering lifts the fade and slides the
// content in; only this column's content moves. The item itself never changes size or position.
//
// Put the column's content inside it (it lands in the body area under the heading); put buttons
// for the heading row in `headerActions`.
Item {
    id: column

    property string title
    property string badge                   // a count next to the title ("8"); empty: none
    property bool alignRight: false
    // How much of the content stays visible at rest (0..1).
    property real restVisible: 0.5

    default property alias body: bodyArea.data
    property alias headerActions: actionsRow.data            // follow the title
    property alias headerActionsEnd: actionsEndRow.data      // pushed to the far edge

    clip: true

    // A click anywhere in the column that isn't the focused text field leaves that field.
    FocusClearTapHandler { hostWindow: column.Window.window }

    // Hover-in is debounced (the pointer must rest on the column briefly); hover-out is instant.
    property bool revealed: false
    // Set while something that belongs to the column (e.g. a context menu) is open: the pointer
    // is then over that popup, not the column, but the column must stay put.
    property bool pinned: false
    // After a popup closes, the hover handler still says "not hovering" (it saw the pointer move
    // onto the popup) and says nothing new until the pointer moves. Without this the column would
    // collapse the instant a menu closes. So after unpinning, trust the pointer's last known
    // place (inside the column) until the next real pointer movement.
    property bool settling: false
    readonly property bool hovered: zone.hover.hovered || pinned || settling
    onPinnedChanged: settling = !pinned && !zone.hover.hovered
    onHoveredChanged: {
        if (hovered) revealTimer.restart()
        else { revealTimer.stop(); revealed = false }
    }

    Timer {
        id: revealTimer
        interval: 70
        onTriggered: column.revealed = column.hovered
    }

    Item {
        id: content
        width: column.width
        height: column.height
        // At rest the content fades out towards the outer edge. It is the content itself that fades,
        // not a colour laid on top, so whatever lies behind the column shows through.
        property real fade: column.revealed ? 0 : 1
        Behavior on fade { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        layer.enabled: true
        layer.effect: ShaderEffect {
            readonly property real shift: content.x / Math.max(1, column.width)
            readonly property real alignRight: column.alignRight ? 1 : 0
            readonly property real amount: content.fade
            fragmentShader: "shaders/sidefade.frag.qsb"
        }
        x: column.revealed ? 0
                           : (column.alignRight ? 1 : -1) * column.width * (1 - column.restVisible)

        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        // At rest the title hugs the edge that stays visible (right-aligned in the left column).
        // When the column opens it glides to the left edge, and the actions fade in after it:
        // "Library [switch] [create]".
        SectionTitle {
            id: heading
            x: column.alignRight || column.revealed ? 12 : parent.width - width - 12
            height: 56
            text: column.title
            badge: column.badge

            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        Row {
            id: actionsRow
            x: heading.x + heading.width + 16
            height: 56
            spacing: 10
            visible: children.length > 0
            opacity: column.revealed ? 1 : 0
            enabled: column.revealed
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
        Row {
            id: actionsEndRow
            x: parent.width - width - 12
            height: 56
            spacing: 10
            visible: children.length > 0
            opacity: column.revealed ? 1 : 0
            enabled: column.revealed
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        Item {
            id: bodyArea
            x: 12
            y: heading.height + 6
            width: parent.width - 24
            height: parent.height - y - 12
        }
    }

    // Hover zone: the visible strip at rest, the whole column while revealed (so it can't flicker
    // while the content slides under the pointer). It lies over the content and doesn't block, so
    // hovering a button or card inside the column still counts as hovering the column.
    Item {
        id: zone
        property alias hover: hoverHandler
        z: 3                          // above the content, so child hover handlers can't mask it
        height: parent.height
        width: column.revealed ? column.width : column.width * column.restVisible
        x: column.alignRight ? column.width - width : 0
        HoverHandler {
            id: hoverHandler
            blocking: false
            onPointChanged: column.settling = false     // the pointer moved: the handler is right again
            onHoveredChanged: column.settling = false
        }
    }
}
