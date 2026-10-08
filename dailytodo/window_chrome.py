"""A window without Windows' own title bar: the app's header is the title bar, and its minimize,
maximize and close buttons are drawn by the app (qml/DailyTodo/Controls/WindowControls.qml).

Everything else stays native, so the window behaves like any other:

* the window keeps its frame styles, so it has the shadow, can be resized from its edges and
  snapped (Aero snap, Win+arrows);
* the empty parts of the header are the caption: drag to move, double-click to maximize, right-click
  for the system menu;
* hovering the maximize button shows Windows 11's snap layouts.

This is done by answering three window messages before Qt does: WM_NCCALCSIZE (the client area is
the whole window, so the title bar is gone), WM_NCHITTEST (what is under the pointer) and the
mouse messages of the maximize button. On anything but Windows nothing is installed, and the
window keeps its normal title bar.

The QML side tells this object where the maximize button is (setMaxButtonRect) and answers
``captionAt(x, y)``: is that point of the header empty, so that it can be used to move the window?
"""
from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes

from PySide6.QtCore import (
    Property,
    QAbstractNativeEventFilter,
    QMetaObject,
    QObject,
    Q_ARG,
    Qt,
    Signal,
    Slot,
)

# window messages
WM_NCCALCSIZE = 0x0083
WM_NCHITTEST = 0x0084
WM_NCMOUSEMOVE = 0x00A0
WM_NCLBUTTONDOWN = 0x00A1
WM_NCLBUTTONUP = 0x00A2
WM_NCMOUSELEAVE = 0x02A2
WM_DPICHANGED = 0x02E0

# hit test results
HTCLIENT, HTCAPTION, HTMAXBUTTON = 1, 2, 9
HTLEFT, HTRIGHT, HTTOP, HTTOPLEFT, HTTOPRIGHT = 10, 11, 12, 13, 14
HTBOTTOM, HTBOTTOMLEFT, HTBOTTOMRIGHT = 15, 16, 17

SM_CXFRAME, SM_CYFRAME, SM_CXPADDEDBORDER = 32, 33, 92
SW_MAXIMIZE, SW_RESTORE = 3, 9
SWP_FLAGS = 0x0001 | 0x0002 | 0x0004 | 0x0010 | 0x0020  # NOSIZE NOMOVE NOZORDER NOACTIVATE FRAMECHANGED
TME_LEAVE, TME_NONCLIENT = 0x2, 0x10
RESIZE_BORDER = 5  # device independent pixels, inside the window


class _Rect(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long), ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


class _NcCalcSizeParams(ctypes.Structure):
    _fields_ = [("rgrc", _Rect * 3), ("lppos", ctypes.c_void_p)]


class _Margins(ctypes.Structure):
    _fields_ = [("left", ctypes.c_int), ("right", ctypes.c_int), ("top", ctypes.c_int), ("bottom", ctypes.c_int)]


class _TrackMouseEvent(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                ("hwndTrack", wintypes.HWND), ("dwHoverTime", wintypes.DWORD)]


def supported() -> bool:
    return sys.platform == "win32"


class _Filter(QAbstractNativeEventFilter):
    """Qt wants the filter to be a class of its own (mixed into a QObject its properties would not
    reach QML)."""

    def __init__(self, chrome: "WindowChrome"):
        super().__init__()
        self._chrome = chrome

    def nativeEventFilter(self, event_type, message):
        return self._chrome.native_event(event_type, message)


