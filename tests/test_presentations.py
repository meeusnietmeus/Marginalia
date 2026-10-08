import os
import subprocess
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path

from PySide6.QtCore import QEventLoop, QTimer
from PySide6.QtGui import QGuiApplication

from dailytodo.core import export_needed, is_legacy_format, is_presentation, pdf_file_name, read_annotations
from dailytodo.powerpoint import ExportResult, export_pdf
from dailytodo.storage import ClientState, SqliteTodoRepository
from dailytodo.ui import TodoController

P = "http://schemas.openxmlformats.org/presentationml/2006/main"
A = "http://schemas.openxmlformats.org/drawingml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
REL = "http://schemas.openxmlformats.org/package/2006/relationships"


def rels(*items):
    body = "".join(f'<Relationship Id="{i}" Type="{t}" Target="{target}"/>' for i, t, target in items)
    return f'<Relationships xmlns="{REL}">{body}</Relationships>'


def make_deck(path: Path) -> None:
    """A deck of 3 slides: notes + an old-style comment on 1, a modern comment with a reply on 3."""
    notes = (
        f'<p:notes xmlns:p="{P}" xmlns:a="{A}"><p:cSld><p:spTree>'
        '<p:sp><p:nvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr></p:sp>'
        '<p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>'
        "<p:txBody><a:p><a:r><a:t>Say hello</a:t></a:r></a:p><a:p><a:r><a:t>then </a:t></a:r>"
        "<a:r><a:t>move on</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:notes>"
    )
    old = (f'<p:cmLst xmlns:p="{P}"><p:cm authorId="0" dt="2026-01-02T10:00:00"><p:pos x="1" y="2"/>'
           "<p:text>Check this figure</p:text></p:cm></p:cmLst>")
    modern = (
        f'<p188:cmLst xmlns:p188="http://schemas.microsoft.com/office/powerpoint/2018/8/main" xmlns:a="{A}">'
        '<p188:cm id="{1}" authorId="{AAA}" created="2026-02-03T09:00:00">'
        "<p188:replyLst><p188:reply id=\"{2}\" authorId=\"{BBB}\" created=\"2026-02-04T09:00:00\">"
        "<p188:txBody><a:p><a:r><a:t>Done</a:t></a:r></a:p></p188:txBody></p188:reply></p188:replyLst>"
        "<p188:txBody><a:p><a:r><a:t>Fix the title</a:t></a:r></a:p></p188:txBody></p188:cm></p188:cmLst>"
    )
    files = {
        "ppt/presentation.xml": (
            f'<p:presentation xmlns:p="{P}" xmlns:r="{R}"><p:sldIdLst>'
            '<p:sldId id="256" r:id="rId1"/><p:sldId id="257" r:id="rId2"/><p:sldId id="258" r:id="rId3"/>'
            "</p:sldIdLst></p:presentation>"
        ),
        "ppt/_rels/presentation.xml.rels": rels(
            ("rId1", R + "/slide", "slides/slide1.xml"),
            ("rId2", R + "/slide", "slides/slide2.xml"),
            ("rId3", R + "/slide", "slides/slide3.xml"),
        ),
        "ppt/slides/slide1.xml": f'<p:sld xmlns:p="{P}"/>',
        "ppt/slides/slide2.xml": f'<p:sld xmlns:p="{P}" show="0"/>',  # hidden, nothing on it
        "ppt/slides/slide3.xml": f'<p:sld xmlns:p="{P}"/>',
        "ppt/slides/_rels/slide1.xml.rels": rels(
            ("rId1", R + "/notesSlide", "../notesSlides/notesSlide1.xml"),
            ("rId2", R + "/comments", "../comments/comment1.xml"),
        ),
        "ppt/slides/_rels/slide3.xml.rels": rels(
            ("rId1", "http://schemas.microsoft.com/office/2018/10/relationships/comments",
             "../comments/modernComment_1.xml"),
        ),
        "ppt/notesSlides/notesSlide1.xml": notes,
        "ppt/comments/comment1.xml": old,
        "ppt/comments/modernComment_1.xml": modern,
        "ppt/commentAuthors.xml": f'<p:cmAuthorLst xmlns:p="{P}"><p:cmAuthor id="0" name="Ann"/></p:cmAuthorLst>',
        "ppt/authors.xml": (
            '<p188:authorLst xmlns:p188="http://schemas.microsoft.com/office/powerpoint/2018/8/main">'
            '<p188:author id="{AAA}" name="Bob"/><p188:author id="{BBB}" name="Cy"/></p188:authorLst>'
        ),
    }
    with zipfile.ZipFile(path, "w") as z:
        for name, content in files.items():
            z.writestr(name, content)


