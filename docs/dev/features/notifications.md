# Notifications

> **Files:** `services/system/NotificationManager.qml`, `shell/Notifications.qml`, `config/NotificationsConfig.qml`, `components/content/Notifications/Notifications.qml`, `components/views/Settings/NotificationsPreview.qml`
> **Config:** `Notifications.*` (reader `NotificationsConfig`)
> **Related:** [Self-update](self-update.md) (registerHandler), [Calendar](calendar.md) (reminders), [Grow and expand](../overlay/grow-expand.md)

The D-Bus notification server, its persistent history, the toasts, and do-not-disturb.

### History
- `NotificationManager` is the D-Bus notification server plus a persistent history.
- `entries` are plain objects, newest first, capped at 100.
- An entry stays until the user removes it, even when the app withdraws the notification. Ways to remove one:
  - `dismiss(uid)`
  - `clearAll()`
  - the `notifications` IPC target.
- The history is saved to `$XDG_STATE_HOME/axiom/notifications.json` (atomically, through axiom: `FileManager.write`).
- `liveNotification(uid)` gives the still-open `Notification` (needed for actions). Entries restored from disk open their app instead (`openApp`).
- `keepOnReload` keeps live notifications across QML reloads.

### What removes an entry (NotificationsConfig)
- `maxEntries` and `maxAge` (ms) set the history's size and age.
- `clearOnFocus`: an `activewindow` event whose class matches the entry's desktop entry or app name.
- `removeOnClick`.
- `closeRemoves`.

### Toasts
- `shell/Notifications` stacks the toasts once per screen of `NotificationsConfig.screen` (`ShellManager.showsOn`).
- A toast the user closes closes on every screen.
- Toasts take their entry's uid when they're created (`uidOf`), because invoking an action can close the notification.
- **Placement:** `NotificationsConfig` sets the toasts' corner and gaps. They are measured inside the work area by an Overlay-layer anchor window with Normal exclusion, like `OverlayPanel`. While the screen shows a fullscreen window the anchor ignores exclusive zones, so the gaps are measured from the screen's edges.
- **Test notification:** the settings card's intro (`views/Settings/NotificationsPreview`, its `x-intro`) has a Show button that sends one through `sendNotification`, so it toasts with the settings as edited (readers read the previews), as the OSD and dock cards' Show does.

### Images
- Cached as PNGs in `$XDG_STATE_HOME/axiom/notifications/`.
- On load, an entry whose image file is gone loses its `image` (`_dropMissingImages`), so its avatar shows the app icon without a `Cannot open` warning.
- Rendered through an `imageHost` item that `shell/Notifications` lends the service, since grabbing an image needs a window.

### Do not disturb
- `dnd` is readonly; change it with `setDnd` / `toggleDnd`.
- Saved in `~/.local/state/axiom/ui/notifications.json`.

### Click handlers
- `NotificationManager.registerHandler(desktopEntry, handler)` routes a click on one of axiom's own notifications by its `desktopEntry`.
- Services that register one: SelfUpdateManager (`axiom-update`, see [Self-update](self-update.md)), CalendarManager (`axiom-calendar`, see [Calendar](calendar.md)), ScreenshotManager and GreeterManager.
