import QtQuick
import DailyTodo.Style

// The highlighted passage a note or question is about: a short italic quote behind a yellow bar,
// the colour of the highlight itself. Set the width; the height follows the text.
Item {
    id: quote

    property alias text: label.rawText
    property color barColor: Theme.highlight       // the highlight's colour

    implicitHeight: label.implicitHeight
    height: label.implicitHeight

    Rectangle {
        width: 3
        height: parent.height
        radius: 1.5
        color: quote.barColor
    }
    Text {
        id: label
        property string rawText
        x: 9
        width: parent.width - 9
        text: "“" + rawText.replace(/\s+/g, " ") + "”"
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.pixelSize: 12
        font.italic: true
        color: Theme.textMuted
    }
}