class AnnotationsTest(unittest.TestCase):
    def test_notes_and_both_kinds_of_comments(self):
        with tempfile.TemporaryDirectory() as folder:
            deck = Path(folder) / "d.pptx"
            make_deck(deck)
            found = read_annotations(str(deck))
        self.assertEqual([a.slide for a in found], [1, 3])  # slide 2 has nothing
        first, third = found
        self.assertEqual(first.notes, "Say hello\nthen move on")
        self.assertEqual([(c.author, c.text) for c in first.comments], [("Ann", "Check this figure")])
        self.assertEqual([(c.author, c.text, c.is_reply) for c in third.comments],
                         [("Bob", "Fix the title", False), ("Cy", "Done", True)])

    def test_anything_unreadable_has_no_annotations(self):
        with tempfile.TemporaryDirectory() as folder:
            bad = Path(folder) / "bad.pptx"
            bad.write_bytes(b"not a zip")
            self.assertEqual(read_annotations(str(bad)), [])
            self.assertEqual(read_annotations(str(Path(folder) / "missing.pptx")), [])


class NamesTest(unittest.TestCase):
    def test_names_and_freshness(self):
        self.assertEqual(pdf_file_name("C:\\decks\\Lecture 3.pptx"), "Lecture 3.pdf")
        self.assertEqual(pdf_file_name("/home/me/a.b.ppt"), "a.b.pdf")
        self.assertTrue(is_presentation("x.PPTX") and is_presentation("y.ppt"))
        self.assertFalse(is_presentation("x.pdf"))
        self.assertTrue(export_needed(None, 100))
        self.assertTrue(export_needed(99, 100))
        self.assertFalse(export_needed(100, 100))
        self.assertFalse(export_needed(101, 100))


class ExportTest(unittest.TestCase):
    def setUp(self):
        self._folder = tempfile.TemporaryDirectory()
        self.dir = Path(self._folder.name)
        self.deck = self.dir / "Deck.pptx"
        self.deck.write_bytes(b"x")
        self.pdf = self.dir / "out" / "Deck.pdf"

    def tearDown(self):
        self._folder.cleanup()

    def runner(self, returncode=0, stderr="", write=b"%PDF-1.7 data"):
        def run(command, **kwargs):
            target = Path(command[command.index("-Target") + 1])
            if write is not None:
                target.write_bytes(write)
            return subprocess.CompletedProcess(command, returncode, "", stderr)
        return run

    def test_success_puts_the_pdf_in_place_all_at_once(self):
        result = export_pdf(self.deck, self.pdf, self.runner())
        self.assertTrue(result.ok)
        self.assertEqual(self.pdf.read_bytes(), b"%PDF-1.7 data")
        self.assertEqual(os.listdir(self.pdf.parent), ["Deck.pdf"])  # no leftovers

    def test_failure_leaves_the_old_pdf_alone(self):
        self.pdf.parent.mkdir()
        self.pdf.write_bytes(b"old")
        result = export_pdf(self.deck, self.pdf, self.runner(2, "Class not registered 80040154", write=None))
        self.assertEqual(result.error, "PowerPoint doesn't seem to be installed")
        self.assertEqual(self.pdf.read_bytes(), b"old")

    def test_timeout_and_missing_source(self):
        def slow(command, **kwargs):
            raise subprocess.TimeoutExpired(command, 1)

        self.assertIn("too long", export_pdf(self.deck, self.pdf, slow).error)
        self.assertIn("not there", export_pdf(self.dir / "nope.pptx", self.pdf, self.runner()).error)

    def test_an_empty_pdf_is_a_failure(self):
        self.assertFalse(export_pdf(self.deck, self.pdf, self.runner(write=b"")).ok)


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


class PresentationFlowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self._folder = tempfile.TemporaryDirectory()
        self.dir = Path(self._folder.name)
        self.deck = self.dir / "Lecture.pptx"
        make_deck(self.deck)
        self.exports = []
        self.fail_with = ""

        def fake_export(source: Path, target: Path) -> ExportResult:
            self.exports.append((source, target))
            if self.fail_with:
                return ExportResult(self.fail_with)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"%PDF fake")
            return ExportResult()

        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(
            self.repo, client_state=ClientState(":memory:"),
            data_dir=self.dir / "data", export_presentation=fake_export,
        )
        self.folder = self.dir / "ws"
        self.ctl.setDefaultResourceFolder(str(self.folder))
        self.ctl.addResource(str(self.deck), "Lecture", [])
        self.rid = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id
        self.opened, self.messages = [], []
        self.ctl.pdfRequested.connect(lambda *a: self.opened.append(a))
        self.ctl.notify.connect(self.messages.append)

    def tearDown(self):
        self.repo.close()
        self._folder.cleanup()

    def settle(self):
        for _ in range(40):
            wait(50)
            if not self.ctl._exporting:
                break
        wait(50)

    @property
    def pdf(self) -> Path:
        return self.folder / "Lecture.pdf"

    def test_first_open_makes_the_pdf_in_the_workspace_folder_then_opens_it(self):
        self.ctl.openResourceById(self.rid)
        self.settle()
        self.assertEqual(self.exports, [(self.deck, self.pdf)])
        self.assertEqual(self.opened, [(self.rid, "Lecture", str(self.pdf), 0)])

    def test_an_up_to_date_pdf_is_reused(self):
        self.ctl.openResourceById(self.rid)
        self.settle()
        self.ctl.openResourceById(self.rid)
        wait(100)
        self.assertEqual(len(self.exports), 1)
        self.assertEqual(len(self.opened), 2)

    def test_a_newer_presentation_makes_the_pdf_again(self):
        self.ctl.openResourceById(self.rid)
        self.settle()
        later = self.pdf.stat().st_mtime + 50
        os.utime(self.deck, (later, later))
        self.ctl.openResourceById(self.rid)
        self.settle()
        self.assertEqual(len(self.exports), 2)

    def test_going_to_a_slide_opens_the_pdf_at_that_page(self):
        self.ctl.openResourceAtPage(self.rid, 3)
        self.settle()
        self.assertEqual(self.opened, [(self.rid, "Lecture", str(self.pdf), 3)])

    def test_without_a_workspace_folder_the_data_folder_is_used(self):
        self.ctl.setDefaultResourceFolder("")
        self.ctl.openResourceById(self.rid)
        self.settle()
        self.assertEqual(self.exports[0][1].parent, self.dir / "data" / "presentations"
                         / f"workspace-{self.ctl.currentWorkspaceId}")

    def test_failure_warns_and_opens_nothing(self):
        self.fail_with = "PowerPoint doesn't seem to be installed"
        self.ctl.openResourceById(self.rid)
        self.settle()
        self.assertEqual(self.opened, [])
        self.assertTrue(any("export it to pdf yourself" in m.lower() for m in self.messages))
        self.assertTrue(any("new resource" in m for m in self.messages))

    def test_deleting_the_resource_deletes_the_pdf_but_not_the_presentation(self):
        self.ctl.openResourceById(self.rid)
        self.settle()
        self.assertTrue(self.pdf.exists())
        self.ctl.deleteResource(self.rid)
        wait(100)
        self.assertFalse(self.pdf.exists())
        self.assertTrue(self.deck.exists())

    def test_deleting_the_workspace_deletes_its_pdfs(self):
        original = self.ctl.currentWorkspaceId
        self.ctl.createWorkspace("Other", str(self.dir / "other-ws"))
        self.ctl.setWorkspace(original)
        self.ctl.openResourceById(self.rid)
        self.settle()
        self.assertTrue(self.pdf.exists())
        self.ctl.deleteWorkspace()
        wait(100)
        self.assertFalse(self.pdf.exists())

    def test_the_annotations_of_the_slides(self):
        info = self.ctl.presentationAnnotations(self.rid)
        self.assertEqual([a["slide"] for a in info], [1, 3])
        self.assertEqual(info[0]["notes"], "Say hello\nthen move on")
        self.assertEqual(self.ctl.presentationAnnotations(99999), [])


