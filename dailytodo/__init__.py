"""DailyTodo: a day-by-day todo list (PySide6 + Qt Quick).

Layers, from the inside out. Each one only imports the ones listed before it:

    core/     plain-Python domain types and view logic (no Qt, no storage)
    storage/  persistence behind the ``TodoRepository`` contract (no Qt)
    ui/       the Qt bridge: list models + the controller QML talks to
    app.py    wiring: parse config, pick storage, start Qt, load qml/Main.qml
"""
