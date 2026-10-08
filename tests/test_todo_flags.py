"""The two flags a todo can have: priority, and in progress."""
import sqlite3
import tempfile
import unittest
from datetime import date
from pathlib import Path

from PySide6.QtGui import QGuiApplication

from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController

DAY = date(2026, 10, 9)


class RepositoryFlagsTest(unittest.TestCase):
    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ws = self.repo.list_workspaces()[0].id
        self.todo = self.repo.add(self.ws, DAY, "write the intro")

    def tearDown(self):
        self.repo.close()

    def flags(self):
        t = next(t for t in self.repo.list_todos(self.ws) if t.id == self.todo.id)
        return t.done, t.priority, t.in_progress

    def test_a_new_todo_has_neither(self):
        self.assertEqual(self.flags(), (False, False, False))

    def test_each_flag_on_and_off(self):
        self.repo.set_priority(self.todo.id, True)
        self.repo.set_in_progress(self.todo.id, True)
        self.assertEqual(self.flags(), (False, True, True))
        self.repo.set_priority(self.todo.id, False)
        self.repo.set_in_progress(self.todo.id, False)
        self.assertEqual(self.flags(), (False, False, False))

    def test_done_and_in_progress_rule_each_other_out(self):
        self.repo.set_in_progress(self.todo.id, True)
        self.repo.set_done(self.todo.id, True)
        self.assertEqual(self.flags(), (True, False, False))      # done: no longer in progress
        self.repo.set_in_progress(self.todo.id, True)
        self.assertEqual(self.flags(), (False, False, True))      # back in progress: open again
        self.repo.set_priority(self.todo.id, True)
        self.repo.set_done(self.todo.id, True)
        self.assertEqual(self.flags(), (True, True, False))       # a done todo keeps its priority

    def test_an_older_database_gets_the_flags(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "old.db"
            first = SqliteTodoRepository(path)
            ws = first.list_workspaces()[0].id
            first.close()
            old = sqlite3.connect(path)
            old.executescript(
                "DROP TABLE todos;"
                "CREATE TABLE todos (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL,"
                " is_completed INTEGER NOT NULL DEFAULT 0, date TEXT,"
                " workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE);"
                f"INSERT INTO todos (text, date, workspace_id) VALUES ('from before', '2026-10-01', {ws});"
            )
            old.close()
            repo = SqliteTodoRepository(path)
            (todo,) = repo.list_todos(ws)
            self.assertEqual((todo.text, todo.priority, todo.in_progress), ("from before", False, False))
            repo.set_priority(todo.id, True)
            self.assertTrue(repo.list_todos(ws)[0].priority)
            repo.close()


class ControllerFlagsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo, today=lambda: DAY)
        self.ws = self.ctl.currentWorkspaceId
        self.ctl.addTodo(DAY.isoformat(), "on the timeline")
        self.ctl.addBacklogTodo("in the backlog")
        by_text = {t.text: t.id for t in self.repo.list_todos(self.ws)}
        self.dated, self.loose = by_text["on the timeline"], by_text["in the backlog"]

    def tearDown(self):
        self.repo.close()

    def day_todo(self):
        row = next(r for r in self.ctl.days.rows if r.date_iso == DAY.isoformat())
        return next(t for t in row.todos if t["id"] == self.dated)

    def test_the_timeline_and_the_backlog_show_the_flags(self):
        self.ctl.setPriority(self.dated, True)
        self.ctl.setInProgress(self.dated, True)
        self.assertEqual((self.day_todo()["priority"], self.day_todo()["inProgress"]), (True, True))
        self.ctl.setInProgress(self.loose, True)
        (loose,) = self.ctl.backlog.rows
        self.assertEqual((loose.priority, loose.in_progress), (False, True))

    def test_undoing_a_delete_brings_the_flags_back(self):
        self.ctl.setPriority(self.dated, True)
        self.ctl.setInProgress(self.dated, True)
        offers = []
        self.ctl.undoOffered.connect(lambda token, message: offers.append(token))
        self.ctl.deleteTodo(self.dated)
        self.ctl.undo(offers[-1])
        self.assertEqual((self.day_todo()["priority"], self.day_todo()["inProgress"]), (True, True))


if __name__ == "__main__":
    unittest.main()
