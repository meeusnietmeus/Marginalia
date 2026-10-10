import unittest
from datetime import datetime

from PySide6.QtGui import QGuiApplication

from dailytodo.core import Note, describe, search_notes
from dailytodo.core.models import Resource
from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController

T = datetime(2026, 1, 1)


def note(id, rid, page, body, *, q=False, parent=None):
    return Note(id, rid, page, body, q, parent, T, T)


def card(rid, name, uri="https://x.example/a"):
    return describe(Resource(rid, name, uri, T, T), lambda p: True)


CARDS = {1: card(1, "Beta book"), 2: card(2, "Alpha paper")}
NOTES = [
    note(1, 1, 4, "The Basis theorem"),
    note(2, 2, None, "general basis remark"),
    note(3, 2, 2, "What is a basis?", q=True),
    note(4, 2, 2, "A spanning set", parent=3),
    note(5, 2, 7, "BASIS again"),
    note(6, 9, 1, "basis in a resource that is not listed"),
]


class SearchNotesTest(unittest.TestCase):
    def test_empty_search_finds_nothing(self):
        self.assertEqual(search_notes(NOTES, CARDS, "  "), {"total": 0, "groups": []})

    def test_case_insensitive_and_grouped_with_the_busiest_resource_first(self):
        result = search_notes(NOTES, CARDS, "basis")
        self.assertEqual(result["total"], 4)
        self.assertEqual([g["name"] for g in result["groups"]], ["Alpha paper", "Beta book"])
        self.assertEqual([i["id"] for i in result["groups"][0]["items"]], [2, 3, 5])  # General, p2, p7

    def test_kinds_page_labels_and_the_question_an_answer_belongs_to(self):
        items = {i["id"]: i for g in search_notes(NOTES, CARDS, "spanning")["groups"] for i in g["items"]}
        self.assertEqual(items[4]["kind"], "answer")
        self.assertEqual(items[4]["question"], "What is a basis?")
        self.assertEqual(items[4]["pageLabel"], "Page 2")
        question = search_notes(NOTES, CARDS, "what is")["groups"][0]["items"][0]
        self.assertEqual((question["kind"], question["answered"]), ("question", True))
        general = search_notes(NOTES, CARDS, "general")["groups"][0]["items"][0]
        self.assertEqual((general["page"], general["pageLabel"]), (0, "General"))

    def test_the_text_searched_is_what_was_typed_not_the_stored_form(self):
        stored = [note(1, 1, 1, "see @{5|Doc}")]
        plain = lambda body: "see @{Doc}"
        self.assertEqual(search_notes(stored, CARDS, "@{doc}", plain)["total"], 1)
        self.assertEqual(search_notes(stored, CARDS, "5|", plain)["total"], 0)


class SearchControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def test_searches_the_notes_of_the_open_workspace(self):
        repo = SqliteTodoRepository(":memory:")
        ctl = TodoController(repo)
        ctl.addResource("https://a.example/x", "Alpha", [])
        rid = repo.list_resources(ctl.currentWorkspaceId)[0].id
        repo.add_note(rid, 3, "needle in a haystack")
        repo.add_note(rid, None, "hay only")
        result = ctl.searchNotes("Needle")
        self.assertEqual((result["total"], result["groups"][0]["items"][0]["page"]), (1, 3))
        repo.close()


if __name__ == "__main__":
    unittest.main()
