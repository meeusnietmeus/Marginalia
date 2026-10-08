import unittest

from PySide6.QtGui import QGuiApplication

from dailytodo.core import HIGHLIGHT_COLORS
from dailytodo.storage import RepositoryError, SqliteTodoRepository
from dailytodo.ui import TodoController

RECTS = [(72.0, 80.0, 150.0, 20.0), (72.0, 100.0, 90.0, 20.0)]


class _Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        self.ctl.addResource("https://example.com/a", "Doc", [])
        self.ctl.addResource("https://example.com/b", "Other", [])
        by_name = {r.name: r.id for r in self.repo.list_resources(self.ctl.currentWorkspaceId)}
        self.rid, self.other = by_name["Doc"], by_name["Other"]

    def tearDown(self):
        self.repo.close()


class HighlightRepoTest(_Base):
    def test_add_and_list(self):
        h = self.repo.add_highlight(self.rid, 3, "quick brown", RECTS)
        self.assertEqual(self.repo.list_highlights(self.rid), [h])
        self.assertEqual((h.page, h.text, h.rects), (3, "quick brown", tuple(RECTS)))
        self.assertEqual(self.repo.list_highlights(self.other), [])

    def test_needs_a_rectangle_and_a_page(self):
        with self.assertRaises(RepositoryError):
            self.repo.add_highlight(self.rid, 1, "x", [])
        with self.assertRaises(RepositoryError):
            self.repo.add_highlight(self.rid, 0, "x", RECTS)

    def test_note_tied_to_a_highlight_lives_on_its_page(self):
        h = self.repo.add_highlight(self.rid, 4, "words", RECTS)
        note = self.repo.add_note(self.rid, 1, "about it", highlight_id=h.id)  # page argument is overruled
        self.assertEqual((note.page, note.highlight_id), (4, h.id))
        self.assertEqual(self.repo.list_notes(self.rid, 4)[0].highlight_id, h.id)

    def test_highlight_of_another_resource_is_refused(self):
        h = self.repo.add_highlight(self.other, 1, "words", RECTS)
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.rid, 1, "nope", highlight_id=h.id)

    def test_answers_cannot_be_tied(self):
        h = self.repo.add_highlight(self.rid, 1, "words", RECTS)
        q = self.repo.add_note(self.rid, 1, "why", is_question=True)
        with self.assertRaises(RepositoryError):
            self.repo.add_note(self.rid, 1, "because", parent_id=q.id, highlight_id=h.id)

    def test_deleting_a_highlight_keeps_the_note(self):
        h = self.repo.add_highlight(self.rid, 2, "words", RECTS)
        note = self.repo.add_note(self.rid, 2, "keep me", highlight_id=h.id)
        self.repo.delete_highlight(h.id)
        kept = self.repo.list_notes(self.rid, 2)
        self.assertEqual([(n.id, n.highlight_id) for n in kept], [(note.id, None)])

    def test_deleting_the_resource_deletes_its_highlights(self):
        self.repo.add_highlight(self.rid, 2, "words", RECTS)
        self.repo.delete_resource(self.rid)
        self.assertEqual(self.repo.list_highlights(self.rid), [])

    def test_link_and_unlink(self):
        h = self.repo.add_highlight(self.rid, 2, "words", RECTS)
        note = self.repo.add_note(self.rid, 2, "n")
        self.repo.set_note_highlight(note.id, h.id)
        self.assertEqual(self.repo.list_notes(self.rid, 2)[0].highlight_id, h.id)
        self.repo.set_note_highlight(note.id, None)
        self.assertIsNone(self.repo.list_notes(self.rid, 2)[0].highlight_id)

    def test_cannot_link_across_pages(self):
        h = self.repo.add_highlight(self.rid, 2, "words", RECTS)
        note = self.repo.add_note(self.rid, 3, "n")
        with self.assertRaises(RepositoryError):
            self.repo.set_note_highlight(note.id, h.id)

    def test_moving_a_note_off_the_page_unlinks_it(self):
        h = self.repo.add_highlight(self.rid, 2, "words", RECTS)
        a = self.repo.add_note(self.rid, 2, "a", highlight_id=h.id)
        b = self.repo.add_note(self.rid, 2, "b", highlight_id=h.id)
        self.repo.move_note(a.id, None)
        self.repo.move_note(b.id, 2)  # same page: stays tied
        self.assertIsNone(self.repo.list_notes(self.rid, None)[0].highlight_id)
        self.assertEqual(self.repo.list_notes(self.rid, 2)[0].highlight_id, h.id)

    def test_restore_highlight_ties_the_notes_again(self):
        h = self.repo.add_highlight(self.rid, 2, "words", RECTS)
        note = self.repo.add_note(self.rid, 2, "n", highlight_id=h.id)
        ids = self.repo.highlight_note_ids(h.id)
        self.repo.delete_highlight(h.id)
        self.repo.restore_highlight(h, ids)
        self.assertEqual(self.repo.list_highlights(self.rid), [h])
        self.assertEqual(self.repo.list_notes(self.rid, 2)[0].highlight_id, h.id)
        self.assertEqual(ids, [note.id])

    def test_restoring_a_deleted_note_keeps_its_link(self):
        h = self.repo.add_highlight(self.rid, 2, "words", RECTS)
        note = self.repo.add_note(self.rid, 2, "n", highlight_id=h.id)
        snapshot = self.repo.get_note_with_answers(note.id)
        self.repo.delete_note(note.id)
        self.repo.restore_notes(snapshot)
        self.assertEqual(self.repo.list_notes(self.rid, 2)[0].highlight_id, h.id)


