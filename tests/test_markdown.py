import unittest

from dailytodo.core import segments


def shown(text):
    return [(p["text"], p["bold"], p["italic"]) for p in segments(text, lambda kind, i: "Doc")]


class MarkdownTests(unittest.TestCase):
    def test_bold_and_italic_drop_their_markers(self):
        self.assertEqual(shown("a **b** *c*"), [("a ", False, False), ("b", True, False), (" ", False, False), ("c", False, True)])

    def test_bullet_lines(self):
        self.assertEqual(shown("- one\n- two")[0][0], "• one\n• two")

    def test_unpaired_markers_stay_as_typed(self):
        self.assertEqual(shown("2 * 3 ** 4"), [("2 * 3 ** 4", False, False)])

    def test_bold_wraps_references_and_links(self):
        pieces = segments("**see @{1|Doc} [x](https://a.io)**", lambda kind, i: "Doc")
        self.assertTrue(all(p["bold"] for p in pieces))
        self.assertEqual([p["type"] for p in pieces], ["text", "resource", "text", "link"])

    def test_formulas(self):
        pieces = segments("a $x^2$ b", lambda kind, i: "Doc")
        self.assertEqual([(p["type"], p["text"]) for p in pieces], [("text", "a "), ("math", "x^2"), ("text", " b")])

    def test_prices_are_not_formulas(self):
        self.assertEqual(shown("costs $5 and $6"), [("costs $5 and $6", False, False)])

    def test_emphasis_markers_inside_a_formula_are_left_alone(self):
        pieces = segments("**bold $a*b*c$ x**", lambda kind, i: "Doc")
        self.assertEqual([p["text"] for p in pieces], ["bold ", "a*b*c", " x"])


if __name__ == "__main__":
    unittest.main()
