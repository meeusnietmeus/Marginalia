import unittest

from dailytodo.core import segments, split_links


def kinds(text):
    return [(k, shown, address) for k, shown, address in split_links(text)]


class LinksTest(unittest.TestCase):
    def test_markdown_link(self):
        self.assertEqual(kinds("see [the docs](https://example.com/a?b=1&c=2) now"),
                         [("text", "see ", ""), ("link", "the docs", "https://example.com/a?b=1&c=2"),
                          ("text", " now", "")])

    def test_bare_addresses_and_their_punctuation(self):
        self.assertEqual(kinds("go to https://youtu.be/abc, or (www.example.org/x)."), [
            ("text", "go to ", ""), ("link", "https://youtu.be/abc", "https://youtu.be/abc"),
            ("text", ", or (", ""), ("link", "www.example.org/x", "https://www.example.org/x"),
            ("text", ").", ""),
        ])

    def test_other_schemes_in_a_markdown_link(self):
        self.assertEqual(kinds("[note](obsidian://open?vault=a)")[0], ("link", "note", "obsidian://open?vault=a"))
        self.assertEqual(kinds("[mail me](mailto:me@example.com)")[0][2], "mailto:me@example.com")
        self.assertEqual(kinds("[x](www.example.org)")[0][2], "https://www.example.org")

    def test_not_links(self):
        for text in ("[just brackets] and (parens)", "[name](not a link)", "[name]()", "a [b] (https://x.io)"):
            kinds_found = [k for k, _, _ in split_links(text)]
            if text.startswith("a [b]"):
                self.assertEqual(kinds_found, ["text", "link", "text"])      # the bare address still is
            else:
                self.assertNotIn("link", kinds_found, text)

    def test_a_markdown_link_that_shows_an_address_is_one_link(self):
        self.assertEqual(kinds("[https://a.io](https://b.io)"), [("link", "https://a.io", "https://b.io")])

    def test_unsafe_schemes_are_not_made_into_links(self):
        self.assertNotIn("link", [k for k, _, _ in split_links("[x](javascript:alert(1))")])

    def test_segments_carry_the_links_next_to_references(self):
        pieces = segments("@{1|Doc} and [site](https://x.io) and !{2|tag}", lambda kind, i: "Doc" if i == 1 else None)
        self.assertEqual([p["type"] for p in pieces], ["resource", "text", "link", "text", "tag"])
        self.assertEqual((pieces[2]["text"], pieces[2]["url"]), ("site", "https://x.io"))
        self.assertEqual(pieces[0]["url"], "")


if __name__ == "__main__":
    unittest.main()
