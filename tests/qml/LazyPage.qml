import QtQuick
import DailyTodo.Views

// A LazyPage that unloads quickly, for test_lazy_page.py.
Item {
    property QtObject page: lazy
    LazyPage {
        id: lazy
        unloadAfter: 150
        sourceComponent: Item {}
    }
}
