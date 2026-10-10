import unittest
from datetime import date

from PySide6.QtGui import QGuiApplication

from dailytodo.core import STATUSES, GraphResource, build_graph
from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController


class ResourceStatusTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        self.ctl.addResource("https://a.example/x", "Alpha", [])
        self.rid = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id

    def tearDown(self):
        self.repo.close()

    def status(self):
        return self.repo.list_resources(self.ctl.currentWorkspaceId)[0].status

    def test_a_new_resource_is_unopened(self):
        self.assertEqual(self.status(), "unopened")

    def test_opening_makes_it_opened_but_never_changes_a_status_set_by_hand(self):
        self.ctl.touchResource(self.rid)
        self.assertEqual(self.status(), "opened")
        self.ctl.setResourceStatus(self.rid, "in_progress")
        self.ctl.touchResource(self.rid)
        self.assertEqual(self.status(), "in_progress")

    def test_every_status_can_be_set_and_nonsense_is_refused(self):
        seen = []
        self.ctl.resourceStatusChanged.connect(lambda i, s: seen.append((i, s)))
        for status in STATUSES:
            self.ctl.setResourceStatus(self.rid, status)
            self.assertEqual(self.status(), status)
        self.ctl.setResourceStatus(self.rid, "nonsense")
        self.assertEqual(self.status(), STATUSES[-1])
        self.assertEqual(seen[-1], (self.rid, STATUSES[-1]))
        self.assertEqual(self.ctl.resourceInfo(self.rid)["status"], STATUSES[-1])

    def test_the_graph_carries_the_status(self):
        graph = build_graph([GraphResource(1, "Doc", "pdf", False, (), (), "finished")], [])
        self.assertEqual(graph.nodes[0].status, "finished")

    def test_resources_opened_before_statuses_existed_count_as_opened(self):
        import sqlite3
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "old.db"
            repo = SqliteTodoRepository(str(path))
            ws = repo.list_workspaces()[0].id
            a = repo.add_resource(ws, "https://a.example", "A")
            b = repo.add_resource(ws, "https://b.example", "B")
            repo.touch_resource(b.id)
            repo.close()
            conn = sqlite3.connect(path)
            conn.execute("UPDATE resources SET status = 'unopened'")
            conn.execute("ALTER TABLE resources DROP COLUMN status")
            conn.commit()
            conn.close()
            repo = SqliteTodoRepository(str(path))
            got = {r.name: r.status for r in repo.list_resources(ws)}
            repo.close()
        self.assertEqual(got, {"A": "unopened", "B": "opened"})


if __name__ == "__main__":
    unittest.main()
