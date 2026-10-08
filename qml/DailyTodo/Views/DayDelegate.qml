import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import DailyTodo.Style
import DailyTodo.Controls

// One day in the list: its slice of the git graph, an optional week divider, the day
// header, its todos, and the floating "add a todo" box.
Item {
    id: day

    // ---- model roles (see ui/day_list_model.py) ----
    required property int index
    required property string dateIso
    required property string dayTitle
    required property string dateLabel
    required property string dayKind
    required property string weekLabel
    required property var todos

    // ---- context, set by DayView ----
    required property var controller
    required property ListView listView
    required property Item overlay          // layer the add box floats in

    signal revealRequested(Item item)        // "scroll so this item is visible"

    readonly property bool isPast: dayKind === "past"
    readonly property bool isToday: dayKind === "today"
    readonly property bool isFirst: index === 0
    readonly property bool isLast: index === listView.count - 1
    // the day after today keeps a little distance from today's raised panel
    readonly property real gapAbove: dayTitle === "Tomorrow" ? 12 : 0
    readonly property int doneCount: todos.filter(t => t.done).length

    // y (in this delegate) of the middle of the day header: where the graph branch arrives
    readonly property real headerY: card.y + Theme.dayPadding + header.height / 2

    // ---- "move all to today": line from the header label down to the todos' move buttons ----
    readonly property bool hasMissed: isPast && todos.some(t => !t.done)
    property real moveLineX: 0              // centre of the move buttons (delegate coords)
    property real moveLineStartX: 0         // just right of the "move all to today" label
    property real moveLineEndY: 0           // centre of the last move button

    function updateMoveLine() {
        if (!hasMissed)
            return
        let last = null
        for (let i = 0; i < todoRepeater.count; i++) {
            const item = todoRepeater.itemAt(i)
            if (item && item.todoRow.canMoveToToday)
                last = item.todoRow.moveButton
        }
        if (!last)
            return
        const p = last.mapToItem(day, last.width / 2, last.height / 2)
        moveLineX = p.x
        moveLineEndY = p.y
        const l = header.moveAllLabel
        moveLineStartX = l.mapToItem(day, l.width + 6, 0).x
    }
    onTodosChanged: Qt.callLater(updateMoveLine)
    onWidthChanged: Qt.callLater(updateMoveLine)
    Component.onCompleted: Qt.callLater(updateMoveLine)

    // ---- floating "add todo" state ----
    property bool addRequested: false              // set by clicking the arrow / gap
    readonly property bool addOpen: addRequested || addBox.text.length > 0
    // The gaps react to the pointer only while the box is closed, and never on past (missed)
    // days. While the box is open a click on a gap is just a click "somewhere else" and
    // closes an empty box like any other outside click.
    readonly property bool gapsLive: !addOpen && !isPast
    property Item hoverGap: null                   // gap the pointer has rested on (after the delay)
    property Item pendingGap: null                 // gap the pointer just entered
    property real arrowY: 0                        // where the arrow sits (delegate coords)

    // Where this day's add box belongs, in this delegate's coordinates: right under the
    // last todo. Glides when todos are added/removed, but never while the box is hidden.
    readonly property real boxX: card.x + column.anchors.leftMargin
    property real boxY: card.y + column.anchors.topMargin + todosArea.y + todosArea.height
    Behavior on boxY {
        enabled: addBox.visible
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    width: listView.width
    // the last day gets some extra room so the graph line can fade out below it
    height: gapAbove + weekSeparator.height + card.height + Theme.daySpacing + (isLast ? 40 : 0)

    // Called by the AddGap strips.
    function gapHovered(gap, hovered) {
        if (hovered) {
            pendingGap = gap
            revealTimer.restart()
        } else if (pendingGap === gap) {
            revealTimer.stop()
            pendingGap = null
            if (hoverGap === gap)
                hoverGap = null
        }
    }

    function openAdd() {
        if (isPast)
            return
        revealTimer.stop()
        hoverGap = null
        addRequested = true
        // Deferred: the tap that got us here is still being delivered, and the
        // window-level tap handler would otherwise take the focus right back.
        Qt.callLater(function () {
            if (!addRequested)
                return            // closed again in the meantime: never focus a hidden box
            addBox.focusInput()
            day.revealRequested(addBox)
        })
    }

    onHoverGapChanged: {
        if (hoverGap)
            arrowY = hoverGap.mapToItem(day, 0, hoverGap.height / 2).y
    }

    Timer {
        id: revealTimer
        interval: Theme.revealDelay
        onTriggered: day.hoverGap = day.pendingGap
    }

    GraphSlice {
        anchors.fill: parent
        headerY: day.headerY
        isFirst: day.isFirst
        isLast: day.isLast
        isToday: day.isToday
        isPast: day.isPast
        dateIso: day.dateIso
        offset: day.y
        total: day.todos.length
        done: day.doneCount
    }

    // Drawn under the todos so their move buttons (opaque base) sit on it like nodes.
    Shape {
        id: moveLine
        visible: day.hasMissed && day.moveLineX > day.moveLineStartX
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: moveShape
            readonly property real r: Theme.graphRadius
            strokeColor: header.moveAllHovered ? Theme.warning : Theme.graphColor
            strokeWidth: Theme.graphLineWidth
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            startX: day.moveLineStartX
            startY: day.headerY
            PathLine { x: day.moveLineX - moveShape.r; y: day.headerY }
            PathArc {
                x: day.moveLineX
                y: day.headerY + moveShape.r
                radiusX: moveShape.r
                radiusY: moveShape.r
                direction: PathArc.Clockwise
            }
            PathLine { x: day.moveLineX; y: Math.max(day.headerY + moveShape.r, day.moveLineEndY) }
        }
    }

    AddArrow {
        shown: day.hoverGap !== null && !day.addOpen
        centerY: day.arrowY
    }

    WeekSeparator {
        id: weekSeparator
        y: day.gapAbove
        x: Theme.contentX
        width: parent.width - Theme.contentX - 16
        label: day.weekLabel
    }

    // Today lies on a slightly raised panel, so it stands out from the days around it.
    Surface {
        visible: day.isToday
        x: card.x + 4
        y: card.y - 2
        width: card.width - 8
        height: card.height + Theme.todoGap - 2
        radius: 14
        topColor: Qt.lighter(Theme.panelRaised, 1.04)
    }

    // Day content. Unstyled on purpose: it only gives the column its size and padding.
    Item {
        id: card
        x: Theme.contentX - 12                      // column.leftMargin (12) puts the text on contentX
        y: day.gapAbove + weekSeparator.height
        width: parent.width - x - 16
        height: column.implicitHeight + 2 * Theme.dayPadding

        ColumnLayout {
            id: column
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 12
                rightMargin: 12
                topMargin: Theme.dayPadding
            }
            spacing: 4

            DayHeader {
                id: header
                Layout.fillWidth: true
                title: day.dayTitle
                dateIso: day.dateIso
                dateLabel: day.dateLabel
                isToday: day.isToday
                isPast: day.isPast
                showLateNightWarning: day.isToday && Clock.lateNight
                showMoveAll: day.hasMissed
                done: day.doneCount
                total: day.todos.length
                onMoveAllRequested: day.controller.moveAllToToday(day.dateIso)
            }

            // Todos. Each one is followed by an AddGap (the spacing between todos); only the
            // gap under the LAST todo of the day reacts to the pointer.
            ColumnLayout {
                id: todosArea
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    id: todoRepeater
                    model: day.todos
                    delegate: ColumnLayout {
                        id: todoItem
                        required property int index
                        required property var modelData
                        property alias todoRow: todoRow
                        Layout.fillWidth: true
                        spacing: 0

                        TodoRow {
                            id: todoRow
                            controller: day.controller
                            onMoveToBacklogRequested: day.controller.moveToBacklog(todoItem.modelData.id)
                            onMoveToDayRequested: (iso) => day.controller.moveToTimeline(todoItem.modelData.id, iso)
                            todo: todoItem.modelData
                            muted: day.isPast
                            reserveMoveSlot: day.hasMissed
                            moveHighlighted: header.moveAllHovered
                            canMoveToToday: day.isPast && !todoItem.modelData.done
                            onDoneToggled: (done) => day.controller.setDone(todoItem.modelData.id, done)
                            onEdited: (text) => day.controller.editTodo(todoItem.modelData.id, text)
                            onCopyRequested: day.controller.copyText(day.controller.toEditText(todoItem.modelData.text))
                            onMoveToTodayRequested: day.controller.moveToToday(todoItem.modelData.id)
                            onDeleteRequested: day.controller.deleteTodo(todoItem.modelData.id)
                        }

                        AddGap {
                            id: todoGap
                            live: day.gapsLive && todoItem.index === day.todos.length - 1
                            onPointerHovered: (hovered) => day.gapHovered(todoGap, hovered)
                            onTapped: day.openAdd()
                        }
                    }
                }

                CapsLabel {
                    visible: day.todos.length === 0
                    text: "Nothing planned"
                    color: Theme.textFaint
                    Layout.leftMargin: 8
                    Layout.topMargin: 4
                }
                // On an empty day the strip under "Nothing planned" plays the same role.
                AddGap {
                    id: emptyGap
                    visible: day.todos.length === 0
                    live: day.gapsLive
                    onPointerHovered: (hovered) => day.gapHovered(emptyGap, hovered)
                    onTapped: day.openAdd()
                }
            }
        }
    }

    // Floats in the overlay layer (not in any layout), so opening it never resizes the day
    // or moves the list, and it can float over the next day.
    AddTodoBox {
        id: addBox
        controller: day.controller
        parent: day.overlay
        // delegate coordinates -> overlay coordinates; re-evaluated on scroll / relayout
        x: day.mapToItem(day.overlay, day.boxX, 0).x
        y: {
            day.listView.contentY; day.y; day.height
            return day.mapToItem(day.overlay, 0, day.boxY).y
        }
        width: card.width - column.anchors.leftMargin - column.anchors.rightMargin
        open: day.addOpen
        backdrop: day.listView
        backdropTracking: [day.listView.contentY, x, y]
        onSubmitted: (text) => day.controller.addTodo(day.dateIso, text)
        onDismissed: day.addRequested = false
    }
}
