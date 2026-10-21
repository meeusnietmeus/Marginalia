import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// Modal settings window: the PDF scroll speed, backups, a help link and the backup action.
AppDialog {
    id: dialog

    property bool showExport: true
    property real pdfScrollSpeed: 1.5
    property bool backupOnClose: false
    property int backupKeep: 10               // 0: keep them all

    signal exportClicked()
    signal pdfScrollSpeedPicked(real speed)
    signal backupOnCloseToggled(bool on)
    signal backupKeepPicked(int keep)

    width: Math.min(360, parent.width - 40)

    contentItem: ColumnLayout {
        spacing: 16

        RowLayout {
            DialogTitle {
                text: "Settings"
                Layout.fillWidth: true
            }
            IconButton {
                iconSource: Theme.iconClose
                fallbackText: "×"
                onClicked: dialog.close()
            }
        }

        // How fast the mouse wheel scrolls the PDF viewer (1 = Qt's default step).
        ColumnLayout {
            spacing: 6
            Layout.fillWidth: true

            RowLayout {
                Label {
                    text: "PDF scroll speed"
                    font.pixelSize: 12
                    color: Theme.textMuted
                    Layout.fillWidth: true
                }
                Label {
                    text: dialog.pdfScrollSpeed.toFixed(1) + "×"
                    font.pixelSize: 12
                    color: Theme.text
                }
            }
            Slider {
                id: speedSlider
                Layout.fillWidth: true
                from: 0.5
                to: 4
                stepSize: 0.1
                snapMode: Slider.SnapAlways
                value: dialog.pdfScrollSpeed
                onMoved: dialog.pdfScrollSpeedPicked(value)

                background: Rectangle {
                    x: speedSlider.leftPadding
                    y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                    width: speedSlider.availableWidth
                    height: 4
                    radius: 2
                    color: Theme.inputFocus
                    Rectangle {
                        width: speedSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }
                }
                handle: Rectangle {
                    x: speedSlider.leftPadding + speedSlider.visualPosition * (speedSlider.availableWidth - width)
                    y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                    width: 16
                    height: 16
                    radius: 8
                    color: speedSlider.pressed ? Theme.accentHover : Theme.text
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }

        // Backups: made into the workspace folder's .backups folder.
        ColumnLayout {
            spacing: 10
            Layout.fillWidth: true

            Label {
                text: "Backups"
                font.pixelSize: 12
                color: Theme.textMuted
            }
            RowLayout {
                spacing: 8
                AppCheckBox {
                    checked: dialog.backupOnClose
                    onToggled: dialog.backupOnCloseToggled(checked)
                }
                Label {
                    text: "Back up every time the app closes"
                    font.pixelSize: 13
                    color: Theme.text
                    ClickHandler { onTapped: dialog.backupOnCloseToggled(!dialog.backupOnClose) }
                }
            }
            RowLayout {
                spacing: 10
                NumberField {
                    value: dialog.backupKeep
                    from: 0
                    to: 999
                    onValueModified: (value) => dialog.backupKeepPicked(value)
                }
                Label {
                    text: dialog.backupKeep === 0 ? "backups to keep: all of them"
                                                  : "backups to keep (the oldest is removed first)"
                    font.pixelSize: 13
                    color: Theme.text
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }

        // Help: where to look things up.
        ColumnLayout {
            spacing: 6
            Layout.fillWidth: true

            Label {
                text: "Help"
                font.pixelSize: 12
                color: Theme.textMuted
            }
            Label {
                id: mathHelp
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: 13
                color: Theme.accent
                font.underline: mathHelpHover.hovered
                text: "Formula symbols for $...$ (mathtext)"

                HoverHandler {
                    id: mathHelpHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: Qt.openUrlExternally("https://matplotlib.org/stable/users/explain/text/mathtext.html")
                }
            }
        }

        AppButton {
            visible: dialog.showExport
            text: "Back up now"
            filled: true
            Layout.alignment: Qt.AlignLeft
            onClicked: dialog.exportClicked()
        }
    }
}
