"""Qt-side tests. Run with QT_QPA_PLATFORM=offscreen on a machine without a display."""
import unittest
from datetime import date, timedelta

from PySide6.QtGui import QGuiApplication

from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController

THU = date(2026, 10, 1)


class TodoControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.today = THU
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo, today=lambda: self.today)
        self.model = self.ctl.days

    def tearDown(self):
        self.repo.close()

    def role(self, row, name):
        role = next(r for r, n in self.model.roleNames().items() if n == name.encode())
        return self.model.data(self.model.index(row), role)

    def test_add_updates_only_that_row(self):
        changed = []
        self.model.dataChanged.connect(lambda a, b: changed.append(a.row()))
        count = self.model.rowCount()
        self.ctl.addTodo(THU.isoformat(), "  hello  ")
        self.assertEqual(self.model.rowCount(), count)
        self.assertEqual(changed, [0])
        self.assertEqual(self.role(0, "todos")[0]["text"], "hello")

    def test_switching_workspace_loads_its_todos(self):
        personal, work = (w["id"] for w in self.ctl.workspaces[:2])
        self.assertEqual(self.ctl.currentWorkspaceId, personal)
        self.ctl.addTodo(THU.isoformat(), "personal todo")
        self.ctl.setWorkspace(work)
        self.assertEqual(self.ctl.currentWorkspaceId, work)
        self.assertEqual(self.role(0, "todos"), [])
        self.ctl.addTodo(THU.isoformat(), "work todo")
        self.assertEqual(self.role(0, "todos")[0]["text"], "work todo")
        self.ctl.setWorkspace(personal)
        self.assertEqual([t["text"] for t in self.role(0, "todos")], ["personal todo"])

    def workspace_folder(self, name):
        import tempfile
        folder = tempfile.mkdtemp(prefix=f"ws-{name}-")
        self.addCleanup(__import__("shutil").rmtree, folder, True)
        return folder

    def test_create_workspace_opens_it(self):
        self.ctl.addTodo(THU.isoformat(), "personal todo")
        self.ctl.createWorkspace("  Gym  ", self.workspace_folder("gym"))
        self.assertEqual(self.ctl.workspaces[-1]["name"], "Gym")
        self.assertEqual(self.ctl.currentWorkspaceId, self.ctl.workspaces[-1]["id"])
        self.assertEqual(self.role(0, "todos"), [])
        count = len(self.ctl.workspaces)
        self.ctl.createWorkspace("gym", self.workspace_folder("gym2"))  # duplicate (case-insensitive) is rejected
        self.ctl.createWorkspace("   ", self.workspace_folder("blank"))
        self.assertEqual(len(self.ctl.workspaces), count)

    def test_move_all_to_today(self):
        self.ctl.addTodo(THU.isoformat(), "late")
        self.today = THU + timedelta(days=1)
        self.ctl.checkNewDay()
        self.ctl.moveAllToToday(THU.isoformat())
        self.assertEqual([t["text"] for t in self.role(0, "todos")], ["late"])

    def test_rename_and_delete_workspace(self):
        first = self.ctl.workspaces[0]["id"]
        self.ctl.renameWorkspace("  Home ")
        self.assertEqual(self.ctl.workspaces[0]["name"], "Home")
        self.ctl.renameWorkspace("work")  # taken by another workspace
        self.assertEqual(self.ctl.workspaces[0]["name"], "Home")
        self.ctl.addTodo(THU.isoformat(), "bye")
        self.ctl.deleteWorkspace()
        self.assertEqual(len(self.ctl.workspaces), 2)
        self.assertNotEqual(self.ctl.currentWorkspaceId, first)
        self.assertEqual(self.role(0, "todos"), [])

    def test_cannot_delete_last_workspace(self):
        for _ in range(3):
            self.ctl.deleteWorkspace()
        self.assertEqual(len(self.ctl.workspaces), 1)

    def test_resources_follow_the_workspace(self):
        res = self.ctl.resources
        self.ctl.addResource("https://example.com/y", "  ")  # a name is required
        self.ctl.addResource("  https://example.com/x ", "x")
        self.ctl.addResource("not a link", "n")  # rejected
        self.assertEqual(res.rowCount(), 1)
        self.assertEqual((res.rows[0].kind, res.rows[0].name), ("web", "x"))
        rid = res.rows[0].id
        self.ctl.updateResource(rid, r"C:\definitely\missing\file.pdf", "Mine")
        self.assertEqual((res.rows[0].kind, res.rows[0].missing, res.rows[0].title), ("pdf", True, "Mine"))
        self.ctl.deleteResource(rid)
        self.assertEqual(res.rowCount(), 0)
        self.ctl.addResource("https://example.com", "e")
        self.ctl.setWorkspace(self.ctl.workspaces[1]["id"])
        self.assertEqual(res.rowCount(), 0)
        self.ctl.setWorkspace(self.ctl.workspaces[0]["id"])
        self.assertEqual(res.rowCount(), 1)

    def test_tags(self):
        self.ctl.createTag("  reading ")
        self.ctl.createTag("Reading")  # duplicate, ignored
        self.assertEqual([t.name for t in self.ctl.tags.rows], ["reading"])
        tag_id = self.ctl.tags.rows[0].id
        self.ctl.addResource("https://example.com", "e", [float(tag_id)])
        self.assertEqual(self.ctl.resources.rows[0].tag_ids, [tag_id])
        self.ctl.setWorkspace(self.ctl.workspaces[1]["id"])
        self.assertEqual(self.ctl.tags.rowCount(), 0)

    def test_rename_and_delete_tag(self):
        self.ctl.createTag("a")
        self.ctl.createTag("b")
        a, b = (t.id for t in self.ctl.tags.rows)
        self.ctl.addResource("https://example.com", "e", [a, b])
        self.ctl.updateTag(a, "b", -1)  # taken
        self.assertEqual([t.name for t in self.ctl.tags.rows], ["a", "b"])
        self.ctl.updateTag(a, "z", -1)
        self.assertEqual([t.name for t in self.ctl.tags.rows], ["b", "z"])
        self.ctl.deleteTag(a)
        self.assertEqual([t.name for t in self.ctl.tags.rows], ["b"])
        self.assertEqual(self.ctl.resources.rows[0].tag_ids, [b])

    def test_inline_references_in_todos(self):
        self.ctl.addResource("https://example.com", "Quarterly report")
        self.ctl.createTag("work")
        rid, tid = self.ctl.resources.rows[0].id, self.ctl.tags.rows[0].id
        self.ctl.addTodo(THU.isoformat(), "review @{quarterly REPORT} for !{work} and @{nothing}")
        stored = self.role(0, "todos")[0]["text"]
        self.assertEqual(stored, f"review @{{{rid}|Quarterly report}} for !{{{tid}|work}} and @{{nothing}}")
        self.assertEqual(self.ctl.toEditText(stored), "review @{Quarterly report} for !{work} and @{nothing}")
        kinds = [p["type"] for p in self.ctl.segments(stored, self.ctl.referencesRevision)]
        self.assertEqual(kinds, ["text", "resource", "text", "tag", "text"])
        # renaming the resource changes how the todo reads, without touching the todo
        self.ctl.updateResource(rid, "https://example.com", "Annual report")
        names = [p["text"] for p in self.ctl.segments(stored, self.ctl.referencesRevision) if p["type"] == "resource"]
        self.assertEqual(names, ["Annual report"])
        # deleting it leaves a missing link, still showing the saved name
        self.ctl.deleteResource(rid)
        gone = [p for p in self.ctl.segments(stored, self.ctl.referencesRevision) if p["type"] == "resource"][0]
        self.assertEqual((gone["missing"], gone["text"]), (True, "Quarterly report"))

    def test_search_references(self):
        for n in ("alpha", "Alphabet soup", "beta", "gamma", "delta", "epsilon", "zeta"):
            self.ctl.createTag(n)
        self.assertEqual([r["name"] for r in self.ctl.searchReferences("!", "alph")], ["alpha", "Alphabet soup"])
        self.assertEqual(len(self.ctl.searchReferences("!", "")), 5)  # top five only
        self.assertEqual(self.ctl.searchReferences("@", "x"), [])  # no resources yet

    def test_library_search_filter_and_sort(self):
        for name in ("Banana", "apple", "Cherry"):
            self.ctl.addResource("https://example.com/" + name.lower(), name)
        self.ctl.createTag("fruit")
        names = lambda: [c.name for c in self.ctl.resources.rows]
        self.assertEqual(self.ctl.resourceSort, "recent")
        self.assertEqual(names(), ["Cherry", "apple", "Banana"])  # newest first: nothing was used yet
        # opening a resource makes it the most recently used
        banana = next(c for c in self.ctl.resources.rows if c.name == "Banana")
        import time
        time.sleep(0.01)  # timestamps have millisecond resolution
        self.ctl.touchResource(banana.id)
        self.assertEqual(names()[0], "Banana")  # re-sorted at once, no refresh needed
        self.ctl.setResourceSort("name")
        self.assertEqual(names(), ["apple", "Banana", "Cherry"])
        self.ctl.setResourceQuery(" AN ")
        self.assertEqual(names(), ["Banana"])
        self.assertTrue(self.ctl.resourceFilterActive)
        self.assertEqual(self.ctl.resourceTotal, 3)
        self.ctl.setResourceQuery("")
        fruit = self.ctl.tags.rows[0].id
        self.ctl.updateResource(banana.id, banana.uri, "Banana", [fruit])
        self.ctl.toggleResourceTag(fruit)
        self.assertEqual((names(), self.ctl.resourceTagFilter), (["Banana"], [fruit]))
        self.ctl.toggleResourceTag(fruit)  # unselect
        self.assertEqual(len(names()), 3)
        self.assertFalse(self.ctl.resourceFilterActive)
        self.ctl.toggleResourceTag(fruit)
        self.ctl.deleteTag(fruit)  # a deleted tag no longer filters
        self.assertEqual(len(names()), 3)

    def test_undo_a_deleted_todo(self):
        offers = []
        self.ctl.undoOffered.connect(lambda token, message: offers.append((token, message)))
        self.ctl.addTodo(THU.isoformat(), "first")
        self.ctl.addTodo(THU.isoformat(), "second")
        self.ctl.addTodo(THU.isoformat(), "third")
        second = self.role(0, "todos")[1]
        self.ctl.setDone(second["id"], True)
        self.ctl.deleteTodo(second["id"])
        self.assertEqual([t["text"] for t in self.role(0, "todos")], ["first", "third"])
        self.assertEqual(len(offers), 1)
        self.assertEqual(offers[0][1], "Deleted \"second\"")
        self.ctl.undo(offers[0][0])
        todos = self.role(0, "todos")
        self.assertEqual([t["text"] for t in todos], ["first", "second", "third"])  # same place
        self.assertTrue(todos[1]["done"])  # and still done
        self.ctl.undo(offers[0][0])  # a second undo of the same toast does nothing
        self.assertEqual(len(self.role(0, "todos")), 3)

    def test_expired_undo_is_final(self):
        offers = []
        self.ctl.undoOffered.connect(lambda token, message: offers.append(token))
        self.ctl.addTodo(THU.isoformat(), "gone for good")
        self.ctl.deleteTodo(self.role(0, "todos")[0]["id"])
        self.ctl.expireUndo(offers[0])  # the toast timed out
        self.ctl.undo(offers[0])
        self.assertEqual(self.role(0, "todos"), [])

    def test_two_deletes_can_be_undone_separately(self):
        offers = []
        self.ctl.undoOffered.connect(lambda token, message: offers.append(token))
        self.ctl.addTodo(THU.isoformat(), "a")
        self.ctl.addTodo(THU.isoformat(), "b")
        a, b = (t["id"] for t in self.role(0, "todos"))
        self.ctl.deleteTodo(a)
        self.ctl.deleteTodo(b)
        self.ctl.undo(offers[0])
        self.assertEqual([t["text"] for t in self.role(0, "todos")], ["a"])
        self.ctl.undo(offers[1])
        self.assertEqual([t["text"] for t in self.role(0, "todos")], ["a", "b"])

    def test_backlog(self):
        offers = []
        self.ctl.undoOffered.connect(lambda token, message: offers.append(token))
        texts = lambda: [b.text for b in self.ctl.backlog.rows]
        self.ctl.addBacklogTodo("  read chapter 3  ")
        self.ctl.addBacklogTodo("   ")  # ignored
        self.assertEqual(texts(), ["read chapter 3"])
        self.assertEqual([t["text"] for t in self.role(0, "todos")], [])  # not on the timeline
        todo_id = self.ctl.backlog.rows[0].id
        self.ctl.setDone(todo_id, True)
        self.assertTrue(self.ctl.backlog.rows[0].done)
        # backlog -> timeline (only days the timeline shows)
        self.ctl.moveToTimeline(todo_id, (THU + timedelta(days=60)).isoformat())
        self.assertEqual(texts(), ["read chapter 3"])  # refused
        self.ctl.moveToTimeline(todo_id, (THU + timedelta(days=1)).isoformat())
        self.assertEqual(texts(), [])
        self.assertEqual([(t["text"], t["done"]) for t in self.role(1, "todos")], [("read chapter 3", True)])
        # timeline -> backlog keeps text and done state
        self.ctl.moveToBacklog(todo_id)
        self.assertEqual([(b.text, b.done) for b in self.ctl.backlog.rows], [("read chapter 3", True)])
        self.assertEqual([t["text"] for t in self.role(1, "todos")], [])
        # editing and deleting (with undo) work the same for backlog todos
        self.ctl.editTodo(todo_id, "read chapter 4")
        self.ctl.deleteTodo(todo_id)
        self.assertEqual(texts(), [])
        self.ctl.undo(offers[-1])
        self.assertEqual(texts(), ["read chapter 4"])
        bounds = self.ctl.timelineRange()
        self.assertEqual(bounds["min"], THU.isoformat())
        self.assertEqual(bounds["max"], "2026-10-11")  # Sunday of next week

    def test_resorting_moves_rows_instead_of_resetting(self):
        res = self.ctl.resources
        for name in ("a", "b", "c"):
            self.ctl.addResource("https://example.com/" + name, name)
        events = []
        res.modelReset.connect(lambda: events.append("reset"))
        res.rowsMoved.connect(lambda *args: events.append("move"))
        self.ctl.setResourceSort("name")  # c b a -> a b c
        self.assertEqual([c.name for c in res.rows], ["a", "b", "c"])
        self.assertNotIn("reset", events)
        self.assertIn("move", events)

    def test_open_resource_by_id_ignores_the_library_filter(self):
        messages = []
        self.ctl.notify.connect(messages.append)
        self.ctl.addResource(r"C:\definitely\missing\file.pdf", "Mine")
        rid = self.ctl.resources.rows[0].id
        self.ctl.setResourceQuery("something else")  # the library hides it now
        self.assertEqual(self.ctl.resources.rowCount(), 0)
        self.ctl.openResourceById(rid)
        self.assertEqual(messages[-1], "File not found: Mine")

    def test_deleting_resources_reports_them_removed(self):
        removed = []
        self.ctl.resourceRemoved.connect(removed.append)
        self.ctl.addResource("https://example.com/a", "a")
        self.ctl.addResource("https://example.com/b", "b")
        a, b = sorted(c.id for c in self.ctl.resources.rows)
        self.ctl.deleteResource(a)
        self.assertEqual(removed, [a])
        self.ctl.deleteWorkspace()  # takes its remaining resources with it
        self.assertEqual(removed, [a, b])

    def test_refreshing_unchanged_resources_does_not_rerender_todos(self):
        self.ctl.addResource("https://example.com", "e")
        revision = self.ctl.referencesRevision
        self.ctl.refreshResources()  # e.g. the window got focus again
        self.ctl.touchResource(self.ctl.resources.rows[0].id)
        self.assertEqual(self.ctl.referencesRevision, revision)

    def test_rollover_keeps_missed_day(self):
        self.ctl.addTodo(THU.isoformat(), "late")
        self.today = THU + timedelta(days=1)
        self.ctl.checkNewDay()
        self.assertEqual(self.role(0, "dayKind"), "past")


if __name__ == "__main__":
    unittest.main()
