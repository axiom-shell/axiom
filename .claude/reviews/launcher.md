# launcher
reviewed: d51805b 2026-11-01  (full)

In good shape: one row shape for every provider, `/config` kept off bars, overlay pages and edge menus, both hosts placed and sized as documented, the daemon's clipboard history matching its contract. Open: `/generate` reads a LauncherConfig member that doesn't exist (General's target monitor's wallpaper is used), and about 29 lines of dead or repeated code.

## Open findings
- Major: [The launcher's /generate reads a monitor setting that doesn't exist](../../docs/dev/issues.md#the-launchers-generate-reads-a-monitor-setting-that-doesnt-exist)
- Cleanup: "EmojiManager's groups() is never called" (fixed, row 20 platform-01)
- Cleanup: "LauncherManager keeps a dead clear() and a cliphist test" (fixed, row 20 platform-01)
- Cleanup: [A clip's label and detail are written in both the launcher and the clipboard module](../../docs/dev/issues.md#a-clips-label-and-detail-are-written-in-both-the-launcher-and-the-clipboard-module)
- Cleanup: [App scoring is written twice and the use bonus three times](../../docs/dev/issues.md#app-scoring-is-written-twice-and-the-use-bonus-three-times)
- Minor: launcher.md's row shape and LauncherManager's header leave out `armed` (command rows waiting for their confirming Enter; LauncherRow reads it).
- Minor: systems.md's launcher Check names `Overlay.views` (format 1); the blocked keys are `Bars.items`, `Overlay.items`, `EdgeMenus` (`SettingsManager._blockedPrefixes`).
- Known, not re-filed: `LauncherConfig.clipboardMaxEntries` unread ("Three reader members nothing reads" (fixed, row 20 config-01)); `/config` reaching takeover settings ([The launcher's /config can switch a takeover setting](../../docs/dev/issues.md#the-launchers-config-can-switch-a-takeover-setting)); Shift+Enter emoji typing on niri.

## Contract
Holds: `open(text)` searches before the host shows and `reset` skips a second search; reversed lists lay out bottom to top; detached is a `FloatingPopout` through `FloatPlacement` (claimKey `launcher:<screen>`, `maxContentHeight`, `growUp`, `animateHeight` off); attached an `EdgePopout` holding its height on side edges; only the host in use is created; the list frame glides and rows are reused (a grown/shrunk ListModel), dipping on a new `kind`+`title`; run true/false/string and Tab's `complete`; the prefix table and each provider's toggle; 42 command entries all with name, aliases, glyph, description; `confirm` arms for 3 s; `/config` offers only `settingPaths`, saves through `commitValue`, save/restore/example/community as documented, Show in settings only while a card shows the key; IPC `appLauncher` on the target instance only; locking closes it. Every `tool: true` view has a `_page` entry except CalendarPage, which has the equivalent hand-built `calendar` command (falls back to a Calendar module's page). Providers: qalc per-caller keys, one run at a time behind a 120 ms debounce, an echo is no answer, history/draft in PersistentProperties; the daemon's history (image > text > image-only HTML, secret hint skipped, hash dedupe, size caps, 0600 files in a private runtime dir cleared when off and at start/stop, every `clipboard.*` shell-only); pins on disk matched by text or preview; emoji from the committed JSON, typed 150 ms later through `input.type`.

## Coverage
Read deeply: LauncherManager, LauncherPanel, Launcher, LauncherRow, LauncherConfigBrowser, LauncherConfig, shell/AppLauncher, ClipboardManager, EmojiManager, CalculatorManager, methods/Search, FloatPlacement, backend/internal/clipboard/clipboard.go, daemon/clipboard.go. Outlined: LauncherCommands (entry shapes, builders, option lists; about 60% read), ClipboardHistory's helpers, EmojiPicker, LauncherPlace. Skipped: wayland/datacontrol (dbus-wayland's core), Calculator module (modules), generate_emoji.py (generator with committed output), tests and emoji.json.

## History
- 2026-11-01 full: 7 findings (1 Major, 4 Cleanup, 2 Minor); recorded
