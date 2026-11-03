# Notifications

> **Files:** `qml/services/system/NotificationManager.qml`, `qml/services/system/NotificationFiles.qml`, `qml/services/system/ConnectionNotes.qml`, `qml/components/methods/NotificationLevel.qml`, `qml/components/content/parts/notifications/NotificationQuietHeader.qml`, `qml/shell/Notifications.qml`, `qml/components/surfaces/notifications/ToastStack.qml`, `qml/components/surfaces/notifications/ToastItem.qml`, `qml/components/methods/ToastMotion.qml`, `qml/components/methods/NotificationMatch.qml`, `qml/config/NotificationsConfig.qml`, `qml/components/content/Notifications/Notifications.qml`, `qml/components/views/Settings/NotificationsPreview.qml`, `qml/components/content/parts/notifications/`, `backend/internal/notification/`
> **Config:** `Notifications.*` (reader `NotificationsConfig`)
> **Related:** [Self-update](self-update.md) (registerHandler), [Drives](drives.md) (buttons), [Calendar](calendar.md) (reminders), [Grow and expand](../overlay/grow-expand.md)

The D-Bus notification server, its persistent history, the toasts, and do-not-disturb.

### Levels
Every notification has a level (`methods/NotificationLevel`, the single source of the decision):
| Level | Toast | Kept | Badge |
|---|---|---|---|
| `alert` | yes (not through do not disturb, but a critical one) | the list | counted |
| `silent` | never | the list's **Quiet** section | not counted |
| `toast` | yes | never (tracked only while its toasts last) | — |
| `off` | never | never | — |

- An app's level is its rule's (`Notifications.apps[].level`), else `Notifications.lowUrgency` for a low-urgency one, else alert (`levelOf`). A critical one is never silent: a Silent rule (one for `axiom` too) lets it alert, as Block still blocks it. Urgent is a critical alert: it stays (`criticalStays`) and shows through do not disturb. A transient one (the hint) is never kept, whatever its level (`files`).
- A silent app notification is still live: its actions and reply work from the Quiet section.
- The shell's own choose theirs: `sendNotification`'s `silent` (and `transient`). A rule naming one of its sources exactly by desktop entry (`axiom-update`, `axiom-drives`, …; `_sourceLevel`, never a rule for `axiom`, which is for its alerts) overrides `silent`.
- The maintainer's split (2026-11-02): the shell's status that nobody waits on is silent, what needs attention alerts, and answers to what was just done are OSD cards or toasts that aren't kept (`ShellManager.confirm` / `refuse`). Low-urgency app notifications default to silent.

