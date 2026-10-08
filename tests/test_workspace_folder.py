import os
import shutil
import tempfile
import unittest
from pathlib import Path

from PySide6.QtGui import QGuiApplication

from dailytodo.core import is_inside
from dailytodo.storage import ClientState, SqliteTodoRepository
from dailytodo.ui import TodoController


class InsideTest(unittest.TestCase):
    def test_inside(self):
        self.assertTrue(is_inside("C:\\Work\\ws\\a.pdf", "C:\\Work\\ws"))
        self.assertTrue(is_inside("C:/Work/WS/sub/dir/a.pdf", "c:\\work\\ws\\"))
        self.assertFalse(is_inside("C:\\Work\\ws2\\a.pdf", "C:\\Work\\ws"))     # not just a prefix
        self.assertFalse(is_inside("C:\\Work\\a.pdf", "C:\\Work\\ws"))
        self.assertFalse(is_inside("D:\\ws\\a.pdf", "C:\\Work\\ws"))            # another drive
        self.assertFalse(is_inside("a.pdf", ""))


class WorkspaceFolderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo, client_state=ClientState(":memory:"))
        self.folder = self.root / "workspace"
        self.folder.mkdir()
        self.ctl.setDefaultResourceFolder(str(self.folder))
        self.elsewhere = self.root / "downloads"
        self.elsewhere.mkdir()
        self.messages = []
        self.ctl.notify.connect(self.messages.append)

    def tearDown(self):
        self.repo.close()
        self._tmp.cleanup()

    def make(self, folder: Path, name="paper.pdf") -> Path:
        path = folder / name
        path.write_bytes(b"%PDF data")
        return path

    def resource_uris(self):
        return [r.uri for r in self.repo.list_resources(self.ctl.currentWorkspaceId)]

    # ------------------------------------------------- moving the file in
    def test_a_file_from_elsewhere_is_moved_into_the_workspace_folder(self):
        source = self.make(self.elsewhere)
        self.assertFalse(self.ctl.isInWorkspaceFolder(str(source)))
        self.ctl.addResource(str(source), "Paper", [], True)
        moved = self.folder / "paper.pdf"
        self.assertEqual(self.resource_uris(), [str(moved)])
        self.assertTrue(moved.is_file())
        self.assertFalse(source.exists())                  # cut, not copied

    def test_unchecked_leaves_the_file_alone(self):
        source = self.make(self.elsewhere)
        self.ctl.addResource(str(source), "Paper", [], False)
        self.assertEqual(self.resource_uris(), [str(source)])
        self.assertTrue(source.is_file())

    def test_a_file_already_in_the_folder_stays_put(self):
        inside = self.make(self.folder / "..", "x.pdf") if False else self.make(self.folder)
        self.assertTrue(self.ctl.isInWorkspaceFolder(str(inside)))
        self.ctl.addResource(str(inside), "Paper", [], True)
        self.assertEqual(self.resource_uris(), [str(inside)])
        (self.folder / "sub").mkdir()
        deeper = self.make(self.folder / "sub", "deep.pdf")
        self.assertTrue(self.ctl.isInWorkspaceFolder(str(deeper)))

    def test_a_name_that_is_taken_is_never_overwritten(self):
        self.make(self.folder, "paper.pdf").write_bytes(b"the one that was there")
        source = self.make(self.elsewhere)
        self.ctl.addResource(str(source), "Paper", [], True)
        self.assertEqual(self.resource_uris(), [str(source)])        # added where it is
        self.assertEqual((self.folder / "paper.pdf").read_bytes(), b"the one that was there")
        self.assertTrue(any("already in the workspace folder" in m for m in self.messages))

    def test_links_are_never_moved(self):
        self.ctl.addResource("https://example.com/x", "Page", [], True)
        self.assertEqual(self.resource_uris(), ["https://example.com/x"])

    def test_a_failed_move_still_adds_the_resource(self):
        source = self.make(self.elsewhere)
        original = shutil.move

        def broken(*args, **kwargs):
            raise PermissionError("in use")

        shutil.move = broken
        try:
            self.ctl.addResource(str(source), "Paper", [], True)
        finally:
            shutil.move = original
        self.assertEqual(self.resource_uris(), [str(source)])
        self.assertTrue(source.is_file())
        self.assertTrue(any("Couldn't move" in m for m in self.messages))

    # ------------------------------------------------ creating a workspace
    def test_a_workspace_needs_a_folder(self):
        count = len(self.ctl.workspaces)
        self.ctl.createWorkspace("Gym", "")
        self.ctl.createWorkspace("Gym", "   ")
        self.assertEqual(len(self.ctl.workspaces), count)
        self.assertTrue(any("Choose a folder" in m for m in self.messages))

    def test_the_folder_is_made_and_belongs_to_the_new_workspace(self):
        target = self.root / "new" / "gym"
        self.ctl.createWorkspace("Gym", str(target))
        self.assertTrue(target.is_dir())
        self.assertEqual(self.ctl.defaultResourceFolder(), str(target))
        first = self.ctl.workspaces[0]["id"]
        self.ctl.setWorkspace(first)
        self.assertEqual(self.ctl.defaultResourceFolder(), str(self.folder))

    def test_a_folder_that_cannot_be_made_creates_nothing(self):
        blocker = self.root / "a-file"
        blocker.write_text("x")
        count = len(self.ctl.workspaces)
        self.ctl.createWorkspace("Gym", str(blocker / "inside"))
        self.assertEqual(len(self.ctl.workspaces), count)


if __name__ == "__main__":
    unittest.main()
