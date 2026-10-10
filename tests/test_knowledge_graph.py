import threading
import unittest

from PySide6.QtCore import QEventLoop, QTimer
from PySide6.QtGui import QGuiApplication

from dailytodo.core import UNTAGGED, GraphResource, GraphTag, build_graph, find_clusters, layout_cluster
from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


class ClustersTest(unittest.TestCase):
    def test_clusters_are_connected_components_biggest_first(self):
        clusters, edges = find_clusters(range(1, 8), [(1, 2), (2, 3), (5, 6)])
        self.assertEqual([sorted(c) for c in clusters], [[1, 2, 3], [5, 6], [4], [7]])
        self.assertEqual(len(edges), 3)

    def test_cycles_and_mutual_links_end_and_merge(self):
        clusters, edges = find_clusters([1, 2, 3], [(1, 2), (2, 3), (3, 1), (2, 1)])
        self.assertEqual([sorted(c) for c in clusters], [[1, 2, 3]])
        self.assertEqual(len(edges), 3)  # 1-2 once, even though it is linked both ways
        both = edges[(1, 2)]
        self.assertTrue(both.a_to_b and both.b_to_a)

    def test_links_to_unknown_resources_and_self_links_are_dropped(self):
        clusters, edges = find_clusters([1, 2], [(1, 1), (1, 99), (99, 2)])
        self.assertEqual(edges, {})
        self.assertEqual(len(clusters), 2)

    def test_a_dense_graph_is_one_cluster_with_each_link_kept_once(self):
        links = [(a, b) for a in range(30) for b in range(a + 1, 30)]
        links += [(b, a) for a, b in links]  # and every one of them again, reversed
        clusters, edges = find_clusters(range(30), links)
        self.assertEqual(len(clusters), 1)
        self.assertEqual(len(edges), 30 * 29 // 2)
    def test_layout_is_deterministic_and_keeps_every_resource(self):
        members = list(range(10))
        edges = [(i, i + 1) for i in range(9)]
        first = layout_cluster(members, edges)
        self.assertEqual(first, layout_cluster(members, edges))
        self.assertEqual(sorted(first), members)
        self.assertEqual(len(set(first.values())), 10)  # nothing on top of anything else


class BuildTest(unittest.TestCase):
    # Maths > Linear algebra, and Thesis
    TAGS = [GraphTag(1, "Maths"), GraphTag(2, "Linear algebra", 1), GraphTag(3, "Thesis")]

    def graph(self):
        resources = [
            GraphResource(10, "Lecture 4", "pdf", tags=("Linear algebra", "Maths"), own=(2,)),
            GraphResource(11, "Eigen video", "video", tags=("Linear algebra", "Maths"), own=(2,)),
            GraphResource(12, "Calculus notes", "pdf", tags=("Maths",), own=(1,)),
            # tagged twice: drawn in the more specific region, counted in both
            GraphResource(13, "Both", "web", tags=("Linear algebra", "Maths", "Thesis"), own=(3, 2)),
            GraphResource(14, "Outline", "word", tags=("Thesis",), own=(3,)),
            GraphResource(15, "Loner", "web"),
        ]
        return build_graph(resources, [(10, 11), (11, 14)], self.TAGS)

    def test_every_resource_is_drawn_in_the_region_of_its_most_specific_tag(self):
        graph = self.graph()
        self.assertEqual(len(graph.nodes), 6)  # linked or not
        home = {n.id: n.region for n in graph.nodes}
        self.assertEqual(home, {10: 2, 11: 2, 12: 1, 13: 2, 14: 3, 15: UNTAGGED})
        regions = {r.tag: r for r in graph.regions}
        self.assertEqual(set(regions), {1, 2, 3, UNTAGGED})
        for n in graph.nodes:  # inside its region
            r = regions[n.region]
            self.assertTrue(r.x <= n.x <= r.x + r.width and r.y <= n.y <= r.y + r.height, n.name)

    def test_a_sub_tag_region_sits_inside_its_tag_and_shares_its_colour(self):
        regions = {r.tag: r for r in self.graph().regions}
        outer, inner = regions[1], regions[2]
        self.assertTrue(outer.x < inner.x and inner.x + inner.width < outer.x + outer.width)
        self.assertTrue(outer.y < inner.y and inner.y + inner.height < outer.y + outer.height)
        self.assertEqual((inner.depth, inner.color), (1, outer.color))
        self.assertNotEqual(regions[3].color, outer.color)
        self.assertEqual((outer.size, inner.size), (4, 3))

    def test_the_legend_lists_every_tag_in_tree_order_with_its_count(self):
        areas = self.graph().areas
        self.assertEqual([(a.name, a.depth, a.count) for a in areas],
                         [("Maths", 0, 4), ("Linear algebra", 1, 3), ("Thesis", 0, 2)])
        self.assertEqual(areas[1].path, "Maths › Linear algebra")

    def test_links_between_regions_are_kept(self):
        graph = self.graph()
        self.assertEqual([(e.a, e.b) for e in graph.edges], [(10, 11), (11, 14)])

    def test_regions_and_resources_do_not_overlap(self):
        graph = self.graph()
        tops = [r for r in graph.regions if r.depth == 0]
        for i, a in enumerate(tops):
            for b in tops[i + 1:]:
                apart = (a.x + a.width <= b.x or b.x + b.width <= a.x
                         or a.y + a.height <= b.y or b.y + b.height <= a.y)
                self.assertTrue(apart, (a.name, b.name))
        spots = [(round(n.x), round(n.y)) for n in graph.nodes]
        self.assertEqual(len(set(spots)), len(spots))

    def test_damaged_tags_still_build(self):
        loop = [GraphTag(1, "A", 2), GraphTag(2, "B", 1), GraphTag(3, "C", 99)]
        graph = build_graph([GraphResource(1, "x", "web", own=(1,)), GraphResource(2, "y", "web", own=(3,))],
                            [], loop)
        self.assertEqual(len(graph.nodes), 2)

    def test_empty_workspace(self):
        graph = build_graph([], [])
        self.assertEqual((graph.nodes, graph.edges, graph.regions), ((), (), ()))


class ModelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)
        for name in ("One", "Two", "Three"):
            self.ctl.addResource(f"https://{name}.example", name, [])
        ids = {r.name: r.id for r in self.repo.list_resources(self.ctl.currentWorkspaceId)}
        self.repo.add_note(ids["One"], None, f"@{{{ids['Two']}|Two}}")
        self.kg = self.ctl.knowledgeGraph

    def tearDown(self):
        self.repo.close()

    def test_builds_off_the_main_thread_result_arrives_later(self):
        self.assertFalse(self.kg.built)
        self.kg.rebuild()
        wait(300)
        self.assertTrue(self.kg.built)
        self.assertEqual(len(self.kg.nodes), 3)
        self.assertEqual(len(self.kg.edges), 1)

    def test_nothing_is_rebuilt_when_nothing_changed(self):
        calls = []
        real = self.kg._compute
        self.kg._compute = lambda *a: (calls.append(1), real(*a))[1]
        self.kg.rebuild()
        wait(200)
        self.kg.rebuild()
        wait(200)
        self.assertEqual(len(calls), 1)

    def test_loading_shows_only_when_it_takes_long(self):
        real = self.kg._compute
        release = threading.Event()
        self.kg._compute = lambda *a: (release.wait(2), real(*a))[1]
        self.kg._delay.setInterval(60)
        shown = []
        self.kg.loadingChanged.connect(lambda: shown.append(self.kg.loading))
        self.kg.rebuild()
        self.assertFalse(self.kg.loading)  # not at once
        wait(200)
        self.assertTrue(self.kg.loading)
        release.set()
        wait(300)
        self.assertFalse(self.kg.loading)
        self.assertTrue(self.kg.built)
        self.assertEqual(shown, [True, False])

    def test_a_quick_build_never_shows_the_indicator(self):
        shown = []
        self.kg.loadingChanged.connect(lambda: shown.append(self.kg.loading))
        self.kg.rebuild()
        wait(300)
        self.assertEqual(shown, [])

    def test_failures_are_reported_and_retried(self):
        errors = []
        self.kg.error.connect(errors.append)
        real = self.kg._compute

        def boom(*a):
            raise RuntimeError("boom")

        self.kg._compute = boom
        self.kg.rebuild()
        wait(300)
        self.assertEqual(len(errors), 1)
        self.assertFalse(self.kg.loading)
        self.kg._compute = real
        self.kg.rebuild()  # the failed input was forgotten, so this builds
        wait(300)
        self.assertTrue(self.kg.built)


if __name__ == "__main__":
    unittest.main()


class NameLimitTest(unittest.TestCase):
    def test_names_are_cut_after_eighty_characters(self):
        from dailytodo.core import node_label

        self.assertEqual(node_label("x" * 80), "x" * 80)
        self.assertEqual(node_label("x" * 81), "x" * 80 + "…")

    def test_pills_grow_with_the_name_and_the_layout_leaves_room(self):
        from dailytodo.core.knowledge_graph import NODE_W, node_width

        self.assertEqual(node_width("short"), NODE_W)
        self.assertGreater(node_width("y" * 80), 3 * NODE_W)
        self.assertEqual(node_width("y" * 200), node_width("y" * 81))  # both end in the ellipsis
        long_name = "z" * 80
        graph = build_graph([GraphResource(1, long_name, "pdf"), GraphResource(2, "b", "pdf")], [(1, 2)])
        first, second = graph.nodes
        self.assertEqual((first.label, first.width), (long_name, node_width(long_name)))
        gap = abs(first.x - second.x) - (first.width + second.width) / 2
        near_vertical = abs(first.y - second.y) >= 30
        self.assertTrue(gap >= 0 or near_vertical, "pills overlap")
