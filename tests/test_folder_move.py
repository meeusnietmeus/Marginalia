"""Moving a workspace's folder: the plan (pure) and the whole thing against real files."""
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest

from dailytodo.core import folder_problem, plan_folder_move
from dailytodo.storage import ClientState, SqliteTodoRepository
from dailytodo.ui import TodoController


class PlanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.old = os.path.join(self.tmp, "old")
        self.new = os.path.join(self.tmp, "new")
        os.makedirs(os.path.join(self.old, "sub"))

    def test_problems(self):
        self.assertEqual(folder_problem(self.old, ""), "Choose a folder")
        self.assertIn("already", folder_problem(self.old, self.old))
        self.assertIn("inside", folder_problem(self.old, os.path.join(self.old, "sub")))
        self.assertIn("inside", folder_problem(os.path.join(self.old, "sub"), self.old))
        self.assertEqual(folder_problem(self.old, self.new), "")

    def test_keeps_the_place_in_the_folder_and_skips_the_rest(self):
        inside = os.path.join(self.old, "sub", "a.pdf")
        outside = os.path.join(self.tmp, "elsewhere", "b.pdf")
        plan = plan_folder_move(self.old, self.new, [
            (1, inside, True, "pdf"), (2, outside, True, "pdf"), (3, "https://x.org", False, "web"),
        ])
        self.assertEqual(plan.link_updates, {1: os.path.join(self.new, "sub", "a.pdf")})

    def test_the_pdf_of_a_presentation_goes_along(self):
        deck = os.path.join(self.tmp, "elsewhere", "Deck.pptx")
        Path(self.old, "Deck.pdf").write_bytes(b"%PDF")
        plan = plan_folder_move(self.old, self.new, [(4, deck, True, "powerpoint")])
        self.assertEqual(plan.link_updates, {})  # the deck itself stays
        self.assertEqual([(i.source, i.target) for i in plan.items],
                         [(os.path.join(self.old, "Deck.pdf"), os.path.join(self.new, "Deck.pdf"))])


class MoveTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = SqliteTodoRepository(":memory:")
        self.client = ClientState(self.tmp / "client.db")
        self.ctl = TodoController(self.repo, client_state=self.client)
        self.old = self.tmp / "old"
        self.new = self.tmp / "new"
        self.ctl.createWorkspace("Docs", str(self.old))
        self.notes = []
        self.ctl.notify.connect(self.notes.append)
        (self.old / "sub").mkdir()
        self.a = self.old / "a.txt"
        self.b = self.old / "sub" / "b.txt"
        self.outside = self.tmp / "outside.txt"
        for f in (self.a, self.b, self.outside):
            f.write_text(f.name)
        for f in (self.a, self.b, self.outside):
            self.ctl.addResource(str(f), f.name, [], False)

    def tearDown(self):
        self.repo.close()
        self.client.close()

    def uris(self):
        wid = self.ctl.currentWorkspaceId
        return {r.name: r.uri for r in self.repo.list_resources(wid)}

    def run_move(self, target):
        self.ctl.retargetWorkspaceFolder(str(target))
        QTest.qWait(900)

    def test_preview_counts_files(self):
        info = self.ctl.previewFolderRetarget(str(self.new))
        self.assertEqual((info["ok"], info["count"], info["missing"]), (True, 2, 0))

    def test_moves_files_links_and_the_setting(self):
        self.run_move(self.new)
        self.assertTrue((self.new / "a.txt").is_file())
        self.assertTrue((self.new / "sub" / "b.txt").is_file())
        self.assertFalse(self.a.exists())
        self.assertEqual(self.uris(), {
            "a.txt": str(self.new / "a.txt"), "b.txt": str(self.new / "sub" / "b.txt"),
            "outside.txt": str(self.outside)})
        self.assertEqual(Path(self.ctl.defaultResourceFolder()), self.new)

    def test_a_clash_changes_nothing(self):
        self.new.mkdir()
        (self.new / "a.txt").write_text("already here")
        info = self.ctl.previewFolderRetarget(str(self.new))
        self.assertFalse(info["ok"])
        self.run_move(self.new)
        self.assertTrue(self.a.is_file())
        self.assertEqual(self.uris()["a.txt"], str(self.a))
        self.assertEqual(Path(self.ctl.defaultResourceFolder()), self.old)

    def test_a_missing_file_still_gets_its_link_moved(self):
        self.b.unlink()
        info = self.ctl.previewFolderRetarget(str(self.new))
        self.assertEqual((info["count"], info["missing"]), (1, 1))
        self.run_move(self.new)
        self.assertEqual(self.uris()["b.txt"], str(self.new / "sub" / "b.txt"))
        self.assertTrue((self.new / "a.txt").is_file())

    def test_a_failure_halfway_undoes_the_moves(self):
        real_move = shutil.move
        calls = []

        def flaky(src, dst, *a, **k):
            calls.append(src)
            if len(calls) == 2:
                raise OSError(28, "No space left on device")
            return real_move(src, dst, *a, **k)

        shutil.move = flaky
        try:
            self.run_move(self.new)
        finally:
            shutil.move = real_move
        self.assertTrue(self.a.is_file() and self.b.is_file())
        self.assertEqual(self.uris()["a.txt"], str(self.a))
        self.assertEqual(Path(self.ctl.defaultResourceFolder()), self.old)
        self.assertTrue(any("nothing was changed" in n for n in self.notes))


if __name__ == "__main__":
    unittest.main()