class HighlightColorTest(_Base):
    def test_default_is_yellow(self):
        self.assertEqual(self.repo.add_highlight(self.rid, 1, "x", RECTS).color, "yellow")

    def test_every_palette_colour_is_accepted_and_kept(self):
        for color in HIGHLIGHT_COLORS:
            h = self.repo.add_highlight(self.rid, 1, color, RECTS, color)
            self.assertEqual(h.color, color)
        stored = {h.text: h.color for h in self.repo.list_highlights(self.rid)}
        self.assertEqual(stored, {c: c for c in HIGHLIGHT_COLORS})

    def test_unknown_colour_is_refused(self):
        with self.assertRaises(RepositoryError):
            self.repo.add_highlight(self.rid, 1, "x", RECTS, "chartreuse")
        h = self.repo.add_highlight(self.rid, 1, "x", RECTS)
        with self.assertRaises(RepositoryError):
            self.repo.set_highlight_color(h.id, "#ff0000")

    def test_recolour(self):
        h = self.repo.add_highlight(self.rid, 1, "x", RECTS)
        self.repo.set_highlight_color(h.id, "none")
        self.assertEqual(self.repo.list_highlights(self.rid)[0].color, "none")

    def test_restore_keeps_the_colour(self):
        h = self.repo.add_highlight(self.rid, 1, "x", RECTS, "purple")
        self.repo.delete_highlight(h.id)
        self.repo.restore_highlight(h, [])
        self.assertEqual(self.repo.list_highlights(self.rid)[0].color, "purple")

    def test_old_database_without_the_column_is_migrated(self):
        import sqlite3, tempfile, os
        path = os.path.join(tempfile.mkdtemp(), "old.db")
        first = SqliteTodoRepository(path)
        first.close()
        conn = sqlite3.connect(path)
        conn.executescript("DROP TABLE highlights; CREATE TABLE highlights (id INTEGER PRIMARY KEY AUTOINCREMENT,"
                           " resource_id INTEGER NOT NULL, page INTEGER NOT NULL, text TEXT NOT NULL,"
                           " rects TEXT NOT NULL, created_at TEXT NOT NULL);"
                           " INSERT INTO highlights (resource_id, page, text, rects, created_at)"
                           " VALUES (1, 1, 'old', '[[1,2,3,4]]', '2026-01-01T00:00:00.000+00:00');")
        conn.commit(); conn.close()
        reopened = SqliteTodoRepository(path)
        try:
            self.assertEqual(reopened.list_highlights(1)[0].color, "yellow")
        finally:
            reopened.close()


