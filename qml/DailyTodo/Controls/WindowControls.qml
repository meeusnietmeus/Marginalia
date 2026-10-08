import QtQuick
import DailyTodo.Style

// Minimize, maximize / restore and close, in the style of Windows' own caption buttons (the same
// icon font), for a window that has no title bar of its own.
//
// The maximize button is not clicked here: Windows hit-tests that spot as the maximize button (so
// that Windows 11 can show its snap layouts) and so no mouse events come through. The host feeds
// maxHovered / maxPressed in, and toggles the window itself when it is released.
Row {
    id: controls

    property bool maximized: false
    property bool maxHovered: false
    property bool maxPressed: false
    readonly property Item maximizeButton: maxButton
    // Windows 11 has Segoe Fluent Icons, Windows 10 Segoe MDL2 Assets: same glyphs
    readonly property string iconFont: Qt.fontFamilies().indexOf("Segoe Fluent Icons") >= 0
                                       ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

    signal minimizeClicked()
    signal closeClicked()

    component CaptionButton: Rectangle {
        id: button

        property string glyph
        property bool hovered: false
        property bool pressed: false
        property color hoverColor: Qt.alpha(Theme.text, 0.10)
        property color pressedColor: Qt.alpha(Theme.text, 0.17)
        property color hoverGlyph: Theme.text
        readonly property bool interactive: true      // not part of the movable title bar

        width: 46
        height: controls.height
        color: pressed ? pressedColor : hovered ? hoverColor : "transparent"

        Text {
            anchors.centerIn: parent
            text: button.glyph
            font.family: controls.iconFont
            font.pixelSize: 10
            color: button.hovered || button.pressed ? button.hoverGlyph : Theme.text
            renderType: Text.NativeRendering
        }
    }

    CaptionButton {
        glyph: ""                                   // ChromeMinimize
        hovered: minimizeHover.hovered
        pressed: minimizeTap.pressed
        HoverHandler { id: minimizeHover }
        ClickHandler { id: minimizeTap; onTapped: controls.minimizeClicked() }
    }
    CaptionButton {
        id: maxButton
        glyph: controls.maximized ? "" : ""   // ChromeRestore / ChromeMaximize
        hovered: controls.maxHovered
        pressed: controls.maxPressed
    }
    CaptionButton {
        glyph: ""                                   // ChromeClose
        hovered: closeHover.hovered
        pressed: closeTap.pressed
        hoverColor: "#c42b1c"
        pressedColor: "#b32a1b"
        hoverGlyph: "white"
        HoverHandler { id: closeHover }
        ClickHandler { id: closeTap; onTapped: controls.closeClicked() }
    }
}
