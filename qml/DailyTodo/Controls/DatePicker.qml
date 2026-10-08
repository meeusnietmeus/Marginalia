import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import DailyTodo.Style

// Modal month calendar. Call ask(payload, minIso, maxIso); picked(payload, "yyyy-MM-dd") fires
// when a day is chosen. Days outside [min, max] are dimmed and cannot be picked, and the month
// arrows stop at the first and last month that has a pickable day.
AppDialog {
    id: picker

    property var payload: null
    property date minDate: new Date()
    property date maxDate: new Date()
    property int shownYear: minDate.getFullYear()
    property int shownMonth: minDate.getMonth()
    property string title: "Pick a day"

    signal picked(var payload, string iso)

    function parse(iso) {
        const p = iso.split("-")
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    }
    function isoOf(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function inRange(d) {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        return t >= minDate.getTime() && t <= maxDate.getTime()
    }
    function choose(d) {
        const item = payload
        close()
        picked(item, isoOf(d))
    }
    function ask(item, minIso, maxIso) {
        payload = item
        minDate = parse(minIso)
        maxDate = parse(maxIso)
        shownYear = minDate.getFullYear()
        shownMonth = minDate.getMonth()
        open()
    }
    function step(delta) {
        const d = new Date(shownYear, shownMonth + delta, 1)
        shownYear = d.getFullYear()
        shownMonth = d.getMonth()
    }

    // weeks start on Monday, like the timeline (en_GB has Monday as first day of the week)
    readonly property var weekLocale: Qt.locale("en_GB")

    readonly property int shownIndex: shownYear * 12 + shownMonth
    readonly property bool canGoBack: shownIndex > minDate.getFullYear() * 12 + minDate.getMonth()
    readonly property bool canGoForward: shownIndex < maxDate.getFullYear() * 12 + maxDate.getMonth()

    padding: 16

    contentItem: ColumnLayout {
        spacing: 10

        DialogTitle {
            text: picker.title
            font.pixelSize: 20
        }

        RowLayout {
            spacing: 4
            AppButton {
                compact: true
                text: "‹"
                font.pixelSize: 16
                enabled: picker.canGoBack
                onClicked: picker.step(-1)
            }
            Label {
                text: picker.weekLocale.monthName(picker.shownMonth) + " " + picker.shownYear
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                color: Theme.text
                Layout.fillWidth: true
            }
            AppButton {
                compact: true
                text: "›"
                font.pixelSize: 16
                enabled: picker.canGoForward
                onClicked: picker.step(1)
            }
        }

        DayOfWeekRow {
            locale: grid.locale
            Layout.fillWidth: true
            delegate: Text {
                required property var model
                text: model.shortName
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 11
                color: Theme.textMuted
            }
        }

        MonthGrid {
            id: grid
            month: picker.shownMonth
            year: picker.shownYear
            locale: picker.weekLocale
            Layout.fillWidth: true

            delegate: Rectangle {
                id: cell
                required property var model
                readonly property bool inMonth: model.month === grid.month
                readonly property bool allowed: inMonth && picker.inRange(model.date)

                implicitWidth: 36
                implicitHeight: 32
                radius: Theme.controlRadius
                color: allowed && hover.hovered ? Theme.hover : "transparent"
                border.color: inMonth && model.today ? Theme.accent : "transparent"

                Text {
                    anchors.centerIn: parent
                    visible: cell.inMonth
                    text: cell.model.day
                    font.pixelSize: 13
                    color: cell.allowed ? Theme.text : Theme.textFaint
                    opacity: cell.allowed ? 1 : 0.5
                }
                HoverHandler { id: hover; cursorShape: cell.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor }
                ClickHandler {
                    enabled: cell.allowed
                    onTapped: picker.choose(cell.model.date)
                }
            }
        }

        RowLayout {
            spacing: 8
            AppButton {
                compact: true
                text: "Today"
                visible: picker.inRange(new Date())
                onClicked: picker.choose(new Date())
            }
            Item { Layout.fillWidth: true }
            AppButton {
                compact: true
                text: "Cancel"
                onClicked: picker.close()
            }
        }
    }
}
