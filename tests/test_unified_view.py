import unittest
from datetime import datetime

from PySide6.QtGui import QGuiApplication

from dailytodo.core import Highlight, Note, unified_rows
from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController

T = datetime(2026, 1, 1)


def note(id, page, body, *, q=False, parent=None, hl=None):
    return Note(id, 1, page, body, q, parent, T, T, hl)


def highlight(id, page, text, y=100.0):
    return Highlight(id, 1, page, text, ((72.0, y, 100.0, 18.0),), T)


NOTES = [
    note(1, 3, "late note"),
    note(2, None, "general"),
    note(3, 3, "why?", q=True),
    note(4, 3, "because", parent=3),
    note(5, 3, "about the top", hl=10),
    note(6, 1, "open question", q=True),
    note(7, 3, "about the bottom", hl=11),
]
HIGHLIGHTS = [highlight(10, 3, "top passage", y=50), highlight(11, 3, "bottom passage", y=400)]


def labels(result):
    return [r["label"] if r["kind"] == "page" else r["body"] for r in result["rows"]]


class UnifiedRowsTest(unittest.TestCase):
    def test_general_first_then_pages_with_quoted_notes_in_reading_order(self):
        self.assertEqual(
            labels(unified_rows(NOTES, HIGHLIGHTS)),
            ["General", "general", "Page 1", "open question",
             "Page 3", "about the top", "about the bottom", "late note", "why?"],
        )

    def test_answers_sit_under_their_question_and_quotes_come_along(self):
        rows = unified_rows(NOTES, HIGHLIGHTS)["rows"]
        question = next(r for r in rows if r["kind"] == "thread" and r["id"] == 3)
        self.assertEqual([a["body"] for a in question["answers"]], ["because"])
        self.assertTrue(question["answered"])
        top = next(r for r in rows if r["kind"] == "thread" and r["id"] == 5)
        self.assertEqual(top["quote"], "top passage")

    def test_counts_ignore_the_filter(self):
        result = unified_rows(NOTES, HIGHLIGHTS, mode="unanswered")
        self.assertEqual((result["notes"], result["questions"], result["unanswered"]), (4, 2, 1))
        self.assertEqual(labels(result), ["Page 1", "open question"])

    def test_filters_drop_pages_that_end_up_empty(self):
        self.assertEqual(labels(unified_rows(NOTES, HIGHLIGHTS, mode="questions")),
                         ["Page 1", "open question", "Page 3", "why?"])
        self.assertNotIn("Page 1", labels(unified_rows(NOTES, HIGHLIGHTS, mode="notes")))

    def test_slides_and_plain_text(self):
        result = unified_rows([note(1, 2, "@{5|Doc}")], [], plain=lambda b: "@{Doc}", slides=True)
        self.assertEqual(result["rows"][0]["label"], "Slide 2")
        self.assertEqual(result["rows"][1]["text"], "@{Doc}")


class UnifiedControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def test_notes_come_back_with_names_as_typed_and_unknown_filters_mean_all(self):
        repo = SqliteTodoRepository(":memory:")
        ctl = TodoController(repo)
        ctl.addResource("https://a.example/x", "Alpha", [])
        rid = repo.list_resources(ctl.currentWorkspaceId)[0].id
        repo.add_note(rid, 2, f"see @{{{rid}|Alpha}}")
        repo.add_note(rid, 2, "why?", is_question=True)
        rows = ctl.unifiedNotes(rid, "nonsense")["rows"]
        self.assertEqual([r["kind"] for r in rows], ["page", "thread", "thread"])
        self.assertEqual(rows[1]["text"], "see @{Alpha}")
        self.assertEqual(len(ctl.unifiedNotes(rid, "questions")["rows"]), 2)
        repo.close()


if __name__ == "__main__":
    unittest.main()
