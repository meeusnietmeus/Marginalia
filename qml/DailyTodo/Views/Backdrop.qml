import QtQuick
import DailyTodo.Style

// The Overview's background, as chosen by Theme.backdrop: "ambient" (soft glows and dial arcs) or
// "dots" (a faint dot grid).
Loader {
    sourceComponent: Theme.backdrop === "dots" ? dots : ambient

    Component { id: dots; DotGrid {} }
    Component { id: ambient; AmbientBackdrop {} }
}
