"""Pure view logic: turns a flat todo list into the day rows the UI shows.

No Qt and no storage here, so it can be unit-tested with plain lists.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Literal

from .models import Todo

WEEK_STARTS_ON = 0  # 0 = Monday ... 6 = Sunday
WEEKS_AHEAD = 1  # how many weeks after the current one are shown (1 = through next week)

DayKind = Literal["past", "today", "future"]


@dataclass(frozen=True, slots=True)
class DayRow:
    """One row of the day list. ui/day_list_model.py maps these fields to QML roles."""

    date_iso: str
    title: str  # "Yesterday" / "Today" / "Tomorrow" / weekday name
    date_label: str  # "30 Sep" (+ year when not the current year)
    kind: DayKind
    todos: list[dict]  # [{"id", "text", "done"}], plain dicts so QML gets JS objects
    week_label: str  # "Next week" etc. on the first day of a week, "" otherwise


# ---------------------------------------------------------------- labels
def _week_start(d: date) -> date:
    return d - timedelta(days=(d.weekday() - WEEK_STARTS_ON) % 7)


def _week_offset(d: date, today: date) -> int:
    """0 = current week, 1 = next week, -1 = last week, ..."""
    return (_week_start(d) - _week_start(today)).days // 7


def _week_label(offset: int) -> str:
    if offset == 0:
        return "This week"
    if offset == 1:
        return "Next week"
    if offset == -1:
        return "Last week"
    return f"{-offset} weeks ago" if offset < 0 else f"In {offset} weeks"


def _day_title(delta_days: int, day: date) -> str:
    """Yesterday / Today / Tomorrow, otherwise just the weekday name."""
    return {-1: "Yesterday", 0: "Today", 1: "Tomorrow"}.get(delta_days) or day.strftime("%A")


def _date_label(day: date, today: date) -> str:
    """'30 Sep'; the year is added only when it isn't the current year."""
    label = f"{day.day} {day.strftime('%b')}"
    return label if day.year == today.year else f"{label} {day.year}"


def _day_kind(delta_days: int) -> DayKind:
    return "past" if delta_days < 0 else "today" if delta_days == 0 else "future"


# ------------------------------------------------------------- building
def last_visible_day(today: date) -> date:
    """The last day the timeline shows (the end of next week)."""
    return _week_start(today) + timedelta(days=7 * (WEEKS_AHEAD + 1) - 1)


def missed_days(todos: list[Todo], today: date) -> set[date]:
    """Past days that still have at least one uncompleted todo."""
    return {t.day for t in todos if t.day is not None and t.day < today and not t.done}


def build_days(todos: list[Todo], today: date, pinned_past: set[date]) -> list[DayRow]:
    last_visible = last_visible_day(today)

    by_date: dict[date, list[dict]] = defaultdict(list)
    for t in todos:
        if t.day is not None:  # backlog todos are not on the timeline
            by_date[t.day].append({"id": t.id, "text": t.text, "done": t.done})

    # Shown days: missed past days + today through the end of the last visible week.
    # Todos dated further out exist in storage but stay hidden until their week is in range.
    dates = {d for d in pinned_past if d in by_date}
    dates |= {today + timedelta(days=i) for i in range((last_visible - today).days + 1)}

    rows: list[DayRow] = []
    prev_offset = None
    for day in sorted(dates):
        delta = (day - today).days
        offset = _week_offset(day, today)
        # Separator before the first day of every week. The very first week in the
        # list gets none, unless it is a past week (then the current week's
        # separator would otherwise look like it belongs to the wrong group).
        show_sep = (offset != 0) if prev_offset is None else (offset != prev_offset)
        prev_offset = offset
        rows.append(
            DayRow(
                date_iso=day.isoformat(),
                title=_day_title(delta, day),
                date_label=_date_label(day, today),
                kind=_day_kind(delta),
                todos=by_date.get(day, []),
                week_label=_week_label(offset) if show_sep else "",
            )
        )
    return rows


class DayPlanner:
    """Remembers which past days stay pinned in the list for this session.

    Past days that had uncompleted todos when the app opened (or when the day
    rolled over) stay visible, even after you complete their todos, so you can
    see what you just checked off.
    """

    def __init__(self, today: date, todos: list[Todo]):
        self.today = today
        self._pinned_past: set[date] = missed_days(todos, today)

    def roll_over(self, today: date, todos: list[Todo]) -> None:
        """A new day started while the app was open."""
        self.today = today
        self._pinned_past |= missed_days(todos, today)

    def rows(self, todos: list[Todo]) -> list[DayRow]:
        return build_days(todos, self.today, self._pinned_past)
