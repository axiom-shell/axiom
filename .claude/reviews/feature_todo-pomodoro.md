# feature:todo-pomodoro
reviewed: e98fea2 2026-11-01  (full)

The todo list, pomodoro and timer/stopwatch match their doc almost line for line; the pure helpers and DeadlineTicker are sound. Open: deadlines ending up to an hour late after a suspend, a skipped focus session counted as finished, recent-timer chips re-parsing their label into the time, a deleted unreadable todo.json blocking saves, and about 34 lines of deletions plus option-gated parts built hidden.

## Open findings
- Major: [A pomodoro, timer or caffeine end due during a suspend fires up to an hour after waking](../../docs/dev/issues.md#a-pomodoro-timer-or-caffeine-end-due-during-a-suspend-fires-up-to-an-hour-after-waking)
- Major: [Skipping a focus session counts it as finished](../../docs/dev/issues.md#skipping-a-focus-session-counts-it-as-finished)
- Major: [A recent timer chip reads its label back as part of the duration](../../docs/dev/issues.md#a-recent-timer-chip-reads-its-label-back-as-part-of-the-duration)
- Major: [A todo.json deleted while unreadable blocks every save until restart](../../docs/dev/issues.md#a-todojson-deleted-while-unreadable-blocks-every-save-until-restart)
- Cleanup: [Dead and forwarding members in the timer services and helpers](../../docs/dev/issues.md#dead-and-forwarding-members-in-the-timer-services-and-helpers)
- Cleanup: [PomodoroDial redraws DialControls' ring and buttons](../../docs/dev/issues.md#pomodorodial-redraws-dialcontrols-ring-and-buttons)
- Cleanup: [Focus and Pomodoro build the parts their properties turn off](../../docs/dev/issues.md#focus-and-pomodoro-build-the-parts-their-properties-turn-off)
- Minor: ticking off the pomodoro's task leaves it as the task (`components/content/parts/PomodoroDial.qml:97`, `services/apps/PomodoroManager.qml:37` `todoText`): the next notification names a done task and the picker holds a uid not among its options. Fix: `todoText` empty for a done item.
- Known, not re-filed: [Unbounded lists still built in full](../../docs/dev/issues.md#unbounded-lists-still-built-in-full) (laps, TodoList); [A dropdown in an edge menu card with nothing scrolling gets two rows](../../docs/dev/issues.md#a-dropdown-in-an-edge-menu-card-with-nothing-scrolling-gets-two-rows); [Eight modules' full layouts need more room than their fullMin sizes, even inside the padding](../../docs/dev/issues.md#eight-modules-full-layouts-need-more-room-than-their-fullmin-sizes-even-inside-the-padding) (Pomodoro, Focus); [Parts shown in one mode are built hidden in every mode, in ten modules and parts](../../docs/dev/issues.md#parts-shown-in-one-mode-are-built-hidden-in-every-mode-in-ten-modules-and-parts): its CountdownTimer item is fixed by #262's idle/set Loader, its Stopwatch and TodoList items stand; [Three row options nothing sets](../../docs/dev/issues.md#three-row-options-nothing-sets) (`showFocus`).

## Contract
Holds: todo.json `{ version: 1, items }` under `Paths.userDataPath` through FileManager write/watch (own writes skipped), unreadable file reported once and the list kept, nothing in the greeter; TodoItems' VTODO fields, `shown` order, `due` unset; IPC `todo` and `/todo`. PomodoroCycle with absolute `endsAt`, long break every `longBreakEvery`-th, auto-start flags; DeadlineTicker as both services' default child, restored in `onLoaded`, end re-checked in `_end`, single-shot alarm, 5-minute `late` rule, `axiom-pomodoro` / `axiom-stopwatch` notifications opening a page or menu; `now` ticks only while running and acquired, at the shortest interval asked; widget click mappings; IPC `pomodoro` / `stopwatch` and the four launcher commands; StopwatchClock's parse forms, idle-keeps-duration, `addTime` floor, recents (times of day and +1 min kept out), notification buttons only while idle; Stopwatch's mode switch, CountdownTimer's idle/set Loader, DialControls' keys/choices/wheel, lap flags from three laps, tab-separated copy; Focus acquires CalendarManager only with `showAgenda`; sections Modules, `personal`.

## Coverage
Read deeply: DeadlineTicker, PomodoroManager, StopwatchManager, TodoManager, StopwatchClock, PomodoroCycle, TodoItems, ChipRows, the three readers and schema sections, TodoList, Todo, PomodoroDial, Pomodoro, Focus, Stopwatch (module and widgets), CountdownTimer, DialControls, TimeRing, LauncherCommands' four commands. Outlined: FileManager, ConsumerRegistry, StyledComboEntry (`expandsInline`), IdleManager's ticker use, the logind watcher. Skipped: test files beyond the rows cited.

## History
- 2026-11-01 full: 8 findings (4 Major, 3 Cleanup, 1 Minor); recorded
