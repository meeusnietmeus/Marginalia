import unittest
from datetime import datetime, timedelta, timezone

from PySide6.QtGui import QGuiApplication

from dailytodo.core import ResourceCard, recently_used, time_ago
from dailytodo.storage import ClientState, SqliteTodoRepository
from dailytodo.ui import TodoController

NOW = datetime(2026, 10, 8, 12, 0, tzinfo=timezone.utc)


def card(id, used_minutes_ago, missing=False):
    when = NOW - timedelta(minutes=used_minutes_ago)
    return ResourceCard(id, f"r{id}", f"https://x/{id}", "web", f"r{id}", False, missing, [], when, when)


class TimeAgoTest(unittest.TestCase):
    def test_steps(self):
        for delta, expected in [
            (timedelta(seconds=20), "just now"),
            (timedelta(minutes=5), "5 min ago"),
            (timedelta(hours=3, minutes=59), "3 h ago"),
            (timedelta(hours=30), "yesterday"),
            (timedelta(days=4), "4 days ago"),
            (timedelta(days=12), "26 Sep"),
        ]:
            self.assertEqual(time_ago(NOW - delta, NOW), expected, delta)


class RecentlyUsedTest(unittest.TestCase):
    def test_newest_first_without_missing_files(self):
        cards = [card(1, 50), card(2, 5), card(3, 1, missing=True), card(4, 20)]
        self.assertEqual([c.id for c in recently_used(cards, 2)], [2, 4])


class RecentResourcesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.state = ClientState(":memory:")
        self.ctl = TodoController(self.repo, client_state=self.state,
                                  now=lambda: datetime.now(timezone.utc))

    def tearDown(self):
        self.repo.close()

    def test_lists_the_last_opened_with_the_page_a_pdf_was_left_on(self):
        self.ctl.addResource("https://example.com/a", "A")
        self.ctl.addResource(r"C:\notes\b.pdf", "B")  # missing on disk: left out
        recent = self.ctl.recentResources
        self.assertEqual([r["name"] for r in recent], ["A"])
        self.assertEqual((recent[0]["page"], recent[0]["when"]), (0, "just now"))

    def test_saving_a_page_announces_a_change(self):
        changes = []
        self.ctl.recentChanged.connect(lambda: changes.append(1))
        self.ctl.savePdfPage(7, 12)
        self.assertEqual(changes, [1])

    def test_how_many_is_chosen_kept_within_1_to_10_and_remembered(self):
        for i in range(12):
            self.ctl.addResource(f"https://example.com/{i}", f"R{i}")
        self.assertEqual((self.ctl.recentCount, len(self.ctl.recentResources)), (4, 4))
        changes = []
        self.ctl.recentChanged.connect(lambda: changes.append(1))
        self.ctl.setRecentCount(7)
        self.assertEqual((self.ctl.recentCount, len(self.ctl.recentResources), changes), (7, 7, [1]))
        self.ctl.setRecentCount(50)
        self.assertEqual(self.ctl.recentCount, 10)
        self.ctl.setRecentCount(0)
        self.assertEqual(self.ctl.recentCount, 1)
        self.ctl.setRecentCount(6)
        again = TodoController(self.repo, client_state=self.state)   # the next start
        self.assertEqual(again.recentCount, 6)

    def test_resource_info_for_its_menu(self):
        self.ctl.addResource("https://example.com/a", "A")
        rid = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id
        info = self.ctl.resourceInfo(rid)
        self.assertEqual((info["id"], info["name"], info["uri"], info["isPath"]),
                         (rid, "A", "https://example.com/a", False))
        self.assertEqual(self.ctl.resourceInfo(9999), {})


if __name__ == "__main__":
    unittest.main()
