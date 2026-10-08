import unittest
from datetime import date

from PySide6.QtCore import QEventLoop, QTimer
from PySide6.QtGui import QGuiApplication

from dailytodo.core import with_question_mark
from dailytodo.storage import RepositoryError, SqliteTodoRepository
from dailytodo.ui import NotesSession


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


class QuestionMarkTest(unittest.TestCase):
    def test_rule(self):
        for given, expected in [
            ("why does it work", "why does it work?"),
            ("already a question?", "already a question?"),
            ("  spaces around  ", "spaces around?"),
            ("ends with a full stop.", "ends with a full stop?"),
            ("trailing space after mark?  ", "trailing space after mark?"),
            ("what is x?!", "what is x?!?"),
            ("full width？", "full width？"),
            ("   ", ""),
        ]:
            self.assertEqual(with_question_mark(given), expected, given)


class NotesRepositoryTest(unittest.TestCase):
    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        ws = self.repo.list_workspaces()[0].id
        self.res = self.repo.add_resource(ws, r"C:\a.pdf", "a").id
        self.other = self.repo.add_resource(ws, r"C:\b.pdf", "b").id

    def tearDown(self):
        self.repo.close()

    def test_notes_are_found_by_resource_and_page(self):
        self.repo.add_note(self.res, 3, "on three")
        self.repo.add_note(self.res, 3, "also three")
        self.repo.add_note(self.res, 4, "on four")
        self.repo.add_note(self.res, None, "about the whole pdf")
        self.repo.add_note(self.other, 3, "other pdf")
        self.assertEqual([n.body for n in self.repo.list_notes(self.res, 3)], ["on three", "also three"])
        self.assertEqual([n.body for n in self.repo.list_notes(self.res, None)], ["about the whole pdf"])
        self.assertEqual(self.repo.list_notes(self.res, 9), [])

    def test_note_rules(self):
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.res, 1, "  ")
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.res, 0, "page numbers start at 1")
        with self.assertRaises(RepositoryError):
            self.repo.add_note(9999, 1, "no such resource")

    def test_notes_go_with_their_resource(self):
        self.repo.add_note(self.res, 1, "x")
        other = self.repo.add_note(self.other, 1, "kept")
        self.repo.delete_resource(self.res)
        self.assertEqual(self.repo.list_notes(self.res, 1), [])
        self.assertEqual(self.repo.list_notes(self.other, 1), [other])
        count = self.repo._conn.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
        self.assertEqual(count, 1)  # no orphaned rows left behind

    def test_notes_go_when_the_whole_workspace_is_deleted(self):
        ws = self.repo.list_workspaces()[0].id
        self.repo.add_note(self.res, 1, "x")
        self.repo.add_note(self.other, None, "y")
        self.repo.delete_workspace(ws)  # workspace -> resources -> notes
        count = self.repo._conn.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
        self.assertEqual(count, 0)

    def test_questions_and_answers(self):
        q = self.repo.add_note(self.res, 4, "why?", is_question=True)
        a1 = self.repo.add_note(self.res, 99, "because", parent_id=q.id)  # page comes from the question
        plain = self.repo.add_note(self.res, 4, "just a note")
        self.assertEqual((a1.page, a1.parent_id, a1.is_question), (4, q.id, False))
        stored = {n.id: n for n in self.repo.list_notes(self.res, 4)}
        self.assertEqual(set(stored), {q.id, a1.id, plain.id})
        self.assertTrue(stored[q.id].is_question)
        self.assertIsNone(stored[plain.id].parent_id)
        # rules
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.res, 4, "x", parent_id=plain.id)  # parent must be a question
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.other, 4, "x", parent_id=q.id)  # ... of the same resource
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.res, 4, "x", is_question=True, parent_id=q.id)  # no question answers
        # deleting the question deletes its answers, nothing else
        self.repo.delete_note(q.id)
        self.assertEqual([n.id for n in self.repo.list_notes(self.res, 4)], [plain.id])

    def test_questions_get_their_question_mark_in_the_database(self):
        q = self.repo.add_note(self.res, 1, "how come", is_question=True)
        self.assertEqual(q.body, "how come?")
        self.assertEqual(self.repo.list_notes(self.res, 1)[0].body, "how come?")
        self.repo.update_note(q.id, "why exactly")
        self.assertEqual(self.repo.list_notes(self.res, 1)[0].body, "why exactly?")
        # notes and answers are left alone
        note = self.repo.add_note(self.res, 1, "no mark here")
        answer = self.repo.add_note(self.res, 1, "because", parent_id=q.id)
        self.repo.update_note(answer.id, "because of x")
        bodies = {n.id: n.body for n in self.repo.list_notes(self.res, 1)}
        self.assertEqual((bodies[note.id], bodies[answer.id]), ("no mark here", "because of x"))
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.res, 1, "   ", is_question=True)  # blank is still rejected

    def test_move_between_global_and_local(self):
        note = self.repo.add_note(self.res, 3, "a note")
        q = self.repo.add_note(self.res, 3, "why?", is_question=True)
        a = self.repo.add_note(self.res, 3, "because", parent_id=q.id)
        self.repo.move_note(note.id, None)
        self.assertEqual([n.body for n in self.repo.list_notes(self.res, None)], ["a note"])
        self.repo.move_note(note.id, 9)
        self.assertEqual([n.body for n in self.repo.list_notes(self.res, 9)], ["a note"])
        # moving an answer moves its whole thread: the question and every answer share a page
        self.repo.move_note(a.id, None)
        self.assertEqual({n.body for n in self.repo.list_notes(self.res, None)}, {"why?", "because"})
        self.repo.move_note(q.id, 4)
        self.assertEqual({n.body for n in self.repo.list_notes(self.res, 4)}, {"why?", "because"})
        with self.assertRaises(RepositoryError):
            self.repo.move_note(note.id, 0)
        with self.assertRaises(RepositoryError):
            self.repo.move_note(9999, 1)

    def test_migrates_notes_without_questions(self):
        import sqlite3
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "old.db"
            first = SqliteTodoRepository(path)
            ws = first.list_workspaces()[0].id
            rid = first.add_resource(ws, "https://a.b", "a").id
            first.close()
            old = sqlite3.connect(path)
            old.executescript(
                "DROP TABLE notes;"
                "CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT,"
                " resource_id INTEGER NOT NULL REFERENCES resources(id) ON DELETE CASCADE,"
                " page INTEGER, body TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);"
                f"INSERT INTO notes (resource_id, page, body, created_at, updated_at)"
                f" VALUES ({rid}, 2, 'old note', '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:00+00:00');"
            )
            old.close()
            repo = SqliteTodoRepository(path)
            (n,) = repo.list_notes(rid, 2)
            self.assertEqual((n.body, n.is_question, n.parent_id), ("old note", False, None))
            q = repo.add_note(rid, 2, "q?", is_question=True)
            repo.add_note(rid, 2, "a", parent_id=q.id)
            repo.close()

    def test_snapshot_and_restore_a_question_thread(self):
        q = self.repo.add_note(self.res, 6, "why?", is_question=True)
        a1 = self.repo.add_note(self.res, 6, "because", parent_id=q.id)
        a2 = self.repo.add_note(self.res, 6, "also", parent_id=q.id)
        other = self.repo.add_note(self.res, 6, "unrelated")
        snapshot = self.repo.get_note_with_answers(q.id)
        self.assertEqual([n.id for n in snapshot], [q.id, a1.id, a2.id])  # the question first
        self.assertEqual([n.id for n in self.repo.get_note_with_answers(a1.id)], [a1.id])
        self.assertEqual(self.repo.get_note_with_answers(9999), [])
        self.repo.delete_note(q.id)
        self.assertEqual([n.id for n in self.repo.list_notes(self.res, 6)], [other.id])
        self.repo.restore_notes(snapshot)
        restored = self.repo.list_notes(self.res, 6)
        self.assertEqual([n.id for n in restored], [q.id, a1.id, a2.id, other.id])
        self.assertEqual(restored[1].parent_id, q.id)
        self.assertEqual(restored[0].created_at, q.created_at)  # not a fresh note

    def test_edit_and_delete_note(self):
        note = self.repo.add_note(self.res, 2, "first")
        self.repo.update_note(note.id, "second")
        (stored,) = self.repo.list_notes(self.res, 2)
        self.assertEqual((stored.body, stored.page), ("second", 2))
        self.assertGreaterEqual(stored.updated_at, stored.created_at)
        with self.assertRaises(RepositoryError):
            self.repo.update_note(note.id, " ")
        self.repo.delete_note(note.id)
        self.assertEqual(self.repo.list_notes(self.res, 2), [])


