import tempfile
import sys
import unittest
from pathlib import Path
import uuid
from urllib.parse import quote

from PySide6.QtCore import QCoreApplication, QDeadlineTimer, QProcess
from PySide6.QtGui import QGuiApplication

from dailytodo.core import Capture, parse_capture, same_page
from dailytodo.instance import SingleInstance
from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController

ID = "dQw4w9WgXcQ"
WATCH = f"https://www.youtube.com/watch?v={ID}"


def link(kind="note", url=WATCH, t="754"):
    return f"marginalia://capture?kind={kind}&url={quote(url, safe='')}&t={t}"


class ParseTest(unittest.TestCase):
    def test_a_capture(self):
        self.assertEqual(parse_capture(link()), Capture("note", WATCH, 754))
        self.assertEqual(parse_capture(link("question", t="12.7")), Capture("question", WATCH, 12))
        self.assertEqual(parse_capture(f"marginalia://capture?kind=note&url={quote(WATCH, safe='')}"),
                         Capture("note", WATCH, 0))
        self.assertEqual(parse_capture(link().replace("marginalia://", "MARGINALIA:")), Capture("note", WATCH, 754))

    def test_anything_else_is_no_capture(self):
        for bad in [link(kind="delete"), link(url="javascript:alert(1)"), link(url="file:///C:/x"),
                    link(t="soon"), link().replace("capture", "erase", 1), WATCH, "",
                    "obsidian://capture?kind=note&url=https%3A%2F%2Fx"]:
            self.assertIsNone(parse_capture(bad), bad)

    def test_a_title_comes_along(self):
        capture = parse_capture(link() + "&title=" + quote("  Eigenvectors,\n visually "))
        self.assertEqual(capture.title, "Eigenvectors, visually")

    def test_negative_or_huge_times_are_clamped(self):
        self.assertEqual(parse_capture(link(t="-5")).seconds, 0)
        self.assertLess(parse_capture(link(t="99999999")).seconds, 400000)


class SamePageTest(unittest.TestCase):
    def test_youtube_links_are_the_same_video_whatever_their_form(self):
        self.assertTrue(same_page(f"https://youtu.be/{ID}?t=30", f"{WATCH}&list=PL1&index=3"))
        self.assertTrue(same_page(f"https://m.youtube.com/watch?v={ID}", WATCH))
        self.assertFalse(same_page(WATCH, "https://www.youtube.com/watch?v=aaaaaaaaaaa"))
        self.assertFalse(same_page(WATCH, "https://example.com/watch"))

    def test_other_links(self):
        self.assertTrue(same_page("https://www.Example.com/a/", "https://example.com/a#top"))
        self.assertFalse(same_page("https://example.com/a", "https://example.com/b"))
        self.assertFalse(same_page("https://example.com/a?x=1", "https://example.com/a?x=2"))


class ControllerCaptureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        self.ctl.addResource(f"https://youtu.be/{ID}", "Clip", [])
        self.clip = self.repo.list_resources(self.ctl.currentWorkspaceId)[0].id
        self.ready, self.missing, self.videos, self.toasts = [], [], [], []
        self.ctl.captureReady.connect(lambda *a: self.ready.append(a))
        self.ctl.captureNeedsResource.connect(lambda *a: self.missing.append(a))
        self.ctl.videoRequested.connect(lambda *a: self.videos.append(a))
        self.ctl.notify.connect(self.toasts.append)

    def tearDown(self):
        self.repo.close()

    def test_a_known_video_opens_its_tab_at_the_moment(self):
        self.ctl.handleLink(link("question", t="90"))
        self.assertEqual(self.ready, [(self.clip, "question", 90)])
        self.assertEqual([v[0] for v in self.videos], [self.clip])
        self.assertEqual(self.videos[0][3], 90)
        self.assertEqual(self.missing, [])

    def test_an_unknown_page_asks_for_a_resource_first(self):
        other = "https://www.youtube.com/watch?v=aaaaaaaaaaa"
        self.ctl.handleLink(link(url=other, t="5"))
        self.assertEqual(self.missing, [(other, "", "note", 5)])
        self.assertEqual(self.ready, [])
        # made from the dialog: the capture goes on
        self.ctl.addResource(other, "Other", [])
        self.ctl.capture("note", other, 5)
        self.assertEqual(len(self.ready), 1)

    def test_a_video_in_another_workspace_switches_to_it(self):
        with tempfile.TemporaryDirectory() as folder:
            self.ctl.createWorkspace("Other", folder)
        other_ws = self.ctl.currentWorkspaceId
        first_ws = [w.id for w in self.repo.list_workspaces() if w.id != other_ws][0]
        self.ctl.setWorkspace(other_ws)
        self.ctl.handleLink(link())
        self.assertEqual(self.ctl.currentWorkspaceId, first_ws)
        self.assertEqual(self.ready, [(self.clip, "note", 754)])

    def test_made_in_another_workspace_the_capture_opens_there(self):
        # what the capture dialog does when another workspace is picked in it
        first = self.ctl.currentWorkspaceId
        with tempfile.TemporaryDirectory() as folder:
            self.ctl.createWorkspace("Uni", folder)
        uni = self.ctl.currentWorkspaceId
        self.ctl.setWorkspace(first)
        tag = self.ctl.createTagIn(uni, "Lectures")             # made from the picker, over there
        self.assertGreater(tag, 0)
        self.assertEqual([t["name"] for t in self.ctl.tagChoicesIn(uni)], ["Lectures"])
        self.assertNotIn("Lectures", [t["name"] for t in self.ctl.tagParentChoices(-1)])
        self.assertEqual(self.ctl.createTagIn(uni, "lectures"), -1)  # taken, in that workspace
        other = "https://www.youtube.com/watch?v=aaaaaaaaaaa"
        self.ctl.handleLink(link(url=other, t="9"))
        self.assertEqual(len(self.missing), 1)
        self.ctl.setWorkspace(uni)
        self.ctl.addResource(other, "New one", [tag])
        self.ctl.capture("note", other, 9)
        self.assertEqual(self.ctl.currentWorkspaceId, uni)
        self.assertEqual(len(self.ready), 1)
        made = self.repo.list_resources(uni)[0]
        self.assertEqual(self.repo.list_resource_tags(uni)[made.id], [tag])

    def test_a_bad_link_only_says_so(self):
        self.ctl.handleLink("marginalia://capture?kind=nope")
        self.assertEqual((self.ready, self.missing, len(self.toasts)), ([], [], 1))


class SingleInstanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QCoreApplication.instance() or QGuiApplication([])

    @staticmethod
    def stop(running):
        running.close()
        QCoreApplication.sendPostedEvents(None, 0)   # the deferred deletes, now
        QCoreApplication.processEvents()

    def test_a_second_start_hands_its_link_to_the_running_one(self):
        name = "MarginaliaTest-" + uuid.uuid4().hex[:8]
        self.assertFalse(SingleInstance(name).send_to_running(link()))  # nothing running yet
        running = SingleInstance(name)
        self.assertTrue(running.listen())
        self.addCleanup(self.stop, running)
        received = []
        running.linkReceived.connect(received.append)
        # each new start is a process of its own (a thread would wait holding Python's lock, and
        # this side could not answer it)
        code = ("import sys; from dailytodo.instance import SingleInstance as S; "
                "sys.exit(0 if S(sys.argv[1]).send_to_running(sys.argv[2]) else 3)")
        for message in (link(), ""):
            process = QProcess()
            process.setWorkingDirectory(str(Path(__file__).resolve().parent.parent))
            process.start(sys.executable, ["-c", code, name, message])
            deadline = QDeadlineTimer(15000)
            while process.state() != QProcess.ProcessState.NotRunning and not deadline.hasExpired():
                QCoreApplication.processEvents()
                process.waitForFinished(5)
            self.assertEqual(process.exitCode(), 0)
        QCoreApplication.processEvents()
        self.assertEqual(received, [link(), ""])
