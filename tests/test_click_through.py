"""Clicks belong to what is clicked: nothing that floats over a card lets a click through to it
(ClickHandler and InputBlocker, see their QML files)."""
import unittest
from pathlib import Path

from PySide6.QtCore import QPoint, QUrl, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parent.parent


class ClickThroughTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        QQuickStyle.setStyle("Basic")

    def setUp(self):
        self.engine = QQmlApplicationEngine()
        self.engine.addImportPath(str(ROOT / "qml"))
        self.engine.load(QUrl.fromLocalFile(str(ROOT / "tests" / "qml" / "ClickThrough.qml")))
        self.assertTrue(self.engine.rootObjects(), "the test scene did not load")
        self.win = self.engine.rootObjects()[0]
        QTest.qWaitForWindowExposed(self.win)
        QTest.qWait(50)

    def tearDown(self):
        self.win.close()
        self.engine.deleteLater()

    def click(self, x, y):
        QTest.mouseClick(self.win, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(x, y))
        QTest.qWait(20)

    def counts(self):
        return tuple(self.win.property(p) for p in ("cardClicks", "popupRowClicks", "boxRowClicks"))

    def test_the_card_itself_is_clickable(self):
        self.click(560, 380)
        self.assertEqual(self.counts(), (1, 0, 0))

    def test_a_row_in_a_popup_takes_the_click(self):
        self.click(100, 45)
        self.assertEqual(self.counts(), (0, 1, 0))

    def test_a_floating_box_takes_clicks_on_its_rows_and_its_empty_part(self):
        self.click(400, 45)
        self.click(400, 140)
        self.assertEqual(self.counts(), (0, 0, 1))
