# Todo, pomodoro and stopwatch

> **Files:** `qml/services/apps/TodoManager.qml`, `qml/services/apps/PomodoroManager.qml`, `qml/components/methods/TodoItems.qml`, `qml/components/methods/PomodoroCycle.qml`, `qml/services/apps/StopwatchManager.qml`, `qml/services/apps/DeadlineTicker.qml`, `qml/components/methods/StopwatchClock.qml`, `qml/config/StopwatchConfig.qml`, `qml/components/bar/widgets/Stopwatch/Stopwatch.qml`, `qml/components/content/Stopwatch/Stopwatch.qml`, `qml/config/TodoConfig.qml`, `qml/config/PomodoroConfig.qml`, `qml/components/bar/widgets/Todo/Todo.qml`, `qml/components/bar/widgets/Pomodoro/Pomodoro.qml`, `qml/components/content/Todo/Todo.qml`, `qml/components/content/Pomodoro/Pomodoro.qml`, `qml/components/content/Focus/Focus.qml`, `qml/components/content/parts/TodoList.qml`, `qml/components/content/parts/PomodoroDial.qml`, `qml/components/content/parts/TimeRing.qml`, `qml/components/content/parts/CountdownTimer.qml`, `qml/components/content/parts/DialControls.qml`, `qml/components/methods/ChipRows.qml`
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
  - Every `longBreakEvery`-th finished focus session is followed by a long break. A focus session counts once started (`advance`): one skipped before it started goes to a short break uncounted.
  - `Pomodoro.autoStartBreaks` / `autoStartWork` say whether the next phase starts by itself.
- **Shared plumbing:** both services own a `DeadlineTicker` (`qml/services/apps/`): their saved values, the alarm at the deadline, the ticking `now` with its `acquire`/`release`, and the notification (`notify`, `notificationClicked`). Each service keeps only its own state shape (`restore`) and what its end does (`ended`). The ticker is a `Scope` declared as its service's default child (`DeadlineTicker { id: _ticker … }`), never in a named property: a Singleton passes a reload only to its default Reloadable children, matched by order, so anything else starts with empty values on every reload. Its `PersistentProperties`' `loaded` restores the values (from the state file when there's nothing to copy, a restart) and sets `ready`; nothing acts on `values` before.
- **Kept:** in the ticker's `PersistentProperties` (a QML reload) and StateManager `pomodoro` (a restart), with the todo it's for (`todoUid`).
- **The end:** handled once per end (the ticker re-checks the deadline before `ended`, since a restart can queue it twice); one single-shot timer to `endsAt`, at most an hour at a time, running with nothing showing the timer (the service is created from `qml/shell.qml`'s `_services`). At the end it advances and, with `Pomodoro.notify`, sends a notification (`desktopEntry` `axiom-pomodoro`; a click opens a page or edge menu with a Pomodoro or Focus module: `openTimer`). A phase that ended over 5 minutes before axiom noticed (it wasn't running) advances without one.
- **The display:** `now` ticks once a second only while running and something has `acquire(owner)`d it (the widget, the modules).
- **UI:** `PomodoroDial` (ring, phase, a dot per session to the long break, stop / start-pause / skip, task picker). In a popout or edge menu the task picker's list opens inline (`StyledComboEntry.expandsInline`): a dropdown window there isn't one the popout's hover and blur reach. The `Pomodoro` widget: time left while not idle, colored by phase; left click toggles, right skips, middle stops. Its popout and module are `content/Pomodoro/Pomodoro.qml`.
- **Entry points:** IPC `pomodoro` (`start`, `pause`, `toggle`, `skip`, `stop`, `reset`, `status`); launcher `/pomodoro [start|pause|skip|stop]`.

### Timer and stopwatch
- **State** (`StopwatchClock`, pure, `tst_StopwatchClock`): a timer `{ running, endsAt, remaining, duration, label }` and a stopwatch `{ running, startedAt, elapsed, laps }`, both absolute, both able to run at once.
  - `StopwatchClock.parse` reads a duration and an optional label: `10m`, `1h30m`, `90s`, `1:30` (m:s), `1:02:03`, a plain number as minutes, `10m tea`. Given `now`, also a time of day after `at`, `until` or `@` (`at 17:30`, `until 5pm`, `@9:15am standup`): the time until then, tomorrow's once it's past, marked `clock`. Every caller that starts a timer passes `Date.now()`.
  - A timer that ends goes back to idle keeping its duration and label (`toggleTimer` starts it again).
  - `addTime` takes a negative `ms` too (the wheel, `-`), never leaving under a second; it needs `now` then.
  - **Recent:** `StopwatchManager.recent`, the last 3 timers started (`{ ms, label }`, `pushRecent`, kept in the same state file), the newest first. A time of day stays out of them.
- **Kept:** the `DeadlineTicker`'s `PersistentProperties` + StateManager `stopwatch`, as the pomodoro. The end runs with no consumers (created from `_services`) and notifies with `Stopwatch.notify` (`desktopEntry` `axiom-stopwatch`, a click opens a page or menu with the module: `openModule`); one over 5 minutes late doesn't. The notification's buttons (`+1 min`, `Restart`) start a 1-minute timer with the same label (kept out of the recent ones) or the same duration again, unless another timer was started meanwhile.
- **The display:** `acquire(owner, interval)`: `now` ticks at the shortest interval asked (the module asks 100 ms while its stopwatch shows, for tenths), only while one of them runs.
- **UI:** the `Stopwatch` widget shows the timer while it's set, else the stopwatch while it's going; left click pauses or resumes it (with neither, starts the stopwatch), right resets, middle laps. `content/Stopwatch/Stopwatch.qml` (popout and module): a Timer / Stopwatch switch (`properties.mode`, `auto` opening on whichever is going); the timer is a `CountdownTimer` (`content/parts/`, shared with caffeine's popout so both look the same).
  - **Idle:** the field, with what it reads as at its right end (`5m · ends 14:05`, or "Not a duration" in red), over `Stopwatch.presets` and the recent timers that aren't presets (`history` icon), spread evenly over full-width rows (`ChipRows.split`).
  - **Set:** `DialControls`: the ring (sweeping between ticks, the warning colour in the last minute or fifth) with the time and the label or "Ends 14:05", reset, pause/resume (filled) and +1 min. A right click or long press on +1 min swaps the buttons for +5m / +10m / +30m; the wheel over the ring and `+` / `-` add or take a minute; Space pauses, `R` resets once the dial has the keyboard (clicked, or started from the field). Centred in a card and side by side in a wide, short one.
  - **The stopwatch:** `DialControls` too, its ring sweeping the current minute (accentAlt), the time in tenths, "Lap n" while laps are taken; reset, start-pause, lap (`L`). The laps under it share a card's height with the ring, the fastest green and the slowest red from three laps on (`lapRows`' flags), with Copy (`lapsText`, tab-separated).
- **Entry points:** IPC `stopwatch` (`timer <text>`, `toggleTimer`, `resetTimer`, `toggle`, `lap`, `reset`, `status`); launcher `/timer <duration> [label]` (a row previews it; pause and reset while set) and `/stopwatch [start|pause|lap|reset]`.

### Focus module
- `content/Focus/Focus.qml`: the dial (no task picker: the list's "work on this" picks it), the todo list, and today's events (`DayPane`; `CalendarManager` acquired only while `showAgenda` is on), side by side when wide. `showTimer` / `showTodos` / `showAgenda`.

### Settings
- `Todo`, `Pomodoro` and `Stopwatch` are Modules sections, scope `personal`: shared by every widget and module, carried by an export only with personal parts.
