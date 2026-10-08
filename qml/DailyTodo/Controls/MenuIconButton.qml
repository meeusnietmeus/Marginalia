import QtQuick
import QtQuick.Layouts
import DailyTodo.Style

// An icon button for the top row of a CrudMenu. Muted at rest; on hover the icon takes `tint` and
// a soft wash appears. Clicking it closes the menu, then `triggered` fires. The tooltip is `text`.
RowActionButton {
    id: button

    // `text` (the button's own property) is not drawn by an icon button: it is the tooltip.
    signal triggered()

    // The CrudMenu this button sits in (found through the top row it lives in).
    function owner() {
        let p = parent
        while (p) {
            if (p.crudMenu !== undefined) return p.crudMenu
            p = p.parent
        }
        return null
    }

    Layout.fillWidth: true
    Layout.preferredHeight: 32
    onClicked: {
        const menu = owner()
        if (menu) menu.close()
        triggered()
    }

    AppToolTip {
        text: button.text
        shown: button.hovered && button.text !== ""
    }
}