class SpyRepo(SqliteTodoRepository):
    def __init__(self):
        super().__init__(":memory:")
        self.note_queries = []

    def list_notes(self, resource_id, page):
        self.note_queries.append(page)
        return super().list_notes(resource_id, page)


class NotesSessionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SpyRepo()
        ws = self.repo.list_workspaces()[0].id
        self.res = self.repo.add_resource(ws, r"C:\a.pdf", "a").id
        self.repo.add_note(self.res, 50, "fifty")
        self.session = NotesSession(self.repo, self.res, debounce_ms=30)

    def tearDown(self):
        self.repo.close()

    def test_scrolling_fast_queries_only_the_final_page(self):
        for page in range(1, 51):
            self.session.setPage(page)
        self.assertEqual(self.repo.note_queries, [])  # nothing yet
        wait(150)
        self.assertEqual(self.repo.note_queries, [50])
        self.assertEqual([n.body for n in self.session.notes.rows], ["fifty"])

    def test_loading_flag_covers_the_wait(self):
        changes = []
        self.session.loadingChanged.connect(lambda: changes.append(self.session.loading))
        self.session.setPage(3)
        self.assertTrue(self.session.loading)
        wait(150)
        self.assertFalse(self.session.loading)
        self.assertEqual(changes, [True, False])

    def test_session_splits_notes_from_questions_and_answers(self):
        self.session.loadNow(8)
        self.session.addNote("note")
        self.session.addQuestion("question one?")
        self.session.addQuestion("question two?")
        q1, q2 = (n for n in self.session.questions.rows if n.is_question)
        self.session.addAnswer(q1.id, "answer to one")
        self.session.addAnswer(q2.id, "answer to two")
        self.session.addAnswer(q1.id, "second answer to one")
        self.assertEqual([n.body for n in self.session.notes.rows], ["note"])
        self.assertEqual(
            [n.body for n in self.session.questions.rows],
            ["question one?", "answer to one", "second answer to one", "question two?", "answer to two"],
        )

    def test_global_notes_and_the_answered_flag(self):
        self.session.loadNow(2)
        self.session.addNote("local note")
        self.session.addNote("global note", True)
        self.session.addQuestion("global question?", True)
        self.session.addQuestion("local question?")
        self.assertEqual([n.body for n in self.session.notes.rows], ["local note"])
        self.assertEqual([n.body for n in self.session.globalNotes.rows], ["global note"])
        self.assertTrue(all(n.is_global for n in self.session.globalNotes.rows))
        local_q = self.session.questions.rows[0]
        global_q = self.session.globalQuestions.rows[0]
        self.assertEqual((local_q.body, local_q.answered), ("local question?", False))
        self.session.addAnswer(local_q.id, "yes")
        self.session.addAnswer(global_q.id, "no")
        self.assertEqual([(n.body, n.answered) for n in self.session.questions.rows],
                         [("local question?", True), ("yes", False)])
        self.assertEqual([n.body for n in self.session.globalQuestions.rows], ["global question?", "no"])
        # moving: local note -> global, global note -> this page
        self.session.moveToGlobal(self.session.notes.rows[0].id)
        self.assertEqual(list(self.session.notes.rows), [])
        self.assertEqual(sorted(n.body for n in self.session.globalNotes.rows), ["global note", "local note"])
        self.session.moveToPage(self.session.globalNotes.rows[0].id, 2)
        self.assertEqual(len(self.session.notes.rows), 1)
        self.assertEqual(len(self.session.globalNotes.rows), 1)

    def test_no_undo_is_offered_when_the_delete_fails(self):
        offered, errors = [], []
        session = NotesSession(self.repo, self.res, debounce_ms=30,
                               undo_sink=lambda message, restore: offered.append(message))
        session.error.connect(errors.append)
        session.loadNow(50)
        note = session.notes.rows[0]

        def broken(note_id):
            raise RepositoryError("disk full")

        self.repo.delete_note = broken
        session.deleteNote(note.id)
        self.assertEqual(offered, [])
        self.assertEqual(errors, ["Couldn't delete: disk full"])
        self.assertEqual([n.body for n in session.notes.rows], ["fifty"])

    def test_session_offers_undo_for_deleted_notes(self):
        offered = []
        session = NotesSession(self.repo, self.res, debounce_ms=30,
                               undo_sink=lambda message, restore: offered.append((message, restore)))
        session.loadNow(4)
        session.addQuestion("why", False)
        q = session.questions.rows[0]
        session.addAnswer(q.id, "a")
        session.addAnswer(q.id, "b")
        session.addNote("plain")
        note = session.notes.rows[0]
        session.deleteNote(note.id)
        self.assertEqual(offered[-1][0], "Note deleted")
        self.assertEqual(list(session.notes.rows), [])
        offered[-1][1]()  # undo
        self.assertEqual([n.body for n in session.notes.rows], ["plain"])
        self.assertEqual(session.notes.rows[0].id, note.id)
        answer = session.questions.rows[1]
        session.deleteNote(answer.id)
        self.assertEqual(offered[-1][0], "Answer deleted")
        session.deleteNote(q.id)
        self.assertEqual(offered[-1][0], "Question and 1 answer deleted")
        self.assertEqual(list(session.questions.rows), [])
        offered[-1][1]()
        self.assertEqual([n.body for n in session.questions.rows], ["why?", "b"])

    def test_session_edit_and_delete(self):
        self.session.loadNow(50)
        note_id = self.session.notes.rows[0].id
        self.session.editNote(note_id, " fifty, revised ")
        self.assertEqual([n.body for n in self.session.notes.rows], ["fifty, revised"])
        self.session.editNote(note_id, "   ")  # ignored
        self.assertEqual([n.body for n in self.session.notes.rows], ["fifty, revised"])
        self.session.deleteNote(note_id)
        self.assertEqual(list(self.session.notes.rows), [])

    def test_add_note_goes_on_the_current_page_and_shows_up(self):
        self.session.loadNow(7)
        self.session.addNote("  hello ")
        self.assertEqual([n.body for n in self.session.notes.rows], ["hello"])
        self.assertEqual(self.repo.list_notes(self.res, 7)[0].page, 7)


if __name__ == "__main__":
    unittest.main()