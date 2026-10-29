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
 *     urgency, time, live }
 * `live` while its Notification is still around (liveNotification(uid)),
 * so its actions work; restored or withdrawn entries have none.
 *
 * The history keeps NotificationsConfig.maxEntries entries, none older
 * than maxAge (when set), and with clearOnFocus an app's entries go
 * when one of its windows is focused; with followApps one its app
 * withdraws goes too. DND is saved in Paths.statePath.
 */
Singleton {
  id: root

  // Newest first
  property var entries: []
  readonly property int count: entries.length
  // The count for a badge: "99+" past 99
  readonly property string countLabel: count > 99 ? "99+" : String(count)
  readonly property int maxEntries: NotificationsConfig.maxEntries
  readonly property real maxAge: NotificationsConfig.maxAge

  // Do Not Disturb: no toasts but critical ones (notifications still go
  // into the history). Kept across restarts. Set through setDnd/toggleDnd,
  // or by its schedule (NotificationsConfig.dnd).
  readonly property bool dnd: root._dnd
  property bool _dnd: false
  on_DndChanged: {
    if (root._stateLoaded)
      root._state.save({
        dnd: root._dnd
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
  property DailySchedule _dndSchedule: DailySchedule {
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
  property Item imageHost: null

  readonly property string historyPath: Paths.userStatePath + "notifications.json"
  readonly property string imageDir: Paths.userStatePath + "notifications/"

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

  function clearAll() {
    const old = root.entries;
    root.entries = [];
    old.forEach(e => root._forget(e));
    CommandManager.runDetached(["sh", "-c", "rm -f \"$1\"*.png", "sh", root.imageDir]);
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
    const windows = CompositorManager.windows.filter(w => NotificationMatch.matches(keys, root._windowKeys(w)));
    return windows.sort((a, b) => (a.focusRank ?? 0) - (b.focusRank ?? 0))[0] ?? null;
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
    CommandManager.runDetached(["xdg-open", url]);
  }

  // Makes clicking a notification with this desktop entry call
  // handler(entry) instead of opening an app: how the shell's own
  // notifications (sendNotification's `desktopEntry`) lead somewhere
  function registerHandler(desktopEntry, handler) {
    root._handlers[desktopEntry] = handler;
  }

  // NotificationServer can't create notifications itself, so send one over
  // DBus; it comes back through our own server like any other (DND applies).
  // opts: { desktopEntry (see registerHandler), icon (a name or path) }
  function sendNotification(appName, summary, body, opts) {
    const hints = opts?.desktopEntry ? ["-h", "string:desktop-entry:" + opts.desktopEntry] : [];
    const icon = opts?.icon ? ["-i", opts.icon] : [];
    CommandManager.runDetached(["notify-send", "-a", appName].concat(icon, hints, ["--", summary, body]));
  }

  // -- Private --

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
  property int _serial: 0

  function _newUid() {
    root._serial += 1;
    return Date.now().toString(36) + "-" + root._serial;
  }

  function _entryFrom(notif, uid, time) {
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
      live: true
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

  // Sorts entries newest first and drops (forgetting) those past the
  // history's size or age
  function _prune(list) {
    const cutoff = root.maxAge > 0 ? Date.now() - root.maxAge : -Infinity;
    const sorted = list.slice().sort((a, b) => b.time - a.time);
    const kept = sorted.filter(e => e.time >= cutoff).slice(0, root.maxEntries);
    sorted.filter(e => !kept.includes(e)).forEach(e => root._forget(e));
    return kept;
  }

  function _pruneNow() {
    const kept = root._prune(root.entries);
    if (kept.length === root.entries.length)
      return;
    root.entries = kept;
    root._save();
  }

  onMaxEntriesChanged: Qt.callLater(root._pruneNow)
  onMaxAgeChanged: Qt.callLater(root._pruneNow)

  // Entries age out while the shell runs, too
  property Timer _ageTimer: Timer {
    interval: 3600000
    repeat: true
    running: root.maxAge > 0
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
    const fresh = root._entryFrom(notif, uid, Date.now());
    if (fresh.image !== root._sources[uid])
      root._cacheImage(uid, fresh.image);
    else
      fresh.image = entry.image;
    root._put(fresh);
  }

  property var _watchers: ({})
  // uid -> the image source an entry's cached image came from
  property var _sources: ({})

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
    delete root._sources[entry.uid];
    notif?.dismiss();
    if (entry.image.startsWith("file://" + root.imageDir))
      CommandManager.runDetached(["rm", "-f", entry.image.slice(7).split("?")[0]]);
  }

  // Copies a notification's image to disk (scaled down: the UI only shows
  // thumbnails), then points the entry at the copy. If that fails the entry
  // keeps the original, which lasts as long as the notification does.
  function _cacheImage(uid, source) {
    root._sources[uid] = source;
    if (!source)
      return;
    if (!root.imageHost) {
      console.warn("[NotificationManager] No image host yet, not caching", source);
      return;
    }
    const img = imageGrabber.createObject(root.imageHost, {
      source: source
    });
    const done = ok => {
      if (!ok)
        console.warn("[NotificationManager] Could not cache image", source);
      img.destroy();
    };
    const grab = () => {
      if (img.status === Image.Error)
        return done(false);
      if (img.status !== Image.Ready)
        return;
      const scale = Math.min(1, 160 / Math.max(img.implicitWidth, img.implicitHeight, 1));
      img.width = Math.max(1, Math.round(img.implicitWidth * scale));
      img.height = Math.max(1, Math.round(img.implicitHeight * scale));
      const path = root.imageDir + uid + ".png";
      const ok = img.grabToImage(result => {
        if (!result.saveToFile(path))
          return done(false);
        root._update(uid, {
          image: "file://" + path + "?" + Date.now()
        });
        done(true);
      });
      if (!ok)
        done(false);
    };
    img.statusChanged.connect(grab);
    grab();
  }

  property Component _imageGrabber: Component {
    id: imageGrabber
    Image {
      asynchronous: false
      cache: false
      sourceSize: Qt.size(160, 160)
      fillMode: Image.PreserveAspectFit
    }
  }

  function _load() {
    const content = FileManager.read("file://" + root.historyPath);
    let saved = [];
    if (content) {
      try {
        saved = JSON.parse(content);
      } catch (e) {
        console.warn("[NotificationManager] Could not parse", root.historyPath, e);
      }
    }
    if (!Array.isArray(saved))
      saved = [];
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

  // Forgets saved images no longer on disk (removed by hand), which would
  // warn on every row built from them; the avatar falls back to the app icon
  function _dropMissingImages() {
    const pathOf = image => image.startsWith("file://") ? image.slice(7).split("?")[0] : "";
    const paths = root.entries.map(e => pathOf(e.image)).filter(p => p !== "");
    if (paths.length === 0)
      return;
    CommandManager.run(["sh", "-c", "for f; do [ -e \"$f\" ] || echo \"$f\"; done", "sh"].concat(paths), (code, out) => {
      const gone = out.split("\n").filter(p => p !== "");
      if (gone.length === 0)
        return;
      root.entries = root.entries.map(e => gone.includes(pathOf(e.image)) ? Object.assign({}, e, {
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
    // One its app's rule keeps out of the history had only its toasts,
    // which the reload took
    if (root.ruleFor(notif)?.history === false) {
      notif.expire();
      return;
    }
    const entry = root.entries.find(e => !root._live[e.uid] && e.nid === notif.id && e.summary === (notif.summary || ""));
    if (entry) {
      root.entries = root.entries.map(e => e === entry ? Object.assign({}, e, {
          live: true,
          image: e.image || notif.image || ""
        }) : e);
      root._sources[entry.uid] = notif.image || "";
      root._link(notif, entry.uid);
    } else {
      const uid = root._newUid();
      const fresh = root._entryFrom(notif, uid, Date.now());
      root._put(fresh);
      root._link(notif, uid);
      root._cacheImage(uid, fresh.image);
    }
  }

  function _save() {
    saveTimer.restart();
  }

  function _writeNow() {
    saveTimer.stop();
    FileManager.write(root.historyPath, JSON.stringify(root.entries.map(e => Object.assign({}, e, {
        live: undefined
      })), null, 2));
  }

  property Timer _saveTimer: Timer {
    id: saveTimer
    interval: 500
    onTriggered: root._writeNow()
  }

  Component.onCompleted: {
    CommandManager.runDetached(["mkdir", "-p", root.imageDir]);
    root._load();
    root._dnd = root._state.load({}).dnd === true;
    root._stateLoaded = true;
  }

  Component.onDestruction: {
    if (saveTimer.running)
      root._writeNow();
  }

  // axiom ipc notifications clear | toggleDnd
  property IpcTarget _ipc: IpcTarget {
    target: "notifications"
    function clear(): void {
      root.clearAll();
    }
    function toggleDnd(): void {
      root.toggleDnd();
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
      // None for an app whose rule shows none, nor while Do Not Disturb
      // is on but a critical one (unless NotificationsConfig.
      // dndAllowCritical is off)
      const rule = root.ruleFor(notification);
      const urgency = root.urgencyOf(notification);
      const toasts = rule?.toasts !== false && (!root.dnd || (NotificationsConfig.dndAllowCritical && urgency === NotificationUrgency.Critical));
      // Tracked, so the object outlives this handler; transient ones
      // (e.g. volume changes) only pop up, and those of an app whose rule
      // keeps none only while their toasts last (toastsGone)
      if (!notification.transient && rule?.history !== false) {
        notification.tracked = true;
        const uid = root._newUid();
        const entry = root._entryFrom(notification, uid, Date.now());
        root._put(entry);
        root._link(notification, uid);
        root._cacheImage(uid, entry.image);
      } else if (!notification.transient && toasts) {
        notification.tracked = true;
        root._toastOnly = root._toastOnly.concat([notification]);
      }
      if (toasts)
        root.showPopup(notification);
    }
  }
}
