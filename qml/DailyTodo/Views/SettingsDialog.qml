import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style
import DailyTodo.Controls

// The app's settings, in sections: how the PDF viewer scrolls, backups (made into the workspace
// folder's .backups folder), and where to look things up.
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

    width: Math.min(parent.width - 40, Math.max(480, parent.width * 0.4))
    height: Math.min(implicitHeight, parent.height - 40)

    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: AppScrollBar {}

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

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

            // ---- the PDF viewer ----
            SettingsSection {
                title: "PDF viewer"
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 6
                    Layout.fillWidth: true
                    RowLayout {
                        Text {
                            text: "Scroll speed"
                            font.pixelSize: 13
                            color: Theme.text
                            Layout.fillWidth: true
                        }
                        Text {
                            text: dialog.pdfScrollSpeed.toFixed(1) + "×"
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.text
                        }
                    }
                    Text {
                        text: "How far the mouse wheel scrolls a page (1× is the usual step)"
                        font.pixelSize: 11
                        color: Theme.textFaint
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
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
            }

            // ---- backups ----
            SettingsSection {
                title: "Backups"
                note: "Backups are saved in the .backups folder of the open workspace."
                Layout.fillWidth: true

                SettingsRow {
                    label: "Back up when the app closes"
                    hint: "A new backup every time you quit"
                    AppCheckBox {
                        checked: dialog.backupOnClose
                        onToggled: dialog.backupOnCloseToggled(checked)
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }
                SettingsRow {
                    label: "Backups to keep"
                    hint: dialog.backupKeep === 0 ? "Unlimited: none are ever removed"
                                                  : "When there are more, the oldest is removed"
                    NumberField {
                        value: dialog.backupKeep
                        from: 0
                        to: 999
                        onValueModified: (value) => dialog.backupKeepPicked(value)
                    }
                }
                Rectangle { visible: dialog.showExport; Layout.fillWidth: true; height: 1; color: Theme.hairline }
                SettingsRow {
                    visible: dialog.showExport
                    label: "Manual backup"
                    hint: "Save a backup right now"
                    AppButton {
                        text: "Back up now"
                        filled: true
                        onClicked: dialog.exportClicked()
                    }
                }
            }

            // ---- help ----
            SettingsSection {
                title: "Help"
                Layout.fillWidth: true

                SettingsRow {
                    label: "Formula symbols"
                    hint: "The symbols you can use between $...$ (mathtext)"
                    Text {
                        id: mathHelp
                        text: "Open reference"
                        font.pixelSize: 13
                        color: Theme.accent
                        font.underline: mathHelpHover.hovered

                        HoverHandler {
                            id: mathHelpHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: Qt.openUrlExternally("https://matplotlib.org/stable/users/explain/text/mathtext.html")
                        }
                    }
                }
            }
        }
    }
}
