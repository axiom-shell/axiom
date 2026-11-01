# feature:notifications
reviewed: 47db042 2026-11-01  (full)

The server, history, per-app rules, DND and the toast stack match their doc and the helpers are tested. Open: a transient notification toasts blank (deleted untracked object), removeOnClick does nothing from toasts, the list's delegates use their own easing and repeat one swipe mechanism, and clearAll spawns a process per entry.

## Open findings
- Major: [A transient notification toasts blank](../../docs/dev/issues.md#a-transient-notification-toasts-blank)
- Major: [removeOnClick never removes a clicked toast's entry](../../docs/dev/issues.md#removeonclick-never-removes-a-clicked-toasts-entry)
- Major: [The notification list's delegates animate with their own easing](../../docs/dev/issues.md#the-notification-lists-delegates-animate-with-their-own-easing)
- Cleanup: [The history's group and entry delegates repeat one swipe-away mechanism](../../docs/dev/issues.md#the-historys-group-and-entry-delegates-repeat-one-swipe-away-mechanism)
- Cleanup: [clearAll removes each cached image twice, one process per entry](../../docs/dev/issues.md#clearall-removes-each-cached-image-twice-one-process-per-entry)
- Minor: notifications.md says the history is "capped at 100" (it's `maxEntries`, 10–500) and its handler list misses DependencyManager and DeadlineTicker.
- Minor: `NotificationManager.uidOf` only forwards `_uidOf` (3 lines).
- Minor: a notification with an app name but no desktop entry or default action isn't clickable, though `openApp` would match its app (product question: intended?).
- Minor: the critical stripe Rectangle is written twice (ToastItem.qml:305, NotificationGroupDelegate.qml:205).

## Contract
Holds: history (order, prune by size and age, debounced atomic save), liveNotification, activate/openApp/windowOf, NotificationMatch (tested), keepOnReload adoption, the list's grouping and swipes, actions/reply/links, clearOnFocus, followApps, closeRemoves, toasts per screen with showsOn and hideEverywhere, timer pauses, placement detached and attached, ToastMotion (tested), yielding under popouts, blur, the settings Show button, image caching, per-app rules, DND and its schedule, registerHandler/dismissApp. Not holding: the doc's "capped at 100" and handler list (Minor).

## Coverage
Read deeply: all 16 files in scope, plus Quickshell's notifications server.cpp/notification.cpp (tracking, invoke, reply). Outlined: the Notifications schema bounds, ShellManager.showsOn, General.screensFor, the registerHandler callers, the tests' case lists. Skipped: PopoutGeometry's toast rank, EdgePopout and BlurShape internals (other systems).

## History
- 2026-11-01 full: 9 findings (3 Major, 2 Cleanup, 4 Minor); recorded
