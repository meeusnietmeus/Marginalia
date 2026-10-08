import unittest

from dailytodo.core import search, segments, sanitize_name, to_edit_text, to_storage_text

RESOURCES = {12: "Quarterly report", 13: "Budget {2026}"}
TAGS = {3: "work"}


def name_of(kind, ref_id):
    return (RESOURCES if kind == "resource" else TAGS).get(ref_id)


def resolve(kind, name):
    table = RESOURCES if kind == "resource" else TAGS
    for ref_id, real in table.items():
        if sanitize_name(real).casefold() == name.casefold():
            return ref_id, real
    return None


class ReferencesTest(unittest.TestCase):
    def test_edit_to_storage_and_back(self):
        edit = "review @{Quarterly report} for !{Work} today"
        stored = to_storage_text(edit, resolve)
        self.assertEqual(stored, "review @{12|Quarterly report} for !{3|work} today")
        self.assertEqual(to_edit_text(stored, name_of), "review @{Quarterly report} for !{work} today")

    def test_unknown_names_stay_plain_text(self):
        self.assertEqual(to_storage_text("see @{Nope} and !{nothing}", resolve), "see @{Nope} and !{nothing}")

    def test_names_with_braces_are_sanitized_and_still_resolve(self):
        stored = to_storage_text("@{Budget (2026)}", resolve)
        self.assertEqual(stored, "@{13|Budget (2026)}")
        self.assertEqual(to_edit_text(stored, name_of), "@{Budget (2026)}")

    def test_segments(self):
        pieces = segments("a @{12|Old name} b !{3|work} c @{99|Gone}", name_of)
        self.assertEqual([p["type"] for p in pieces],
                         ["text", "resource", "text", "tag", "text", "resource"])
        self.assertEqual(pieces[1]["text"], "Quarterly report")  # the live name, not the saved one
        self.assertFalse(pieces[1]["missing"])
        self.assertEqual((pieces[5]["text"], pieces[5]["missing"], pieces[5]["id"]), ("Gone", True, 99))

    def test_plain_text_is_one_segment(self):
        self.assertEqual([p["text"] for p in segments("nothing special {here}", name_of)],
                         ["nothing special {here}"])

    def test_search_ranks_prefix_before_contains_and_limits(self):
        items = [(1, "Zebra notes"), (2, "notes on zebras"), (3, "Notebook"), (4, "random"),
                 (5, "Another note"), (6, "note A"), (7, "note B"), (8, "note C")]
        names = [n for _, n in search(items, "note", limit=5)]
        self.assertEqual(names, ["note A", "note B", "note C", "Notebook", "notes on zebras"])  # prefix matches first
        self.assertEqual(len(search(items, "", limit=3)), 3)
        self.assertEqual(search(items, "zzz"), [])


if __name__ == "__main__":
    unittest.main()