### Keys
- A `key` is held by one entry at a time: a newer notification with it replaces the entry (and closes its toast) instead of piling up. The shell's own carry it as `sendNotification`'s `key` (the `x-axiom-key` hint over D-Bus, `_keyOf`; filed directly for a silent one, `_dropKey`). `dismissKey(key)` removes it.
- Keys in use: `drive:<id>` (a drive's last event), `monitor:<connector>`, `battery`, `screenshot`, `recording`, `update-available` / `update-applied` / `update-failed` / `update-build`, `greeter-outdated`, `theme-failed`, `dev-build`, `vpn:<uuid>`, `updates`, `config-migrated`, `dnd-summary`, `network:<name>` / `bluetooth:<address>` / `tailscale:tailscale`.

### History
- `NotificationManager` is the D-Bus notification server plus a persistent history.
- `entries` are plain objects, newest first (`silent` and `key` among their fields). `alerts` and `quiet` split them; `count` / `countLabel` (the badge, the header, the launcher) count only the alerts, `quietCount` the rest.
- **Limits** (`NotificationLevel.kept`): alerts by `maxEntries` / `maxAge`, silent ones apart by `quiet.maxEntries` / `quiet.maxAge` (default 50 and 7 days), so status notes never push real notifications out.
- An entry stays until the user removes it, or (with `followApps`) until its app withdraws the notification (`closed` with `CloseRequested`). Ways to remove one:
  - `dismiss(uid)`
  - `clearAll()`
  - the `notifications` IPC target.
- The history is saved to `$XDG_STATE_HOME/axiom/notifications.json` (atomically, through axiom: `FileManager.write`), half a second after a change, by `NotificationFiles` (the manager's `_files`, which also holds the image cache).
- `liveNotification(uid)` gives the still-open `Notification` (needed for actions). Entries restored from disk open their app instead (`openApp`).
- **A click** goes through `activate(entry, live)`: it runs the default action, then with `clickFocuses` focuses the app's window itself, since the server sends no xdg-activation token with the action and niri (Hyprland without focus_on_activate too) refuses the app's own raise. Without a default action it's `openApp`: a registered handler, else the app's window, else a launch.
- **Which windows are an entry's app** (`windowOf`, clear on focus): `methods/NotificationMatch` reduces both sides to keys (the desktop entry, app name, the desktop entry's id and `startupClass`; the window's class and its desktop entry's id), lowercased, last reverse-DNS part, without `-desktop`/`-bin`, and they match when they share one (`Vesktop` ↔ `dev.vencord.Vesktop`, `Telegram` ↔ `org.telegram.desktop`).
- `keepOnReload` keeps live notifications across QML reloads.
- **The list** (`content/Notifications`, `parts/notifications/`): one card per app (`NotificationLevel.groupKey`); the shell's own (app name `axiom`) get a card per source, by desktop entry, named from `NotificationLevel.sources` (`axiom-drives` "Drives", …; one with no desktop entry, or one not listed, "axiom"). A lone or collapsed card swipes away whole, either way, dismissing what it holds (`NotificationGroupDelegate`); an expanded one swipes entry by entry (`NotificationItemDelegate.swipeable`).
- **The Quiet section**, pinned to the end of the menu: a separator, a `NotificationQuietHeader` (a `FoldRow`: its count, a dot while `quietUnseen`, its own clear, `clearQuiet`), then the silent ones' app cards (`quiet`, a fainter fill) in a `FoldingColumn` built only while open, in its own scroll view up to `quietCap` (half the list's room: half the card's column, or half `maxListHeight` in a popout); opening it shrinks the alerts (or the empty state) above, so it grows toward them. Folded shut by default; `NotificationManager.quietOpen` / `setQuietOpen` keep it across restarts (`axiom notifications toggle-quiet`, `clear-quiet`: the IPC's `toggleQuiet` / `clearQuiet`), and a reopened one's cards start collapsed (they're rebuilt). Clear all (there while there are alerts) slides out both parts' cards and clears both.
- **Unseen:** `quietUnseen` while a silent one is newer than `_quietSeen` (saved with the other state), which the menu moves to the newest whenever it shows the section open (`markQuietSeen`). A keyed one replaced is new again, so a note is only re-sent when it changes (`UpdatesManager._note` leaves a kept one saying the same).

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
- `qml/shell/Notifications` builds a `surfaces/notifications/ToastStack` per screen of `NotificationsConfig.screen` (`ShellManager.showsOn`). A toast goes on every screen (`hideEverywhere`) when the user closes it, or when its app or the list closes it.
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
- **Under popouts:** the stack holds a resident `PopoutClaim` (kind `toast`, `toasts:<screen>`) ranked under every popout (`PopoutGeometry.rankOf`: -1). One shown over it yields it (`covered`): its toasts slide out of sight, their timers paused, and slide back once that closes; toasts arriving under one wait the same way. Docks and toasts never collide, or an always-shown dock would hide a stack over it for good. The maintainer, 2026-10-30: "Yield, then come back".
- **Blur:**
  - A card's fill is drawn by the blur window: a `BlurShape` rect following its slide, clipped to the window (`notifications` is among `LayerStack.blurBacked`).
  - The attached box blurs as an EdgePopout does.
