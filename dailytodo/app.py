"""Wires everything together. The only module that knows about all the layers."""
from __future__ import annotations

import ctypes
import sys
from pathlib import Path

from PySide6.QtCore import QMetaObject, QStandardPaths, QTimer, QUrl
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from .config import AppConfig, parse_args
from .instance import SingleInstance, server_name
from .window_chrome import WindowChrome
from .storage import ClientState, ClientStateError, RepositoryError, build_repository
from .ui import TodoController

PROJECT_DIR = Path(__file__).resolve().parent.parent
QML_DIR = PROJECT_DIR / "qml"  # import path for the DailyTodo.* QML modules
APP_ICON = PROJECT_DIR / "marginalia.ico"
# Internal id, not the visible name (that is "Marginalia", see config.py). It names the data folder
# (%APPDATA%/DailyTodo/...) and the Windows taskbar identity, so changing it would orphan the
# existing database.
APP_ID = "DailyTodo"


def default_db_path() -> Path:
    """%APPDATA%/DailyTodo/DailyTodo/todos.db (needs the app/org name to be set first)."""
    base = Path(QStandardPaths.writableLocation(QStandardPaths.StandardLocation.AppDataLocation))
    base.mkdir(parents=True, exist_ok=True)
    return base / "todos.db"


def client_state_path(db_path: Path) -> Path:
    """Local UI state lives next to its central database (todos.db -> todos.client.db), so a
    second database chosen with --db gets its own state: resource ids only mean something per file."""
    return db_path.with_suffix(".client.db")


def _set_windows_app_id() -> None:
    # Without this, Windows groups the app under pythonw.exe and shows Python's taskbar icon.
    if sys.platform == "win32":
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(f"{APP_ID}.App")


def _create_qt_app(qt_args: list[str]) -> QGuiApplication:
    app = QGuiApplication([sys.argv[0], *qt_args])
    app.setOrganizationName(APP_ID)
    app.setApplicationName(APP_ID)
    app.setWindowIcon(QIcon(str(APP_ICON)))
    QQuickStyle.setStyle("Basic")  # Basic supports full control customisation
    return app


def run(argv: list[str] | None = None) -> int:
    config, qt_args = parse_args(sys.argv[1:] if argv is None else argv)
    _set_windows_app_id()
    app = _create_qt_app(qt_args)

    db_path = config.db_path or default_db_path()
    # Already running on this database: hand it the link (or just bring it to the front) and stop.
    instance = SingleInstance(server_name(db_path), parent=app)
    if instance.send_to_running(config.open_link):
        return 0
    try:
        repo = build_repository(db_path)
        try:
            client_state = ClientState(client_state_path(db_path))
        except ClientStateError as exc:  # a convenience only: run without it
            print(f"Could not open client state, continuing without: {exc}", file=sys.stderr)
            client_state = None
        controller = TodoController(
            repo, parent=app, client_state=client_state, data_dir=db_path.parent
        )  # outlives the QML engine
    except RepositoryError as exc:
        print(f"Could not open storage: {exc}", file=sys.stderr)
        return 1
    # client_state is not closed on quit: PDF tabs save their page while the app shuts down, and
    # every write is committed on its own anyway.
    app.aboutToQuit.connect(repo.close)

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(QML_DIR))
    # Main.qml declares these as properties, so there are no hidden context-property globals.
    engine.setInitialProperties({"controller": controller, "appTitle": config.title})
    engine.load(QUrl.fromLocalFile(str(QML_DIR / "Main.qml")))
    if not engine.rootObjects():
        return 1
    # The app's own header takes the place of the title bar (Windows; elsewhere nothing changes).
    chrome = WindowChrome(engine.rootObjects()[0], parent=app)
    if chrome.install():
        engine.rootObjects()[0].setProperty("chrome", chrome)

    # Links from later starts (see instance.py), and the one this start was given.
    window = engine.rootObjects()[0]

    def handle(link: str) -> None:
        QMetaObject.invokeMethod(window, "bringToFront")
        if link:
            controller.handleLink(link)

    instance.linkReceived.connect(handle)
    instance.listen()
    app.aboutToQuit.connect(instance.close)
    if config.open_link:
        QTimer.singleShot(0, lambda: controller.handleLink(config.open_link))
    return app.exec()


__all__ = ["AppConfig", "run"]
