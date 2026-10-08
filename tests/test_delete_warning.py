import unittest
from datetime import date

from PySide6.QtGui import QGuiApplication

from dailytodo.core import delete_warning
from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController


class DeleteWarningTextTest(unittest.TestCase):
    def test_nothing_attached(self):
        text = delete_warning("Book", 0, 0, 0)
        self.assertEqual(text, 'Delete "Book"? Deleting a resource cannot be undone.')
        self.assertNotIn("attached", text)

    def test_lists_what_is_attached(self):
        text = delete_warning("Book", 3, 1, 2)
        self.assertIn("It has 3 notes, 1 question and 2 todos attached", text)
        self.assertIn("deleted with it", text)
        self.assertIn("broken link", text)
        self.assertIn("cannot be undone", text)

    def test_only_mentions_relevant_consequences(self):
        self.assertNotIn("broken link", delete_warning("Book", 1, 0, 0))
        self.assertNotIn("deleted with it", delete_warning("Book", 0, 0, 1))
        self.assertIn("It has 1 note attached", delete_warning("Book", 1, 0, 0))


class DeleteWarningControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        self.ctl.addResource("https://example.com/doc", "Doc", [])
        self.rid = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id

    def tearDown(self):
        self.repo.close()

    def test_empty_resource(self):
        self.assertNotIn("attached", self.ctl.deleteResourceWarning(self.rid, "Doc"))

    def test_counts_notes_questions_answers_and_todos(self):
        self.repo.add_note(self.rid, 1, "a note")
        self.repo.add_note(self.rid, None, "global note")
        question = self.repo.add_note(self.rid, 2, "why", is_question=True)
        self.repo.add_note(self.rid, 2, "because", parent_id=question.id)  # not counted
        self.ctl.addTodo(date.today().isoformat(), "read @{Doc}")
        self.ctl.addTodo(date.today().isoformat(), "unrelated")
        text = self.ctl.deleteResourceWarning(self.rid, "Doc")
        self.assertIn("2 notes, 1 question and 1 todo attached", text)


if __name__ == "__main__":
    unittest.main()
