import unittest

from PySide6.QtGui import QGuiApplication

from dailytodo.core import group_by_resource, order_for_resource, page_label
from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController


class OpenQuestionsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        self.ctl.addResource("https://a.example/x", "Alpha", [])
        self.ctl.addResource("https://b.example/y", "Beta", [])
        by_name = {r.name: r.id for r in self.repo.list_resources(self.ctl.currentWorkspaceId)}
        self.alpha, self.beta = by_name["Alpha"], by_name["Beta"]
        self.oq = self.ctl.openQuestions

    def tearDown(self):
        self.repo.close()

    def ask(self, rid, page, text="why?"):
        return self.repo.add_note(rid, page, text, is_question=True)

    def open_ids(self):
        return [q.id for q in self.repo.list_open_questions(self.ctl.currentWorkspaceId)]

    def test_nothing_open(self):
        self.oq.refresh()
        self.assertEqual(self.oq.total, 0)
        self.assertEqual(self.oq.resources.rowCount(), 0)

    def test_answered_questions_are_not_open(self):
        open_q = self.ask(self.alpha, 1, "open one")
        done = self.ask(self.alpha, 2, "done one")
        self.repo.add_note(self.alpha, 2, "answer", parent_id=done.id)
        self.repo.add_note(self.alpha, 3, "just a note")
        self.oq.refresh()
        self.assertEqual(self.open_ids(), [open_q.id])
        self.assertEqual(self.oq.total, 1)

    def test_resources_with_counts_most_first(self):
        self.ask(self.alpha, 1)
        for page in (1, 2, 2):
            self.ask(self.beta, page)
        self.oq.refresh()
        rows = [(r.name, r.count) for r in self.oq.resources.rows]
        self.assertEqual(rows, [("Beta", 3), ("Alpha", 1)])

    def test_other_workspaces_are_left_out(self):
        self.ask(self.alpha, 1)
        other = next(w.id for w in self.repo.list_workspaces() if w.id != self.ctl.currentWorkspaceId)
        self.ctl.setWorkspace(other)
        self.assertEqual(self.oq.total, 0)

    def test_select_shows_questions_grouped_by_page(self):
        self.ask(self.beta, 5, "p5 first")
        self.ask(self.beta, 2, "p2")
        self.ask(self.beta, None, "general")
        self.ask(self.beta, 5, "p5 second")
        self.ask(self.alpha, 1, "other resource")
        self.oq.refresh()
        self.oq.select(self.beta)
        shown = [(q.page_label, q.body) for q in self.oq.questions.rows]
        self.assertEqual(
            [(label, body.rstrip("?")) for label, body in shown],
            [("General", "general"), ("Page 2", "p2"), ("Page 5", "p5 first"), ("Page 5", "p5 second")],
        )

    def test_with_no_resource_picked_every_question_shows_resource_by_resource(self):
        self.ask(self.alpha, 1, "a1")
        self.ask(self.beta, 3, "b3")
        self.ask(self.beta, None, "b general")
        self.oq.refresh()
        self.assertEqual(self.oq.selectedResourceId, -1)
        shown = [(q.resource_name, q.page_label, q.body.rstrip("?")) for q in self.oq.questions.rows]
        self.assertEqual(shown, [("Beta", "General", "b general"), ("Beta", "Page 3", "b3"), ("Alpha", "Page 1", "a1")])
        self.assertEqual(self.oq.shownCount, 3)
        self.oq.select(self.alpha)
        self.assertEqual(self.oq.shownCount, 1)
        self.oq.select(-1)
        self.assertEqual(self.oq.shownCount, 3)

    def test_answering_removes_the_question_and_empty_resource(self):
        q = self.ask(self.alpha, 4, "to answer")
        self.oq.refresh()
        self.oq.select(self.alpha)
        self.oq.answer(q.id, "  the answer ")
        self.assertEqual(self.oq.total, 0)
        self.assertEqual(self.oq.selectedResourceId, -1)
        self.assertEqual(self.repo.list_notes(self.alpha, 4)[-1].body, "the answer")

    def test_delete_is_undoable(self):
        q = self.ask(self.alpha, 1)
        offers = []
        self.ctl.undoOffered.connect(lambda token, message: offers.append((token, message)))
        self.oq.refresh()
        self.oq.delete(q.id)
        self.assertEqual(self.oq.total, 0)
        self.assertEqual(offers[0][1], "Question deleted")
        self.ctl.undo(offers[0][0])
        self.assertEqual(self.oq.total, 1)

    def test_edit(self):
        q = self.ask(self.alpha, 1, "old")
        self.oq.refresh()
        self.oq.edit(q.id, "new")
        self.assertTrue(self.repo.get_note_with_answers(q.id)[0].body.startswith("new"))

    def test_page_of(self):
        a = self.ask(self.alpha, 7)
        g = self.ask(self.alpha, None)
        self.oq.refresh()
        self.assertEqual((self.oq.pageOf(a.id), self.oq.pageOf(g.id)), (7, 0))

    def test_open_at_page_goes_to_the_notes_tab_for_non_pdfs(self):
        pdf_tabs, notes_tabs = [], []
        self.ctl.pdfRequested.connect(lambda *a: pdf_tabs.append(a))
        self.ctl.notesRequested.connect(lambda *a: notes_tabs.append(a))
        self.ctl.openResourceAtPage(self.alpha, 3)  # a web link
        self.assertEqual(pdf_tabs, [])
        self.assertEqual(notes_tabs, [(self.alpha, "Alpha", "https://a.example/x", 3)])

    def test_clicking_a_web_link_only_opens_its_notes_tab(self):
        order = []
        self.ctl.notesRequested.connect(lambda *a: order.append(("tab", a[0])))
        self.ctl.openResource = lambda uri: order.append(("external", uri))
        self.ctl.openResourceById(self.alpha)
        self.assertEqual(order, [("tab", self.alpha)])  # "Open link" in the tab opens the page

    def test_noted_pages_for_resources_without_pages(self):
        session = self.ctl.createNotesSession(self.alpha)
        session.loadNow(1)
        self.assertEqual(session.notedPages, [])
        session.addNote("x", False)                       # page 1
        session.setPage(7)
        session.addNote("y", False)
        session.addQuestion("z", False)
        session.addNote("global", True)                   # no page: not listed
        self.assertEqual(session.notedPages, [{"page": 1, "count": 1}, {"page": 7, "count": 2}])

    def test_helpers(self):
        self.assertEqual((page_label(None), page_label(3)), ("General", "Page 3"))
        self.assertEqual(group_by_resource([], {}), [])
        self.assertEqual(order_for_resource([], 1), [])


if __name__ == "__main__":
    unittest.main()
