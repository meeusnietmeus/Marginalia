import QtQuick
import DailyTodo.Style

// A calm backdrop for the Overview: a few very large, very soft glows of colour (warm amber behind
// the top left, a hint of green towards the bottom right, a faint ember near the top), and a set of
// hairline arcs sweeping in from the bottom-right corner, like the edge of a dial. Painted once, and
// again when the size changes.
Canvas {
    id: backdrop

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function glow(ctx, x, y, r, colour) {
        const g = ctx.createRadialGradient(x, y, 0, x, y, r)
        g.addColorStop(0, colour)
        g.addColorStop(1, Qt.alpha(colour, 0))
        ctx.fillStyle = g
        ctx.fillRect(0, 0, width, height)
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const big = Math.max(width, height)

        // the glows
        glow(ctx, width * 0.18, height * 0.12, big * 0.55, Qt.alpha(Theme.ambientWarm, 0.10))
        glow(ctx, width * 0.86, height * 0.95, big * 0.6, Qt.alpha(Theme.ambientCool, 0.07))
        glow(ctx, width * 0.55, -height * 0.05, big * 0.35, Qt.alpha(Theme.now, 0.035))

        // the arcs, centred beyond the bottom-right corner; every third one a little stronger
        const cx = width * 1.02
        const cy = height * 1.08
        ctx.lineWidth = 1
        for (let i = 1; i <= 14; i++) {
            const r = i * Theme.ambientRingSpacing
            ctx.strokeStyle = i % 3 === 0 ? Theme.ambientRingStrong : Theme.ambientRing
            ctx.beginPath()
            ctx.arc(cx, cy, r, Math.PI, Math.PI * 1.5)
            ctx.stroke()
        }
        // short ticks along the outermost strong arc, like the scale on a dial
        const rt = 12 * Theme.ambientRingSpacing
        ctx.strokeStyle = Theme.ambientRingStrong
        for (let a = 0; a <= 36; a++) {
            const t = Math.PI + a * (Math.PI / 2) / 36
            const inner = rt - (a % 6 === 0 ? 10 : 5)
            ctx.beginPath()
            ctx.moveTo(cx + Math.cos(t) * inner, cy + Math.sin(t) * inner)
            ctx.lineTo(cx + Math.cos(t) * rt, cy + Math.sin(t) * rt)
            ctx.stroke()
        }
    }
}
