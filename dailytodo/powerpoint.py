"""Making a PDF of a presentation with PowerPoint itself (so it looks exactly like in PowerPoint).

PowerPoint is driven through COM by a small PowerShell script (powerpoint_export.ps1): nothing to
install for Python, but it needs Windows with PowerPoint. Everything that can go wrong comes back
as an error message instead of an exception.
"""
from __future__ import annotations

import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

SCRIPT = Path(__file__).with_name("powerpoint_export.ps1")
TIMEOUT_SECONDS = 300  # a big deck with many pictures takes a while

Runner = Callable[..., "subprocess.CompletedProcess[str]"]


@dataclass(frozen=True, slots=True)
class ExportResult:
    error: str = ""

    @property
    def ok(self) -> bool:
        return not self.error


def _explain(stderr: str) -> str:
    text = " ".join(stderr.split())
    if "80040154" in text or "Class not registered" in text or "Retrieving the COM class" in text:
        return "PowerPoint doesn't seem to be installed"
    return text or "PowerPoint didn't produce a PDF"


def export_pdf(source: Path, target: Path, run: Runner = subprocess.run) -> ExportResult:
    """Export ``source`` to ``target`` (a .pdf). The PDF appears all at once: it is written beside
    the target first, so a failed or interrupted export never leaves half a file behind."""
    return _save_copy(source, target, "pdf", run)


def convert_to_pptx(source: Path, target: Path, run: Runner = subprocess.run) -> ExportResult:
    """Save a copy of a presentation as .pptx (an old .ppt keeps its notes and comments in a binary
    format that only PowerPoint reads; a .pptx is XML that we can read ourselves)."""
    return _save_copy(source, target, "pptx", run)


def _save_copy(source: Path, target: Path, fmt: str, run: Runner) -> ExportResult:
    if sys.platform != "win32":
        return ExportResult("exporting presentations needs Windows with PowerPoint")
    if not source.is_file():
        return ExportResult("the presentation file is not there")
    partial = target.with_name(f"{target.stem}.exporting{target.suffix}")
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        partial.unlink(missing_ok=True)
        done = run(
            [
                "powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-File", str(SCRIPT), "-Source", str(source), "-Target", str(partial),
                "-Format", fmt,
            ],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except subprocess.TimeoutExpired:
        partial.unlink(missing_ok=True)
        return ExportResult("PowerPoint took too long")
    except OSError as exc:
        return ExportResult(f"couldn't start PowerShell: {exc}")
    if done.returncode != 0 or not partial.is_file() or partial.stat().st_size == 0:
        partial.unlink(missing_ok=True)
        return ExportResult(_explain(done.stderr or ""))
    return _put_in_place(partial, target)


def _put_in_place(partial: Path, target: Path, tries: int = 20, pause: float = 0.5) -> ExportResult:
    """Replace the old PDF. Windows refuses while the old one is still open somewhere (a viewer
    tab that is just being closed), so this tries again for a few seconds."""
    error: OSError | None = None
    for _ in range(tries):
        try:
            os.replace(partial, target)
            return ExportResult()
        except OSError as exc:
            error = exc
            time.sleep(pause)
    partial.unlink(missing_ok=True)
    return ExportResult(f"couldn't save the PDF, it is in use: {error}")
