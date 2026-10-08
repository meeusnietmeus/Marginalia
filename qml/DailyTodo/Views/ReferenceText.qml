import QtQuick
import QtQuick.Shapes
import DailyTodo.Style

// Todo text as stored (with `@{id|name}` / `!{id|name}`), rendered with its references:
//   * a resource is normal-coloured text with a dotted underline (click to open it, like a card
//     in the library)
//   * a tag is normal-coloured text on a slightly lighter background, like a chip (click to see
//     it in the Knowledge graph)
//   * a reference to something that was deleted stays as dim, struck-through text
// A web address, written bare or as [name](address), is a link too (accent coloured).
// A read-only TextEdit rather than a Text, because it can tell where each character is drawn
// (positionToRectangle). Qt Quick cannot draw a dotted underline, so the links' own underline is
// switched off (controller.styleLinks) and dotted lines are drawn under them instead.
TextEdit {
    id: label

    property var controller
    property string source                    // the stored text
    property color baseColor: Theme.text
    readonly property color linkColor: Theme.accent      // web links; resources keep the text colour

    readonly property var pieces: controller
        ? controller.segments(source, controller.referencesRevision)
        : [{ type: "text", text: source, id: -1, missing: false }]

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                .replace(/\n/g, "<br>")
    }

    function html() {
        let out = ""
        for (const p of pieces) {
            if (p.type === "link")
                out += "<a href=\"link:" + p.url.replace(/&/g, "&amp;").replace(/"/g, "%22") + "\"><span style=\"color:"
                     + linkColor + ";\">" + esc(p.text) + "</span></a>"
            else if (p.type === "resource" && !p.missing)
                // the colour goes on a span inside the link: rich text would make a link blue
                out += "<a href=\"resource:" + p.id + "\"><span style=\"color:" + baseColor + ";\">"
                     + esc(p.text) + "</span></a>"
            else if (p.type === "tag" && !p.missing)
                out += "<a href=\"tag:" + p.id + "\"><span style=\"background-color:" + Theme.hover
                     + ";color:" + baseColor + ";\">&nbsp;" + esc(p.text) + "&nbsp;</span></a>"
            else if (p.missing)
                out += "<span style=\"color:" + Theme.textFaint + ";\"><s>" + esc(p.text) + "</s></span>"
            else
                out += esc(p.text)
        }
        return out
    }

    // ---- dotted underlines ------------------------------------------------------------------
    property var underlines: []               // [{x1, x2, y}], one per line a resource name is on

    FontMetrics { id: metrics; font: label.font }

    // Where every resource name sits right now. Character offsets are known from the pieces: a
    // piece is as long as its text, a tag chip has a no-break space on each side.
    function computeUnderlines() {
        const out = []
        let pos = 0
        for (const p of pieces) {
            const len = p.text.length + (p.type === "tag" && !p.missing ? 2 : 0)
            if ((p.type === "resource" || p.type === "link") && !p.missing && len > 0) {
                const colour = p.type === "link" ? linkColor : baseColor
                let from = pos
                let lineY = positionToRectangle(pos).y
                for (let i = pos + 1; i <= pos + len; i++) {
                    const next = i < pos + len ? positionToRectangle(i) : null
                    if (next === null || next.y !== lineY) {          // the line ends before i
                        const first = positionToRectangle(from)
                        const last = positionToRectangle(i - 1)
                        const ch = p.text.charAt(i - 1 - pos)
                        out.push({ x1: first.x, x2: last.x + metrics.advanceWidth(ch),
                                   y: first.y + first.height - 1, colour: colour })
                        from = i
                        if (next !== null) lineY = next.y
                    }
                }
            }
            pos += len
        }
        underlines = out
    }

    // restyling edits the document, which reports a change again: ignore that echo
    property bool styling: false
    function restyle() {
        if (controller) {
            styling = true
            controller.styleLinks(textDocument)
            styling = false
        }
        computeUnderlines()
    }
    onTextChanged: if (!styling) restyleLater.restart()
    onWidthChanged: underlinesLater.restart()               // wrapping changed
    onContentHeightChanged: underlinesLater.restart()
    // "Later" as timers, not Qt.callLater: a list that is rebuilt destroys its texts before a
    // queued call runs, and a timer goes with its text.
    Timer { id: restyleLater; interval: 0; onTriggered: label.restyle() }
    Timer { id: underlinesLater; interval: 0; onTriggered: label.computeUnderlines() }

    Repeater {
        model: label.underlines
        Shape {
            required property var modelData
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.alpha(modelData.colour, 0.85)
                strokeWidth: 1
                strokeStyle: ShapePath.DashLine
                dashPattern: [1, 2]                          // 1px dot, 2px gap
                capStyle: ShapePath.FlatCap
                fillColor: "transparent"
                startX: modelData.x1
                startY: modelData.y + 0.5
                PathLine { x: modelData.x2; y: modelData.y + 0.5 }
            }
        }
    }
    text: html()
    textFormat: TextEdit.RichText
    wrapMode: TextEdit.Wrap
    readOnly: true
    activeFocusOnPress: false
    selectByMouse: false
    color: baseColor

    // A resource opens like its card in the library, a tag in the Knowledge graph, a web address
    // in the browser.
    onLinkActivated: (link) => {
        if (controller)
            controller.openLink(link.indexOf("link:") === 0 ? link.substring(5) : link)
    }
    HoverHandler {
        cursorShape: label.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}