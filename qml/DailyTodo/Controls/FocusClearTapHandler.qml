import QtQuick

// Click outside a text field = unfocus it.
// Put one in every area that may swallow taps (window, toolbar, a ListView, ...).
// Only reacts to taps, not drags, so scrolling is unaffected.
TapHandler {
    id: handler

    // The window whose focus is managed. From inside an Item, bind it to `Window.window`.
    property var hostWindow: null

    onTapped: (eventPoint, button) => {
        const win = handler.hostWindow
        const item = win ? win.activeFocusItem : null
        if (!item || typeof item.selectAll !== "function")
            return                                   // nothing text-like is focused
        const pos = eventPoint.scenePosition
        if (!item.contains(item.mapFromItem(null, pos.x, pos.y)))
            win.contentItem.forceActiveFocus()
    }
}
