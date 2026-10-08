pragma Singleton
import QtQuick

// Single source of truth for the look of the app.
// Change a value here and it changes everywhere.
QtObject {
    // ---- surfaces ----
    readonly property color window: "#2b2118"          // app background (dark bark brown)
    readonly property color toolbar: "#33261c"
    readonly property color border: "#4a3a2c"
    readonly property color card: "#3a2d22"            // future days
    readonly property color cardToday: "#2f4a36"       // today (dark green tint)
    readonly property color cardPast: "#241b14"        // missed / past days (faded)
    readonly property color cardPastBorder: "#33271d"
    readonly property color menu: "#3a2d22"
    readonly property color menuBorder: "#5a4838"
    readonly property color toast: "#15100b"

    // ---- floating "add todo" box: brownish frosted glass ----
    readonly property color glassTint: Qt.rgba(0.30, 0.20, 0.12, 0.62)    // brown wash over the blurred backdrop
    readonly property color glassBorder: Qt.rgba(1.0, 0.90, 0.78, 0.16)   // faint light rim
    readonly property real glassBlur: 1                                  // 0..1 (blur strength)

    // ---- text ----
    readonly property color text: "#f1ece4"
    readonly property color textMuted: "#a89b8a"
    readonly property color textFaint: "#8f8272"
    readonly property color textDone: "#7d7263"
    readonly property color warning: "#f5cf7a"         // "Missed · ..." label, "move to today" hover
    // PDF text: a permanent highlight (yellow marker) and the transient selection (blue)
    readonly property color highlight: "#ffdd33"
    // The colours a highlight can be given (names as stored in the database; "none" is transparent)
    readonly property var highlightKeys: ["yellow", "green", "blue", "pink", "orange", "purple", "none"]
    function highlightColor(key) {
        switch (key) {
        case "green": return "#6fd36f"
        case "blue": return "#5cb8ff"
        case "pink": return "#ff7eb6"
        case "orange": return "#ff9f43"
        case "purple": return "#b48cff"
        case "none": return "transparent"
        default: return highlight
        }
    }
    // The coloured bar in front of a quote; a transparent highlight gets a quiet grey one.
    function highlightBar(key) { return key === "none" ? textFaint : highlightColor(key) }
    readonly property color selection: "#4d99ff"

    // ---- knowledge graph: one colour per area (cycles when there are more areas) ----
    readonly property var areaColors: ["#e0826a", "#e0b152", "#8cc063", "#4fb3a9", "#5fa8d9",
                                       "#9a8fe0", "#c07bd0", "#e07ba5", "#b59a6a", "#7fc7c7"]
    function areaColor(index) { return index < 0 ? textFaint : areaColors[index % areaColors.length] }
    readonly property color info: "#6fb0e8"            // answers
    readonly property color danger: "#f29b9b"          // pastel red: delete hover

    // ---- accent (forest green) ----
    readonly property color accent: "#4f9d5d"
    readonly property color accentHover: "#5fb06d"
    readonly property color accentPressed: "#3f7a4d"
    readonly property color accentText: "#ffffff"
    readonly property color todayBadge: "#3f7a4d"      // pill behind "Today"
    readonly property color todayBadgeText: "#e3f5e7"

    // ---- controls ----
    readonly property color input: "#241b14"           // text field background
    readonly property color inputFocus: "#1d1610"
    readonly property color hover: "#4a3a2c"
    readonly property color pressed: "#5a4838"
    readonly property color checkBorder: "#8a7660"
    readonly property color separator: "#5a4838"       // week divider lines

    // ---- shape ----
    // Corner radius of every control (buttons, text fields, checkboxes, menu items).
    // A huge value = fully rounded (Qt clamps it to half the item's height).
    // Set it to e.g. 6 to get softly rounded corners everywhere instead.
    readonly property real controlRadius: 6
    readonly property real cardRadius: 12

    // ---- instrument look (Overview): hairlines, rings, tick marks, serif titles ----
    readonly property string serifFont: "Georgia"
    readonly property color hairline: Qt.rgba(1.0, 0.92, 0.82, 0.08)       // card borders, rules
    readonly property color hairlineStrong: Qt.rgba(1.0, 0.92, 0.82, 0.18) // ... when hovered
    readonly property color panel: "#2f241b"           // a card on the canvas
    readonly property color panelRaised: "#382b20"     // its lighter top edge
    readonly property color canvasDot: Qt.rgba(1.0, 0.92, 0.82, 0.07)      // the dot grid
    readonly property real canvasDotSpacing: 22
    // The Overview's background: "ambient" (soft glows of colour and a few dial arcs from the
    // bottom-right corner) or "dots" (the dot grid above).
    readonly property string backdrop: "ambient"
    readonly property color ambientWarm: "#e0a35a"
    readonly property color ambientCool: "#62c37a"
    readonly property color ambientRing: Qt.rgba(1.0, 0.92, 0.82, 0.035)
    readonly property color ambientRingStrong: Qt.rgba(1.0, 0.92, 0.82, 0.07)
    readonly property real ambientRingSpacing: 64
    readonly property color now: "#ff5a4a"             // "now": today's node
    readonly property color ringTrack: Qt.rgba(1.0, 0.92, 0.82, 0.12)     // the empty part of a ring
    readonly property color ringDone: "#62c37a"        // the done part
    readonly property color ringMissed: Qt.rgba(0.95, 0.61, 0.61, 0.55)   // open todos on a past day
    readonly property real labelSpacing: 1.3           // letter spacing of the small uppercase labels
    // a little depth: raised surfaces catch light on their top edge and cast a soft shadow,
    // fields are sunk into the surface
    readonly property color surfaceHighlight: Qt.rgba(1.0, 0.95, 0.88, 0.10)
    readonly property color shadow: Qt.rgba(0, 0, 0, 0.42)
    readonly property color well: "#1f1812"            // inside an inset field
    readonly property color focusRing: Qt.rgba(0.38, 0.76, 0.48, 0.75)
    readonly property color accentTop: "#5fae6c"       // a raised green button: lighter at the top
    readonly property color accentBottom: "#437f50"

    // ---- day list: git-graph gutter on the left ----
    readonly property real graphX: 30                  // x of the vertical line's centre
    readonly property real graphLineWidth: 2
    readonly property real graphRadius: 14             // radius of the curve where a day branches off
    readonly property color graphColor: separator
    readonly property real graphFadeLength: 160        // how long the line takes to fade out after the last day
    readonly property real contentX: 68                // where day titles / todos start (right of the graph)
    readonly property real todoGap: 14                 // empty strip under every todo = hover/click zone for "add"
    readonly property real arrowSize: 14               // the green "add here" arrow on the graph

    // ---- spacing between days ----
    readonly property int dayPadding: 6                // vertical padding inside each day
    readonly property int daySpacing: 0                // extra gap between two days

    // ---- sizes ----
    readonly property int controlHeight: 32
    readonly property int checkSize: 14
    readonly property int iconSize: 16

    // ---- behaviour ----
    // How long (ms) the pointer must rest on a day's "add todo" row before it fades in.
    readonly property int revealDelay: 50
    // Mouse-wheel / touchpad scroll speed in the todo list, relative to Qt's default (1 = default).
    readonly property real scrollSpeed: 1.0

    // ---- icons (drop your own files into the icons/ folder next to this file) ----
    readonly property url iconAdd: Qt.resolvedUrl("icons/add.svg")
    readonly property url iconPlus: Qt.resolvedUrl("icons/plus.svg")
    readonly property url iconSave: Qt.resolvedUrl("icons/save.svg")
    readonly property url iconCancel: Qt.resolvedUrl("icons/cancel.svg")
    readonly property url iconClockAlert: Qt.resolvedUrl("icons/clock-alert.svg")
    readonly property url iconTrash: Qt.resolvedUrl("icons/trash.svg")
    readonly property url iconCopy: Qt.resolvedUrl("icons/copy.svg")
    readonly property url iconExport: Qt.resolvedUrl("icons/download.svg")
    readonly property url iconDocument: Qt.resolvedUrl("icons/file-text.svg")
    readonly property url iconEdit: Qt.resolvedUrl("icons/pencil.svg")
    readonly property url iconCalendar: Qt.resolvedUrl("icons/calendar.svg")
    readonly property url iconInbox: Qt.resolvedUrl("icons/inbox.svg")
    readonly property url iconMoveToToday: Qt.resolvedUrl("icons/calendar-chevrons-right.svg")
    readonly property url iconChevronsUpDown: Qt.resolvedUrl("icons/chevrons-up-down.svg")
    readonly property url iconSettings: Qt.resolvedUrl("icons/settings.svg")
    readonly property url iconClose: Qt.resolvedUrl("icons/x.svg")
    readonly property url iconChevronUp: Qt.resolvedUrl("icons/chevron-up.svg")
    readonly property url iconChevronDown: Qt.resolvedUrl("icons/chevron-down.svg")
    readonly property url iconSearch: Qt.resolvedUrl("icons/search.svg")
    readonly property url iconInfo: Qt.resolvedUrl("icons/info.svg")
    readonly property url iconWarning: Qt.resolvedUrl("icons/triangle-alert.svg")
    readonly property url iconFolder: Qt.resolvedUrl("icons/folder.svg")
    readonly property url iconExternal: Qt.resolvedUrl("icons/external-link.svg")
    readonly property url iconInApp: Qt.resolvedUrl("icons/app-window.svg")
    readonly property url iconMoon: Qt.resolvedUrl("icons/moon.svg")
    readonly property url iconExpand: Qt.resolvedUrl("icons/maximize-2.svg")
    readonly property url iconShrink: Qt.resolvedUrl("icons/minimize-2.svg")
    readonly property url iconSort: Qt.resolvedUrl("icons/arrow-up-down.svg")
    readonly property url iconUndo: Qt.resolvedUrl("icons/undo-2.svg")
    readonly property url iconTag: Qt.resolvedUrl("icons/tag.svg")
    readonly property url iconGrid: Qt.resolvedUrl("icons/layout-grid.svg")
    readonly property url iconPlay: Qt.resolvedUrl("icons/play.svg")
    readonly property url iconFit: Qt.resolvedUrl("icons/fit.svg")
    readonly property url iconZoomIn: Qt.resolvedUrl("icons/zoom-in.svg")
    readonly property url iconZoomOut: Qt.resolvedUrl("icons/zoom-out.svg")
    readonly property url iconLink: Qt.resolvedUrl("icons/link.svg")

    // ---- library resource cards: icon + gradient colour per kind of resource ----
    readonly property color resourcePdf: "#c8504b"
    readonly property color resourceWeb: "#4a9ee0"
    readonly property color resourceWord: "#2f5fb3"
    readonly property color resourceExcel: "#2e8b57"
    readonly property color resourcePowerpoint: "#d9663a"
    readonly property color resourceVideo: "#d4424a"
    readonly property color resourceLink: "#8b6fc9"
    readonly property color resourceFile: "#8a7660"

    function resourceColor(kind) {
        switch (kind) {
        case "pdf": return resourcePdf
        case "web": return resourceWeb
        case "video": return resourceVideo
        case "word": return resourceWord
        case "excel": return resourceExcel
        case "powerpoint": return resourcePowerpoint
        case "link": return resourceLink
        default: return resourceFile
        }
    }

    function resourceIcon(kind) {
        switch (kind) {
        case "pdf":
        case "word": return Qt.resolvedUrl("icons/file-text.svg")
        case "web": return Qt.resolvedUrl("icons/globe.svg")
        case "video": return Qt.resolvedUrl("icons/circle-play.svg")
        case "excel": return Qt.resolvedUrl("icons/file-spreadsheet.svg")
        case "powerpoint": return Qt.resolvedUrl("icons/presentation.svg")
        case "link": return Qt.resolvedUrl("icons/link.svg")
        default: return Qt.resolvedUrl("icons/file.svg")
        }
    }
}
