import json
import tempfile
import unittest
from pathlib import Path

from PySide6.QtGui import QGuiApplication

from dailytodo.core import (
    FLOWCHART_AI_PROMPT,
    Flowchart,
    FlowchartError,
    Resource,
    describe,
    dump_flowchart,
    flowchart_from_view,
    parse_flowchart,
)
from dailytodo.core.flowchart import FlowEdge, FlowNode, join_text, split_text
from dailytodo.storage import RepositoryError, SqliteTodoRepository
from dailytodo.ui import TodoController


class FormatTest(unittest.TestCase):
    def test_title_and_body_come_from_the_text(self):
        self.assertEqual(split_text("# Title\n\nSome *body*\nmore"), ("Title", "Some *body*\nmore"))
        self.assertEqual(split_text("  plain title  "), ("plain title", ""))
        self.assertEqual(split_text(""), ("", ""))
        self.assertEqual(join_text("Title", "Body"), "# Title\n\nBody")
        self.assertEqual(join_text("Title", " "), "# Title")

    def test_a_round_trip_keeps_everything(self):
        chart = Flowchart(
            [FlowNode("a", "Start", "Why it matters", 10, 20, 240, 70, "4", 3),
             FlowNode("b", "End", "", 400, 20)],
            [FlowEdge("e", "a", "b", "right", "left", "so", True, False, "#ff0000")],
        )
        self.assertEqual(parse_flowchart(dump_flowchart(chart)), chart)

    def test_notes_and_collapsed_nodes_round_trip(self):
        chart = Flowchart(
            [FlowNode("a", "Start", "", 0, 0, collapsed=True),
             FlowNode("n", "", "Just a remark", 0, 200, note=True),
             FlowNode("m", "Heading", "and text", 300, 200, note=True)],
            [],
        )
        self.assertEqual(parse_flowchart(dump_flowchart(chart)), chart)
        node = json.loads(dump_flowchart(chart))["nodes"]
        self.assertEqual((node[0].get("collapsed"), node[1].get("note"), node[1]["text"]),
                         (True, True, "Just a remark"))
        self.assertNotIn("note", node[0])
        self.assertEqual(flowchart_from_view(chart.to_view()), chart)

    def test_list_edges_round_trip(self):
        chart = Flowchart(
            [FlowNode("p", "Parent"), FlowNode("a", "Case A"), FlowNode("b", "Case B")],
            [FlowEdge("e1", "p", "a", list=True), FlowEdge("e2", "p", "b")],
        )
        self.assertEqual(parse_flowchart(dump_flowchart(chart)), chart)
        self.assertEqual(flowchart_from_view(chart.to_view()), chart)
        edges = json.loads(dump_flowchart(chart))["edges"]
        self.assertEqual([e.get("list") for e in edges], [True, None])

    def test_a_note_needs_a_title_or_a_body(self):
        chart = parse_flowchart(json.dumps({"nodes": [
            {"id": "n", "note": True, "text": "  ", "x": 0, "y": 0},
            {"id": "m", "note": True, "title": "", "body": "kept", "x": 0, "y": 0},
            {"id": "a", "text": "", "x": 0, "y": 0},          # a node keeps its place: "Untitled"
        ]}))
        self.assertEqual([(n.id, n.title, n.body) for n in chart.nodes],
                         [("m", "", "kept"), ("a", "Untitled", "")])

    def test_the_file_is_json_canvas(self):
        text = dump_flowchart(Flowchart([FlowNode("a", "A", "body", 1.6, 2)], []))
        node = json.loads(text)["nodes"][0]
        self.assertEqual(node, {"id": "a", "type": "text", "text": "# A\n\nbody",
                                "x": 2, "y": 2, "width": 220, "height": 60})

    def test_an_obsidian_canvas_reads(self):
        chart = parse_flowchart(json.dumps({
            "nodes": [
                {"id": "1", "type": "text", "text": "Idea", "x": 0, "y": 0, "width": 250, "height": 60},
                {"id": "2", "type": "file", "file": "notes/Paper.pdf", "x": 300, "y": 0, "width": 250, "height": 60},
                {"id": "3", "type": "link", "url": "https://example.org", "x": 0, "y": 200, "width": 250, "height": 60},
                {"id": "g", "type": "group", "label": "Group", "x": -20, "y": -20, "width": 900, "height": 400},
            ],
            "edges": [{"id": "x", "fromNode": "1", "toNode": "2"}, {"id": "y", "fromNode": "1", "toNode": "g"}],
        }))
        self.assertEqual([n.title for n in chart.nodes], ["Idea", "Paper.pdf", "https://example.org"])
        self.assertEqual([(e.source, e.target) for e in chart.edges], [("1", "2")])  # the group is gone

    def test_an_ai_answer_without_positions_is_laid_out_left_to_right(self):
        chart = parse_flowchart(json.dumps({
            "nodes": [{"id": "c", "title": "C"}, {"id": "a", "title": "A", "body": "first"},
                      {"id": "b", "title": "B"}, {"id": "b2", "title": "B2"}],
            "edges": [{"from": "a", "to": "b"}, {"from": "a", "to": "b2"}, {"from": "b", "to": "c"},
                      {"from": "c", "to": "b"}],  # a loop
        }))
        x = {n.id: n.x for n in chart.nodes}
        self.assertLess(x["a"], x["b"])
        self.assertEqual(x["b"], x["b2"])
        self.assertLess(x["b"], x["c"])
        y = {n.id: n.y for n in chart.nodes}
        self.assertNotEqual(y["b"], y["b2"])
        self.assertEqual(len({e.id for e in chart.edges}), 4)  # ids were made up

    def test_bad_input(self):
        for bad in ["{", "3", '"x"', '{"nodes": 4}']:
            with self.assertRaises(FlowchartError, msg=bad):
                parse_flowchart(bad)
        self.assertEqual(parse_flowchart("  "), Flowchart())
        chart = parse_flowchart(json.dumps({
            "nodes": [{"id": "a", "text": "A", "x": 0, "y": 0}, {"id": "a", "text": "Same id", "x": 0, "y": 0},
                      "junk", {"text": "", "x": "5", "y": None, "width": -3, "color": "red", "page": "x"}],
            "edges": [{"fromNode": "a", "toNode": "nowhere"}, {"fromNode": "a", "toNode": "a"}],
        }))
        self.assertEqual(len({n.id for n in chart.nodes}), 3)
        last = chart.nodes[-1]
        self.assertEqual((last.title, last.color, last.page, last.width), ("Untitled", "", 0, 80))
        self.assertEqual(chart.edges, [])

    def test_the_view_shape_goes_both_ways(self):
        chart = parse_flowchart(json.dumps({"nodes": [{"id": "a", "text": "# A\nb", "x": 0, "y": 0, "page": 2},
                                                      {"id": "b", "text": "B", "x": 5, "y": 5}],
                                            "edges": [{"id": "e", "fromNode": "a", "toNode": "b", "label": "l"}]}))
        self.assertEqual(flowchart_from_view(chart.to_view()), chart)

    def test_the_prompt_example_is_a_flowchart(self):
        example = FLOWCHART_AI_PROMPT[FLOWCHART_AI_PROMPT.index("{"): FLOWCHART_AI_PROMPT.index("Rules:")]
        chart = parse_flowchart(example)
        self.assertEqual([n.title for n in chart.nodes], ["Short title", "Another point"])
        self.assertEqual(chart.nodes[0].page, 1)

    def test_a_canvas_file_is_a_flowchart_resource(self):
        from datetime import datetime
        now = datetime.now()
        card = describe(Resource(1, "Map", r"C:\x\map.canvas", now, now, attached_to=4), lambda _: True)
        self.assertEqual((card.kind, card.attached_to), ("flowchart", 4))


