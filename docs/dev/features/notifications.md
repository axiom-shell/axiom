# Notifications

> **Files:** `services/system/NotificationManager.qml`, `shell/Notifications.qml`, `config/NotificationsConfig.qml`, `components/content/Notifications/Notifications.qml`, `components/views/Settings/NotificationsPreview.qml`
> **Config:** `Notifications.*` (reader `NotificationsConfig`)
> **Related:** [Self-update](self-update.md) (registerHandler), [Calendar](calendar.md) (reminders), [Grow and expand](../overlay/grow-expand.md)

The D-Bus notification server, its persistent history, the toasts, and do-not-disturb.

### History
- `NotificationManager` is the D-Bus notification server plus a persistent history.
- `entries` are plain objects, newest first, capped at 100.
- An entry stays until the user removes it, or (with `followApps`) until its app withdraws the notification (`closed` with `CloseRequested`). Ways to remove one:
  - `dismiss(uid)`
  - `clearAll()`
  - the `notifications` IPC target.
- The history is saved to `$XDG_STATE_HOME/axiom/notifications.json` (atomically, through axiom: `FileManager.write`).
- `liveNotification(uid)` gives the still-open `Notification` (needed for actions). Entries restored from disk open their app instead (`openApp`).
- **A click** goes through `activate(entry, live)`: it runs the default action, then with `clickFocuses` focuses the app's window itself, since the server sends no xdg-activation token with the action and niri (Hyprland without focus_on_activate too) refuses the app's own raise. Without a default action it's `openApp`: a registered handler, else the app's window, else a launch.
- **Which windows are an entry's app** (`windowOf`, clear on focus): `methods/NotificationMatch` reduces both sides to keys (the desktop entry, app name, the desktop entry's id and `startupClass`; the window's class and its desktop entry's id), lowercased, last reverse-DNS part, without `-desktop`/`-bin`, and they match when they share one (`Vesktop` ↔ `dev.vencord.Vesktop`, `Telegram` ↔ `org.telegram.desktop`).
- `keepOnReload` keeps live notifications across QML reloads.
- **The list** (`content/Notifications`, `parts/notifications/`): one card per app. A lone or collapsed card swipes away whole, either way, dismissing what it holds (`NotificationGroupDelegate`); an expanded one swipes entry by entry (`NotificationItemDelegate.swipeable`).

### What removes an entry (NotificationsConfig)
- `maxEntries` and `maxAge` (ms) set the history's size and age.
- `clearOnFocus`: `CompositorManager.windowFocused` for a window of the entry's app (`NotificationMatch`).
- `followApps`: the app withdrawing it.
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
- `NotificationManager.dismissApp(desktopEntry)` removes every notification of that `desktopEntry`: one of axiom's asking for something to be done goes away once it's done (the login screen's update, the "available" one after a self-update, a missing font once it's installed).
- Services that register one: SelfUpdateManager (`axiom-update`, see [Self-update](self-update.md)), CalendarManager (`axiom-calendar`, see [Calendar](calendar.md)), ScreenshotManager and GreeterManager.
