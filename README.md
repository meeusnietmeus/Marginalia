# Marginalia

A study space: plan your days, keep a library of PDFs, links and books, and take notes and
questions in the margins. Built with PySide6 and Qt Quick. (The Python package and the QML
modules are still called `dailytodo` / `DailyTodo`; that is just the code's name.)

```
python main.py [--db PATH] [--title TEXT] [--open marginalia://...]
python -m unittest                # tests (set QT_QPA_PLATFORM=offscreen if there's no display)
```

## Dependencies

`requirements.txt` pins every package to an exact version (`pip install -r requirements.txt`).
Pinned versions don't update themselves, so check the packages for significant new releases and
security fixes every now and then (`pip list --outdated`, or the release notes of PySide6 and
matplotlib), then bump the pins deliberately and run the tests.

## Layout

```
main.py                      entry point (the desktop shortcut runs it with the venv's pythonw.exe)
create_shortcut.ps1          makes that shortcut (-ViaPowerShell: go through run_todo.ps1 instead)
dailytodo/
  app.py                     wiring: config -> storage -> controller -> QML engine
  config.py                  AppConfig + command-line parsing
  window_chrome.py           the app's header as the Windows title bar (Qt + Win32, no app logic)
  powerpoint.py              .pptx/.ppt -> PDF through PowerPoint (COM, via powerpoint_export.ps1)
  titles.py, thumbnails.py   fetching a web page's title / a video's preview picture
  core/                      plain Python, no Qt, no storage: models, days, resources, labels (tags),
                             references (@{..} / !{..}), notes, open questions, video timestamps and
                             timeline, presentations (reading notes/comments), knowledge graph layout,
                             Markdown export
  storage/                   persistence, no Qt
    base.py                  TodoRepository contract, BackupCapable, RepositoryError
    sqlite_repository.py     SQLite implementation (the central data)
    client_state.py          per-machine UI state in its own SQLite file (last page, settings)
    factory.py               build_repository(): the one place that picks the storage
    backup.py, text_export.py
  ui/                        the Qt bridge
    keyed_list_model.py      reusable diffing list model over dataclass rows (+ one model per list)
    todo_controller.py       the object QML talks to (slots, models, notify / undo)
    notes_session.py         the notes and highlights of one open tab
    open_questions.py        state of the "Open questions" page
    knowledge_graph.py       state of the "Knowledge graph" page (layout on a worker thread: every
                             resource in the region of its tag, sub-tags nested, see core/knowledge_graph.py)
qml/
  Main.qml                   window shell: fixed pages, resource tabs, toasts
  DailyTodo/Style/           Theme singleton + icons/
  DailyTodo/Controls/        generic styled widgets (AppButton, FrostedGlass, AppToast, ...)
  DailyTodo/Views/           app-specific pages and pieces
tests/
```

Dependencies only point inwards: `core` <- `storage` <- `ui` <- `app.py`; the helpers at the top of
`dailytodo/` (PowerPoint, web lookups) are used by `ui` only.

Pages other than the Overview are made the first time they are shown, which keeps startup short.
Opening a resource always goes through `TodoController.openResourceById` / `openResourceAtPage`:
the controller decides which tab it gets (PDF, presentation, video or notes tab) and tells `Main.qml`
with `pdfRequested`, `videoRequested` or `notesRequested`.

## Presentations (PowerPoint)

A `.pptx` resource opens in the PDF viewer, as the PDF that PowerPoint itself makes of it (in the
background, needs Windows with PowerPoint). The PDF goes in the workspace's default resource folder
(or, without one, in the app's data folder) and has the name of the presentation. It is made when
there is none yet or when the presentation is newer than it, and deleted together with the
resource. The speaker notes and comments of the slide show next to it, read from the .pptx.
If PowerPoint can't be used you are told to export a PDF yourself and add it as a new resource.

Known limits: hidden slides are exported too (slide n is page n); animations and transitions are
gone (still pictures); ink is only there if PowerPoint draws it into the slide; comments are listed
but not pinned at their position; a hand-made PDF with the same name is trusted if it is newer, and
overwritten if it is older; two presentations with the same file name share one PDF per workspace.
## Notes from YouTube (browser extension)

On a YouTube video, press **N** (note) or **Q** (question): the video pauses and Marginalia comes up
on that video's tab with its note box open at that moment, the cursor in the text. A video that
isn't a resource yet opens the "New resource" dialog first (link and title filled in); once it is
created, the box opens the same way. A video in another workspace switches to that workspace.

Set it up once:

1. `powershell -ExecutionPolicy Bypass -File .
egister_protocol.ps1` teaches Windows that
   `marginalia://` links open the app (your user only; `-Unregister` undoes it; run it again after
   moving the folder).
2. In Chrome: `chrome://extensions`, turn on *Developer mode*, *Load unpacked*, pick the
   `browser-extension` folder.
3. The first time you press N or Q, Chrome asks whether youtube.com may open Marginalia: tick
   *Always allow*.

How it works: the extension opens `marginalia://capture?kind=note&url=...&t=754&title=...`;
Windows starts `main.py --open <link>`. That start finds the app already running on the same
database through a local socket (`dailytodo/instance.py`), hands it the link and quits; with no app
running, it becomes the app. The link is read in `core/capture.py` (strictly: any web page could
open one) and acted on by `TodoController.capture`. Starting the app twice on the same database now
brings the running window to the front instead of opening a second one.

## Extending

- **New storage (e.g. an HTTP API):** implement `TodoRepository` in `dailytodo/storage/`,
  return it from `factory.py`, add its option to `config.py`.
- **New list in the UI:** subclass `KeyedListModel` with `ROLES` and `KEY`, expose it as a
  `Property(QObject)` on a controller.
- **New action:** add a `@Slot` to `TodoController` (or to the page's own object, e.g.
  `NotesSession`), emit a signal from the QML component and call the slot where the controller is
  known (e.g. `DayDelegate.qml` for todos).
- **Look and feel:** everything visual is in `qml/DailyTodo/Style/Theme.qml`. Depth comes from
  two controls used everywhere: `Controls/Surface.qml` (a raised panel: gradient, light top edge,
  soft shadow; cards, menus, dialogs) and `Controls/Well.qml` (an inset field with a focus ring).
  Reuse the shared pieces rather than styling one by hand: `AppDialog` + `DialogTitle` (every
  modal), `QuietCard` (an entry in a list), `GlassPanel` (a box floating over the page),
  `SectionTitle` (a serif heading with an optional count), `EntryCard` (a note, question or
  answer, on every notes page), `NoteBox` (the box notes are written in) and `GlobalNotes`
  (a resource's global notes and Q&A, on the PDF and video tabs), `ResourceActions` (a
  resource's right-click menu and its edit / delete dialogs: one instance in `Main.qml`, handed
  to the library, "Jump back in" and the resource tabs), `NumberField` and `LazyPage` (a page that
  unloads itself 5 minutes after it was left: Open questions and Knowledge graph).
- **Todo flags:** a todo can be a *priority* (an ember flag before its text) and *in progress* (a
  half-filled amber checkbox), both switched from its right-click menu
  (`Controls/AppMenuToggle.qml`). Done and in progress rule each other out (the repository sees
  to it); a done todo keeps its priority.
- **Clicks and hover:** anything clicked uses `Controls/ClickHandler.qml` (not a plain
  `TapHandler`, which lets the click through to whatever is underneath, even through a popup), and
  anything that floats over the page as a plain item puts `Controls/InputBlocker.qml` at its back
  (so its empty parts stop clicks and hover too). Popups already stop both on their empty parts.
  `tests/test_click_through.py` checks this. `Backdrop` is the
  page background (`Theme.backdrop`: "ambient" or "dots"). The Overview adds `CapsLabel`,
  `PillLabel`, `ProgressOutline` and `KindTile` (in `Views/`); its timeline is a ruler with a date
  dial per day (`GraphSlice.qml`).
