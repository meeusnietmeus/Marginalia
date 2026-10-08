import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl  // IconImage
import QtQuick.Effects
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The video itself, at the top of its tab: its preview picture with a play button (click it to
// watch) and its name under it. The height follows the width.
Surface {
    id: card

    property string title
    property string uri
    property url thumbnail
    property string thumbnailError

    signal watchRequested()

    readonly property bool isYoutube: /^https?:\/\/([a-z0-9-]+\.)*(youtube(-nocookie)?\.[a-z.]+|youtu\.be)\//i.test(uri)
    readonly property string host: {
        const m = /^[a-z][a-z0-9+.\-]*:\/\/(?:www\.)?([^\/?#]+)/i.exec(uri)
        return m ? m[1] : ""
    }

    radius: 18
    implicitHeight: column.implicitHeight + 16

    ColumnLayout {
        id: column
        x: 8
        y: 8
        width: parent.width - 16
        spacing: 0

        // ---- the picture ----
        Item {
            id: screen
            Layout.fillWidth: true
            Layout.preferredHeight: width * 9 / 16

            readonly property bool hovered: screenHover.hovered

            Item {                                       // rounded corners for the picture
                id: screenMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle { anchors.fill: parent; radius: 12 }
            }
            Item {
                id: picture
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: screenMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                Rectangle { anchors.fill: parent; color: Theme.well }
                Image {
                    id: preview
                    anchors.fill: parent
                    source: card.thumbnail
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                    scale: screen.hovered ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
                Rectangle {                              // the lower part darkens a little
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.45; color: "transparent" }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.45) }
                    }
                }
            }
            Rectangle {                                  // its edge, sunk into the card
                anchors.fill: parent
                radius: 12
                color: "transparent"
                border.color: Qt.rgba(0, 0, 0, 0.35)
            }

            // no picture (yet)
            CapsLabel {
                visible: preview.status !== Image.Ready
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                text: card.thumbnailError !== "" ? card.thumbnailError : "Loading the preview..."
                color: Theme.textFaint
            }

            // the play button: a raised red bead
            Item {
                id: play
                anchors.centerIn: parent
                width: Math.min(64, parent.width * 0.2)
                height: width
                scale: screen.hovered ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                RectangularShadow {
                    anchors.fill: parent
                    radius: width / 2
                    offset.y: 4
                    blur: 16
                    color: Qt.alpha(Theme.resourceVideo, screen.hovered ? 0.6 : 0.4)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Theme.resourceVideo, 1.2) }
                        GradientStop { position: 1; color: Qt.darker(Theme.resourceVideo, 1.15) }
                    }
                    border.color: Qt.darker(Theme.resourceVideo, 1.4)
                    Rectangle {                          // the glint
                        x: parent.width * 0.3
                        y: 2
                        width: parent.width * 0.4
                        height: 2
                        radius: 1
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }
                    IconImage {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: parent.width * 0.04
                        source: Theme.iconPlay
                        sourceSize: Qt.size(parent.width * 0.4, parent.width * 0.4)
                        color: "white"
                    }
                }
            }

            // where it is from, in the corner
            PillLabel {
                visible: card.host !== ""
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                text: card.isYoutube ? "YouTube" : card.host
                tint: "white"
                textColor: Qt.rgba(1, 1, 1, 0.85)
                color: Qt.rgba(0, 0, 0, 0.45)
            }

            HoverHandler { id: screenHover; cursorShape: Qt.PointingHandCursor }
            ClickHandler { onTapped: card.watchRequested() }
        }

        // ---- what it is ----
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            text: card.title
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: Theme.serifFont
            font.pixelSize: 20
            color: Theme.text
        }
        Item { implicitHeight: 6 }
    }
}