class HighlightSessionTest(_Base):
    def setUp(self):
        super().setUp()
        self.offers = []
        self.ctl.undoOffered.connect(lambda token, message: self.offers.append((token, message)))
        self.session = self.ctl.createNotesSession(self.rid)
        self.session.loadNow(2)

    def test_add_highlight_exposes_it_to_qml(self):
        hid = self.session.addHighlight(2, " quick brown ", [list(r) for r in RECTS])
        self.assertGreater(hid, 0)
        listed = self.session.highlights
        self.assertEqual([(h["id"], h["page"], h["text"]) for h in listed], [(hid, 2, "quick brown")])
        self.assertEqual(listed[0]["rects"], [list(r) for r in RECTS])

    def test_note_to_highlight_shows_its_quote(self):
        hid = self.session.addHighlight(2, "the passage", [list(RECTS[0])])
        self.session.addNoteTo("my thought", hid)
        row = self.session.notes.rows[0]
        self.assertEqual((row.highlight_id, row.quote, row.page), (hid, "the passage", 2))

    def test_question_to_highlight(self):
        hid = self.session.addHighlight(2, "the passage", [list(RECTS[0])])
        self.session.addQuestionTo("what is this", hid)
        row = self.session.questions.rows[0]
        self.assertTrue(row.is_question)
        self.assertEqual(row.highlight_id, hid)

    def test_colour_through_the_session_and_into_the_quote(self):
        hid = self.session.addHighlight(2, "passage", [list(RECTS[0])], "green")
        self.assertEqual(self.session.highlights[0]["color"], "green")
        self.session.addNoteTo("thought", hid)
        self.assertEqual(self.session.notes.rows[0].quote_color, "green")
        self.session.setHighlightColor(hid, "none")
        self.assertEqual(self.session.highlights[0]["color"], "none")
        self.assertEqual(self.session.notes.rows[0].quote_color, "none")

    def test_bad_colour_is_reported(self):
        errors = []
        self.session.error.connect(errors.append)
        hid = self.session.addHighlight(2, "x", [list(RECTS[0])])
        self.session.setHighlightColor(hid, "nope")
        self.assertTrue(errors)
        self.assertEqual(self.session.highlights[0]["color"], "yellow")

    def test_bad_highlight_reports_and_returns_minus_one(self):
        errors = []
        self.session.error.connect(errors.append)
        self.assertEqual(self.session.addHighlight(2, "x", []), -1)
        self.assertTrue(errors)

    def test_link_and_unlink_a_note(self):
        self.session.addNote("plain", False)
        note_id = self.session.notes.rows[0].id
        hid = self.session.addHighlight(2, "passage", [list(RECTS[0])])
        self.session.linkNote(note_id, hid)
        self.assertEqual(self.session.notes.rows[0].highlight_id, hid)
        self.session.unlinkNote(note_id)
        self.assertEqual(self.session.notes.rows[0].highlight_id, -1)

    def test_delete_highlight_is_undoable_and_keeps_notes(self):
        hid = self.session.addHighlight(2, "passage", [list(RECTS[0])])
        self.session.addNoteTo("thought", hid)
        self.session.deleteHighlight(hid)
        self.assertEqual(self.session.highlights, [])
        self.assertEqual(self.session.notes.rows[0].highlight_id, -1)  # note kept, link gone
        self.assertEqual(self.offers[-1][1], "Highlight removed")
        self.ctl.undo(self.offers[-1][0])
        self.assertEqual(len(self.session.highlights), 1)
        self.assertEqual(self.session.notes.rows[0].highlight_id, hid)


if __name__ == "__main__":
    unittest.main()
