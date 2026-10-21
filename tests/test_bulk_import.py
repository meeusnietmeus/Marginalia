import os
import shutil
import tempfile
import unittest
from pathlib import Path

from dailytodo.core import DUPLICATE, plan_import


class PlanImportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        (self.tmp / "a.pdf").write_text("a")
        (self.tmp / "b.docx").write_text("b")
        (self.tmp / "notes").mkdir()
        (self.tmp / "notes" / "c.txt").write_text("c")
        (self.tmp / "notes" / ".hidden").write_text("h")
        (self.tmp / ".backups").mkdir()
        (self.tmp / ".backups" / "todos-backup.db").write_text("x")

    def names(self, items):
        return [i.name for i in items]

    def test_files_get_a_name_and_a_kind(self):
        items = plan_import([str(self.tmp / "a.pdf"), str(self.tmp / "b.docx")], [])
        self.assertEqual(self.names(items), ["a", "b"])
        self.assertEqual([i.kind for i in items], ["pdf", "word"])
        self.assertEqual({i.status for i in items}, {"ok"})

    def test_a_folder_brings_its_files_but_not_hidden_ones(self):
        items = plan_import([str(self.tmp)], [])
        self.assertEqual(sorted(self.names(items)), ["a", "b", "c"])

    def test_missing_paths_are_dropped(self):
        self.assertEqual(plan_import([str(self.tmp / "nope.pdf")], []), [])

    def test_what_is_already_a_resource_is_marked(self):
        a = str(self.tmp / "a.pdf")
        items = plan_import([a, str(self.tmp / "b.docx")], [a.upper() if os.name == "nt" else a])
        self.assertEqual([i.status for i in items], [DUPLICATE, "ok"])

    def test_listing_a_file_twice_marks_the_second(self):
        a = str(self.tmp / "a.pdf")
        self.assertEqual([i.status for i in plan_import([a, a], [])], ["ok", DUPLICATE])
        self.assertEqual([i.status for i in plan_import([a], [], already_listed=[a])], [DUPLICATE])


if __name__ == "__main__":
    unittest.main()
