import unittest

from PySide6.QtGui import QGuiApplication

from dailytodo.storage import SqliteTodoRepository
from dailytodo.ui import TodoController


class CreateResourceFromTextTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        self.repo = SqliteTodoRepository(":memory:")
        self.ctl = TodoController(self.repo)

    def tearDown(self):
        self.repo.close()

    def test_add_resource_returns_the_name_to_reference(self):
        self.assertEqual(self.ctl.addResource("https://a.example", "  My {odd} name ", []),
                         self.ctl.searchReferences("@", "odd")[0]["name"])

    def test_the_new_name_is_found_by_the_picker(self):
        name = self.ctl.addResource("https://a.example", "Fresh one", [])
        self.assertEqual([r["name"] for r in self.ctl.searchReferences("@", "fresh")], [name])

    def test_invalid_resource_returns_nothing(self):
        self.assertEqual(self.ctl.addResource("not a link", "x", []), "")


if __name__ == "__main__":
    unittest.main()
