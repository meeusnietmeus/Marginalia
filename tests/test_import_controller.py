import shutil
import tempfile
import unittest
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication

from dailytodo.storage import ClientState, SqliteTodoRepository
from dailytodo.ui import TodoController


class ImportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = SqliteTodoRepository(":memory:")
        self.client = ClientState(self.tmp / "client.db")
        self.ctl = TodoController(self.repo, client_state=self.client)
        self.ws = self.tmp / "ws"
        self.ctl.createWorkspace("Docs", str(self.ws))
        self.src = self.tmp / "downloads"
        (self.src / "deep").mkdir(parents=True)
        for rel in ("a.pdf", "b.docx", "deep/c.txt"):
            (self.src / rel).write_text(rel)

    def tearDown(self):
        self.repo.close()
        self.client.close()

    def uris(self):
        return {r.name: r.uri for r in self.repo.list_resources(self.ctl.currentWorkspaceId)}

    def test_preview_of_a_folder_and_of_file_urls(self):
        rows = self.ctl.previewImport([str(self.src)], [])
        self.assertEqual(sorted(r["name"] for r in rows), ["a", "b", "c"])
        url = QUrl.fromLocalFile(str(self.src / "a.pdf")).toString()
        self.assertEqual([r["name"] for r in self.ctl.previewImport([url], [])], ["a"])

    def test_import_adds_resources_with_the_tags_and_their_names(self):
        tag = self.ctl.createTag("lol", -1, -1)
        rows = self.ctl.previewImport([str(self.src)], [])
        items = [{"path": r["path"], "name": r["name"].upper()} for r in rows]
        result = self.ctl.importResources(items, [tag], False)
        self.assertEqual((result["added"], result["failed"]), (3, 0))
        self.assertEqual(sorted(self.uris()), ["A", "B", "C"])
        self.assertTrue((self.src / "a.pdf").exists())  # not moved
        tagged = self.repo.list_resource_tags(self.ctl.currentWorkspaceId)
        self.assertTrue(all(tag in ids for ids in tagged.values()))

    def test_importing_again_marks_everything_as_duplicate(self):
        rows = self.ctl.previewImport([str(self.src)], [])
        self.ctl.importResources([{"path": r["path"], "name": r["name"]} for r in rows], [], False)
        again = self.ctl.previewImport([str(self.src)], [])
        self.assertTrue(all(r["duplicate"] for r in again))

    def test_files_can_move_into_the_workspace_folder(self):
        (self.ws / "a.pdf").write_text("already here")  # a clash: this one stays where it was
        rows = self.ctl.previewImport([str(self.src / "a.pdf"), str(self.src / "b.docx")], [])
        result = self.ctl.importResources(
            [{"path": r["path"], "name": r["name"]} for r in rows], [], True)
        self.assertEqual((result["added"], result["moved"]), (2, 1))
        uris = self.uris()
        self.assertEqual(Path(uris["b"]), self.ws / "b.docx")
        self.assertEqual(Path(uris["a"]), self.src / "a.pdf")
        self.assertFalse((self.src / "b.docx").exists())

    def test_a_vanished_file_is_counted_as_failed(self):
        result = self.ctl.importResources(
            [{"path": str(self.src / "gone.pdf"), "name": "gone"},
             {"path": str(self.src / "a.pdf"), "name": "a"}], [], False)
        self.assertEqual((result["added"], result["failed"]), (1, 1))


if __name__ == "__main__":
    unittest.main()