class WindowChrome(QObject):
    """Installed on one QML window (the root object, an ApplicationWindow)."""

    stateChanged = Signal()

    def __init__(self, window: QObject, parent: QObject | None = None):
        super().__init__(parent)
        self._filter = _Filter(self)
        self._window = window
        self._hwnd = 0
        self._active = False
        self._max_rect = (0.0, 0.0, 0.0, 0.0)  # x, y, width, height in the window's own units
        self._header_height = 0.0
        self._max_hovered = False
        self._max_pressed = False
        self._caption_result = False
        self._tracking = False

    # ------------------------------------------------------------- properties
    @Property(bool, notify=stateChanged)
    def active(self) -> bool:
        """The title bar is replaced: QML shows its own window buttons."""
        return self._active

    @Property(bool, notify=stateChanged)
    def maxHovered(self) -> bool:
        return self._max_hovered

    @Property(bool, notify=stateChanged)
    def maxPressed(self) -> bool:
        return self._max_pressed

    @Slot(float, float, float, float)
    def setMaxButtonRect(self, x: float, y: float, width: float, height: float) -> None:
        self._max_rect = (x, y, width, height)

    @Slot(bool)
    def setCaptionResult(self, empty: bool) -> None:
        """The answer to captionAt (see Main.qml)."""
        self._caption_result = empty

    @Slot(float)
    def setHeaderHeight(self, height: float) -> None:
        self._header_height = height

    # ---------------------------------------------------------------- install
    @Slot()
    def install(self) -> bool:
        """Take the title bar away. Returns False (and changes nothing) where that isn't possible."""
        if not supported() or self._active:
            return self._active
        try:
            from PySide6.QtGui import QGuiApplication

            self._hwnd = int(self._window.winId())
            QGuiApplication.instance().installNativeEventFilter(self._filter)
            self._active = True
            self._refresh_frame()
            self.stateChanged.emit()
        except Exception as exc:  # the normal title bar is a fine fallback
            print(f"Could not use a custom title bar: {exc}", file=sys.stderr)
            self._active = False
        return self._active

    def _refresh_frame(self) -> None:
        user32, dwm = ctypes.windll.user32, ctypes.windll.dwmapi
        # a sliver of the frame kept as glass is what makes the window keep its shadow
        dwm.DwmExtendFrameIntoClientArea(wintypes.HWND(self._hwnd), ctypes.byref(_Margins(0, 0, 1, 0)))
        user32.SetWindowPos(wintypes.HWND(self._hwnd), None, 0, 0, 0, 0, SWP_FLAGS)

    # ---------------------------------------------------------------- helpers
    def _dpi(self) -> int:
        try:
            return int(ctypes.windll.user32.GetDpiForWindow(wintypes.HWND(self._hwnd))) or 96
        except (AttributeError, OSError):
            return 96

    def _frame(self) -> tuple[int, int]:
        """How far a maximized window reaches beyond the screen on each side."""
        user32, dpi = ctypes.windll.user32, self._dpi()
        padded = user32.GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi)
        return (user32.GetSystemMetricsForDpi(SM_CXFRAME, dpi) + padded,
                user32.GetSystemMetricsForDpi(SM_CYFRAME, dpi) + padded)

    def _maximized(self) -> bool:
        return bool(ctypes.windll.user32.IsZoomed(wintypes.HWND(self._hwnd)))

    def _set_state(self, hovered: bool | None = None, pressed: bool | None = None) -> None:
        changed = False
        if hovered is not None and hovered != self._max_hovered:
            self._max_hovered, changed = hovered, True
        if pressed is not None and pressed != self._max_pressed:
            self._max_pressed, changed = pressed, True
        if changed:
            self.stateChanged.emit()

    def _caption_at(self, x: float, y: float) -> bool:
        """Ask the header: is this point empty (movable) space?"""
        self._caption_result = False
        QMetaObject.invokeMethod(
            self._window, "captionAt", Qt.ConnectionType.DirectConnection,
            Q_ARG("QVariant", x), Q_ARG("QVariant", y),
        )
        return self._caption_result

    def _hit_test(self, x_screen: int, y_screen: int) -> int:
        user32 = ctypes.windll.user32
        hwnd = wintypes.HWND(self._hwnd)
        point = wintypes.POINT(x_screen, y_screen)
        user32.ScreenToClient(hwnd, ctypes.byref(point))
        rect = _Rect()
        user32.GetClientRect(hwnd, ctypes.byref(rect))
        scale = self._dpi() / 96.0
        x, y = point.x, point.y
        if x < 0 or y < 0 or x >= rect.right or y >= rect.bottom:
            return HTCLIENT
        # the edges and corners resize the window (not while it is maximized)
        if not self._maximized():
            border = max(3, int(RESIZE_BORDER * scale))
            left, right = x < border, x >= rect.right - border
            top, bottom = y < border, y >= rect.bottom - border
            if top and left: return HTTOPLEFT
            if top and right: return HTTOPRIGHT
            if bottom and left: return HTBOTTOMLEFT
            if bottom and right: return HTBOTTOMRIGHT
            if left: return HTLEFT
            if right: return HTRIGHT
            if top: return HTTOP
            if bottom: return HTBOTTOM
        if y >= self._header_height * scale:
            return HTCLIENT
        mx, my, mw, mh = self._max_rect
        if mw > 0 and mx * scale <= x < (mx + mw) * scale and my * scale <= y < (my + mh) * scale:
            return HTMAXBUTTON  # Windows 11 shows its snap layouts over this one
        return HTCAPTION if self._caption_at(x / scale, y / scale) else HTCLIENT

    # --------------------------------------------------------- the event filter
    def native_event(self, event_type, message):
        if not self._active or bytes(event_type) != b"windows_generic_MSG":
            return False, 0
        try:
            msg = wintypes.MSG.from_address(int(message))
            if msg.hWnd != self._hwnd:
                return False, 0
            return self._handle(msg)
        except Exception as exc:  # never break the message loop
            print(f"window chrome: {exc}", file=sys.stderr)
            return False, 0

    def _handle(self, msg) -> tuple[bool, int]:
        code = msg.message
        if code == WM_NCCALCSIZE:
            if msg.wParam and self._maximized():
                params = ctypes.cast(msg.lParam, ctypes.POINTER(_NcCalcSizeParams)).contents
                fx, fy = self._frame()
                rect = params.rgrc[0]
                rect.left += fx
                rect.right -= fx
                rect.top += fy
                rect.bottom -= fy
            return True, 0  # no non-client area: the app draws everything
        if code == WM_NCHITTEST:
            x = ctypes.c_short(msg.lParam & 0xFFFF).value
            y = ctypes.c_short((msg.lParam >> 16) & 0xFFFF).value
            hit = self._hit_test(x, y)
            self._set_state(hovered=hit == HTMAXBUTTON)
            if hit == HTMAXBUTTON and not self._tracking:
                self._track_leave()
            return True, hit
        if code == WM_NCMOUSEMOVE and msg.wParam != HTMAXBUTTON:
            self._set_state(hovered=False, pressed=False)
        elif code == WM_NCMOUSELEAVE:
            self._tracking = False
            self._set_state(hovered=False, pressed=False)
        elif code == WM_NCLBUTTONDOWN and msg.wParam == HTMAXBUTTON:
            self._set_state(pressed=True)
            return True, 0
        elif code == WM_NCLBUTTONUP and msg.wParam == HTMAXBUTTON:
            was_pressed = self._max_pressed
            self._set_state(pressed=False)
            if was_pressed:
                ctypes.windll.user32.ShowWindow(
                    wintypes.HWND(self._hwnd), SW_RESTORE if self._maximized() else SW_MAXIMIZE
                )
            return True, 0
        return False, 0

    def _track_leave(self) -> None:
        track = _TrackMouseEvent(ctypes.sizeof(_TrackMouseEvent), TME_LEAVE | TME_NONCLIENT, wintypes.HWND(self._hwnd), 0)
        ctypes.windll.user32.TrackMouseEvent(ctypes.byref(track))
        self._tracking = True
