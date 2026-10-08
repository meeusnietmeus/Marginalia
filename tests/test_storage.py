import sqlite3
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path

from dailytodo.storage import BackupCapable, RepositoryError, SqliteTodoRepository, export_backup

DAY = date(2026, 10, 1)


class SqliteRepositoryTest(unittest.TestCase):
    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ws = self.repo.list_workspaces()[0].id

    def tearDown(self):
        self.repo.close()

    def test_crud(self):
        todo = self.repo.add(self.ws, DAY, "write tests")
        self.repo.set_done(todo.id, True)
        self.repo.update_text(todo.id, "write more tests")
        self.repo.move_to_day(todo.id, date(2026, 10, 2))
        (stored,) = self.repo.list_todos(self.ws)
        self.assertEqual((stored.text, stored.done, stored.day), ("write more tests", True, date(2026, 10, 2)))
        self.repo.delete(todo.id)
        self.assertEqual(self.repo.list_todos(self.ws), [])

    def test_seeds_default_workspaces(self):
        self.assertEqual([w.name for w in self.repo.list_workspaces()], ["Personal", "Work", "Side projects"])

    def test_todos_are_scoped_to_their_workspace(self):
        personal, work = (w.id for w in self.repo.list_workspaces()[:2])
        self.repo.add(personal, DAY, "p")
        self.repo.add(work, DAY, "w")
        self.assertEqual([t.text for t in self.repo.list_todos(personal)], ["p"])
        self.assertEqual([t.text for t in self.repo.list_todos(work)], ["w"])

    def test_resource_name_is_required(self):
        ws = self.ws
        with self.assertRaises(RepositoryError):
            self.repo.add_resource(ws, "https://example.com", "   ")
        res = self.repo.add_resource(ws, "https://example.com", "ok")
        with self.assertRaises(RepositoryError):
            self.repo.update_resource(res.id, "https://example.com", "")

    def test_restore_todo_keeps_its_id_and_place(self):
        first = self.repo.add(self.ws, DAY, "one")
        second = self.repo.add(self.ws, DAY, "two")
        third = self.repo.add(self.ws, DAY, "three")
        self.repo.set_done(second.id, True)
        stored = next(t for t in self.repo.list_todos(self.ws) if t.id == second.id)
        self.repo.delete(second.id)
        self.repo.restore_todo(self.ws, stored)
        todos = self.repo.list_todos(self.ws)
        self.assertEqual([t.id for t in todos], [first.id, second.id, third.id])  # same place
        self.assertTrue(todos[1].done)

    def test_backlog_todos(self):
        dated = self.repo.add(self.ws, DAY, "dated")
        a = self.repo.add(self.ws, None, "first idea")
        b = self.repo.add(self.ws, None, "second idea")
        todos = self.repo.list_todos(self.ws)
        self.assertEqual([t.text for t in todos], ["first idea", "second idea", "dated"])  # backlog first
        self.assertEqual((a.day, todos[0].day), (None, None))
        self.repo.move_to_day(a.id, DAY)  # onto the timeline
        self.repo.move_to_day(dated.id, None)  # and off it again
        by_text = {t.text: t.day for t in self.repo.list_todos(self.ws)}
        self.assertEqual(by_text, {"first idea": DAY, "second idea": None, "dated": None})
        # a deleted backlog todo can be restored as a backlog todo
        stored = next(t for t in self.repo.list_todos(self.ws) if t.id == b.id)
        self.repo.delete(b.id)
        self.repo.restore_todo(self.ws, stored)
        self.assertIsNone(next(t for t in self.repo.list_todos(self.ws) if t.id == b.id).day)

    def test_migrates_todos_with_a_required_date(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "old.db"
            first = SqliteTodoRepository(path)
            ws = first.list_workspaces()[0].id
            first.close()
            old = sqlite3.connect(path)
            old.executescript(
                "DROP TABLE todos;"
                "CREATE TABLE todos (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL,"
                " is_completed INTEGER NOT NULL DEFAULT 0, date TEXT NOT NULL,"
                " workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE);"
                f"INSERT INTO todos (text, is_completed, date, workspace_id) VALUES ('kept', 1, '2026-10-01', {ws});"
            )
            old.close()
            repo = SqliteTodoRepository(path)
            (todo,) = repo.list_todos(ws)
            self.assertEqual((todo.text, todo.done, todo.day), ("kept", True, DAY))
            backlog = repo.add(ws, None, "now possible")  # the date may be empty now
            self.assertIsNone(backlog.day)
            repo.close()

    def test_move_open_todos(self):
        other = self.repo.list_workspaces()[1].id
        done = self.repo.add(self.ws, DAY, "done")
        self.repo.set_done(done.id, True)
        self.repo.add(self.ws, DAY, "open")
        self.repo.add(other, DAY, "elsewhere")
        target = date(2026, 10, 3)
        self.repo.move_open_todos(self.ws, DAY, target)
        days = {t.text: t.day for t in self.repo.list_todos(self.ws)}
        self.assertEqual(days, {"done": DAY, "open": target})
        self.assertEqual(self.repo.list_todos(other)[0].day, DAY)

    def test_create_workspace(self):
        created = self.repo.create_workspace("Gym")
        self.assertEqual(self.repo.list_workspaces()[-1], created)
        with self.assertRaises(RepositoryError):
            self.repo.create_workspace("Gym")

    def test_rename_and_delete_workspace(self):
        a, b = (w.id for w in self.repo.list_workspaces()[:2])
        self.repo.rename_workspace(a, "Renamed")
        self.assertEqual(self.repo.list_workspaces()[0].name, "Renamed")
        with self.assertRaises(RepositoryError):
            self.repo.rename_workspace(a, "Work")
        self.repo.add(a, DAY, "gone")
        self.repo.add(b, DAY, "stays")
        self.repo.delete_workspace(a)
        self.assertEqual(self.repo.list_workspaces()[0].id, b)
        self.assertEqual([t.text for t in self.repo.list_todos(b)], ["stays"])
        self.assertEqual(self.repo.list_todos(a), [])

    def test_resources_are_scoped_and_updatable(self):
        a, b = (w.id for w in self.repo.list_workspaces()[:2])
        first = self.repo.add_resource(a, "https://example.com", "Example")
        self.repo.add_resource(b, r"C:\other.pdf", "Other")
        self.assertEqual([r.uri for r in self.repo.list_resources(a)], ["https://example.com"])
        self.repo.update_resource(first.id, r"C:\moved.pdf", "Moved")
        (stored,) = self.repo.list_resources(a)
        self.assertEqual((stored.uri, stored.name), (r"C:\moved.pdf", "Moved"))
        self.assertEqual(stored.last_used_at, stored.created_at)  # editing is not a use
        self.repo.touch_resource(first.id)
        self.assertGreaterEqual(self.repo.list_resources(a)[0].last_used_at, stored.created_at)
        self.repo.delete_workspace(a)  # resources go with their workspace
        self.assertEqual(self.repo.list_resources(a), [])
        self.assertEqual(len(self.repo.list_resources(b)), 1)

    def test_tags_and_resource_tags(self):
        a, b = (w.id for w in self.repo.list_workspaces()[:2])
        zeta = self.repo.create_tag(a, "zeta")
        alpha = self.repo.create_tag(a, "Alpha")
        foreign = self.repo.create_tag(b, "other")
        self.assertEqual([t.name for t in self.repo.list_tags(a)], ["Alpha", "zeta"])
        with self.assertRaises(RepositoryError):
            self.repo.create_tag(a, "zeta")
        self.repo.create_tag(b, "zeta")  # same name is fine in another workspace
        res = self.repo.add_resource(a, "https://x.y", "X", [zeta.id, alpha.id, foreign.id])
        self.assertEqual(self.repo.list_resource_tags(a), {res.id: sorted([zeta.id, alpha.id])})
        self.repo.update_resource(res.id, "https://x.y", "X", [alpha.id])
        self.assertEqual(self.repo.list_resource_tags(a), {res.id: [alpha.id]})
        self.repo.rename_tag(alpha.id, "Beta")
        self.assertEqual([t.name for t in self.repo.list_tags(a)], ["Beta", "zeta"])
        self.repo.delete_tag(alpha.id)
        self.assertEqual(self.repo.list_resource_tags(a), {})
        self.repo.delete_resource(res.id)
        self.repo.delete_workspace(a)
        self.assertEqual(self.repo.list_tags(a), [])
        self.assertEqual(len(self.repo.list_tags(b)), 2)

    def test_migrates_resources_without_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "old.db"
            first = SqliteTodoRepository(path)
            ws = first.list_workspaces()[0].id
            first.close()
            old = sqlite3.connect(path)
            old.executescript(
                "DROP TABLE resource_tags; DROP TABLE resources;"
                "CREATE TABLE resources (id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT NOT NULL,"
                " created_at TEXT NOT NULL, updated_at TEXT NOT NULL,"
                f" workspace_id INTEGER NOT NULL REFERENCES workspaces(id));"
                f"INSERT INTO resources (uri, created_at, updated_at, workspace_id)"
                f" VALUES ('C:\\docs\\old.pdf', '2026-01-01T00:00:00+00:00', '2026-02-01T00:00:00+00:00', {ws});"
            )
            old.close()
            repo = SqliteTodoRepository(path)
            (res,) = repo.list_resources(ws)
            self.assertEqual(res.name, "old")
            self.assertEqual(res.last_used_at.month, 2)  # updated_at became last_used_at
            repo.close()

    def test_todo_needs_an_existing_workspace(self):
        with self.assertRaises(RepositoryError):
            self.repo.add(9999, DAY, "orphan")

    def test_migrates_database_without_workspaces(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "old.db"
            old = sqlite3.connect(path)
            old.executescript(
                "CREATE TABLE todos (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL,"
                " is_completed INTEGER NOT NULL DEFAULT 0, date TEXT NOT NULL);"
                "INSERT INTO todos (text, date) VALUES ('legacy', '2026-10-01');"
            )
            old.close()
            repo = SqliteTodoRepository(path)
            first = repo.list_workspaces()[0]
            self.assertEqual(first.name, "Personal")
            self.assertEqual([t.text for t in repo.list_todos(first.id)], ["legacy"])
            repo.close()

    def test_backup(self):
        self.assertIsInstance(self.repo, BackupCapable)
        self.repo.add(self.ws, DAY, "keep me")
        with tempfile.TemporaryDirectory() as tmp:
            dest = export_backup(self.repo, Path(tmp), now=datetime(2026, 10, 1, 9, 30))
            self.assertEqual(dest.name, "todos-backup-2026-10-01_09-30-00.db")
            copy = SqliteTodoRepository(dest)
            self.assertEqual([t.text for t in copy.list_todos(self.ws)], ["keep me"])
            copy.close()


if __name__ == "__main__":
    unittest.main()
