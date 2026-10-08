import QtQuick
import DailyTodo.Style

// A small uppercase label with wide letter spacing ("THU · 8 OCT", "NEXT WEEK"): metadata, as
// opposed to content. Give it the text in any case.
Text {
    font.pixelSize: 10
    font.weight: Font.DemiBold
    font.letterSpacing: Theme.labelSpacing
    font.capitalization: Font.AllUppercase
    color: Theme.textMuted
}
