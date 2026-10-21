import QtQuick

// Click outside a text field = unfocus it.
// Put one in every area that may swallow taps (window, toolbar, a ListView, ...).
// Only reacts to taps, not drags, so scrolling is unaffected.
TapHandler {
    id: handler

    // The window whose focus is managed. From inside an Item, bind it to `Window.window`.
    property var hostWindow: null

    // What had the keyboard when the press began. A field that only got it during this very tap
    // (opened by a menu entry, a button...) must keep it: the tap was never aimed at "elsewhere".
    property var focusAtPress: null

    onPressedChanged: {
        if (pressed)
            focusAtPress = handler.hostWindow ? handler.hostWindow.activeFocusItem : null
    }

    onTapped: (eventPoint, button) => {
        const win = handler.hostWindow
        const item = win ? win.activeFocusItem : null
        if (item !== handler.focusAtPress)
            return                                   // focus moved while tapping: leave it be
        if (!item || typeof item.selectAll !== "function")
            return                                   // nothing text-like is focused
        const pos = eventPoint.scenePosition
        if (!item.contains(item.mapFromItem(null, pos.x, pos.y)))
            win.contentItem.forceActiveFocus()
    }
}
