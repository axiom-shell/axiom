# feature:screenshots-recording
reviewed: e750d42 2026-11-01  (full)

The system holds most of its contract (one picker, one watchdog, the niri grim path, the recorder's lifetime). Open: the picker's Screenshot / Record switch keeps the first kind's folder and sound, and a capture notification opens the newest capture, not its own.

## Open findings
- Major: [Switching an open picker between screenshot and recording keeps the first kind's folder and sound](../../docs/dev/issues.md#switching-an-open-picker-between-screenshot-and-recording-keeps-the-first-kinds-folder-and-sound)
- Major: [Clicking an older capture's notification opens the newest capture](../../docs/dev/issues.md#clicking-an-older-captures-notification-opens-the-newest-capture)
- Cleanup: [The screenshot's Edit notification rebuilds sendNotification's actions](../../docs/dev/issues.md#the-screenshots-edit-notification-rebuilds-sendnotifications-actions)
- Cleanup: [ScreenRecord's recording time repeats StopwatchClock.format, and the bar's differs past an hour](../../docs/dev/issues.md#screenrecords-recording-time-repeats-stopwatchclockformat-and-the-bars-differs-past-an-hour)

Unrecorded (Minor):
- The ScreenRecord card's "Screen" records an edge menu still open (`ScreenRecord.qml:56` `start`, `ScreenshotManager.qml:143`).
- Enter takes the whole screen in the chat's pick, whose hints hide it (`ScreenshotPickerWindow.qml:205`, `:400`).
- hasSystemAudio's comment says pactl finds the monitor (`ScreenshotManager.qml:55`).
- The feature doc's Files header leaves out `components/content/Screenshot/Screenshot.qml`.

## Contract
Holds: entry points (binds via table.json, IPC screenshot/screenRecord, launcher, cards, chat `pick`); per-screen picker, only the captured screen for `screen`; window -> region without supports.windowGeometry; crop at buffer resolution; grim path on !supports.outputCapture with frames dropped on close/cancel; single watchdog + frameArrived; folders with ~ expanded; ClipboardManager.copyFile; wf-recorder -g/-o, system sound via sh -c exec, SIGINT via pkill -P $PPID, pre-reload/lost-answer paths; recordAudio saved with copyOnly; bar widget hidden unless recording; Privacy indicator; recent list (12, one find at a time, stale folder dropped).

## Coverage
Read deeply: ScreenshotManager, ScreenshotPickerWindow, content/ScreenRecord, bar/widgets/ScreenRecord, shell/Screenshot, config/Screenshots. Outlined: content/Screenshot, LauncherCommands, KeybindManager.callLabels, actions/table.json, cli/named.go, NotificationManager.sendNotification/openApp, StopwatchClock.format. Skipped: ScreenRecord on the lock screen / greeter (security audit).

## History
- 2026-11-01 full: 8 findings (2 Major, 2 Cleanup, 4 Minor); recorded
