r"""Draws the Marginalia icon and writes marginalia.ico (and tools/marginalia-preview.png).

    .venv\Scripts\python.exe tools\make_icon.py

The icon is a page of text with a note in its margin: a green highlighted line and a yellow
question mark, on the app's dark brown. Everything is drawn once at 1024 px and scaled down for
every size in the .ico, so small sizes stay clean.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from PySide6.QtCore import QBuffer, QByteArray, QIODevice, QPointF, QRectF, Qt
from PySide6.QtGui import (
    QBrush, QColor, QFont, QGuiApplication, QImage, QLinearGradient, QPainter, QPainterPath, QPen,
)

ROOT = Path(__file__).resolve().parent.parent
SIZES = (16, 24, 32, 48, 64, 128, 256)

# the app's palette (qml/dailytodo/Style/Theme.qml)
BARK_TOP = QColor("#3d2f23")
BARK_BOTTOM = QColor("#211812")
PAPER = QColor("#f1ece4")
PAPER_FOLD = QColor("#d9d0c3")
INK = QColor("#4a3a2c")
GREEN = QColor("#4f9d5d")
GREEN_LIGHT = QColor("#5fb06d")
YELLOW = QColor("#f5cf7a")


def draw(size: int = 1024) -> QImage:
    image = QImage(size, size, QImage.Format.Format_ARGB32_Premultiplied)
    image.fill(Qt.GlobalColor.transparent)
    p = QPainter(image)
    p.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.TextAntialiasing)
    p.scale(size / 1024, size / 1024)
    p.setPen(Qt.PenStyle.NoPen)

    # rounded tile with a gentle top-to-bottom gradient
    tile = QLinearGradient(0, 0, 0, 1024)
    tile.setColorAt(0, BARK_TOP)
    tile.setColorAt(1, BARK_BOTTOM)
    p.setBrush(QBrush(tile))
    p.drawRoundedRect(QRectF(24, 24, 976, 976), 220, 220)

    # the page, with a folded corner
    page = QPainterPath()
    left, top, right, bottom, fold = 236, 150, 700, 874, 150
    page.moveTo(left + 48, top)
    page.lineTo(right - fold, top)
    page.lineTo(right, top + fold)
    page.lineTo(right, bottom - 48)
    page.quadTo(right, bottom, right - 48, bottom)
    page.lineTo(left + 48, bottom)
    page.quadTo(left, bottom, left, bottom - 48)
    page.lineTo(left, top + 48)
    page.quadTo(left, top, left + 48, top)
    p.setBrush(PAPER)
    p.drawPath(page)
    corner = QPainterPath()
    corner.moveTo(right - fold, top)
    corner.lineTo(right - fold, top + fold - 30)
    corner.quadTo(right - fold, top + fold, right - fold + 30, top + fold)
    corner.lineTo(right, top + fold)
    corner.closeSubpath()
    p.setBrush(PAPER_FOLD)
    p.drawPath(corner)

    # a highlighted line (the one the note is about), then the lines of text over it
    p.setBrush(GREEN_LIGHT)
    p.drawRoundedRect(QRectF(left + 46, 502, 392, 82), 30, 30)
    p.setBrush(INK)
    for y, width in ((338, 330), (430, 270), (522, 330), (614, 220), (706, 300)):
        p.drawRoundedRect(QRectF(left + 70, y, width, 42), 21, 21)
    # margin note: the highlight runs out of the page edge towards the badge...
    p.setBrush(GREEN_LIGHT)
    p.drawRoundedRect(QRectF(left + 46 + 360, 520, 230, 46), 23, 23)

    # ...ending in a yellow "?" badge
    badge = QPointF(790, 553)
    ring = QLinearGradient(0, 400, 0, 700)
    ring.setColorAt(0, YELLOW.lighter(112))
    ring.setColorAt(1, YELLOW.darker(108))
    p.setBrush(QBrush(ring))
    p.drawEllipse(badge, 150, 150)
    font = QFont("Segoe UI", 1)
    font.setBold(True)
    font.setPixelSize(250)
    p.setFont(font)
    p.setPen(QPen(BARK_BOTTOM))
    p.drawText(QRectF(badge.x() - 150, badge.y() - 150 - 8, 300, 300), Qt.AlignmentFlag.AlignCenter, "?")
    p.end()
    return image


def png_bytes(image: QImage) -> bytes:
    data = QByteArray()
    buffer = QBuffer(data)
    buffer.open(QIODevice.OpenModeFlag.WriteOnly)
    image.save(buffer, "PNG")
    return bytes(data)


def write_ico(path: Path, images: list[QImage]) -> None:
    """An .ico holding one PNG per size (supported since Windows Vista)."""
    payloads = [png_bytes(image) for image in images]
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = b""
    for image, payload in zip(images, payloads):
        side = image.width()
        entries += struct.pack(
            "<BBBBHHII", side % 256, side % 256, 0, 0, 1, 32, len(payload), offset
        )
        offset += len(payload)
    path.write_bytes(header + entries + b"".join(payloads))


def main() -> None:
    app = QGuiApplication(sys.argv)  # needed for fonts
    master = draw(1024)
    images = [
        master.scaled(s, s, Qt.AspectRatioMode.IgnoreAspectRatio, Qt.TransformationMode.SmoothTransformation)
        for s in SIZES
    ]
    write_ico(ROOT / "marginalia.ico", images)
    master.scaled(512, 512, Qt.AspectRatioMode.IgnoreAspectRatio,
                  Qt.TransformationMode.SmoothTransformation).save(str(ROOT / "tools" / "marginalia-preview.png"))
    print("wrote marginalia.ico with sizes", SIZES)
    app.quit()


if __name__ == "__main__":
    main()
