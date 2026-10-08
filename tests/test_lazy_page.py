"""LazyPage: made when shown, kept for a while after it is left, then unloaded."""
import unittest
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parent.parent


class LazyPageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.engine = QQmlEngine()
        self.engine.addImportPath(str(ROOT / "qml"))
        component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(ROOT / "tests" / "qml" / "LazyPage.qml")))
        self.root = component.create()
        self.assertIsNotNone(self.root, component.errorString())
        self.page = self.root.property("page")

    def state(self):
        return self.page.property("loaded"), self.page.property("unloadsAt") > 0

    def test_loads_when_shown_and_unloads_after_it_was_left(self):
        self.assertEqual(self.state(), (False, False))     # never shown: not made at all
        self.page.setProperty("shown", True)
        self.assertEqual(self.state(), (True, False))
        self.page.setProperty("shown", False)
        self.assertEqual(self.state(), (True, True))       # kept, counting down
        QTest.qWait(400)
        self.assertEqual(self.state(), (False, False))

    def test_coming_back_in_time_keeps_it(self):
        self.page.setProperty("shown", True)
        self.page.setProperty("shown", False)
        QTest.qWait(60)
        self.page.setProperty("shown", True)
        QTest.qWait(300)
        self.assertEqual(self.state(), (True, False))
