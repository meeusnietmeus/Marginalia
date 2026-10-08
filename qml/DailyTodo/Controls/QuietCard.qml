import QtQuick
import DailyTodo.Style

// A quiet card for one entry of a list (a backlog todo, a note): a faint top-to-bottom gradient
// and a hairline edge that brightens while `lit` (hovered, being edited). No shadow: lists of
// these stay calm; Surface is for things that should stand off the page.
Rectangle {
    property bool lit: false

    radius: 12
    gradient: Gradient {
        GradientStop { position: 0; color: Theme.panelRaised }
        GradientStop { position: 1; color: Theme.panel }
    }
    border.color: lit ? Theme.hairlineStrong : Theme.hairline
}
