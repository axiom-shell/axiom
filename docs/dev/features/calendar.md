# Calendar

> **Files:** `services/apps/CalendarManager.qml`, `scripts/calendar_sync.py`, `config/CalendarConfig.qml`, `components/views/Settings/CalendarAccountsCard.qml`, `components/methods/CalendarEvents.qml`, `components/content/Calendar/Calendar.qml`, `components/content/Agenda/Agenda.qml`, `components/content/ClockCalendar/ClockCalendar.qml`, `components/content/parts/calendar/`
> **Config:** `Calendar.*` (reader `CalendarConfig`)
> **Related:** [Secrets](../core/secrets.md), [Services pattern](../core/services-pattern.md), [Notifications](notifications.md), [Lockscreen](lockscreen.md), [Greeter runtime](greeter-runtime.md)

CalDAV accounts, read-only .ics feeds and local calendars: syncing through a Python helper, editing events, reminders, and the calendar UI parts.

### Sources
- **CalDAV accounts.**
- **Read-only .ics subscriptions:** `https://` / `webcal://`, or a local `file://` feed.
- **Local calendars** (kind `local`, "On this computer"): no server and no password.
  - Each calendar's `href` is a folder name, `<account id>-<base36 time>` (never one a removed calendar left behind), under `$XDG_DATA_HOME/axiom/calendars/` (`dataDir` in the request).
  - Each event is a `<uid>.ics` file in it; its etag is the file's mtime and size, and a write whose etag no longer matches is a `conflict`. A `.ics` file dropped in by hand is picked up by the next sync.
  - The Accounts card's **Add calendar** makes one; names are edited in place. Removing a calendar or the account only drops it from the config: its folder stays (a draft can be reverted, so nothing is deleted).
  - An href that isn't one plain name, or an event href leaving its folder, is refused (`notFound`).
  - `CalendarConfig.writableKind(kind)` is the one place that says local and CalDAV calendars can be changed.
- All three go through `scripts/calendar_sync.py`:
  - run with the system `python3`;
  - uses `icalendar` (and `python-dateutil`, its dependency), system packages on every distribution;
  - expands recurrences itself (`occurrences`, on `dateutil.rrule`): never `recurring-ical-events`, which Fedora doesn't package. `CalendarSync` makes importing it fail, so Arch and Fedora run the same code;
  - a `RANGE=THISANDFUTURE` override changes only its own occurrence, not the ones after it;
  - uses stdlib HTTP and XML for the WebDAV side.

### Reader (CalendarConfig)
- Accounts with their ids filled in.
- `calendars`, flattened, with resolved colors.
- `shownCalendars` / `writableCalendars`.
- `newEventCalendar`.
- `colors`, by calendar id.
- `timeFormat`, from `use24Hour`.

### Helper protocol
- Every helper call goes through `CommandManager.run`, with one JSON request on stdin.
  - Passwords come from `SecretsManager.withSecret("calendar", id)` and are included in the request.
- It prints one JSON result: `ok`, or a `code`:
  - `auth`, `network`, `notFound`, `notCalendar`, `conflict`, `readOnly`, `noPassword`, `parse`;
  - `helper` when it couldn't run at all, which also clears `available`;
  - `missingModule` (`message` the module) when icalendar or dateutil isn't installed: `missingModule` is set, `available` cleared, and `missingText` names the package to install (the Accounts card's description).
- `errorText(result)` turns these into words.
- One call runs at a time. Later jobs are queued, and a sync isn't queued twice.

### Discover
- Finds an account's calendars from any URL on the server:
  - `current-user-principal` → `calendar-home-set` → the collections;
  - redirects are followed for every method, which iCloud's per-user host needs;
  - `/.well-known/caldav` is tried second.
- For a feed, it reads the feed's name and color.

### Sync
- **Objects:** each calendar's objects are kept in `$XDG_STATE_HOME/axiom/calendar/objects.json`.
  - A calendar whose getctag / sync-token is unchanged is skipped.
  - Otherwise `calendar-multiget` fetches the changed etags.
  - A feed is checked by its ETag.
- **Events:** it writes the shown calendars' occurrences within `range` to `events.json`.
  - Both files are mode 600 and written atomically.
  - The manager reads `events.json` at startup and after each call, so events show at once and offline.
- **Errors:** a calendar that fails keeps its last copy and reports in `errors`.

**Occurrences:** recurrence and time zones are expanded in the helper. An occurrence is:
- `key`
- `calendar`: `"<account>|<href>"`
- `href`, `etag`, `uid`
- `rid`: the original start, `D:<date>` or `T:<epoch s>`
- `recurring`, `repeat`, `allDay`
- `start`, `end`: epoch ms
- `dayStart` / `dayEnd`: for all-day events, end exclusive
- `title`, `location`, `description`, `alarms`, `reminder`

