pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.system
import qs.services.ui

/*
 * Calendars (the Calendar section): CalDAV accounts, .ics subscriptions and
 * local calendars, through axiom's calendar.* methods (backend/internal/
 * calendar, which looks each CalDAV account's password up by its id:
 * none passes through here). axiom
 * keeps the server's objects in $XDG_STATE_HOME/axiom/calendar/objects.json
 * and writes their occurrences in `range` to events.json, which this reads
 * (so the calendar shows at once, and offline). Syncs every
 * `Calendar.syncInterval` minutes while something has acquire()d it, or
 * while reminders are on; one call runs at a time, later jobs queued.
 *   CalendarManager.acquire(owner) / release(owner)
 *   CalendarManager.eventsOn("2026-10-05")    // that day's, in order
 *   CalendarManager.dotsFor("2026-10-05")     // its calendars' colors
 *   CalendarManager.save(draft, scope, cb) / remove(event, scope, cb)
 * What a server says of a calendar (its name, color, whether it's
 * read-only, what it holds) is kept here, in the calendar state (`info`),
 * not in config: an account's calendars there hold only what the user set
 * (CalendarConfig.accounts). `calendars` joins the two.
 * Nothing runs in the greeter, which can't read the user's state anyway.
 */
QtObject {
  id: root

  // Occurrences from events.json (ical.Occurrence in backend/internal/calendar/ical)
  property var events: []
  // When the last sync finished (epoch ms; 0 before any)
  property real lastSync: 0
  // The last sync's problems: [{ calendar, kind, message }]
  property var errors: []
  readonly property bool syncing: root._running?.cmd === "sync" || root._jobs.some(job => job.cmd === "sync")
  // A sync, save or delete is running
  readonly property bool busy: root._running !== null
  // What the page or a module was asked to show next ({ kind: "new" |
  // "day", key }), taken by the first one that can (takeRequest)
  property var request: null
  // The span of events kept, widened as views page past it
  property var range: CalendarEvents.rangeFor(Date.now(), CalendarConfig.pastMonths, CalendarConfig.futureMonths)

  // What servers said of each calendar, by "<account>|<href>": { name,
  // serverColor, readOnly, components }, kept in the calendar state
  property var info: ({})
  // Every account's calendars, flattened: { id ("<account>|<href>"),
  // account, accountName, kind, href, name (its own, else the server's),
  // color (its own, else the server's, else the accent), enabled,
  // readOnly, events (it holds events), writable }
  readonly property var calendars: [].concat(...CalendarConfig.accounts.map(account => account.calendars.map(calendar => {
      const id = account.id + "|" + calendar.href;
      const known = root.info[id] ?? {};
      const components = known.components ?? ["VEVENT"];
      const readOnly = !CalendarConfig.writableKind(account.kind) || known.readOnly === true;
      return {
        "id": id,
        "account": account.id,
        "accountName": account.name,
        "kind": account.kind,
        "href": calendar.href,
        "name": calendar.name || known.name || calendar.href,
        "color": String(calendar.color ? Theme.resolveColor(calendar.color) : (known.serverColor || Theme.accent)),
        "enabled": calendar.enabled,
        "readOnly": readOnly,
        "events": components.includes("VEVENT"),
        "writable": !readOnly && components.includes("VEVENT")
      };
    })))
  // The calendars shown, and those of them new events can go to
  readonly property var shownCalendars: root.calendars.filter(calendar => calendar.enabled && calendar.events)
  readonly property var writableCalendars: root.shownCalendars.filter(calendar => calendar.writable)
  // Where a new event goes: the default calendar while it's shown and
  // writable, else the first that is ("" with none)
  readonly property string newEventCalendar: (root.writableCalendars.find(calendar => calendar.id === CalendarConfig.defaultCalendar) ?? root.writableCalendars[0])?.id ?? ""
  // calendar id -> its color, for the views
  readonly property var colors: root.calendars.reduce((map, calendar) => {
    map[calendar.id] = calendar.color;
    return map;
  }, {})
  function calendar(id) {
    return root.calendars.find(calendar => calendar.id === id) ?? null;
  }

  // Keeps what a server said of an account's calendars (discover's
  // `calendars`: { href, name, color, readOnly, components })
  function remember(accountId, found) {
    const info = Object.assign({}, root.info);
    for (const calendar of found ?? [])
      info[accountId + "|" + calendar.href] = {
        "name": calendar.name ?? "",
        "serverColor": calendar.color ?? "",
        "readOnly": calendar.readOnly === true,
        "components": calendar.components ?? ["VEVENT"]
      };
    root.info = info;
    root._saveState();
  }

  // Shown calendars' events by day ({ "YYYY-MM-DD": [event] })
  readonly property var byDay: CalendarEvents.byDay(root.events, root.shownCalendars.map(calendar => calendar.id))
  readonly property bool hasCalendars: root.shownCalendars.length > 0

  function eventsOn(key) {
    return root.byDay[key] ?? [];
  }

  function dotsFor(key) {
    return CalendarEvents.dotColors(root.byDay[key], root.colors, CalendarConfig.maxDots);
  }

  // When an event happens on a day, for its row: "All day", "9:00 – 10:00",
  // "From 22:00" (it runs past the day), "Until 2:00" (it began before)
  function timeText(event, key) {
    const time = t => I18n.formatDate(new Date(t), CalendarConfig.timeFormat);
    switch (CalendarEvents.spanOn(event, key)) {
    case "single":
      return event.start === event.end ? time(event.start) : I18n.tr("{0} – {1}", time(event.start), time(event.end));
    case "starts":
      return I18n.tr("From {0}", time(event.start));
    case "ends":
      return I18n.tr("Until {0}", time(event.end));
    default:
      return I18n.tr("All day");
    }
  }

  // Shown events from now until `until` (epoch ms), by start
  function upcoming(now, until, allDay) {
    const shown = root.shownCalendars.map(calendar => calendar.id);
    return CalendarEvents.upcoming(root.events.filter(event => shown.includes(event.calendar)), now, until, allDay);
  }

  function acquire(owner) {
    root._registry.acquire(owner, true);
  }

  function release(owner) {
    root._registry.release(owner);
  }

  // Keeps the six weeks a view shows for a month in range, fetching them
  // when they weren't
  function ensureMonth(year, month) {
    const next = CalendarEvents.widened(root.range, year, month);
    if (next.from === root.range.from && next.to === root.range.to)
      return;
    root.range = next;
    root.sync();
  }

  // Syncs now (queued behind a running call; a queued sync isn't doubled)
  function sync() {
    if (Paths.greeter || root._jobs.some(job => job.cmd === "sync"))
      return;
    root._enqueue("sync", done => BackendManager.call("calendar.sync", {
        "range": root.range,
        "accounts": root._accounts(null)
      }, (error, result) => done(error ? root._failure(error) : {
          "ok": true
        })), result => {
      if (!result.ok)
        console.warn("[CalendarManager] Sync failed:", result.message);
    });
  }

  // Finds an account's calendars (with its saved password): calls back
  // with { ok, calendars, code, message }
  function discover(account, callback) {
    if (Paths.greeter)
      return;
    // Not queued: it writes nothing a sync reads
    BackendManager.call("calendar.discover", {
      "id": account.id,
      "kind": account.kind,
      "url": account.url,
      "username": account.username
    }, (error, result) => callback?.(error ? root._failure(error) : result.calendars.length > 0 ? {
        "ok": true,
        "calendars": result.calendars
      } : {
        "ok": false,
        "kind": "no_calendars",
        "message": "No calendars found at that address"
      }));
  }

  // Saves a draft (CalendarEvents.newDraft/draftOf): a new event without an
  // href; `scope` "series" or "occurrence". Calls back with { ok, kind,
  // message }.
  function save(draft, scope, callback) {
    if (Paths.greeter)
      return;
    const calendar = root.calendar(draft.calendar);
    if (!calendar?.writable)
      return callback?.({
        "ok": false,
        "kind": "refused",
        "message": "That calendar can't be changed"
      });
    // Moving an event to another calendar: a new one there, then the old
    // one deleted
    if (draft.href && draft.originalCalendar && draft.originalCalendar !== draft.calendar) {
      const moved = Object.assign({}, draft, {
        "href": "",
        "etag": "",
        "rid": ""
      });
      return root.save(moved, "series", result => {
        if (!result.ok)
          return callback?.(result);
        root.remove({
          "calendar": draft.originalCalendar,
          "href": draft.href,
          "etag": draft.etag,
          "rid": "",
          "key": ""
        }, "series", callback);
      });
    }
    root._enqueue("save", done => BackendManager.call("calendar.save", {
        "range": root.range,
        "accounts": root._accounts(calendar.account),
        "account": calendar.account,
        "calendar": calendar.href,
        "href": draft.href,
        "etag": draft.etag,
        "scope": scope,
        "rid": draft.rid,
        "event": CalendarEvents.payloadOf(draft)
      }, (error, result) => done(error ? root._failure(error) : {
          "ok": true,
          "href": result.href
        })), callback);
  }

  // Deletes an event: "series" (the whole of a recurring one) or
  // "occurrence" (this one). It disappears at once, and comes back if the
  // server refuses.
  function remove(event, scope, callback) {
    if (Paths.greeter)
      return;
    const calendar = root.calendar(event.calendar);
    if (!calendar?.writable)
      return callback?.({
        "ok": false,
        "kind": "refused",
        "message": "That calendar can't be changed"
      });
    root.events = root.events.filter(e => scope === "occurrence" ? e.key !== event.key : e.href !== event.href);
    root._enqueue("delete", done => BackendManager.call("calendar.delete", {
        "range": root.range,
        "accounts": root._accounts(calendar.account),
        "account": calendar.account,
        "calendar": calendar.href,
        "href": event.href,
        "etag": event.etag,
        "scope": scope,
        "rid": event.rid
      }, error => done(error ? root._failure(error) : {
          "ok": true
        })), callback);
  }

  // The launcher's quick add, parsed (null when it can't be: no title)
  function parseQuickAdd(text) {
    return CalendarEvents.parseQuickAdd(text, Date.now(), root._quickAddWords(), CalendarConfig.defaultDuration);
  }

  // Adds a quick add's event to the new-event calendar; false when it
  // can't (no title, or no calendar to add to)
  function quickAdd(text, callback) {
    const parsed = root.parseQuickAdd(text);
    if (!parsed || !root.newEventCalendar)
      return false;
    const draft = CalendarEvents.newDraft(CalendarEvents.dayKey(parsed.start), Date.now(), root.newEventCalendar, CalendarConfig.defaultDuration, CalendarConfig.defaultReminder);
    root.save(Object.assign(draft, parsed), "series", result => {
      if (result.ok)
        NotificationManager.sendNotification(I18n.tr("Calendar"), I18n.tr("Added {0}", parsed.title), parsed.allDay ? I18n.formatDate(new Date(parsed.start), I18n.dateFormat("longDate")) : I18n.tr("{0} · {1}", I18n.formatDate(new Date(parsed.start), I18n.dateFormat("longDate")), I18n.formatDate(new Date(parsed.start), CalendarConfig.timeFormat)), {
          "desktopEntry": root._desktopEntry,
          "icon": "x-office-calendar"
        });
      else
        NotificationManager.sendNotification(I18n.tr("Calendar"), I18n.tr("Couldn't add {0}", parsed.title), root.errorText(result), {
          "desktopEntry": root._desktopEntry,
          "icon": "x-office-calendar"
        });
      callback?.(result);
    });
    return true;
  }

  // Opens the Calendar page (else the page with a Calendar module), asked
  // to show `request` ({ kind: "new" | "day", key }) when given
  function openPage(request) {
    root.request = request ?? null;
    const page = OverlayConfig.views.some(view => view.type === "CalendarPage" && view.visible !== false) ? "CalendarPage" : OverlayConfig.pageWithModule("Calendar");
    if (page)
      ShellManager.openOverlayPage(page);
    else
      SettingsManager.openSetting("Calendar");
  }

  // The pending request, once (null when there's none)
  function takeRequest() {
    const request = root.request;
    root.request = null;
    return request;
  }

  // A failed save, delete or discover, for people: by its axerr kind, or
  // the shell's own no_calendars and no_password (axiom's unauthorized when
  // no password is saved)
  function errorText(result) {
    switch (result?.kind) {
    case "unauthorized":
      return I18n.tr("The server refused the username or password.");
    case "unavailable":
      return I18n.tr("Couldn't reach the server.");
    case "not_found":
      return I18n.tr("Nothing was found at that address.");
    case "no_calendars":
      return I18n.tr("No calendars were found at that address.");
    case "conflict":
      return I18n.tr("The event changed elsewhere. It has been reloaded: check it and try again.");
    case "refused":
      return I18n.tr("This calendar can't be changed.");
    case "no_password":
      return I18n.tr("No password is saved for this account.");
    case "bad_reply":
      return I18n.tr("The server sent something unreadable.");
    default:
      return result?.message ?? "";
    }
  }

  // -- Private --

  readonly property string _stateDir: Paths.userStatePath + "calendar"
  readonly property string _desktopEntry: "axiom-calendar"
  property ConsumerRegistry _registry: ConsumerRegistry {}
  // [{ cmd, run(done), callback }], and the one running
  property var _jobs: []
  property var _running: null
  readonly property var _state: StateManager.createStateHandler("calendar")
  // Reminders shown: { "<event key>@<time>": time }
  property var _fired: ({})

  // Syncs while something shows calendars, or reminders are on
  readonly property bool _wanted: !Paths.greeter && CalendarConfig.accounts.length > 0 && (root._registry.active || CalendarConfig.reminders)

  // What a sync fetches: a change syncs again (colors and names don't)
  readonly property string _syncKey: JSON.stringify(CalendarConfig.accounts.map(account => [account.id, account.kind, account.url, account.username, root.shownCalendars.filter(calendar => calendar.account === account.id).map(calendar => calendar.href)]))
  on_SyncKeyChanged: {
    if (root._loaded && !Paths.greeter)
      root._syncSoon.restart();
  }

  property bool _loaded: false

  property Timer _syncSoon: Timer {
    interval: 800
    onTriggered: root.sync()
  }

  property Timer _poll: Timer {
    interval: Math.max(60000, CalendarConfig.syncInterval)
    repeat: true
    running: root._wanted
    triggeredOnStart: true
    onTriggered: {
      // On start, only when the last sync is that old
      if (Date.now() - root.lastSync < interval - 30000)
        return;
      // The range follows today, keeping what views paged to
      const base = CalendarEvents.rangeFor(Date.now(), CalendarConfig.pastMonths, CalendarConfig.futureMonths);
      root.range = {
        "from": Math.min(base.from, root.range.from),
        "to": Math.max(base.to, root.range.to)
      };
      root.sync();
    }
  }

  // Every account with its shown calendars, as every call sends them;
  // with `onlyAccount`, that one even with none shown
  function _accounts(onlyAccount) {
    return CalendarConfig.accounts.map(account => ({
          "id": account.id,
          "kind": account.kind,
          "url": account.url,
          "username": account.username,
          "calendars": root.shownCalendars.filter(calendar => calendar.account === account.id).map(calendar => ({
                "href": calendar.href
              }))
        })).filter(account => account.calendars.length > 0 || account.id === onlyAccount);
  }

  // A failed call as the result callers get; axiom's refusal for a CalDAV
  // account with no password saved is told apart by its message
  // (calendar.NoPassword)
  function _failure(error) {
    return {
      "ok": false,
      "kind": error.kind === "unauthorized" && error.message === "No password saved for this account" ? "no_password" : error.kind,
      "message": error.message
    };
  }

  function _enqueue(cmd, run, callback) {
    root._jobs = root._jobs.concat([
      {
        "cmd": cmd,
        "run": run,
        "callback": callback
      }
    ]);
    root._next();
  }

  function _next() {
    if (root._running || root._jobs.length === 0)
      return;
    const job = root._jobs[0];
    root._jobs = root._jobs.slice(1);
    root._running = job;
    job.run(result => {
      root._loadEvents();
      root._running = null;
      job.callback?.(result);
      root._next();
    });
  }

  function _loadEvents() {
    const content = FileManager.read("file://" + root._stateDir + "/events.json");
    if (!content)
      return;
    try {
      const data = JSON.parse(content);
      root.events = data.events ?? [];
      root.errors = data.errors ?? [];
      root.lastSync = data.updated ?? 0;
    } catch (e) {
      console.warn("[CalendarManager] Could not read events.json:", e);
    }
    root._scheduleAlarm();
  }

  // --- Reminders ---

  property Timer _alarmTimer: Timer {
    onTriggered: root._fireDue()
  }

  function _scheduleAlarm() {
    root._alarmTimer.stop();
    if (Paths.greeter || !CalendarConfig.reminders)
      return;
    const shown = root.shownCalendars.map(calendar => calendar.id);
    const next = CalendarEvents.nextAlarm(root.events.filter(event => shown.includes(event.calendar)), Date.now(), root._fired, 300000);
    if (!next)
      return;
    // At most an hour at a time, so a suspend can't leave it late
    root._alarmTimer.interval = Math.max(500, Math.min(next.time - Date.now(), 3600000));
    root._alarmTimer.start();
  }

  function _fireDue() {
    const now = Date.now();
    const shown = root.shownCalendars.map(calendar => calendar.id);
    const events = root.events.filter(event => shown.includes(event.calendar));
    let next = CalendarEvents.nextAlarm(events, now, root._fired, 300000);
    let fired = false;
    while (next && next.time <= now + 1000) {
      const fresh = Object.assign({}, root._fired);
      fresh[next.id] = next.time;
      root._fired = fresh;
      fired = true;
      root._notify(next.event);
      next = CalendarEvents.nextAlarm(events, now, root._fired, 300000);
    }
    if (fired) {
      // Forget reminders over two days old
      const kept = {};
      for (const id in root._fired)
        if (root._fired[id] > now - 2 * 86400000)
          kept[id] = root._fired[id];
      root._fired = kept;
      root._saveState();
    }
    root._scheduleAlarm();
  }

  function _saveState() {
    root._state.save({
      "fired": root._fired,
      "info": root.info
    });
  }

  function _notify(event) {
    const when = event.allDay ? I18n.tr("All day") : I18n.formatDate(new Date(event.start), CalendarConfig.timeFormat);
    const body = event.location ? I18n.tr("{0} · {1}", when, event.location) : when;
    NotificationManager.sendNotification(I18n.tr("Calendar"), event.title || I18n.tr("(No title)"), body, {
      "desktopEntry": root._desktopEntry,
      "icon": "x-office-calendar"
    });
  }

  readonly property bool _reminders: CalendarConfig.reminders
  on_RemindersChanged: root._scheduleAlarm()

  // Words the quick add knows, in the language and in English
  function _quickAddWords() {
    const words = text => text.toLowerCase().split(",").map(word => word.trim()).filter(word => word);
    const weekdays = [];
    const english = [["sunday", "sun"], ["monday", "mon"], ["tuesday", "tue", "tues"], ["wednesday", "wed"], ["thursday", "thu", "thur", "thurs"], ["friday", "fri"], ["saturday", "sat"]];
    for (let day = 0; day < 7; day++)
      weekdays.push([I18n.locale.dayName(day, Locale.LongFormat).toLowerCase(), I18n.locale.dayName(day, Locale.ShortFormat).toLowerCase().replace(/\.$/, "")].concat(english[day]));
    const shortFormat = I18n.locale.dateFormat(Locale.ShortFormat);
    // A comma-separated list of words for each, in the language
    return {
      "today": words(I18n.tr("today")).concat(["today"]),
      "tomorrow": words(I18n.tr("tomorrow, tmr")).concat(["tomorrow", "tmr"]),
      "allDay": words(I18n.tr("all day, all-day")).concat(["all day", "all-day"]),
      "weekdays": weekdays,
      "monthFirst": shortFormat.indexOf("M") < shortFormat.indexOf("d")
    };
  }

  property IpcTarget _ipc: IpcTarget {
    target: "calendar"
    enabled: !Paths.greeter

    function open(): void {
      root.openPage();
    }

    function newEvent(): void {
      root.openPage({
        "kind": "new",
        "key": CalendarEvents.dayKey(Date.now())
      });
    }

    function sync(): void {
      root.sync();
    }

    function add(text: string): bool {
      return root.quickAdd(text);
    }
  }

  Component.onCompleted: {
    if (Paths.greeter)
      return;
    const state = root._state.load({
      "fired": {},
      "info": {}
    });
    root._fired = state.fired ?? {};
    root.info = state.info ?? {};
    root._loadEvents();
    root._loaded = true;
    NotificationManager.registerHandler(root._desktopEntry, () => root.openPage());
  }
}
