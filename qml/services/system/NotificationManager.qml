pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

import qs.config
import qs.services.core
import qs.services.compositor
import qs.components.methods

/*
 * NotificationManager is the DBus notification server and the notification
 * history. Every notification (bar transient ones) becomes an entry that
 * stays until the user removes it (dismiss, swipe, clear all), even if its
 * app withdraws it, and survives restarts: entries are saved to
 * $XDG_STATE_HOME/axiom/notifications.json, their images cached as small
 * PNGs beside it (raw image data is gone once the notification is).
 *
 * An entry is a plain object:
 *   { uid, nid, appName, appIcon, desktopEntry, summary, body, image,
 *     urgency, time, live, silent, key, actions, data }
 * `live` while its Notification is still around (liveNotification(uid)),
 * so its actions work; restored or withdrawn entries have none. `silent`
 * ones (NotificationLevel: the shell's status, apps set to Silent) sit in
 * the list's Quiet section, never toast and aren't counted. A `key` (the
 * shell's x-axiom-key hint) is held by one entry at a time: a newer one
 * replaces it. `actions` and `data` are a filed one's (sendNotification's
 * silent), run by its desktop entry's handler (registerHandler).
 *
 * The history keeps NotificationsConfig.maxEntries alerts and
 * quietMaxEntries silent ones, none older than their age limits; with
 * clearOnFocus an app's entries go when one of its windows is focused,
 * with followApps one its app withdraws goes too.
 */
