from __future__ import annotations

from dataclasses import dataclass

from ..core import Todo, TodoId
from .keyed_list_model import KeyedListModel


@dataclass(frozen=True, slots=True)
class BacklogTodo:
    id: TodoId
    text: str
    done: bool

    @classmethod
    def from_todo(cls, todo: Todo) -> BacklogTodo:
        return cls(todo.id, todo.text, todo.done)


class BacklogListModel(KeyedListModel[BacklogTodo]):
    """The todos without a date, in the order they were added."""

    ROLES = {"todoId": "id", "text": "text", "done": "done"}
    KEY = "id"