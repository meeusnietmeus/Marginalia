import tempfile
import unittest
from pathlib import Path

from PySide6.QtGui import QGuiApplication

from dailytodo.app import client_state_path
from dailytodo.storage import ClientState, SqliteTodoRepository
from dailytodo.ui import TodoController


class ClientStateTest(unittest.TestCase):
    def test_unknown_pdf_has_no_page(self):
        self.assertIsNone(ClientState(":memory:").pdf_page(1))

    def test_set_creates_then_updates(self):
        state = ClientState(":memory:")
        state.set_pdf_page(7, 3)
        self.assertEqual(state.pdf_page(7), 3)
        state.set_pdf_page(7, 12)
        self.assertEqual(state.pdf_page(7), 12)
        self.assertIsNone(state.pdf_page(8))

    def test_forget(self):
        state = ClientState(":memory:")
        state.set_pdf_page(7, 3)
        state.forget_pdf(7)
        self.assertIsNone(state.pdf_page(7))

    def test_survives_reopening(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "c.db"
            first = ClientState(path)
            first.set_pdf_page(1, 5)
            first.close()
            second = ClientState(path)
            self.assertEqual(second.pdf_page(1), 5)
            second.close()

    def test_path_sits_next_to_the_central_db(self):
        self.assertEqual(client_state_path(Path("x/todos.db")), Path("x/todos.client.db"))


class ControllerClientStateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.state = ClientState(":memory:")
        self.ctl = TodoController(self.repo, client_state=self.state)

    def tearDown(self):
        self.repo.close()

    def test_default_is_page_one(self):
        self.assertEqual(self.ctl.lastPdfPage(99), 1)

    def test_save_and_read(self):
        self.ctl.savePdfPage(5, 9)
        self.assertEqual(self.ctl.lastPdfPage(5), 9)

    def test_invalid_page_is_ignored(self):
        self.ctl.savePdfPage(5, 0)
        self.assertEqual(self.ctl.lastPdfPage(5), 1)

    def test_deleting_a_resource_forgets_its_page(self):
        self.ctl.addResource("https://example.com/doc", "Doc", [])
        rid = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id
        self.ctl.savePdfPage(rid, 4)
        self.ctl.deleteResource(rid)
        self.assertEqual(self.ctl.lastPdfPage(rid), 1)
        self.ctl.savePdfPage(rid, 6)  # the closing tab saves after the delete: ignored
        self.assertEqual(self.ctl.lastPdfPage(rid), 1)

    def test_works_without_a_client_db(self):
        ctl = TodoController(self.repo)
        ctl.savePdfPage(1, 2)
        self.assertEqual(ctl.lastPdfPage(1), 1)


if __name__ == "__main__":
    unittest.main()
