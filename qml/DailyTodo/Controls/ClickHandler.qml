import QtQuick

// A click on this item, and on nothing under it. Use it instead of a plain TapHandler for anything
// that is clicked (a row, a card, a swatch; also right-clicks for a context menu).
//
// Why: a plain TapHandler only watches a press (a "passive grab") and lets it go on to whatever
// lies underneath, even through a popup; so clicking a row of the tag filter also clicked the
// resource card behind it. This one takes the press for itself (ReleaseWithinBounds: the click
// counts when the button is let go over the item), like a Button does. A Flickable underneath can
// still take the press over once it turns into a drag, so lists keep scrolling.
//
// Deliberately passive handlers stay plain TapHandlers: FocusClearTapHandler (it must see every
// click), and the PDF page's own selection and autoscroll handlers.
TapHandler {
    gesturePolicy: TapHandler.ReleaseWithinBounds
}
