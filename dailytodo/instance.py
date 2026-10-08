"""One running app per database, and a way for a second start to talk to it.

Windows starts a new process for every ``marginalia://`` link (the browser extension opens them)
and for every click on the shortcut. That process asks the running app, over a local socket (a
named pipe on Windows), to do the work instead, and quits: the window comes to the front and the
link is handled there. When no app is running yet, the process becomes the app itself.

The message is one line of JSON: ``{"open": "<link>"}``, or ``{}`` just to come to the front; the
running app answers ``ok``.
"""
from __future__ import annotations

import ctypes
import getpass
import hashlib
import json
import sys
from pathlib import Path

from PySide6.QtCore import QObject, Signal
from PySide6.QtNetwork import QLocalServer, QLocalSocket

CONNECT_TIMEOUT_MS = 400
ANSWER_TIMEOUT_MS = 2000
ASFW_ANY = -1  # AllowSetForegroundWindow: any process may take the foreground


def server_name(db_path: Path) -> str:
    """Per user and per database: two different ``--db`` files are two separate apps."""
    key = f"{getpass.getuser()}|{str(db_path.resolve()).lower()}"
    return "Marginalia-" + hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]


class SingleInstance(QObject):
    """``send_to_running`` from a new process; ``listen`` in the app that keeps running."""

    linkReceived = Signal(str)  # a link to open ("" just brings the window to the front)

    def __init__(self, name: str, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._name = name
        self._server: QLocalServer | None = None
        self._sockets: set[QLocalSocket] = set()

    def send_to_running(self, link: str = "") -> bool:
        """Hand ``link`` to the app that is already running. False when there is none."""
        socket = QLocalSocket()
        socket.connectToServer(self._name)
        if not socket.waitForConnected(CONNECT_TIMEOUT_MS):
            return False
        # This process was started by the user's action (a key press in the browser, a click), so
        # Windows lets it take the foreground; pass that on, or the running app's window could
        # only flash in the taskbar.
        if sys.platform == "win32":
            ctypes.windll.user32.AllowSetForegroundWindow(ASFW_ANY)
        message = json.dumps({"open": link} if link else {}) + "\n"
        socket.write(message.encode("utf-8"))
        socket.flush()
        # Wait for the answer before hanging up: a pipe closed straight after writing can lose
        # what was written. A running app that doesn't answer (hung) still counts as running: a
        # second window on the same database would be worse.
        socket.waitForReadyRead(ANSWER_TIMEOUT_MS)
        socket.disconnectFromServer()
        return True

    def listen(self) -> bool:
        server = QLocalServer(self)
        server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)
        if not server.listen(self._name):
            # left over from an app that crashed (on Unix a stale socket file stays behind)
            QLocalServer.removeServer(self._name)
            if not server.listen(self._name):
                return False
        server.newConnection.connect(self._accept)
        self._server = server
        return True

    def close(self) -> None:
        """Stop listening and let go of every connection, now rather than whenever Python gets
        round to it."""
        for socket in list(self._sockets):
            socket.abort()
            socket.deleteLater()
        self._sockets.clear()
        if self._server is not None:
            self._server.close()
            self._server.deleteLater()
            self._server = None

    def _accept(self) -> None:
        while self._server is not None and self._server.hasPendingConnections():
            self._serve(self._server.nextPendingConnection())

    def _serve(self, socket: QLocalSocket) -> None:
        """Read one line from a new start of the app, answer "ok", then act on it."""
        buffer = bytearray()
        done = False

        def read() -> None:
            nonlocal done
            buffer.extend(socket.readAll().data())
            if not done and b"\n" in buffer:
                done = True
                socket.write(b"ok\n")
                socket.flush()
                self._handle(bytes(buffer).split(b"\n", 1)[0])

        def hung_up() -> None:
            # forgotten when it hangs up, not when it is destroyed: by then this object may be
            # half gone itself (the server and its sockets go together at shutdown)
            self._sockets.discard(socket)
            socket.deleteLater()

        socket.readyRead.connect(read)
        socket.disconnected.connect(hung_up)
        self._sockets.add(socket)  # keep the Python side (and the slots above) alive meanwhile
        read()

    def _handle(self, line: bytes) -> None:
        try:
            message = json.loads(line.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return
        if isinstance(message, dict):
            link = message.get("open", "")
            self.linkReceived.emit(link if isinstance(link, str) else "")
