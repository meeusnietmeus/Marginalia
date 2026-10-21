"""Backups: where they go, how many are kept (by creation date), and moving along with the folder."""
import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path

from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest

from dailytodo.storage import ClientState, SqliteTodoRepository, list_backups, prune_backups
from dailytodo.ui import TodoController


def make(folder: Path, name: str, created: float) -> Path:
    path = folder / name
    path.write_text(name)
    os.utime(path, (created, created))
    return path


class PruneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def names(self):
        return sorted(p.name for p in self.tmp.iterdir())

    def test_keeps_the_newest_by_creation_not_by_name(self):
        # created in this order: b, c, a -- the names say otherwise
        for name in ("todos-backup-b.db", "todos-backup-c.db", "todos-backup-a.db"):
            (self.tmp / name).write_text(name)
            time.sleep(0.05)
        self.assertEqual([p.name for p in list_backups(self.tmp, ".db")],
                         ["todos-backup-b.db", "todos-backup-c.db", "todos-backup-a.db"])
        gone = prune_backups(self.tmp, 2, ".db")
        self.assertEqual([p.name for p in gone], ["todos-backup-b.db"])
        self.assertEqual(self.names(), ["todos-backup-a.db", "todos-backup-c.db"])

    def test_zero_keeps_everything_and_one_keeps_the_newest(self):
        for i in range(4):
            (self.tmp / f"todos-backup-{i}.db").write_text("x")
            time.sleep(0.05)
        self.assertEqual(prune_backups(self.tmp, 0, ".db"), [])
        self.assertEqual(len(self.names()), 4)
        prune_backups(self.tmp, 1, ".db")
        self.assertEqual(self.names(), ["todos-backup-3.db"])

    def test_other_files_are_left_alone(self):
        (self.tmp / "notes.txt").write_text("mine")
        for i in range(3):
            (self.tmp / f"todos-backup-{i}.db").write_text("x")
            time.sleep(0.05)
        prune_backups(self.tmp, 1, ".db")
        self.assertIn("notes.txt", self.names())


class ControllerBackupTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = SqliteTodoRepository(str(self.tmp / "todos.db"))
        self.client = ClientState(self.tmp / "client.db")
        self.ctl = TodoController(self.repo, client_state=self.client)
        self.folder = self.tmp / "ws"
        self.ctl.createWorkspace("Docs", str(self.folder))
        self.notes = []
        self.ctl.notify.connect(self.notes.append)

    def tearDown(self):
        self.repo.close()
        self.client.close()

    def backups(self, folder=None):
        return list_backups((folder or self.folder) / ".backups", ".db")

    def test_a_backup_goes_into_the_workspace_folder(self):
        self.ctl.exportBackup()
        self.assertEqual(len(self.backups()), 1)

    def test_old_backups_go_when_there_are_too_many(self):
        self.ctl.setBackupKeep(2)
        for _ in range(4):
            self.ctl.exportBackup()
            time.sleep(1.05)  # (the file name has a one-second resolution)
        self.assertEqual(len(self.backups()), 2)

    def test_zero_means_unlimited(self):
        self.ctl.setBackupKeep(0)
        for _ in range(3):
            self.ctl.exportBackup()
            time.sleep(1.05)
        self.assertEqual(len(self.backups()), 3)

    def test_settings_are_remembered(self):
        self.assertEqual((self.ctl.backupKeep, self.ctl.backupOnClose), (10, False))
        self.ctl.setBackupKeep(5)
        self.ctl.setBackupOnClose(True)
        self.assertEqual((self.ctl.backupKeep, self.ctl.backupOnClose), (5, True))

    def test_backup_on_quit_only_when_asked(self):
        self.ctl.backupOnQuit()
        self.assertEqual(len(self.backups()), 0)
        self.ctl.setBackupOnClose(True)
        self.ctl.backupOnQuit()
        self.assertEqual(len(self.backups()), 1)

    def test_backups_follow_a_retargeted_folder(self):
        self.ctl.exportBackup()
        old_backup = self.backups()[0].name
        new = self.tmp / "moved"
        info = self.ctl.previewFolderRetarget(str(new))
        self.assertEqual(info["backups"], 1)
        self.ctl.retargetWorkspaceFolder(str(new))
        QTest.qWait(900)
        self.assertEqual([p.name for p in self.backups(new)], [old_backup])
        self.assertFalse((self.folder / ".backups").exists())
        self.ctl.exportBackup()  # and the next one goes to the new place
        self.assertGreaterEqual(len(self.backups(new)), 1)
        self.assertFalse((self.folder / ".backups").exists())


if __name__ == "__main__":
    unittest.main()