class StorageTest(unittest.TestCase):
    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ws = self.repo.list_workspaces()[0].id

    def test_attach_detach_and_delete_the_document(self):
        doc = self.repo.add_resource(self.ws, r"C:\a.pdf", "Doc")
        chart = self.repo.add_resource(self.ws, r"C:\a.canvas", "Chart")
        self.repo.set_resource_attachment(chart.id, doc.id)
        attached = {r.id: r.attached_to for r in self.repo.list_resources(self.ws)}
        self.assertEqual(attached, {doc.id: None, chart.id: doc.id})
        self.repo.delete_resource(doc.id)
        self.assertIsNone(self.repo.list_resources(self.ws)[0].attached_to)

    def test_only_within_a_workspace(self):
        other = self.repo.list_workspaces()[1].id
        doc = self.repo.add_resource(other, r"C:\a.pdf", "Doc")
        chart = self.repo.add_resource(self.ws, r"C:\a.canvas", "Chart")
        with self.assertRaises(RepositoryError):
            self.repo.set_resource_attachment(chart.id, doc.id)
        with self.assertRaises(RepositoryError):
            self.repo.set_resource_attachment(chart.id, chart.id)


class ControllerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.ctl = TodoController(SqliteTodoRepository(":memory:"), data_dir=Path(self.tmp.name))
        pdf = Path(self.tmp.name) / "doc.pdf"
        pdf.write_bytes(b"%PDF-1.4")
        self.ctl.addResource(str(pdf), "Doc", [])
        self.doc = self.ctl.documentChoices()[0]["id"]

    def test_make_attach_save_and_load(self):
        opened = []
        self.ctl.flowchartRequested.connect(lambda *a: opened.append(a))
        chart = self.ctl.createFlowchart("Doc map", self.doc)
        self.assertGreaterEqual(chart, 0)
        self.assertEqual(opened[0][0], chart)
        self.assertTrue(opened[0][2].endswith(".canvas"))
        self.assertEqual([c["id"] for c in self.ctl.flowchartsOf(self.doc)], [chart])
        self.assertEqual(self.ctl.resourceInfo(chart)["attachedTo"], self.doc)

        view = {"nodes": [{"id": "a", "title": "A", "body": "hover me", "x": 0, "y": 0, "width": 200,
                           "height": 50, "color": "", "page": 3},
                          {"id": "b", "title": "B", "body": "", "x": 300, "y": 0, "width": 200,
                           "height": 50, "color": "2", "page": 0}],
                "edges": [{"id": "e", "from": "a", "to": "b", "fromSide": "", "toSide": "",
                           "label": "then", "fromArrow": False, "toArrow": True, "color": ""}]}
        self.assertTrue(self.ctl.saveFlowchart(chart, view))
        loaded = self.ctl.loadFlowchart(chart)
        self.assertTrue(loaded["ok"])
        self.assertEqual(loaded["nodes"][0]["body"], "hover me")
        self.assertEqual(loaded["edges"][0]["label"], "then")

        self.ctl.setAttachment(chart, -1)
        self.assertEqual(self.ctl.flowchartsOf(self.doc), [])

    def test_a_broken_file_says_so(self):
        chart = self.ctl.createFlowchart("Broken", -1)
        Path(self.ctl.resourceInfo(chart)["uri"]).write_text("{oops", encoding="utf-8")
        loaded = self.ctl.loadFlowchart(chart)
        self.assertFalse(loaded["ok"])
        self.assertIn("not a flowchart", loaded["error"])

    def test_paste_an_ai_answer(self):
        QGuiApplication.clipboard().setText('Sure! ```json\n{"nodes": [{"id": "a", "title": "A"}]}\n```')
        pasted = self.ctl.pasteFlowchart()
        self.assertTrue(pasted["ok"])
        self.assertEqual(pasted["nodes"][0]["title"], "A")
        QGuiApplication.clipboard().setText("no chart here")
        self.assertFalse(self.ctl.pasteFlowchart()["ok"])


if __name__ == "__main__":
    unittest.main()
