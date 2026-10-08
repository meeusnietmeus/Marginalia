import QtQuick
import QtQuick.Controls
import DailyTodo.Style
import DailyTodo.Controls

// A small popover with the highlight colours side by side, as actual colours (no labels). The last
// one is "transparent": a crossed-out circle. Open it with openAt(x, y) (the point it points at, in
// the parent's coordinates); picked(color) fires with the colour's name and the popover closes.
Popup {
    id: pop

    property string current: "yellow"       // ringed
    property real px: 0
    property real py: 0

    signal picked(string color)

    function openAt(x, y, currentColor) {
        px = x
        py = y
        current = currentColor
        open()
    }

    // centred over the point, above it (below it when there is no room)
    x: Math.max(8, Math.min(parent.width - width - 8, px - width / 2))
    y: py - height - 12 < 8 ? py + 16 : py - height - 12

    padding: 8
    modal: false
    focus: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Surface {
        elevation: 2
        radius: height / 2
    }

    contentItem: Row {
        spacing: 6

        Repeater {
            model: Theme.highlightKeys

            delegate: Item {
                id: swatch
                required property string modelData
                readonly property bool selected: modelData === pop.current
                width: 28
                height: 28
                scale: swatchHover.hovered ? 1.14 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }

                Rectangle {                                   // the colour
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: width / 2
                    color: swatch.modelData === "none" ? "transparent" : Theme.highlightColor(swatch.modelData)
                    border.width: swatch.modelData === "none" ? 1 : 0
                    border.color: Theme.textMuted

                    Rectangle {                               // "none": crossed out
                        visible: swatch.modelData === "none"
                        anchors.centerIn: parent
                        width: 2
                        height: parent.height - 4
                        rotation: 45
                        color: Theme.textMuted
                    }
                }
                Rectangle {                                   // ring around the current one
                    visible: swatch.selected
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.text
                }

                HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                ClickHandler {
                    onTapped: {
                        pop.close()
                        pop.picked(swatch.modelData)
                    }
                }
            }
        }
    }
}
