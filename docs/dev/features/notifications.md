# Notifications

> **Files:** `services/system/NotificationManager.qml`, `shell/Notifications.qml`, `components/surfaces/notifications/ToastStack.qml`, `components/surfaces/notifications/ToastItem.qml`, `components/methods/ToastMotion.qml`, `components/methods/NotificationMatch.qml`, `config/NotificationsConfig.qml`, `components/content/Notifications/Notifications.qml`, `components/views/Settings/NotificationsPreview.qml`
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

### Actions, replies and links
- `NotificationActions` draws every action but `default` (a click on the text) and `inline-reply`; with `hasActionIcons` each identifier is an icon name, shown in place of the label (the label a tooltip).
- The server advertises `inlineReplySupported`: `NotificationReply` (a field with the app's placeholder and a send button, `sendInlineReply`) shows under an entry or toast whose live notification `hasInlineReply`, built only then (a Loader). The list's bar popout takes the keyboard while one is offered (`NotificationManager.replyable` → `Panel.wantsKeyboardFocus`); the module sets `keyboard`.
- Body links (`bodyHyperlinksSupported`) open through `NotificationManager.openLink` (`xdg-open`).

### What removes an entry (NotificationsConfig)
- `maxEntries` and `maxAge` (ms) set the history's size and age.
- `clearOnFocus`: `CompositorManager.windowFocused` for a window of the entry's app (`NotificationMatch`).
- `followApps`: the app withdrawing it.
- `removeOnClick`.
- `closeRemoves`.

### Toasts
- `shell/Notifications` builds a `surfaces/notifications/ToastStack` per screen of `NotificationsConfig.screen` (`ShellManager.showsOn`). A toast goes on every screen (`hideEverywhere`) when the user closes it, or when its app or the list closes it.
- Toasts take their entry's uid when they're created (`uidOf`), because invoking an action can close the notification.
- **One toast** is a `ToastItem`: its timer (paused while hovered or replied to; `followApps` takes the app's own timeout), a sideways swipe, its actions and reply, and its motion. It's a card of its own (detached) or a row of the attached box.
- **Placement:** `edge`, `position`, `detached` and `gap`, as the OSD's and dock's.
  - **Detached:** cards in one Overlay-layer window covering the free area, held `gap` in from what's on each side (`ScreenEdgeManager.detachedGaps` / `heldInset`, as the detached launcher does).
    - The window has Normal exclusion; over a fullscreen window it ignores the zones, and the gaps are measured from the screen's edges.
    - Its input mask is the cards' bounds.
    - It's always mapped, lending `NotificationManager` its `imageHost`.
  - **Attached:** one `EdgePopout` box (no claim, no trigger) grown out of the border or a bar exactly as an OSD's or a floating edge menu's, whatever the bar (SurfaceContext).
    - The toasts are its rows, divided by hairlines.
    - Each row grows in from nothing and collapses as it leaves, and the rows' places follow their heights, so the box and the rows move as one.
- **Order and motion** (`methods/ToastMotion`):
  - Newest at the stack's start, the rest pushed along. A top or bottom stack grows away from its edge, a side one along it (down from its middle).
  - All of a stack's toasts slide in from and out to one edge, picked while it's empty (`slideEdge`). Attached, it's the stack's own edge. Detached, it's the screen edge nearest the stack, bars aside: a corner stack slides sideways, a centred one from its edge.
  - They slide within the window, so they pass under the bars.
  - When one leaves, the others glide into its place (`leave`):
    - The one at the stack's start slides all the way out.
    - One further along a stack sliding the way it grows tucks behind the others, sliding half its height toward the edge as it fades.
  - `motion.style` (slide, fade, none) and `motion.direction` (auto or an edge) override it.
- **Making way:** toasts hold no `PopoutClaim`. The stack reads `PopoutManager.entries` and moves along its growth past any popout shown over it (`PopoutGeometry.makeWay`), gliding back when it closes.
  - An attached stack on a side edge moves along it, still attached.
  - One on the top or bottom, pushed away from its edge, shows as cards while it is, and joins the edge again after.
- **Blur:**
  - A card's fill is drawn by the blur window: a `BlurShape` rect following its slide, clipped to the window (`notifications` is among `LayerStack.blurBacked`).
  - The attached box blurs as an EdgePopout does.
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
