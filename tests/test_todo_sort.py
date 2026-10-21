import unittest
from datetime import date

from dailytodo.core import Todo, leading_tag, sort_todos

DAY = date(2026, 10, 2)


def todo(id, text, done=False, priority=False):
    return Todo(id, text, done, DAY, priority)


class SortTodosTest(unittest.TestCase):
    def ids(self, todos):
        return [t.id for t in todos]

    def test_created_keeps_the_order(self):
        todos = [todo(1, "a"), todo(2, "b", priority=True), todo(3, "c")]
        self.assertEqual(self.ids(sort_todos(todos)), [1, 2, 3])

    def test_priority_first_is_stable(self):
        todos = [todo(1, "a"), todo(2, "b", priority=True), todo(3, "c"), todo(4, "d", priority=True)]
        self.assertEqual(self.ids(sort_todos(todos, "priority")), [2, 4, 1, 3])

    def test_group_by_leading_tag_in_tag_order(self):
        todos = [
            todo(1, "plain"),
            todo(2, "!{7|Maths} one"),
            todo(3, "!{5|Home} two"),
            todo(4, "!{7|Maths} three"),
            todo(5, "text !{5|Home} not leading"),
        ]
        rank = {5: 0, 7: 1}
        self.assertEqual(self.ids(sort_todos(todos, "tags", tag_rank=rank)), [3, 2, 4, 1, 5])

    def test_a_deleted_tag_counts_as_no_tag(self):
        todos = [todo(1, "!{9|Gone} x"), todo(2, "!{5|Home} y")]
        self.assertEqual(self.ids(sort_todos(todos, "tags", tag_rank={5: 0})), [2, 1])

    def test_done_last_keeps_the_sort_inside_each_part(self):
        todos = [todo(1, "a", done=True), todo(2, "b", priority=True), todo(3, "c", done=True, priority=True),
                 todo(4, "d")]
        self.assertEqual(self.ids(sort_todos(todos, "priority", done_last=True)), [2, 4, 3, 1])

    def test_leading_tag(self):
        self.assertEqual(leading_tag("  !{3|Tag} rest"), 3)
        self.assertIsNone(leading_tag("rest !{3|Tag}"))
        self.assertIsNone(leading_tag("@{3|Resource} rest"))


if __name__ == "__main__":
    unittest.main()