### When it syncs
- Every `syncInterval`, while something has `acquire(owner)`d it or reminders are on.
- On start, only when the last sync is at least that old.
- When what it fetches changes (`_syncKey`: accounts and shown calendars, but not colors or names).
- When a view pages past `range` (`ensureMonth(year, month)`). The range follows today and keeps whatever was paged to.

### Saving and deleting
- **`save`:**
  - edits the stored VCALENDAR in place, so unknown properties survive;
  - PUTs it with `If-Match`;
  - a new event uses `If-None-Match: *`, in the local zone with its VTIMEZONE, so a weekly event keeps its hour over DST.
- **Scope:**
  - `series` moves a recurring series by however far the edited occurrence moved; its overrides' RECURRENCE-IDs and its EXDATEs move with it.
  - `occurrence` adds or edits a RECURRENCE-ID override.
- **`delete`:** DELETEs the event, or adds an EXDATE for a single occurrence.
- **Conflicts:** a 412 is `conflict`. The editor keeps the draft and says so.
- **Moving to another calendar:** a new event there, then the old one is deleted.
- **Local calendars:** the same edits, written to the event's file atomically (mode 600) or unlinked, instead of a PUT or DELETE.

### Reads
- `byDay` (`CalendarEvents.byDay` over the shown calendars)
- `eventsOn(key)`, `dotsFor(key)`
- `upcoming(now, until, allDay)`
- `timeText(event, key)`

### Reminders
- One single-shot timer to the next alarm (`CalendarEvents.nextAlarm`), at most an hour ahead.
- Missed alarms within 5 minutes are still shown.
- A notification with `desktopEntry` `axiom-calendar`; clicking it opens the page.
- Fired ids are kept for two days in `~/.local/state/axiom/ui/calendar.json`.

### Opening the page
- The month's 42 day cells (`MonthGrid`, also the Clock/Calendar module's) are streamed in (`StreamedLoader`, [streamed building](../core/streamed-building.md)), each keeping its place in the grid. Paging a month updates them in place.
- `request` (`{ kind: "new" | "day", key }`) is what `openPage(request)` asked for. It opens:
  - the CalendarPage view;
  - else the page with a Calendar module;
  - else Settings.
- The request is taken once (`takeRequest`) by whichever page or module shows it.

### Quick add
- `parseQuickAdd` / `quickAdd`.
- Uses `CalendarEvents.parseQuickAdd` with the language's words and weekday names, plus the English ones.

### Entry points
- IPC `calendar`: `open`, `newEvent`, `sync`, `add <text>`.
- Launcher `/calendar` and `/event`; the `/event` row previews the parse.
- Created from `shell.qml`'s `_services`.

### Privacy
- Events are private.
- Calendar and Agenda don't list `lockscreen` or `greeter` in `x-hosts`.
- ClockCalendar does list them, but shows events on the lock screen only with `Calendar.showOnLockscreen`, and read-only there:
  - `readOnly` on `DayPane` / `DayAgenda` / `EventRow`;
  - no editor, no +, no settings link.
- Never in the greeter. Nothing calendar-related runs in the greeter.

### UI parts (`content/parts/calendar/`)
- **`MonthGrid`:**
  - Six weeks, starting from the language's first weekday.
  - Owns the month shown: `step` / `showDay` / `showToday`. Asks `CalendarManager.ensureMonth`.
  - Shows a dot per calendar with events on a day, modelled by the joined colors.
  - With `titles`, it shows the events in cells that are tall enough, modelled by count, with "+n more".
  - `showEvents: false` makes it a plain date picker.
- **`EventRow`:** calendar color, title, time and place.
- **`DayAgenda`:** a day's rows under its date, a + to add, and empty / no-calendar states.
- **`EventEditor`:**
  - `open(draft)` takes a `CalendarEvents.newDraft` / `draftOf`.
  - Deleting asks in place of its buttons: This event / All events for a recurring event, a confirm otherwise. Saving a recurring event asks the same.
  - `actionsWidth` is how wide its buttons need it. The Calendar popout widens to it (through `DayPane.actionsWidth`), so a long translation isn't clipped.
  - It is read-only for a calendar axiom can't change.
- **`DateTimeField`:** a date button that folds a `MonthGrid` open, plus a typed time.
- **`DayPane`:** the agenda turning into the editor (`editing`).

Drafts, and everything about days, spans, dots, what's next, reminders due and quick add, are pure, in `methods/CalendarEvents` (tested in `tst_CalendarEvents`).

### Testing
- Test the helper against a scratch Radicale (`pip install radicale`), or with the served-feed and local-calendar tests in `tests/scripts/test_scripts.py` (`CalendarSync`).
- Never add a test account to the live config without removing it again.
