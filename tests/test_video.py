import tempfile
import unittest
import urllib.error
from datetime import date
from pathlib import Path

from PySide6.QtGui import QGuiApplication

from dailytodo.core import (
    describe,
    format_timestamp,
    gap_is_long,
    is_youtube,
    link_at,
    page_label,
    parse_timestamp,
    pdf_markdown,
    position_of,
    start_seconds,
    youtube_video_id,
)
from dailytodo.core.models import Resource
from dailytodo.storage import SqliteTodoRepository
from dailytodo.thumbnails import fetch_thumbnail
from dailytodo.ui import TodoController
from dailytodo.core import timeline_groups
from datetime import datetime, timezone

ID = "dQw4w9WgXcQ"


class RecognisingTest(unittest.TestCase):
    def test_youtube_links(self):
        for link in (
            f"https://www.youtube.com/watch?v={ID}",
            f"http://youtube.com/watch?v={ID}&t=1m5s",
            f"https://m.youtube.com/watch?v={ID}",
            f"https://music.youtube.com/watch?v={ID}",
            f"https://youtu.be/{ID}?t=5",
            f"https://www.youtube.com/embed/{ID}",
            f"https://www.youtube.com/shorts/{ID}",
            f"https://www.youtube.co.uk/watch?v={ID}",
            f"https://www.youtube-nocookie.com/embed/{ID}",
            "https://www.youtube.com/@somechannel",
        ):
            self.assertTrue(is_youtube(link), link)

    def test_other_links(self):
        for link in ("https://example.com/youtube.com", "https://notyoutube.com/watch?v=" + ID,
                     "https://youtube.com.evil.example/watch", "ftp://youtube.com/x", "C:\\a\\b.mp4"):
            self.assertFalse(is_youtube(link), link)

    def test_video_ids(self):
        self.assertEqual(youtube_video_id(f"https://www.youtube.com/watch?v={ID}&list=x"), ID)
        self.assertEqual(youtube_video_id(f"https://youtu.be/{ID}?t=5"), ID)
        self.assertEqual(youtube_video_id(f"https://www.youtube.com/shorts/{ID}"), ID)
        self.assertIsNone(youtube_video_id("https://www.youtube.com/@channel"))
        self.assertIsNone(youtube_video_id("https://www.youtube.com/watch?v=short"))

    def test_start_time_of_a_link(self):
        self.assertEqual(start_seconds(f"https://youtu.be/{ID}?t=90"), 90)
        self.assertEqual(start_seconds(f"https://www.youtube.com/watch?v={ID}&t=1m30s"), 90)
        self.assertEqual(start_seconds(f"https://youtu.be/{ID}"), 0)

    def test_describe_gives_video_kind(self):
        def card(uri):
            now = datetime.now(timezone.utc)
            return describe(Resource(1, "n", uri, now, now), lambda p: True)

        self.assertEqual(card(f"https://youtu.be/{ID}").kind, "video")
        self.assertEqual(card("https://example.com").kind, "web")


class TimestampTest(unittest.TestCase):
    def test_link_at_a_moment(self):
        self.assertEqual(link_at(f"https://youtu.be/{ID}?t=5", 65),
                         f"https://www.youtube.com/watch?v={ID}&t=65s")
        self.assertEqual(link_at(f"https://www.youtube.com/watch?v={ID}&list=x", 0),
                         f"https://www.youtube.com/watch?v={ID}")
        self.assertEqual(link_at("https://vimeo.com/123", 30), "https://vimeo.com/123")

    def test_parse(self):
        cases = {
            "1:05": 65, "0:30": 30, "12:30": 750, "1:02:03": 3723,
            "65": 65, "5": 5, "90": 90,                         # plain seconds
            "105": 65, "1005": 605, "10530": 3930,              # stopwatch style
            "1h2m3s": 3723, "2m": 120, "45s": 45, "1m30": 90, "1h": 3600,
        }
        for text, seconds in cases.items():
            self.assertEqual(parse_timestamp(text), seconds, text)

    def test_not_timestamps(self):
        for text in ("", "  ", "abc", "1:75", "1:2:99", "-5", "1:", ":30", "1.5"):
            self.assertIsNone(parse_timestamp(text), text)

    def test_a_note_is_at_least_one_second_in(self):
        self.assertEqual(position_of("0:00"), 1)
        self.assertEqual(position_of("0:07"), 7)
        self.assertIsNone(position_of("nonsense"))
        self.assertIsNone(position_of("999:00:00"))

    def test_format(self):
        self.assertEqual([format_timestamp(s) for s in (0, 5, 65, 3600, 3725)],
                         ["0:00", "0:05", "1:05", "1:00:00", "1:02:05"])
        self.assertEqual(parse_timestamp(format_timestamp(3725)), 3725)

    def test_long_gaps_are_judged_against_the_whole_span(self):
        # first 0:01, last 1:02:00 (3719 s)
        self.assertTrue(gap_is_long(750, 3720, 1, 3720))
        self.assertFalse(gap_is_long(65, 90, 1, 3720))                 # close together
        self.assertFalse(gap_is_long(1, 30, 1, 40))                    # a gap, but a short video part
        self.assertFalse(gap_is_long(5, 5, 5, 5))                      # a single timestamp

    def test_labels(self):
        self.assertEqual(page_label(125, video=True), "At 2:05")
        self.assertEqual(page_label(125), "Page 125")
        self.assertEqual(page_label(None, video=True), "General")


