import unittest
from datetime import date, timedelta

from dailytodo.core import DayPlanner, Todo, build_days, missed_days

THU = date(2026, 10, 1)  # a Thursday


class BuildDaysTest(unittest.TestCase):
    def test_shows_today_through_end_of_next_week(self):
        rows = build_days([], THU, set())
        self.assertEqual(rows[0].date_iso, "2026-10-01")
        self.assertEqual(rows[-1].date_iso, "2026-10-11")  # Sunday of next week
        self.assertEqual(rows[0].kind, "today")
        self.assertEqual(rows[1].title, "Tomorrow")

    def test_week_separators(self):
        rows = build_days([], THU, set())
        labels = {r.date_iso: r.week_label for r in rows if r.week_label}
        self.assertEqual(labels, {"2026-10-05": "Next week"})

    def test_pinned_past_day_is_shown_with_its_todos(self):
        past = THU - timedelta(days=4)  # Sunday of last week
        todos = [Todo(1, "old", False, past)]
        rows = build_days(todos, THU, missed_days(todos, THU))
        self.assertEqual(rows[0].kind, "past")
        self.assertEqual(rows[0].todos, [{"id": 1, "text": "old", "done": False}])
        self.assertEqual(rows[0].week_label, "Last week")

    def test_backlog_todos_are_not_on_the_timeline(self):
        todos = [Todo(1, "someday", False, None), Todo(2, "today", False, THU)]
        rows = build_days(todos, THU, missed_days(todos, THU))
        self.assertEqual([t["text"] for r in rows for t in r.todos], ["today"])
        self.assertEqual(missed_days(todos, THU + timedelta(days=3)), {THU})  # the backlog one is never "missed"

    def test_far_future_todos_are_hidden(self):
        todos = [Todo(1, "later", False, THU + timedelta(days=30))]
        self.assertTrue(all(not r.todos for r in build_days(todos, THU, set())))


class DayPlannerTest(unittest.TestCase):
    def test_completed_missed_day_stays_pinned(self):
        past = THU - timedelta(days=1)
        planner = DayPlanner(THU, [Todo(1, "x", False, past)])
        rows = planner.rows([Todo(1, "x", True, past)])  # checked off during the session
        self.assertEqual(rows[0].date_iso, past.isoformat())

    def test_roll_over_pins_newly_missed_days(self):
        planner = DayPlanner(THU, [])
        todos = [Todo(1, "x", False, THU)]
        planner.roll_over(THU + timedelta(days=1), todos)
        self.assertEqual(planner.rows(todos)[0].title, "Yesterday")


if __name__ == "__main__":
    unittest.main()
