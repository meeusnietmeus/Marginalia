import QtQuick
import QtQuick.Effects

// Frosted-glass background: a blurred copy of whatever part of `sourceItem` lies under
// this item, clipped to rounded corners, with a tint and a rim on top.
//
// The glass must NOT be inside `sourceItem` (an effect that samples a tree it sits in
// ends up sampling itself), so put it in a sibling layer that lies over the source.
// The blur is only built while the glass is visible, so hidden instances cost nothing.
Item {
    id: glass

    property Item sourceItem: null
    // Anything that moves the glass relative to sourceItem, so the sampled region follows,
    // e.g. [list.contentY, box.x, box.y].
    property var trackedValues: []

    property real radius: 0
    property real blur: 1           // 0..1
    property int blurMax: 48
    property color tint: "transparent"
    property color borderColor: "transparent"

    Loader {
        anchors.fill: parent
        active: glass.visible && glass.sourceItem !== null
        sourceComponent: Item {
            ShaderEffectSource {
                id: backdrop
                sourceItem: glass.sourceItem
                visible: false
                sourceRect: {
                    glass.trackedValues                    // re-evaluate on scroll / move
                    const p = glass.mapToItem(glass.sourceItem, 0, 0)
                    return Qt.rect(p.x, p.y, glass.width, glass.height)
                }
            }
            // rounded-corner mask for the blurred picture
            Item {
                id: mask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle { anchors.fill: parent; radius: glass.radius }
            }
            MultiEffect {
                anchors.fill: parent
                source: backdrop
                blurEnabled: true
                blur: glass.blur
                blurMax: glass.blurMax
                maskEnabled: true
                maskSource: mask
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: glass.tint
        border.color: glass.borderColor
    }
}
