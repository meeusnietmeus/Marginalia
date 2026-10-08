import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path
from unittest import mock

from PySide6.QtGui import QGuiApplication

from dailytodo.core import Highlight, Note, pdf_markdown, safe_file_name
from dailytodo.storage import SqliteTodoRepository, write_text_unique
from dailytodo.ui import TodoController

T = datetime(2026, 1, 1)


def note(id, page, body, *, q=False, parent=None, hl=None):
    return Note(id, 1, page, body, q, parent, T, T, hl)


def highlight(id, page, text, y=100.0, x=72.0):
    return Highlight(id, 1, page, text, ((x, y, 100.0, 18.0),), T)


class MarkdownTest(unittest.TestCase):
    def test_exact_output(self):
        notes = [
            note(1, None, "A general thought"),
            note(2, 3, "About the definition", hl=10),
            note(3, 3, "Why is it so?", q=True, hl=10),
            note(4, 3, "Because of X.\nAnd Y.", parent=3),
            note(5, 3, "A loose note"),
            note(6, 5, "Unanswered one?", q=True),
        ]
        highlights = [
            highlight(10, 3, "the key definition"),
            highlight(11, 3, "an earlier line", y=50),
            highlight(12, 7, "only highlighted"),
        ]
        text = pdf_markdown("Linear algebra", notes, highlights, date(2026, 10, 6))
        self.assertEqual(
            text,
            "# Linear algebra\n"
            "\n"
            "*Exported 6 Oct 2026 · 3 highlights · 3 notes · 2 questions*\n"
            "\n"
            "## General\n"
            "\n"
            "- **Note:** A general thought\n"
            "\n"
            "## Page 3\n"
            "\n"
            "> an earlier line\n"
            "\n"
            "> the key definition\n"
            "\n"
            "- **Note:** About the definition\n"
            "- **Question:** Why is it so?\n"
            "  - **Answer:** Because of X.\n"
            "    And Y.\n"
            "\n"
            "- **Note:** A loose note\n"
            "\n"
            "## Page 5\n"
            "\n"
            "- **Question:** Unanswered one?\n"
            "  - *Not answered yet*\n"
            "\n"
            "## Page 7\n"
            "\n"
            "> only highlighted\n",
        )

    def test_pages_are_in_numeric_order(self):
        notes = [note(1, 10, "ten"), note(2, 2, "two")]
        text = pdf_markdown("T", notes, [], date(2026, 1, 1))
        self.assertLess(text.index("## Page 2"), text.index("## Page 10"))

    def test_multiline_highlight_is_quoted_on_every_line(self):
        text = pdf_markdown("T", [], [highlight(1, 1, "line one\nline two")], date(2026, 1, 1))
        self.assertIn("> line one\n> line two\n", text)

    def test_singular_counts(self):
        text = pdf_markdown("T", [note(1, 1, "n")], [], date(2026, 1, 1))
        self.assertIn("0 highlights · 1 note · 0 questions", text)

    def test_file_names(self):
        self.assertEqual(safe_file_name("Linear algebra"), "Linear algebra - notes.md")
        self.assertEqual(safe_file_name('a/b\\c:d*e?"f<g>h|i'), "a b c d e f g h i - notes.md")
        self.assertEqual(safe_file_name("  ...  "), "PDF - notes.md")
        self.assertLessEqual(len(safe_file_name("x" * 500)), 120)

    def test_files_are_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            first = write_text_unique(Path(folder), "n - notes.md", "one")
            second = write_text_unique(Path(folder), "n - notes.md", "two")
            self.assertEqual(first.name, "n - notes.md")
            self.assertEqual(second.name, "n - notes (2).md")
            self.assertEqual(first.read_text(encoding="utf-8"), "one")
            self.assertEqual(second.read_text(encoding="utf-8"), "two")


class ExportControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo, today=lambda: date(2026, 10, 6))
        self.ctl.addResource("https://example.com/x", "My: book?", [])
        self.rid = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id
        self.messages = []
        self.ctl.notify.connect(self.messages.append)
        self.folder = tempfile.TemporaryDirectory()
        patcher = mock.patch("dailytodo.ui.todo_controller._downloads_folder",
                             return_value=Path(self.folder.name))
        patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self):
        self.repo.close()
        self.folder.cleanup()

    def test_nothing_to_export(self):
        self.ctl.exportPdfMarkdown(self.rid, "My book")
        self.assertEqual(list(Path(self.folder.name).iterdir()), [])
        self.assertIn("Nothing to export", self.messages[-1])

    def test_exports_notes_questions_and_highlights(self):
        h = self.repo.add_highlight(self.rid, 2, "the passage", [(72, 80, 100, 18)])
        self.repo.add_note(self.rid, 2, "my thought", highlight_id=h.id)
        q = self.repo.add_note(self.rid, 4, "what?", is_question=True)
        self.repo.add_note(self.rid, 4, "that.", parent_id=q.id)
        self.repo.add_note(self.rid, None, "global")
        self.ctl.exportPdfMarkdown(self.rid, "My: book?")
        files = list(Path(self.folder.name).iterdir())
        self.assertEqual([f.name for f in files], ["My book - notes.md"])
        text = files[0].read_text(encoding="utf-8")
        for expected in ("# My: book?", "## General", "## Page 2", "> the passage",
                         "- **Note:** my thought", "## Page 4", "- **Answer:** that."):
            self.assertIn(expected, text)
        self.assertIn("Exported to", self.messages[-1])

    def test_a_second_export_gets_its_own_file(self):
        self.repo.add_note(self.rid, 1, "n")
        self.ctl.exportPdfMarkdown(self.rid, "Book")
        self.ctl.exportPdfMarkdown(self.rid, "Book")
        self.assertEqual(sorted(f.name for f in Path(self.folder.name).iterdir()),
                         ["Book - notes (2).md", "Book - notes.md"])


if __name__ == "__main__":
    unittest.main()
