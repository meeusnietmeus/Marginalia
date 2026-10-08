from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class AppConfig:
    """Everything that can be configured from the command line.

    Running the app twice with a different ``--db`` and ``--title`` gives two
    independent lists (e.g. "School" and "Home").
    """

    db_path: Path | None = None  # None = the default location in AppData
    title: str = "Marginalia"
    open_link: str = ""  # a marginalia:// link to handle (Windows passes it when one is opened)


def parse_args(argv: list[str]) -> tuple[AppConfig, list[str]]:
    """Returns the app config plus the arguments meant for Qt itself."""
    parser = argparse.ArgumentParser(prog="dailytodo")
    parser.add_argument("--db", type=Path, help="path to the SQLite database file")
    parser.add_argument("--title", default=AppConfig().title, help="window / toolbar title")
    parser.add_argument("--open", default="", metavar="LINK", help="a marginalia:// link to handle")
    args, qt_args = parser.parse_known_args(argv)
    return AppConfig(db_path=args.db, title=args.title, open_link=args.open), qt_args
