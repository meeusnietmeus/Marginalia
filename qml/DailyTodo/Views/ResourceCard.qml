import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import DailyTodo.Style
import DailyTodo.Controls

// One resource in the library: a raised card with a small tile in the kind's colour holding its
// icon, the kind as a label next to it, and the title under them. A soft glow in the kind's colour
// sits in the top-right corner. Hovering lifts the card and brightens its edge and glow. A local
// file that has disappeared gets a red tile with a warning sign and says so.
Item {
    id: card

    property string kind
    property string title
    property bool missing: false
    property bool menuShown: false     // its context menu is open (it stays lit meanwhile)

    readonly property color kindColor: missing ? Theme.danger : Theme.resourceColor(kind)
    readonly property bool lit: hover.hovered || menuShown

    readonly property var kindNames: ({ pdf: "PDF", web: "Web page", video: "Video", word: "Word",
                                        excel: "Excel", powerpoint: "Slides", link: "Link", file: "File" })

    signal clicked()
    signal menuRequested(point position)   // right-click: the resource menu (ResourceActions)

    implicitHeight: 78

    Item {
        id: lifted
        width: card.width
        height: card.height
        y: card.lit ? -2 : 0
        scale: tap.pressed ? 0.98 : 1
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 90 } }

        Surface {
            anchors.fill: parent
            lit: card.lit
        }

        // the glow in the kind's colour, inside the card's rounded corners
        Shape {
            anchors.fill: parent
            opacity: card.lit ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: 200 } }
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: lifted.width; centerY: 0
                    centerRadius: lifted.width * 0.75
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: Qt.alpha(card.kindColor, 0.28) }
                    GradientStop { position: 1; color: Qt.alpha(card.kindColor, 0) }
                }
                PathRectangle { width: lifted.width; height: lifted.height; radius: Theme.cardRadius }
            }
        }

        // header: the icon tile + the kind
        Row {
            x: 10
            y: 10
            spacing: 8
            KindTile {
                kind: card.kind
                missing: card.missing
            }
            CapsLabel {
                anchors.verticalCenter: parent.verticalCenter
                text: card.missing ? "File not found" : (card.kindNames[card.kind] || card.kind)
                color: card.missing ? Theme.danger : Theme.textMuted
            }
        }

        Text {
            x: 12
            y: 40
            width: lifted.width - 24
            text: card.title
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: card.missing ? Theme.textMuted : Theme.text
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    ClickHandler { id: tap; onTapped: card.clicked() }

    ClickHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (eventPoint) => card.menuRequested(eventPoint.position)
    }
}