Singleton {
  id: root

  // Newest first, silent ones among them
  property var entries: []
  // The alerts (the list, the badge) and the silent ones (its Quiet
  // section), each newest first
  readonly property var alerts: entries.filter(e => !e.silent)
  readonly property var quiet: entries.filter(e => !!e.silent)
  // The alerts only: silent ones are never counted
  readonly property int count: alerts.length
  readonly property int quietCount: quiet.length
  // The count for a badge: "99+" past 99
  readonly property string countLabel: count > 99 ? "99+" : String(count)
  readonly property var _limits: ({
      maxEntries: NotificationsConfig.maxEntries,
      maxAge: NotificationsConfig.maxAge,
      quietMaxEntries: NotificationsConfig.quietMaxEntries,
      quietMaxAge: NotificationsConfig.quietMaxAge
    })

  // Do Not Disturb: no toasts but critical ones (notifications still go
  // into the history). Kept across restarts. Set through setDnd/toggleDnd,
  // or by its schedule (NotificationsConfig.dnd).
  readonly property bool dnd: root._dnd
  property bool _dnd: false
  on_DndChanged: {
    if (root._stateLoaded && !root._dnd)
      root._noteMissed();
    root._dndMissed = 0;
    root._saveState();
  }

  // Alerts kept from toasting by Do Not Disturb, noted (silently) once it
  // turns off
  property int _dndMissed: 0
  function _noteMissed() {
    const missed = root._dndMissed;
    if (missed === 0)
      return;
    root.sendNotification("axiom", I18n.tr("Do not disturb is off"), missed === 1 ? I18n.tr("1 notification came in while it was on.") : I18n.tr("{0} notifications came in while it was on.", missed), {
      "desktopEntry": "axiom-dnd",
      "icon": "notification-disabled",
      "key": "dnd-summary",
      "silent": true
    });
  }

  // Whether the list's Quiet section is open (kept across restarts)
  readonly property bool quietOpen: root._quietOpen
  property bool _quietOpen: false
  on_QuietOpenChanged: root._saveState()
  function setQuietOpen(open: bool): void {
    root._quietOpen = open;
  }

  // Whether a silent one came in (or a keyed one was replaced) since the
  // Quiet section was last seen open, as of _quietSeen (its newest's time)
  readonly property bool quietUnseen: root.quiet.some(e => e.time > root._quietSeen)
  property real _quietSeen: 0
  // The list shows the Quiet section open: what's in it is seen
  function markQuietSeen(): void {
    root._quietSeen = Math.max(root._quietSeen, root.quiet[0]?.time ?? 0);
  }
  on_QuietSeenChanged: root._saveState()

  function _saveState() {
    if (root._stateLoaded)
      root._state.save({
        dnd: root._dnd,
        dndMissed: root._dndMissed,
        quietOpen: root._quietOpen,
        quietSeen: root._quietSeen
      });
  }

  function setDnd(on: bool): void {
    root._dnd = on;
  }

  function toggleDnd(): void {
    root._dnd = !root._dnd;
  }

  // NotificationsConfig.dnd's schedule: on and off at its times; a switch
  // by hand lasts until the next of them
  DailySchedule {
    id: _dndSchedule
    name: "notificationsDnd"
    enabled: NotificationsConfig.dndSchedule
    ready: root._stateLoaded
    startAt: NotificationsConfig.dndStartAt
    endAt: NotificationsConfig.dndEndAt
    onDue: on => root.setDnd(on)
  }

  // Whether a live notification offers an inline reply: a surface listing
  // them takes the keyboard for its field
  readonly property bool replyable: root.entries.some(e => e.live && (root._live[e.uid]?.hasInlineReply ?? false))

  // An item in a window, set by the toast host (shell/Notifications):
  // caching an image renders it there
  property alias imageHost: files.host

  // A new notification to show as a toast (shell/Notifications)
  signal showPopup(variant notification)

  // The live Notification behind an entry, or null
  function liveNotification(uid) {
    return root._live[uid] ?? null;
  }

  // Removes an entry (and closes its notification, if it's still open)
  function dismiss(uid) {
    const entry = root.entries.find(e => e.uid === uid);
    if (!entry)
      return;
    root.entries = root.entries.filter(e => e.uid !== uid);
    root._forget(entry);
    root._save();
  }

  // Removes every entry of a desktop entry (and closes those still open):
  // how a notification of the shell's asking for something to be done
  // goes away once it's done
  function dismissApp(desktopEntry) {
    const gone = root.entries.filter(e => e.desktopEntry === desktopEntry);
    if (gone.length === 0)
      return;
    root.entries = root.entries.filter(e => e.desktopEntry !== desktopEntry);
    gone.forEach(e => root._forget(e));
    root._save();
  }

  // Removes the entry holding a key (sendNotification's `key`), if any:
  // one of the shell's that's done with
  function dismissKey(key) {
    root.entries.filter(e => key && e.key === key).forEach(e => root.dismiss(e.uid));
  }

  // The uid of a live Notification's entry, or "" (transient ones have
  // none). Look it up while it's live: a closed one is forgotten.
  function uidOf(notif) {
    return root._uidOf(notif);
  }

  // Every toast of a notification its app's rule keeps out of the history
  // is gone (shell/Notifications): it closes, as nothing holds it now
  function toastsGone(notif) {
    const held = !!notif && root._toastOnly.includes(notif);
    root._toastOnly = root._toastOnly.filter(n => n && n !== notif);
    if (held)
      notif.expire();
  }
  // Those notifications, tracked only for their toasts (a closed one goes
  // at the next toastsGone)
  property var _toastOnly: []

  // Removes the Quiet section's entries
  function clearQuiet() {
    const gone = root.quiet;
    if (gone.length === 0)
      return;
    root.entries = root.alerts;
    gone.forEach(e => root._forget(e));
    root._save();
  }

  function clearAll() {
    const old = root.entries;
    root.entries = [];
    old.forEach(e => root._forget(e));
    root._files.clear();
    root._save();
  }

  // A click on a notification (a Notification or an entry, with its live
  // Notification or null): runs its default action, then focuses its app's
  // window (NotificationsConfig.clickFocuses: the app can't raise itself
  // under niri, as the server sends no activation token); without a
  // default action it opens the app (openApp). False if nothing happened.
  function activate(entry, live) {
    const action = (live?.actions ?? []).find(a => a.identifier === "default");
    if (!action)
      return root.openApp(entry);
    action.invoke();
    if (NotificationsConfig.clickFocuses) {
      const window = root.windowOf(entry);
      if (window)
        CompositorManager.focusWindow(window.id);
    }
    return true;
  }

  // Runs a filed entry's button (its `actions`' id) through its desktop
  // entry's handler, as handler(entry, id)
  function invokeFiled(entry, id) {
    const handler = root._handlers[entry?.desktopEntry || ""];
    if (handler)
      handler(entry, id);
  }

  // Runs the handler registered for the entry's desktop entry, else
  // focuses its app if it has a window, else launches it; false if its app
  // isn't known
  function openApp(entry) {
    const id = entry?.desktopEntry || "";
    if (id && root._handlers[id]) {
      root._handlers[id](entry);
      return true;
    }
    const window = root.windowOf(entry);
    if (window) {
      CompositorManager.focusWindow(window.id);
      return true;
    }
    const app = root._appOf(entry);
    if (!app)
      return false;
    CommandManager.runDetached(app.command, app.workingDirectory);
    return true;
  }

  // The most recently focused window of an entry's app, or null
  function windowOf(entry) {
    const keys = root._keysOf(entry);
    return CompositorManager.lastFocused(CompositorManager.windows.filter(w => NotificationMatch.matches(keys, root._windowKeys(w))));
  }

  // The per-app rule (NotificationsConfig.apps) a notification or entry
  // falls under, or null
  function ruleFor(entry) {
    const rules = NotificationsConfig.apps.filter(r => r.app !== "");
    if (rules.length === 0)
      return null;
    const keys = root._keysOf(entry);
    return rules.find(r => NotificationMatch.matches(NotificationMatch.keys([r.app]), keys)) ?? null;
  }

  // A notification's urgency, its app's rule's over its own
  function urgencyOf(notif) {
    const rule = root.ruleFor(notif);
    const forced = ["low", "normal", "critical"].indexOf(rule?.urgency ?? "app");
    return forced >= 0 ? [NotificationUrgency.Low, NotificationUrgency.Normal, NotificationUrgency.Critical][forced] : notif.urgency;
  }

  // How long a notification's toast stays (ms) by its app's rule, or -1
  // for the default
  function timeoutOf(notif) {
    return root.ruleFor(notif)?.timeout ?? -1;
  }

  // Opens a link from a notification's body in its app
  function openLink(url) {
    DefaultAppsManager.open(url);
  }

  // Makes clicking a notification with this desktop entry call
  // handler(entry) instead of opening an app: how the shell's own
  // notifications (sendNotification's `desktopEntry`) lead somewhere. A
  // filed one's button calls handler(entry, id) (invokeFiled), with the
  // entry's `data` to say what it's about; it outlives a QML reload, as
  // onAction doesn't
  function registerHandler(desktopEntry, handler) {
    root._handlers[desktopEntry] = handler;
  }

  // NotificationServer can't create notifications itself, so axiom sends
  // one over DBus (notify.send); it comes back through our own server
  // like any other (DND and the app rules apply). opts: { desktopEntry
  // (see registerHandler), icon (a name or path), urgency ("low",
  // "critical"), actions ([{ id, label }]: buttons on it), onAction
  // (called with the picked action's id; without it a button goes to the
  // desktop entry's handler), key (one entry per key: a newer one
  // replaces it), transient (toasts, never kept: an answer to what was
  // just done), silent (filed in the Quiet section only: no popup, its
  // buttons run by the handler), data (a filed one's, for its handler) }.
  // A rule naming its desktop entry overrides silent (_sourceLevel). The pick comes
  // later as notify.action; a QML reload in between loses onAction
  function sendNotification(appName, summary, body, opts) {
    if (opts?.silent === true && ["", "silent"].includes(root._sourceLevel(opts.desktopEntry ?? ""))) {
      root._file(appName, summary, body, opts);
      return;
    }
    const handler = root._handlers[opts?.desktopEntry ?? ""];
    const onAction = opts?.onAction ?? (handler ? id => handler({
          appName: appName,
          desktopEntry: opts.desktopEntry,
          key: opts?.key ?? "",
          data: opts?.data ?? null
        }, id) : null);
    BackendManager.call("notify.send", {
      "appName": appName,
      "summary": summary,
      "body": body,
      "icon": opts?.icon ?? "",
      "desktopEntry": opts?.desktopEntry ?? "",
      "urgency": opts?.urgency ?? "",
      "actions": opts?.actions ?? [],
      "key": opts?.key ?? "",
      "transient": opts?.transient === true
    }, (error, result) => {
      if (error)
        console.warn(`[NotificationManager] Sending "${summary}" failed: ${error.message}`);
      else if (onAction && opts?.actions?.length)
        root._onAction[result.id] = onAction;
    });
  }

  // An event of an OSD status type (`type`: "drive", "battery",
  // "monitor", "screenshot") said where OSDConfig.routeOf puts it, with
  // `notify` its section's switch: on an OSD listing it (the caller shows
  // its card; filed here without a popup with OSD.cardsToHistory), else
  // as a notification, else nowhere. An urgent one (opts.urgency
  // "critical": a critical battery) pops up beside its card too, unless
  // `notify` is off. Returns the route ("osd", "notification" or "")
  function announce(type, notify, summary, body, opts) {
    const route = OSDConfig.routeOf(type, notify);
    if (route === "notification" || (route === "osd" && notify && opts?.urgency === "critical"))
      root.sendNotification("axiom", summary, body, opts);
    else if (route === "osd" && OSDConfig.cardsToHistory)
      root.sendNotification("axiom", summary, body, Object.assign({}, opts, {
        "silent": true
      }));
    return route;
  }

  // -- Private --

  // Files a silent one in the Quiet section (sendNotification's silent):
  // no notification behind it, so a click and its buttons go by its
  // desktop entry (registerHandler, invokeFiled). An icon that's a path is
  // its picture; a key replaces the entry holding it
  function _file(appName, summary, body, opts) {
    const icon = opts.icon ?? "";
    const picture = icon.startsWith("/");
    const entry = {
      uid: root._newUid(),
      nid: -1,
      appName: appName,
      appIcon: picture ? "" : icon,
      desktopEntry: opts.desktopEntry ?? "",
      summary: summary,
      body: body,
      image: "",
      urgency: NotificationUrgency.Normal,
      time: Date.now(),
      live: false,
      silent: true,
      key: opts.key ?? "",
      actions: (opts.actions ?? []).map(a => ({
            id: a.id,
            label: a.label
          })),
      data: opts.data ?? null
    };
    root._dropKey(entry.key);
    root._put(entry);
    if (picture)
      root._files.cache(entry.uid, "file://" + icon);
  }

  readonly property var _state: StateManager.createStateHandler("notifications")
  property bool _stateLoaded: false

  // An entry's desktop entry (by its id, else a guess from its id or app
  // name), or null
  function _appOf(entry) {
    const id = entry?.desktopEntry || "";
    return (id ? DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id) : null) ?? (entry?.appName ? DesktopEntries.heuristicLookup(entry.appName) : null);
  }

  // An entry's app names as NotificationMatch keys: its desktop entry and
  // app name, and the desktop entry's id and window class they lead to
  function _keysOf(entry) {
    const app = root._appOf(entry);
    return NotificationMatch.keys([entry?.desktopEntry, entry?.appName, app?.id, app?.startupClass]);
  }

  // A window's class keys, its desktop entry's id with them
  function _windowKeys(window) {
    const cls = window.appId || window.initialAppId || "";
    const app = cls ? DesktopEntries.heuristicLookup(cls) : null;
    return NotificationMatch.keys([window.appId, window.initialAppId, app?.id]);
  }

  // uid -> Notification, for live entries
  property var _live: ({})
  // desktop entry -> function(entry), from registerHandler
  property var _handlers: ({})
  // notify.send's id -> onAction, until its notify.action
  property var _onAction: ({})
  property int _serial: 0

  function _newUid() {
    root._serial += 1;
    return Date.now().toString(36) + "-" + root._serial;
  }

  // Forgets the entries holding a key, for a newer one: their live
  // notifications close, so their toasts go too
  function _dropKey(key) {
    if (!key)
      return;
    const gone = root.entries.filter(e => e.key === key);
    if (gone.length === 0)
      return;
    root.entries = root.entries.filter(e => e.key !== key);
    gone.forEach(e => root._forget(e));
  }

  // A notification's level (NotificationLevel), by its app's rule and its
  // urgency
  function _levelOf(notif) {
    return NotificationLevel.levelOf(root.ruleFor(notif)?.level ?? "", root.urgencyOf(notif), NotificationsConfig.lowUrgency);
  }

  // The level a rule naming one of the shell's sources (its desktop
  // entry, exactly: a rule for "axiom" is for its alerts) gives, or ""
  function _sourceLevel(desktopEntry) {
    const name = NotificationMatch.normalize(desktopEntry);
    return name ? NotificationsConfig.apps.find(r => NotificationMatch.normalize(r.app) === name)?.level ?? "" : "";
  }

  // The x-axiom-key hint the shell's own carry, or ""
  function _keyOf(notif) {
    return String(notif?.hints?.["x-axiom-key"] ?? "");
  }

  function _entryFrom(notif, uid, time, silent) {
    return {
      uid: uid,
      nid: notif.id,
      appName: notif.appName || "",
      appIcon: notif.appIcon || "",
      desktopEntry: notif.desktopEntry || "",
      summary: notif.summary || "",
      body: notif.body || "",
      image: notif.image || "",
      urgency: root.urgencyOf(notif),
      time: time,
      live: true,
      silent: silent,
      key: root._keyOf(notif)
    };
  }

  function _uidOf(notif) {
    for (const uid in root._live) {
      if (root._live[uid] === notif)
        return uid;
    }
    return "";
  }

  // Replaces an entry's object (so bindings see the change), newest first
  function _put(entry) {
    const rest = root.entries.filter(e => e.uid !== entry.uid);
    root.entries = root._prune([entry].concat(rest));
    root._save();
  }

  // Sorts entries newest first and drops (forgetting) those past their
  // part's size or age (NotificationLevel.kept)
  function _prune(list) {
    const kept = NotificationLevel.kept(list, Date.now(), root._limits);
    list.filter(e => !kept.includes(e)).forEach(e => root._forget(e));
    return kept;
  }

  function _pruneNow() {
    const kept = root._prune(root.entries);
    if (kept.length === root.entries.length)
      return;
    root.entries = kept;
    root._save();
  }

  on_LimitsChanged: Qt.callLater(root._pruneNow)

  // Entries age out while the shell runs, too
  property Timer _ageTimer: Timer {
    interval: 3600000
    repeat: true
    running: root._limits.maxAge > 0 || root._limits.quietMaxAge > 0
    onTriggered: root._pruneNow()
  }

  // clearOnFocus: an app's entries go when one of its windows is focused
  property Connections _focusWatcher: Connections {
    target: CompositorManager
    enabled: NotificationsConfig.clearOnFocus
    function onWindowFocused(appId) {
      const app = appId ? DesktopEntries.heuristicLookup(appId) : null;
      const keys = NotificationMatch.keys([appId, app?.id]);
      root.entries.filter(e => NotificationMatch.matches(root._keysOf(e), keys)).forEach(e => root.dismiss(e.uid));
    }
  }

  function _update(uid, changes) {
    const entry = root.entries.find(e => e.uid === uid);
    if (!entry)
      return;
    root.entries = root.entries.map(e => e.uid === uid ? Object.assign({}, e, changes) : e);
    root._save();
  }

  // Watches a live notification: an app replacing it updates its entry,
  // and withdrawing it keeps the entry without its actions. A Connections
  // owned by this singleton, so a reload's old instance lets go.
  function _link(notif, uid) {
    const live = Object.assign({}, root._live);
    live[uid] = notif;
    root._live = live;
    root._watchers[uid] = watcher.createObject(root, {
      target: notif,
      uid: uid
    });
  }

  function _unlink(uid) {
    root._watchers[uid]?.destroy();
    delete root._watchers[uid];
    const rest = Object.assign({}, root._live);
    delete rest[uid];
    root._live = rest;
  }

  // Qt.callLater collapses calls by function, so pending uids are kept here
  property var _pendingRefresh: ({})
  function _queueRefresh(uid) {
    root._pendingRefresh[uid] = true;
    Qt.callLater(root._flushRefresh);
  }
  function _flushRefresh() {
    const uids = Object.keys(root._pendingRefresh);
    root._pendingRefresh = {};
    uids.forEach(uid => root._refresh(uid));
  }

  function _refresh(uid) {
    const notif = root._live[uid];
    const entry = root.entries.find(e => e.uid === uid);
    if (!notif || !entry)
      return;
    const fresh = root._entryFrom(notif, uid, Date.now(), entry.silent);
    if (root._files.differs(uid, fresh.image))
      root._files.cache(uid, fresh.image);
    else
      fresh.image = entry.image;
    root._put(fresh);
  }

  property var _watchers: ({})

  property Component _watcher: Component {
    id: watcher
    Connections {
      property string uid
      function onSummaryChanged() {
        root._queueRefresh(uid);
      }
      function onBodyChanged() {
        root._queueRefresh(uid);
      }
      function onImageChanged() {
        root._queueRefresh(uid);
      }
      // Withdrawn by its app (read there, say): with followApps it
      // leaves the history too
      function onClosed(reason) {
        root._unlink(uid);
        if (reason === NotificationCloseReason.CloseRequested && NotificationsConfig.followApps)
          root.dismiss(uid);
        else
          root._update(uid, {
            live: false
          });
      }
    }
  }

  function _forget(entry) {
    const notif = root._live[entry.uid];
    root._unlink(entry.uid);
    notif?.dismiss();
    root._files.forget(entry);
  }

  // The history's file and the images' copies (NotificationFiles); a
  // copy saved points its entry at it
  property NotificationFiles _files: NotificationFiles {
    id: files
    entries: root.entries
    onSaved: (uid, url) => root._update(uid, {
        image: url
      })
  }

  function _load() {
    const saved = root._files.read();
    // Nothing from the last run is live, and an uncached image's data is gone
    const entries = saved.filter(e => e && e.uid).map(e => Object.assign({}, e, {
        live: false,
        image: (e.image || "").startsWith("image://") ? "" : (e.image || "")
      }));
    root.entries = root._prune(entries);
    root._dropMissingImages();
    // Usually empty here: the server only goes live after this, and then
    // re-emits each kept notification (see onNotification)
    for (const notif of server.trackedNotifications.values)
      root._adopt(notif);
  }

  // Forgets saved images no longer on disk (removed by hand); the
  // avatar falls back to the app icon
  function _dropMissingImages() {
    root._files.missing(root.entries.map(e => e.image), gone => {
      root.entries = root.entries.map(e => gone.includes(e.image) ? Object.assign({}, e, {
          image: ""
        }) : e);
      root._save();
    });
  }

  // Relinks a notification kept across a QML reload to its saved entry
  // (or gives it one), at most once
  function _adopt(notif) {
    if (root._uidOf(notif))
      return;
    // One kept out of the history (transient, or its level's) had only
    // its toasts, which the reload took
    const level = root._levelOf(notif);
    if (!NotificationLevel.files(level, notif.transient)) {
      notif.expire();
      return;
    }
    const entry = root.entries.find(e => !root._live[e.uid] && e.nid === notif.id && e.summary === (notif.summary || ""));
    if (entry) {
      root.entries = root.entries.map(e => e === entry ? Object.assign({}, e, {
          live: true,
          image: e.image || notif.image || ""
        }) : e);
      root._files.adopt(entry.uid, notif.image || "");
      root._link(notif, entry.uid);
    } else {
      const uid = root._newUid();
      const fresh = root._entryFrom(notif, uid, Date.now(), level === "silent");
      root._put(fresh);
      root._link(notif, uid);
      root._files.cache(uid, fresh.image);
    }
  }

  function _save() {
    root._files.save();
  }

  Component.onCompleted: {
    BackendManager.listen("notify.action", picked => {
      const onAction = root._onAction[picked.id];
      delete root._onAction[picked.id];
      if (onAction && picked.action !== "")
        onAction(picked.action);
    });
    root._load();
    const saved = root._state.load({});
    root._dnd = saved.dnd === true;
    root._quietOpen = saved.quietOpen === true;
    root._dndMissed = saved.dndMissed ?? 0;
    root._quietSeen = saved.quietSeen ?? 0;
    // A click on the summary opens nothing
    root.registerHandler("axiom-dnd", () => {});
    root._stateLoaded = true;
  }

  Component.onDestruction: root._files.flush()

  // axiom ipc notifications clear | clearQuiet | toggleQuiet | toggleDnd
  property IpcTarget _ipc: IpcTarget {
    target: "notifications"
    function clear(): void {
      root.clearAll();
    }
    function clearQuiet(): void {
      root.clearQuiet();
    }
    function toggleQuiet(): void {
      root.setQuietOpen(!root.quietOpen);
    }
    function toggleDnd(): void {
      root.toggleDnd();
    }
  }

  // Do not disturb on or off (keybind action toggleDnd with its call)
  property IpcTarget _dndIpc: IpcTarget {
    target: "dnd"
    function toggle(): void {
      root.toggleDnd();
    }
    function enable(): void {
      root.setDnd(true);
    }
    function disable(): void {
      root.setDnd(false);
    }
    function status(): bool {
      return root.dnd;
    }
  }

  NotificationServer {
    id: server

    actionsSupported: true
    inlineReplySupported: true
    actionIconsSupported: true
    bodySupported: true
    bodyHyperlinksSupported: true
    bodyMarkupSupported: true
    imageSupported: true
    persistenceSupported: true
    // Live notifications (and so their actions) survive a QML reload
    keepOnReload: true

    onNotification: notification => {
      // keepOnReload re-emits every kept notification after a reload:
      // relink it to its entry, with no new entry or toast
      if (notification.lastGeneration) {
        notification.tracked = true;
        root._adopt(notification);
        return;
      }
      // Its level (NotificationLevel): an alert toasts and is kept, a
      // silent one only kept (Quiet), a toast-only one only toasts; none
      // toasts while Do Not Disturb is on but a critical one (unless
      // NotificationsConfig.dndAllowCritical is off)
      const urgency = root.urgencyOf(notification);
      const level = root._levelOf(notification);
      const toasts = NotificationLevel.toasts(level, root.dnd, NotificationsConfig.dndAllowCritical, urgency);
      // Tracked, so the object outlives this handler; transient ones
      // (e.g. volume changes) and toast-only ones only while their toasts
      // last (toastsGone)
      if (NotificationLevel.files(level, notification.transient)) {
        notification.tracked = true;
        root._dropKey(root._keyOf(notification));
        const uid = root._newUid();
        const entry = root._entryFrom(notification, uid, Date.now(), level === "silent");
        root._put(entry);
        root._link(notification, uid);
        root._files.cache(uid, entry.image);
      } else if (toasts) {
        notification.tracked = true;
        root._toastOnly = root._toastOnly.concat([notification]);
      }
      if (toasts)
        root.showPopup(notification);
      else if (root.dnd && level === "alert" && !notification.transient) {
        root._dndMissed += 1;
        root._saveState();
      }
    }
  }
}
