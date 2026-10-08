import QtQuick

// Put this at the back of anything that floats over other content as a plain item (not a Popup):
// the note box, the "add a todo" box, a toolbar over the PDF. It takes the presses and the hover
// that reach its empty parts, so they don't fall through to the cards or rows underneath (which
// would light up, or open). The wheel still goes through: scrolling over a floating box scrolls
// what is under it. Popups don't need it: they already stop presses and hover on their empty parts.
// Clickable things inside the box need ClickHandler (or to be a Control), see ClickHandler.qml.
MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    preventStealing: false
}
