import QtQuick
import DailyTodo.Style

// The canvas the Overview's panels sit on: a faint grid of dots. Painted once, and again when the
// size changes.
Canvas {
    id: grid

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = Theme.canvasDot
        const step = Theme.canvasDotSpacing
        for (let y = step / 2; y < height; y += step) {
            for (let x = step / 2; x < width; x += step)
                ctx.fillRect(x - 1, y - 1, 2, 2)
        }
    }
}
