"""Writing an exported text file without ever overwriting another one."""
from __future__ import annotations

from pathlib import Path


def write_text_unique(folder: Path, file_name: str, text: str) -> Path:
    """Save ``text`` as ``folder/file_name``; if that exists, as "name (2).ext", "name (3).ext"...
    Returns the path written. Raises OSError on failure."""
    folder.mkdir(parents=True, exist_ok=True)
    base = Path(file_name)
    dest = folder / base.name
    n = 2
    while dest.exists():
        dest = folder / f"{base.stem} ({n}){base.suffix}"
        n += 1
    dest.write_text(text, encoding="utf-8", newline="\n")
    return dest
