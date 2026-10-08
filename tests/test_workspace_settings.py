import unittest

from PySide6.QtGui import QGuiApplication

from dailytodo.storage import ClientState, SqliteTodoRepository
from dailytodo.ui import TodoController


class WorkspaceSettingsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.state = ClientState(":memory:")
        self.ctl = TodoController(self.repo, client_state=self.state)

    def tearDown(self):
        self.repo.close()
        self.state.close()

    def test_store_roundtrip_and_clear(self):
        self.assertIsNone(self.state.workspace_setting(1, "k"))
        self.state.set_workspace_setting(1, "k", "a")
        self.state.set_workspace_setting(1, "k", "b")
        self.assertEqual(self.state.workspace_setting(1, "k"), "b")
        self.assertIsNone(self.state.workspace_setting(2, "k"))
        self.state.set_workspace_setting(1, "k", None)
        self.assertIsNone(self.state.workspace_setting(1, "k"))

    def test_folder_is_per_workspace(self):
        first = self.ctl.currentWorkspaceId
        self.ctl.setDefaultResourceFolder("C:\\Books")
        self.assertEqual(self.ctl.defaultResourceFolder(), "C:\\Books")
        other = next(w.id for w in self.repo.list_workspaces() if w.id != first)
        self.ctl.setWorkspace(other)
        self.assertEqual(self.ctl.defaultResourceFolder(), "")
        self.ctl.setWorkspace(first)
        self.assertEqual(self.ctl.defaultResourceFolder(), "C:\\Books")
        self.ctl.setDefaultResourceFolder("")
        self.assertEqual(self.ctl.defaultResourceFolder(), "")

    def test_deleting_workspace_forgets_settings(self):
        first = self.ctl.currentWorkspaceId
        self.ctl.setDefaultResourceFolder("C:\\Books")
        self.ctl.deleteWorkspace()
        self.assertIsNone(self.state.workspace_setting(first, "resource_folder"))

    def test_app_settings_roundtrip(self):
        self.assertIsNone(self.state.app_setting("k"))
        self.state.set_app_setting("k", "1")
        self.state.set_app_setting("k", "2")
        self.assertEqual(self.state.app_setting("k"), "2")
        self.state.set_app_setting("k", None)
        self.assertIsNone(self.state.app_setting("k"))

    def test_pdf_scroll_speed_default_save_and_clamp(self):
        self.assertEqual(self.ctl.pdfScrollSpeed, 1.5)
        changes = []
        self.ctl.pdfScrollSpeedChanged.connect(lambda: changes.append(self.ctl.pdfScrollSpeed))
        self.ctl.setPdfScrollSpeed(2.2)
        self.ctl.setPdfScrollSpeed(2.2)  # no change, no signal
        self.assertEqual(changes, [2.2])
        self.ctl.setPdfScrollSpeed(99)
        self.assertEqual(self.ctl.pdfScrollSpeed, 4.0)
        self.ctl.setPdfScrollSpeed(0)
        self.assertEqual(self.ctl.pdfScrollSpeed, 0.5)

    def test_pdf_scroll_speed_is_remembered(self):
        self.ctl.setPdfScrollSpeed(3.1)
        again = TodoController(self.repo, client_state=self.state)  # "the next launch"
        self.assertEqual(again.pdfScrollSpeed, 3.1)

    def test_garbage_in_the_saved_speed_falls_back_to_the_default(self):
        self.state.set_app_setting("pdf_scroll_speed", "fast")
        self.assertEqual(TodoController(self.repo, client_state=self.state).pdfScrollSpeed, 1.5)

    def test_without_client_db(self):
        ctl = TodoController(self.repo)
        ctl.setDefaultResourceFolder("x")
        self.assertEqual(ctl.defaultResourceFolder(), "")


if __name__ == "__main__":
    unittest.main()