class ThumbnailTest(unittest.TestCase):
    def test_nicest_size_that_exists_is_cached(self):
        tried = []

        def download(url, timeout):
            tried.append(url)
            if "maxres" in url:
                raise urllib.error.HTTPError(url, 404, "no", {}, None)
            return b"x" * 3000

        with tempfile.TemporaryDirectory() as folder:
            result = fetch_thumbnail(ID, Path(folder), download)
            self.assertEqual(result.path, Path(folder) / f"{ID}.jpg")
            self.assertEqual(len(tried), 2)
            again = fetch_thumbnail(ID, Path(folder), lambda *a: self.fail("downloaded again"))
            self.assertEqual(again.path, result.path)

    def test_network_down_is_an_error_not_a_crash(self):
        def download(url, timeout):
            raise urllib.error.URLError("offline")

        with tempfile.TemporaryDirectory() as folder:
            result = fetch_thumbnail(ID, Path(folder), download)
            self.assertIsNone(result.path)
            self.assertIn("offline", result.error)

    def test_blank_placeholders_are_not_pictures(self):
        with tempfile.TemporaryDirectory() as folder:
            result = fetch_thumbnail(ID, Path(folder), lambda url, timeout: b"tiny")
            self.assertIsNone(result.path)


class VideoControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        self.ctl.addResource(f"https://youtu.be/{ID}", "Clip", [])
        self.ctl.addResource("https://example.com/x", "Page", [])
        ids = {r.name: r.id for r in self.repo.list_resources(self.ctl.currentWorkspaceId)}
        self.clip, self.page = ids["Clip"], ids["Page"]
        self.videos, self.notes = [], []
        self.ctl.videoRequested.connect(lambda *a: self.videos.append(a))
        self.ctl.notesRequested.connect(lambda *a: self.notes.append(a))
        self.launched = []
        self.ctl.openResource = self.launched.append

    def tearDown(self):
        self.repo.close()

    def test_a_video_opens_its_page_and_is_not_launched_outside(self):
        self.ctl.openResourceById(self.clip)
        self.assertEqual(self.videos, [(self.clip, "Clip", f"https://youtu.be/{ID}", 0)])
        self.assertEqual((self.notes, self.launched), ([], []))

    def test_going_to_a_question_of_a_video_gives_its_timestamp(self):
        self.ctl.openResourceAtPage(self.clip, 125)
        self.assertEqual(self.videos[0][3], 125)
        self.ctl.openResourceById(self.clip)
        self.assertEqual(len(self.videos), 2)

    def test_other_links_keep_the_notes_tab(self):
        self.ctl.openResourceById(self.page)
        self.assertEqual((self.videos, len(self.notes), self.launched), ([], 1, ["https://example.com/x"]))

    def test_timestamp_slots(self):
        self.assertEqual((self.ctl.timestampOf("1:05"), self.ctl.timestampOf("zzz")), (65, -1))
        self.assertEqual(self.ctl.timestampLabel(65), "1:05")

    def test_no_preview_for_other_links(self):
        got = []
        self.ctl.thumbnailReady.connect(lambda *a: got.append(a))
        self.assertEqual(self.ctl.thumbnailFor("https://example.com"), "")


class TimelineTest(unittest.TestCase):
    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        ws = self.repo.list_workspaces()[0].id
        self.rid = self.repo.add_resource(ws, f"https://youtu.be/{ID}", "Clip", []).id

    def tearDown(self):
        self.repo.close()

    def test_groups_per_timestamp_with_answers_after_their_question(self):
        q = self.repo.add_note(self.rid, 65, "why?", is_question=True)
        self.repo.add_note(self.rid, 30, "early")
        self.repo.add_note(self.rid, 65, "a note at the same time")
        self.repo.add_note(self.rid, 65, "because", parent_id=q.id)
        self.repo.add_note(self.rid, None, "global: not on the timeline")
        groups = timeline_groups(self.repo.list_all_notes(self.rid))
        self.assertEqual([g["label"] for g in groups], ["0:30", "1:05"])
        self.assertEqual([e["body"] for e in groups[1]["entries"]],
                         ["why?", "because", "a note at the same time"])
        self.assertTrue(groups[1]["entries"][0]["answered"])

    def test_long_gaps_are_flagged_on_the_later_stop(self):
        for second in (10, 40, 3600):
            self.repo.add_note(self.rid, second, "x")
        groups = timeline_groups(self.repo.list_all_notes(self.rid))
        self.assertEqual([g["longGap"] for g in groups], [False, False, True])

    def test_markdown_uses_timestamps_for_videos(self):
        notes = [self.repo.add_note(self.rid, 125, "a thought")]
        text = pdf_markdown("Clip", notes, [], date(2026, 1, 1), timestamps=True)
        self.assertIn("## At 2:05", text)
        self.assertNotIn("## Page", text)


if __name__ == "__main__":
    unittest.main()
