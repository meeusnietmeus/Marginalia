import unittest

from PySide6.QtGui import QGuiApplication

from dailytodo.core import Tag, ancestors, descendants, expand_filter, label_rows, valid_parents, with_ancestors
from dailytodo.storage import RepositoryError, SqliteTodoRepository
from dailytodo.ui import TodoController

# Maths > Algebra > Linear, Maths > Calculus, Biology, (Zoology has a parent that is not there)
TAGS = [
    Tag(1, "Maths"), Tag(2, "Algebra", 1), Tag(3, "Linear", 2), Tag(4, "Calculus", 1),
    Tag(5, "Biology"), Tag(6, "Zoology", 99),
]


class LabelTreeTest(unittest.TestCase):
    def test_tree_order_depth_and_paths(self):
        rows = [(r.name, r.depth, r.path, r.child_count) for r in label_rows(TAGS)]
        self.assertEqual(rows, [
            ("Biology", 0, "Biology", 0),
            ("Maths", 0, "Maths", 2),
            ("Algebra", 1, "Maths › Algebra", 1),
            ("Linear", 2, "Maths › Algebra › Linear", 0),
            ("Calculus", 1, "Maths › Calculus", 0),
            ("Zoology", 0, "Zoology", 0),            # an unknown parent: a top-level tag
        ])

    def test_descendants_and_ancestors(self):
        self.assertEqual(descendants(TAGS, 1), {1, 2, 3, 4})
        self.assertEqual(descendants(TAGS, 3), {3})
        self.assertEqual(ancestors(TAGS, 3), [2, 1])
        self.assertEqual(ancestors(TAGS, 1), [])
        self.assertEqual(with_ancestors(TAGS, [3, 5]), [3, 5, 2, 1])
        self.assertEqual(expand_filter(TAGS, {2, 5}), {2, 3, 5})

    def test_a_tag_can_not_go_below_itself(self):
        names = [r.name for r in valid_parents(TAGS, 2)]
        self.assertNotIn("Algebra", names)
        self.assertNotIn("Linear", names)
        self.assertIn("Maths", names)
        self.assertEqual(len(valid_parents(TAGS, None)), 6)

    def test_loops_in_damaged_data_do_not_hang(self):
        loop = [Tag(1, "A", 2), Tag(2, "B", 1)]
        self.assertEqual(len(label_rows(loop)), 0)         # nothing is a root, nothing is shown twice
        self.assertEqual(descendants(loop, 1), {1, 2})
        self.assertEqual(ancestors(loop, 1), [2])


class LabelStorageTest(unittest.TestCase):
    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ws = self.repo.list_workspaces()[0].id
        self.other = self.repo.list_workspaces()[1].id
        self.maths = self.repo.create_tag(self.ws, "Maths")
        self.algebra = self.repo.create_tag(self.ws, "Algebra", self.maths.id)

    def tearDown(self):
        self.repo.close()

    def parents(self):
        return {t.name: t.parent_id for t in self.repo.list_tags(self.ws)}

    def test_parent_is_stored(self):
        self.assertEqual(self.parents(), {"Algebra": self.maths.id, "Maths": None})

    def test_move_and_make_top_level(self):
        bio = self.repo.create_tag(self.ws, "Biology")
        self.repo.set_tag_parent(self.algebra.id, bio.id)
        self.assertEqual(self.parents()["Algebra"], bio.id)
        self.repo.set_tag_parent(self.algebra.id, None)
        self.assertIsNone(self.parents()["Algebra"])

    def test_loops_and_foreign_parents_are_refused(self):
        with self.assertRaises(RepositoryError):
            self.repo.set_tag_parent(self.maths.id, self.algebra.id)    # below its own sub-tag
        with self.assertRaises(RepositoryError):
            self.repo.set_tag_parent(self.maths.id, self.maths.id)
        foreign = self.repo.create_tag(self.other, "Elsewhere")
        with self.assertRaises(RepositoryError):
            self.repo.set_tag_parent(self.algebra.id, foreign.id)
        with self.assertRaises(RepositoryError):
            self.repo.create_tag(self.ws, "X", foreign.id)

    def test_deleting_a_tag_moves_its_sub_tags_up(self):
        linear = self.repo.create_tag(self.ws, "Linear", self.algebra.id)
        self.repo.delete_tag(self.algebra.id)
        self.assertEqual(self.parents(), {"Linear": self.maths.id, "Maths": None})
        self.repo.delete_tag(self.maths.id)
        self.assertEqual(self.parents(), {"Linear": None})
        self.assertEqual(linear.id, self.repo.list_tags(self.ws)[0].id)

    def test_an_old_database_gets_the_column(self):
        import sqlite3, tempfile, os
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "old.db")
            repo = SqliteTodoRepository(path)
            repo._conn.execute("ALTER TABLE tags DROP COLUMN parent_id")
            repo._conn.commit()
            repo.close()
            again = SqliteTodoRepository(path)
            ws = again.list_workspaces()[0].id
            tag = again.create_tag(ws, "New", None)
            self.assertIsNone(again.list_tags(ws)[0].parent_id)
            again.close()


class LabelControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        self.ctl.createTag("Maths", -1)
        ids = {t.name: t.id for t in self.repo.list_tags(self.ctl.currentWorkspaceId)}
        self.maths = ids["Maths"]
        self.ctl.createTag("Algebra", self.maths)
        ids = {t.name: t.id for t in self.repo.list_tags(self.ctl.currentWorkspaceId)}
        self.algebra = ids["Algebra"]
        self.ctl.createTag("Biology", -1)
        ids = {t.name: t.id for t in self.repo.list_tags(self.ctl.currentWorkspaceId)}
        self.bio = ids["Biology"]
        self.ctl.addResource("https://a.example", "In algebra", [self.algebra])
        self.ctl.addResource("https://b.example", "In maths", [self.maths])
        self.ctl.addResource("https://c.example", "In biology", [self.bio])

    def tearDown(self):
        self.repo.close()

    def shown(self):
        return sorted(r.name for r in self.ctl.resources.rows)

    def test_the_model_is_in_tree_order(self):
        rows = [(r.name, r.depth, r.path) for r in self.ctl.tags.rows]
        self.assertEqual(rows, [("Biology", 0, "Biology"), ("Maths", 0, "Maths"),
                                ("Algebra", 1, "Maths › Algebra")])
        self.assertTrue(self.ctl.hasSubTags)

    def test_filtering_by_a_tag_includes_its_sub_tags(self):
        self.ctl.toggleResourceTag(self.maths)
        self.assertEqual(self.shown(), ["In algebra", "In maths"])
        self.ctl.toggleResourceTag(self.maths)
        self.ctl.toggleResourceTag(self.algebra)
        self.assertEqual(self.shown(), ["In algebra"])       # not the other way round

    def test_update_renames_and_moves_in_one_go(self):
        self.ctl.updateTag(self.algebra, "Algebra II", self.bio)
        row = next(r for r in self.ctl.tags.rows if r.id == self.algebra)
        self.assertEqual((row.name, row.path), ("Algebra II", "Biology › Algebra II"))
        self.ctl.updateTag(self.algebra, "Algebra II", -1)
        self.assertEqual(next(r for r in self.ctl.tags.rows if r.id == self.algebra).depth, 0)

    def test_a_loop_is_refused_with_a_message(self):
        messages = []
        self.ctl.notify.connect(messages.append)
        self.ctl.updateTag(self.maths, "Maths", self.algebra)
        self.assertTrue(messages)
        self.assertEqual(next(r for r in self.ctl.tags.rows if r.id == self.maths).depth, 0)

    def test_parent_choices_leave_out_the_tag_and_what_is_below_it(self):
        names = [c["name"] for c in self.ctl.tagParentChoices(self.maths)]
        self.assertEqual(names, ["Biology"])
        self.assertEqual(len(self.ctl.tagParentChoices(-1)), 3)

    def test_creating_a_tag_gives_its_id_and_a_taken_name_gives_none(self):
        new = self.ctl.createTag("Topology", -1)
        self.assertGreater(new, 0)
        self.assertIn(new, [c["id"] for c in self.ctl.tagParentChoices(-1)])
        self.assertEqual(self.ctl.createTag("topology", -1), -1)   # names are unique, any case
        self.assertEqual(self.ctl.createTag("   ", -1), -1)

    def test_a_sub_tag_shares_its_top_tags_colour(self):
        family = {c["name"]: c["family"] for c in self.ctl.tagParentChoices(-1)}
        self.assertEqual(family["Algebra"], family["Maths"])
        self.assertNotEqual(family["Biology"], family["Maths"])

    def test_clicking_a_tag_in_text_asks_to_show_it(self):
        asked, opened = [], []
        self.ctl.tagRequested.connect(asked.append)
        self.ctl.openResource = opened.append            # nothing really opened in a test
        self.ctl.openLink(f"tag:{self.algebra}")
        self.ctl.openLink("tag:nonsense")          # not a tag id: treated as a web address
        self.assertEqual((asked, opened), ([self.algebra], ["tag:nonsense"]))

    def test_the_tag_picker_says_where_a_sub_tag_sits(self):
        found = self.ctl.searchReferences("!", "alg")
        self.assertEqual((found[0]["name"], found[0]["hint"]), ("Algebra", "Maths"))

    def test_the_graph_counts_a_resource_for_the_tags_above_its_own(self):
        graph = self.ctl.knowledgeGraph
        graph.rebuild()
        from PySide6.QtCore import QEventLoop, QTimer
        loop = QEventLoop(); QTimer.singleShot(300, loop.quit); loop.exec()
        areas = {a["name"]: a["count"] for a in graph.areas}
        self.assertEqual(areas, {"Algebra": 1, "Biology": 1, "Maths": 2})
        nodes = {n["name"]: n for n in graph.nodes}
        self.assertEqual(nodes["In algebra"]["region"], self.algebra)   # drawn in its own tag
        self.assertEqual(nodes["In algebra"]["tags"], ["Algebra", "Maths"])


if __name__ == "__main__":
    unittest.main()
