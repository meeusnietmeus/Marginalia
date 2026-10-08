import unittest
from datetime import datetime, timezone

from dailytodo.core import Resource, describe, filter_and_sort, is_valid_uri, suggest_name
from dailytodo.titles import extract_title, http_error_message

NOW = datetime(2026, 10, 1, tzinfo=timezone.utc)


def card(uri, exists=True, name=""):
    return describe(Resource(1, name, uri, NOW, NOW), lambda path: exists)


class TagIdsTest(unittest.TestCase):
    def test_card_carries_tag_ids(self):
        c = describe(Resource(1, "n", "https://a.b", NOW, NOW), lambda p: True, [3, 5])
        self.assertEqual(c.tag_ids, [3, 5])


class FilterSortTest(unittest.TestCase):
    def make(self):
        from datetime import timedelta

        def r(i, name, used, tags=()):
            made = NOW + timedelta(days=i)
            return describe(
                Resource(i, name, "https://x.y/" + name, made, NOW + timedelta(days=used)),
                lambda p: True, tags,
            )

        return [r(1, "banana", 5, [1]), r(2, "Apple", 9, [2]), r(3, "cherry", 1, [1, 2]), r(4, "apricot", 7)]

    def test_sorts(self):
        names = lambda cards: [c.name for c in cards]
        cards = self.make()
        self.assertEqual(names(filter_and_sort(cards, "", set(), "recent")), ["Apple", "apricot", "banana", "cherry"])
        self.assertEqual(names(filter_and_sort(cards, "", set(), "name")), ["Apple", "apricot", "banana", "cherry"])
        self.assertEqual(names(filter_and_sort(cards, "", set(), "added")), ["apricot", "cherry", "Apple", "banana"])
        self.assertEqual(names(filter_and_sort(cards, "", set(), "bogus")), names(filter_and_sort(cards, "", set(), "recent")))

    def test_filters(self):
        names = lambda cards: sorted(c.name for c in cards)
        cards = self.make()
        self.assertEqual(names(filter_and_sort(cards, "  AP ", set(), "name")), ["Apple", "apricot"])
        self.assertEqual(names(filter_and_sort(cards, "", {1}, "name")), ["banana", "cherry"])
        self.assertEqual(names(filter_and_sort(cards, "", {1, 2}, "name")), ["Apple", "banana", "cherry"])  # any of them
        self.assertEqual(names(filter_and_sort(cards, "an", {1}, "name")), ["banana"])  # both rules
        self.assertEqual(filter_and_sort(cards, "zzz", set(), "name"), [])


class NameTest(unittest.TestCase):
    def test_suggestions(self):
        self.assertEqual(suggest_name(r"C:\Docs\Report.pdf"), "Report")
        self.assertEqual(suggest_name(r"C:\Docs\v1.2.final.docx"), "v1.2.final")
        self.assertEqual(suggest_name(r"C:\Docs\.gitignore"), ".gitignore")
        self.assertEqual(suggest_name(r"C:\Docs\README"), "README")
        self.assertEqual(suggest_name("https://www.example.com"), "example.com")
        self.assertEqual(suggest_name("https://example.com/docs/getting%20started/"), "getting started")
        self.assertEqual(suggest_name("obsidian://open"), "open")

    def test_card_uses_the_users_name(self):
        c = card("https://example.com/x", name="My name")
        self.assertEqual((c.name, c.title), ("My name", "My name"))
        self.assertEqual(card(r"C:\a\b.pdf").title, "b")  # unnamed: falls back to a suggestion

    def test_http_error_messages(self):
        self.assertEqual(http_error_message(404), "Page not found (404)")
        self.assertEqual(http_error_message(403), "Access denied (403)")
        self.assertEqual(http_error_message(500), "Server error (500)")
        self.assertEqual(http_error_message(418), "Request failed (418)")

    def test_extract_title(self):
        self.assertEqual(extract_title("<html><TITLE lang=x>\n Tom &amp;  Jerry \n</TITLE>"), "Tom & Jerry")
        self.assertIsNone(extract_title("<html>no title</html>"))


class DescribeTest(unittest.TestCase):
    def test_local_pdf(self):
        c = card(r"C:\Docs\Report.PDF")
        self.assertEqual((c.kind, c.title, c.is_path, c.missing), ("pdf", "Report", True, False))

    def test_office_files(self):
        self.assertEqual(card(r"C:\a\b.docx").kind, "word")
        self.assertEqual(card(r"C:\a\b.xlsx").kind, "excel")
        self.assertEqual(card(r"C:\a\b.pptx").kind, "powerpoint")
        self.assertEqual(card(r"C:\a\b.txt").kind, "file")
        self.assertEqual(card(r"C:\a\noextension").kind, "file")

    def test_missing_local_file(self):
        self.assertTrue(card(r"C:\gone.pdf", exists=False).missing)

    def test_links_are_never_missing(self):
        c = card("https://www.example.com/some/page?q=1", exists=False)
        self.assertEqual((c.kind, c.title, c.is_path, c.missing), ("web", "page", False, False))
        c = card("obsidian://open?vault=notes")
        self.assertEqual((c.kind, c.is_path), ("link", False))

    def test_long_titles_are_truncated(self):
        title = card(r"C:\x\\" + "a" * 100 + ".pdf").title
        self.assertEqual(len(title), 64)
        self.assertTrue(title.endswith("…"))

    def test_validation(self):
        for ok in (r"C:\file.pdf", r"\\server\share\x", "https://a.b", "obsidian://open?x=1", "mailto:a@b.c"):
            self.assertTrue(is_valid_uri(ok), ok)
        for bad in ("", "example.com", "C:", "just words"):
            self.assertFalse(is_valid_uri(bad), bad)


if __name__ == "__main__":
    unittest.main()
