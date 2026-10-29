# Todo, pomodoro and stopwatch

> **Files:** `services/apps/TodoManager.qml`, `services/apps/PomodoroManager.qml`, `components/methods/TodoItems.qml`, `components/methods/PomodoroCycle.qml`, `services/apps/StopwatchManager.qml`, `services/apps/DeadlineTicker.qml`, `components/methods/StopwatchClock.qml`, `config/StopwatchConfig.qml`, `components/bar/widgets/Stopwatch/Stopwatch.qml`, `components/content/Stopwatch/Stopwatch.qml`, `config/TodoConfig.qml`, `config/PomodoroConfig.qml`, `components/bar/widgets/Todo/Todo.qml`, `components/bar/widgets/Pomodoro/Pomodoro.qml`, `components/content/Todo/Todo.qml`, `components/content/Pomodoro/Pomodoro.qml`, `components/content/Focus/Focus.qml`, `components/content/parts/TodoList.qml`, `components/content/parts/PomodoroDial.qml`, `components/content/parts/TimeRing.qml`, `components/content/parts/CountdownTimer.qml`
> **Config:** `Todo.*` (reader `TodoConfig`), `Pomodoro.*` (reader `PomodoroConfig`), `Stopwatch.*` (reader `StopwatchConfig`)
> **Related:** [Calendar](calendar.md), [Notifications](notifications.md), [Launcher](launcher.md), [Writing modules](../overlay/writing-modules.md)

One todo list, one pomodoro timer and one one-off timer + stopwatch, each shown by a bar widget, its popout and an overlay module, plus the Focus module holding the first two and today's events.

### Todo list
- **Storage:** `$XDG_DATA_HOME/axiom/todo.json` (`TodoManager.path`): `{ version: 1, items }`. It's user content, not config: never exported, imported or snapshotted.
  - Written atomically on every change and watched, through axiom (`FileManager.write` / `watch`, which make the data folder), so an edit from elsewhere shows at once. An unreadable file is reported and the list shown stays.
  - Never read or written in the greeter.
- **Items** (`TodoItems`, pure, `tst_TodoItems`): `{ uid, summary, done, created, completed, due, order }`. Every change returns a new list.
  - The fields are a CalDAV VTODO's (UID, SUMMARY, STATUS, CREATED, COMPLETED, DUE), so syncing a task list later maps them one to one. Not done: the calendar sync (`backend/internal/calendar`) reads only VEVENTs, and two-way task sync (servers differ, offline edits, subtasks, repeating tasks) is its own job.
  - `due` is kept but nothing sets it yet.
- **Shown:** `TodoManager.shownItems`: open items in order, then (with `Todo.showCompleted`) the done ones, the last finished first.
- **UI:** `TodoList` (add field, rows: click ticks off or reopens; rename, work on it, delete on hover). The `Todo` widget shows the open count; its popout and module are `content/Todo/Todo.qml` (header with Clear completed).
- **Entry points:** IPC `todo` (`add`, `toggle <text>`, `list`, `count`, `clearCompleted`); launcher `/todo [text]` (with text, a row adding it; the open items matching, picked to tick off).
- Not done yet: reordering by drag (`TodoManager.move` exists).

### Pomodoro timer
- **State** (`PomodoroCycle`, pure, `tst_PomodoroCycle`): `{ phase (work | short | long), running, endsAt, pausedRemaining, completed }`. An absolute `endsAt`, so the time left is worked out, never counted down.
  - Every `longBreakEvery`-th finished focus session is followed by a long break.
  - `Pomodoro.autoStartBreaks` / `autoStartWork` say whether the next phase starts by itself.
- **Shared plumbing:** both services own a `DeadlineTicker` (`services/apps/`): their saved values, the alarm at the deadline, the ticking `now` with its `acquire`/`release`, and the notification (`notify`, `notificationClicked`). Each service keeps only its own state shape (`restore`) and what its end does (`ended`).
- **Kept:** in the ticker's `PersistentProperties` (a QML reload) and StateManager `pomodoro` (a restart), with the todo it's for (`todoUid`).
- **The end:** handled once per end (the ticker re-checks the deadline before `ended`, since a restart can queue it twice); one single-shot timer to `endsAt`, at most an hour at a time, running with nothing showing the timer (the service is created from `shell.qml`'s `_services`). At the end it advances and, with `Pomodoro.notify`, sends a notification (`desktopEntry` `axiom-pomodoro`; a click opens a page or edge menu with a Pomodoro or Focus module: `openTimer`). A phase that ended over 5 minutes before axiom noticed (it wasn't running) advances without one.
- **The display:** `now` ticks once a second only while running and something has `acquire(owner)`d it (the widget, the modules).
- **UI:** `PomodoroDial` (ring, phase, a dot per session to the long break, stop / start-pause / skip, task picker). In a popout or edge menu the task picker's list opens inline (`StyledComboEntry.expandsInline`): a dropdown window there isn't one the popout's hover and blur reach. The `Pomodoro` widget: time left while not idle, colored by phase; left click toggles, right skips, middle stops. Its popout and module are `content/Pomodoro/Pomodoro.qml`.
- **Entry points:** IPC `pomodoro` (`start`, `pause`, `toggle`, `skip`, `stop`, `reset`, `status`); launcher `/pomodoro [start|pause|skip|stop]`.

### Timer and stopwatch
- **State** (`StopwatchClock`, pure, `tst_StopwatchClock`): a timer `{ running, endsAt, remaining, duration, label }` and a stopwatch `{ running, startedAt, elapsed, laps }`, both absolute, both able to run at once.
  - `StopwatchClock.parse` reads a duration and an optional label: `10m`, `1h30m`, `90s`, `1:30` (m:s), `1:02:03`, a plain number as minutes, `10m tea`.
  - A timer that ends goes back to idle keeping its duration and label (Replay starts it again).
- **Kept:** the `DeadlineTicker`'s `PersistentProperties` + StateManager `stopwatch`, as the pomodoro. The end runs with no consumers (created from `_services`) and notifies with `Stopwatch.notify` (`desktopEntry` `axiom-stopwatch`, a click opens a page or menu with the module: `openModule`); one over 5 minutes late doesn't.
- **The display:** `acquire(owner, interval)`: `now` ticks at the shortest interval asked (the module asks 100 ms while its stopwatch shows, for tenths), only while one of them runs.
- **UI:** the `Stopwatch` widget shows the timer while it's set, else the stopwatch while it's going; left click pauses or resumes it (with neither, starts the stopwatch), right resets, middle laps. `content/Stopwatch/Stopwatch.qml` (popout and module): a Timer / Stopwatch switch (`properties.mode`, `auto` opening on whichever is going); the timer is a `CountdownTimer` (`content/parts/`, shared with caffeine's popout so both look the same: the field and `Stopwatch.presets` while idle, the ring, pause, +1 min and reset while set); the stopwatch's time, start-pause, lap, reset and laps.
- **Entry points:** IPC `stopwatch` (`timer <text>`, `toggleTimer`, `resetTimer`, `toggle`, `lap`, `reset`, `status`); launcher `/timer <duration> [label]` (a row previews it; pause and reset while set) and `/stopwatch [start|pause|lap|reset]`.

### Focus module
- `content/Focus/Focus.qml`: the dial (no task picker: the list's "work on this" picks it), the todo list, and today's events (`DayPane`; `CalendarManager` acquired only while `showAgenda` is on), side by side when wide. `showTimer` / `showTodos` / `showAgenda`.

### Settings
- `Todo`, `Pomodoro` and `Stopwatch` are Modules sections, scope `personal`: shared by every widget and module, carried by an export only with personal parts.