class OldFormatTest(unittest.TestCase):
    """A .ppt is a binary file: its notes are read from a .pptx copy that PowerPoint makes."""

    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self._folder = tempfile.TemporaryDirectory()
        self.dir = Path(self._folder.name)
        self.deck = self.dir / "Old.ppt"
        self.deck.write_bytes(b"\xd0\xcf\x11\xe0 binary, not a zip")
        self.converted_calls = []
        self.fail_with = ""

        def fake_convert(source: Path, target: Path) -> ExportResult:
            self.converted_calls.append((source, target))
            if self.fail_with:
                return ExportResult(self.fail_with)
            target.parent.mkdir(parents=True, exist_ok=True)
            make_deck(target)
            return ExportResult()

        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(
            self.repo, client_state=ClientState(":memory:"), data_dir=self.dir / "data",
            convert_presentation=fake_convert,
        )
        self.ctl.addResource(str(self.deck), "Old", [])
        self.rid = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id
        self.ready, self.messages = [], []
        self.ctl.presentationAnnotationsReady.connect(self.ready.append)
        self.ctl.notify.connect(self.messages.append)

    def tearDown(self):
        self.repo.close()
        self._folder.cleanup()

    def settle(self):
        for _ in range(40):
            wait(50)
            if not self.ctl._converting:
                break
        wait(50)

    def test_the_old_format_is_recognised_and_not_readable_directly(self):
        self.assertTrue(is_legacy_format("C:\\x\\Old.PPT") and is_legacy_format("a.pps"))
        self.assertFalse(is_legacy_format("a.pptx"))
        self.assertEqual(read_annotations(str(self.deck)), [])        # this was the bug

    def test_notes_arrive_after_powerpoint_made_the_copy(self):
        self.assertEqual(self.ctl.presentationAnnotations(self.rid), [])   # not yet
        self.settle()
        self.assertEqual(self.ready, [self.rid])
        info = self.ctl.presentationAnnotations(self.rid)
        self.assertEqual([a["slide"] for a in info], [1, 3])
        self.assertEqual(info[0]["notes"], "Say hello\nthen move on")

    def test_the_copy_is_made_once_and_again_when_the_presentation_changes(self):
        self.ctl.presentationAnnotations(self.rid)
        self.settle()
        self.ctl.presentationAnnotations(self.rid)
        self.ctl.presentationAnnotations(self.rid)
        self.assertEqual(len(self.converted_calls), 1)
        later = os.path.getmtime(self.deck) + 100
        os.utime(self.deck, (later, later))
        self.ctl.presentationAnnotations(self.rid)
        self.settle()
        self.assertEqual(len(self.converted_calls), 2)

    def test_a_failed_conversion_says_so(self):
        self.fail_with = "PowerPoint doesn't seem to be installed"
        self.ctl.presentationAnnotations(self.rid)
        self.settle()
        self.assertEqual(self.ready, [])
        self.assertTrue(any("Couldn't read the notes" in m for m in self.messages))
        self.assertIn("conversion failed", self.ctl.presentationDebugInfo(self.rid))

    def test_the_debug_info_says_what_is_going_on(self):
        text = self.ctl.presentationDebugInfo(self.rid)
        self.assertIn("old binary", text)
        self.assertIn("nothing yet", text)
        self.ctl.presentationAnnotations(self.rid)
        self.settle()
        text = self.ctl.presentationDebugInfo(self.rid)
        self.assertIn("Slides with notes or comments: 2", text)
        self.assertIn("1 comments", text)
        self.assertIn("not a presentation", self.ctl.presentationDebugInfo(99999))

if __name__ == "__main__":
    unittest.main()
