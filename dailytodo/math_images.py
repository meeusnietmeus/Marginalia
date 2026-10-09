"""Pictures of `$formulas$`: drawn once with matplotlib's mathtext (a LaTeX subset, no TeX install
needed) into a cache folder and reused afterwards."""
from __future__ import annotations

import hashlib
import struct
from pathlib import Path

SCALE = 2  # drawn at twice the size it is shown at, so it stays sharp on a high-DPI screen
_PNG_HEADER = 8 + 8  # signature + the IHDR chunk's length and name; width and height follow


def _hex_colour(colour: str) -> str:
    """QML writes colours as #rrggbb or #aarrggbb; matplotlib wants #rrggbbaa."""
    if len(colour) == 9 and colour.startswith("#"):
        return "#" + colour[3:] + colour[1:3]
    return colour or "#000000"


def render_formula(latex: str, colour: str, pixel_size: float, folder: Path) -> dict | None:
    """{"path", "width", "height"} (logical pixels) of the formula, or None when it can't be
    drawn: matplotlib isn't installed or the formula isn't valid."""
    key = hashlib.sha1(f"v2|{latex}|{colour}|{pixel_size}".encode()).hexdigest()[:20]
    path = folder / f"{key}.png"
    if not path.is_file():
        try:
            from matplotlib.figure import Figure

            folder.mkdir(parents=True, exist_ok=True)
            figure = Figure(dpi=96 * SCALE)
            figure.text(0, 0, f"${latex}$", fontsize=pixel_size * 0.75,  # points at 96 dpi
                        color=_hex_colour(colour))
            # math_to_image would paint a white background, which hides light text
            figure.savefig(str(path), format="png", transparent=True, bbox_inches="tight", pad_inches=0.02)
        except Exception:  # not installed, or not a formula mathtext understands
            path.unlink(missing_ok=True)
            return None
    try:
        with path.open("rb") as handle:
            head = handle.read(_PNG_HEADER + 8)
        width, height = struct.unpack(">II", head[_PNG_HEADER:])
    except (OSError, struct.error):
        return None
    return {"path": str(path), "width": width / SCALE, "height": height / SCALE}
