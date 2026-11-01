# feature:calendar
reviewed: e98fea2 2026-11-01  (full)

The daemon side (CalDAV, feeds, local calendars, recurrence expansion) is solid and tested; the trouble is in the shell's editing and settings paths. The Accounts card reads two server facts from config entries that can't hold them (a false task-list note under every account, no Read-only chip); a conflict never reloads, a move loses a series' history, Enter saves twice or for every event; a desktop or edge-menu Calendar card takes the page's request; feed titles render as styled text and load remote images. 14 lines of deletions.

## Open findings
- Blocker: [The Accounts card reads read-only and task-list facts from config entries that never hold them](../../docs/dev/issues.md#the-accounts-card-reads-read-only-and-task-list-facts-from-config-entries-that-never-hold-them)
- Major: [A Calendar card on the desktop or in an edge menu takes the page's request](../../docs/dev/issues.md#a-calendar-card-on-the-desktop-or-in-an-edge-menu-takes-the-pages-request)
- Major: [A save conflict reloads nothing, so trying again conflicts again](../../docs/dev/issues.md#a-save-conflict-reloads-nothing-so-trying-again-conflicts-again)
- Major: [Moving a recurring event to another calendar drops its earlier occurrences and exceptions](../../docs/dev/issues.md#moving-a-recurring-event-to-another-calendar-drops-its-earlier-occurrences-and-exceptions)
- Major: [Enter in the editor's title saves again while busy and picks All events while asking](../../docs/dev/issues.md#enter-in-the-editors-title-saves-again-while-busy-and-picks-all-events-while-asking)
- Major: [Removing a CalDAV account deletes its password before the draft is saved](../../docs/dev/issues.md#removing-a-caldav-account-deletes-its-password-before-the-draft-is-saved)
- Major: [Event titles from a feed render as styled text and load remote images](../../docs/dev/issues.md#event-titles-from-a-feed-render-as-styled-text-and-load-remote-images)
- Cleanup: [Calendar results and members nothing reads](../../docs/dev/issues.md#calendar-results-and-members-nothing-reads)
- Cleanup: [The Accounts card's fallbacks for a renamed key and for empty account ids](../../docs/dev/issues.md#the-accounts-cards-fallbacks-for-a-renamed-key-and-for-empty-account-ids)
- Minor: calendar.md's Reader and config-readers.md list `calendars`, `shownCalendars`/`writableCalendars`, `newEventCalendar`, `colors` under CalendarConfig (they're CalendarManager's) and "ids filled in" (the reader fills only `name`); `CalendarManager.discover`'s comment says `code` for `kind`.
- Known, not re-filed: [Calendar times in a Windows zone name with no VTIMEZONE read as local time](../../docs/dev/issues.md#calendar-times-in-a-windows-zone-name-with-no-vtimezone-read-as-local-time); [A popout taller than the screen runs off it](../../docs/dev/issues.md#a-popout-taller-than-the-screen-runs-off-it); [Parts shown in one mode are built hidden in every mode, in ten modules and parts](../../docs/dev/issues.md#parts-shown-in-one-mode-are-built-hidden-in-every-mode-in-ten-modules-and-parts); [Unbounded lists still built in full](../../docs/dev/issues.md#unbounded-lists-still-built-in-full). "The calendar doc's Files header leaves out its page" was already fixed; its entry was removed in this audit.

## Contract
Holds: the three sources; local calendars' folders, hrefs, etags, kept folders, path checks; `writableKind` the one place; Go WebDAV/ical, rrule-go, VTIMEZONE reading and writing; calls through `BackendManager.call` with `range` and `_accounts`, `_failure`, `no_calendars`, `refused` before any call; `errorText`'s kinds; one call at a time, a sync never queued twice, discover outside the queue; discover's principal → home → collections, redirects, `.well-known` second, `[]` never null; sync's ctag/sync-token skip, multiget batches, feed ETag, mode-600 atomic writes, per-calendar errors keeping the last copy; occurrence shape; sync triggers (`_wanted`, start only when stale, `_syncKey`, `ensureMonth`); save/delete in place with If-Match / If-None-Match, series/occurrence scope, EXDATE, resync after; reads; reminders (one timer ≤ 1 h, 5-minute grace, fired ids pruned after two days); opening order; quick add; entry points; privacy (x-hosts, lock screen read-only, nothing in the greeter). Doesn't hold: the editor's "It has been reloaded" (conflict entry), the Reader list (Minor).

## Coverage
Read deeply: CalendarManager, EventEditor, MonthGrid, DayPane, DayAgenda, EventRow, Calendar, CalendarAccountsCard (logic and calendar rows), calendar.go, dav.go (discover, feeds), daemon/calendar.go, ical/expand.go (`occurrences`, `repeatOf`), CalendarConfig, the Calendar schema and its CalendarAccount/CalendarEntry definitions, CalendarEvents (`draftOf`, `problems`, `payloadOf`). Outlined: CalendarPage, Agenda, ClockCalendar, DateTimeField, ical/edit.go, ical/ical.go, ical/zone.go, the rest of CalendarEvents; Go tests and tst_CalendarEvents run, not read. Skipped: nothing.

## History
- 2026-11-01 full: 10 findings (1 Blocker, 6 Major, 2 Cleanup, 1 Minor); recorded
