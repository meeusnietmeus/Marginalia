import unittest

from dailytodo.core import referenced_resource_ids
from dailytodo.storage import SqliteTodoRepository


class ResourceLinksTest(unittest.TestCase):
    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        ws = self.repo.list_workspaces()[0].id
        self.a, self.b, self.c = (
            self.repo.add_resource(ws, f"https://{n}.example", n, []).id for n in "abc"
        )

    def tearDown(self):
        self.repo.close()

    def links(self, rid):
        return self.repo.list_resource_links(rid)

    def test_parsing_counts_each_resource_once_and_ignores_tags(self):
        text = ["@{2|B} and @{2|B} and @{3|C}", "!{4|tag} @{x}"]
        self.assertEqual(referenced_resource_ids(text), {2, 3})

    def test_a_mention_makes_one_forward_link_however_often(self):
        self.repo.add_note(self.a, None, f"@{{{self.b}|b}} again @{{{self.b}|b}}")
        self.repo.add_note(self.a, 3, f"@{{{self.b}|b}}", is_question=True)
        self.assertEqual(self.links(self.a), [(self.a, self.b)])
        self.assertEqual(self.links(self.b), [(self.a, self.b)])  # seen from b too: one row
        rows = self.repo._conn.execute("SELECT COUNT(*) FROM resource_links").fetchone()[0]
        self.assertEqual(rows, 1)  # and no reverse row b -> a

    def test_editing_and_deleting_notes_updates_the_links(self):
        n = self.repo.add_note(self.a, None, f"@{{{self.b}|b}}")
        self.repo.add_note(self.a, None, f"@{{{self.c}|c}}")
        self.repo.update_note(n.id, "no mention any more")
        self.assertEqual(self.links(self.a), [(self.a, self.c)])
        self.repo.delete_note(self.repo.list_all_notes(self.a)[-1].id)
        self.assertEqual(self.links(self.a), [])

    def test_undoing_a_delete_brings_the_link_back(self):
        n = self.repo.add_note(self.a, None, f"@{{{self.b}|b}}")
        snapshot = self.repo.get_note_with_answers(n.id)
        self.repo.delete_note(n.id)
        self.repo.restore_notes(snapshot)
        self.assertEqual(self.links(self.a), [(self.a, self.b)])

    def test_self_mentions_and_unknown_resources_make_no_link(self):
        self.repo.add_note(self.a, None, f"@{{{self.a}|a}} @{{999|ghost}}")
        self.assertEqual(self.links(self.a), [])

    def test_deleting_a_resource_removes_its_links(self):
        self.repo.add_note(self.a, None, f"@{{{self.b}|b}}")
        self.repo.delete_resource(self.b)
        self.assertEqual(self.links(self.a), [])


if __name__ == "__main__":
    unittest.main()