- A toast's click, action or reply with `removeOnClick` dismisses its entry even once the toast is leaving (Quickshell closes a non-resident notification inside `invoke()`).
- **Test notification:** the settings card's intro (`views/Settings/NotificationsPreview`, its `x-intro`) has a Show button that sends one through `sendNotification`, so it toasts with the settings as edited (readers read the previews), as the OSD and dock cards' Show does.
- **The shell's own:** `sendNotification` asks the daemon (`notify.send`, `backend/internal/notification`), which sends it over the session bus (`org.freedesktop.Notifications.Notify`, so the shell's own server shows it like any other) with its `icon` as the `image-path` hint (as `notify-send -i` sent it), its `desktopEntry` and `urgency` hints, `key` as `x-axiom-key` and `transient` as `transient`. Its `opts.actions` (`[{ id, label }]`) become the notification's buttons: the call still answers at once with the notification's id, and the daemon keeps listening on its own bus connection (as notify-send's process did, never holding a call open) until one is picked (`ActionInvoked`) or the notification closes (`NotificationClosed`), the bus closes or the shell disconnects; then it pushes `notify.action` (`{ id, action }`, `""` for none) to that connection alone, and `opts.onAction(id)` gets the one clicked. Nothing else is installed for it (it was `notify-send`, which no package axiom brings depends on; maintainer, 2026-11-01: "yes - note roadmap and issues accordingly to replace notify-send into go"). A QML reload while it's up loses the callback, so its buttons then do nothing. The timer's end and caffeine's warning use it (`DeadlineTicker.notify`).
- **Filed silently:** `sendNotification`'s `opts.silent` puts an entry straight into the Quiet section (`_file`: no D-Bus notification behind it, so no toast; `live` false; an icon that's a path is cached as its picture). Its `actions` and `data` are saved on the entry: the list draws the buttons (`NotificationItemDelegate._filed`, shaped as a live one's) and a pick runs the desktop entry's handler as `handler(entry, id)` (`invokeFiled`), so they work after a reload, unlike `onAction`. A shell alert with buttons but no `onAction` goes to that handler too.
- **Events an OSD may show** (a drive, the battery, a monitor, a screenshot) go through `announce(type, notify, summary, body, opts)`: `OSDConfig.routeOf` picks the OSD's card (filed silently, in Quiet, with `OSD.cardsToHistory`), a notification (at the level its `opts` give), or nothing, and an urgent one notifies beside its card unless `notify` is off ([OSD](osd.md) › Where events go).

### What the shell sends
- **Silent:** the OSD's filed copies; a drive plugged in, mounted, unmounted or disconnected (with Open / Eject / Unlock buttons through `DrivesManager._pick`); a monitor connected or disconnected (`axiom-monitors`, a click opens its settings); main's new commits and "updated to" ([Self-update](self-update.md)); the login screen's update ([Greeter install](greeter-install.md)); pending package updates while an Updates widget checks (`UpdatesManager._note`, an Upgrade button, gone once none are); a config migration (`SettingsManager._noteMigration`, once per version from `ConfigManager.migrated`, what axiom's `State.migrated` says); do not disturb ending with the alerts it held back (`_dndMissed`, kept across restarts); with `quiet.connectivity`, the network, Bluetooth devices and Tailscale connecting and disconnecting (`ConnectionNotes`, a default child of each owner: a change that holds 3 s, nothing in the first 10 s).
- **Alert:** a battery low (critical: urgent), a VPN dropping, a drive pulled without ejecting, in use, failing to eject or Safe to remove, the insert question (`onInsert` ask), a screenshot or recording saved (where no OSD shows it) or failed, the theme failing, the dev build failing (only a failing streak's first build, then "works again" at the next success: `methods/DevBuildStreak`, the streak in StateManager's `dev-build`, so it outlasts the re-exec a build starts; dev mode's notifications, the live-config one too, only while `devNotifications`), a missing font, the compositor's takeover questions (urgent), a release available, an update failing, calendar reminders, the timer, pomodoro and caffeine.
- **Not kept:** "Added …" from the calendar's quick add (`ShellManager.confirm`), refusals (`ShellManager.refuse`: no chat or notes module, …), the Battery and Privacy widgets' clicks (`transient`).

### Images
- Cached as PNGs in `$XDG_STATE_HOME/axiom/notifications/`.
- On load, an entry whose image file is gone loses its `image` (`_dropMissingImages`), so its avatar shows the app icon without a `Cannot open` warning.
- Rendered through an `imageHost` item that `qml/shell/Notifications` lends the service, since grabbing an image needs a window.

### Per-app rules
- `Notifications.apps`: per app (`app`, matched through `NotificationMatch` against the notification's keys, as its windows are), its `level` (Levels; `toast` and transient ones get no entry and are tracked only while a toast shows them: `qml/shell/Notifications` calls `toastsGone` once no screen does, which expires it, and a reload expires one left over; config v92 made `toasts` / `history` into it), its urgency (`urgency`, over the app's: `urgencyOf`, which the entry, the toast and do not disturb use) and its toast duration (`timeout`, ms; -1 the default: `timeoutOf`). `ruleFor` finds an entry's or notification's rule. The App field suggests (`x-suggestions: notificationApps`) the apps in the history and the shell's sources (`NotificationLevel.sources`, chips by name, filled in as the desktop entry `_sourceLevel` matches).

### Do not disturb
- `dnd` is readonly; change it with `setDnd` / `toggleDnd`. Binds, hot corners and `axiom dnd` reach it through the `dnd` IPC target (`toggle`, `enable`, `disable`, `status`).
- `Notifications.dnd.schedule` turns it on at `startAt` and off at `endAt` through a `DailySchedule` (as Night Light's): a switch by hand lasts until the next of them.
- Critical notifications still toast through it unless `dnd.allowCritical` is off; everything goes to the history either way. The alerts it held back are counted, and noted silently when it turns off.
- Saved in `~/.local/state/axiom/ui/notifications.json`.

### Click handlers
- `NotificationManager.registerHandler(desktopEntry, handler)` routes a click on one of axiom's own notifications by its `desktopEntry`.
- `NotificationManager.dismissApp(desktopEntry)` removes every notification of that `desktopEntry`: one of axiom's asking for something to be done goes away once it's done (the login screen's update, the "available" one after a self-update, a missing font once it's installed, a drive's once it's unplugged).
- Services that register one: SelfUpdateManager (`axiom-update`, see [Self-update](self-update.md)), CalendarManager (`axiom-calendar`, see [Calendar](calendar.md)), ScreenshotManager, GreeterManager and DrivesManager (`axiom-drives`: a click opens the Drives module, the buttons mount, open, unlock or eject; see [Drives](drives.md)).
