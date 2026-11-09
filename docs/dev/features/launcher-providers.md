# Launcher providers: calculator, clipboard, emoji, files

> **Files:** `qml/services/apps/CalculatorManager.qml`, `qml/services/system/ClipboardManager.qml`, `backend/internal/clipboard/`, `backend/internal/wayland/datacontrol/`, `backend/internal/daemon/clipboard.go`, `qml/services/apps/EmojiManager.qml`, `qml/config/json/emoji.json`, `scripts/generate_emoji.py`, `qml/components/methods/Search.qml`, `qml/services/apps/FileSearchManager.qml`, `qml/components/content/Calculator/Calculator.qml`, `qml/components/content/ClipboardHistory/ClipboardHistory.qml`, `qml/components/content/EmojiPicker/EmojiPicker.qml`
> **Config:** `Launcher.providers.clipboard.enabled`, `Launcher.providers.clipboard.maxEntries`, `Launcher.providers.emoji`, `Launcher.providers.files.*` (reader `LauncherConfig`)
> **Related:** [Launcher](launcher.md), [File search](file-search.md), [Utility modules](../overlay/utility-modules.md)

This doc covers the services behind the launcher's `=`, `:`, `;` and `~` rows (the files in short: [file search](file-search.md) has the index). Each one also backs an overlay module (Calculator, ClipboardHistory, EmojiPicker).

### CalculatorManager (qalc)
- **Backend:** `qalc -t -- expr`. libqalculate fetches and caches its own exchange rates.
- **Callers:** the launcher's calculator rows and the Calculator module.
- **Per-caller keys:** each caller has its own key, so they never take each other's answers. The API is `evaluate(key, expr)`, `resultFor(key, expr)`, `answered`, `busyFor` and `forget`.
- **Queue:** one qalc runs at a time from a queue, debounced 120 ms.
  - When qalc only echoes its input back, that counts as no answer.
  - `evaluated(key)` fires as each answer lands.
- **Persistence:** these live in a `PersistentProperties`, so they survive reloads but not restarts:
  - `history` (`keep(expr, result)`, newest first, 20 entries)
  - the module's unfinished `draft`.
- **Launcher side:** the launcher asks under the key `launcher`, and its rows are rebuilt when it answers (`evaluated`). Enter copies the answer and keeps it in the calculator's history.

### ClipboardManager
- **Opening it:** the launcher's clipboard history is `:` or `/clipboard`.
- **Toggle:** `Launcher.providers.clipboard.enabled` is on by default and also appears on the onboarder's System page. Turning it off clears the history.
- **Created from** `qml/shell.qml`'s `_services`.

#### The history (the daemon's `internal/clipboard`)
- The axiom daemon reads every selection over the compositor's data control (`wayland/datacontrol`: `ext_data_control_v1`, else `zwlr_data_control_v1`), in place of wl-paste and cliphist. Each offer is read through a pipe, off the Wayland connection's goroutine, in order, while the history is on (the daemon reads `Launcher.providers.clipboard` itself).
- **What's kept**, read as the type preferred:
  - an image (`image/png` > `jpeg` > `webp` > `gif` > `bmp` > any other `image/*`, at most 32 MiB), with its size and, for png, jpeg and gif, its dimensions;
  - else text (`text/plain;charset=utf-8` > `UTF8_STRING` > `text/plain` > …), at most 100 000 characters, not blank;
  - else HTML that is just an `<img>` (a browser's copy without the image itself), shown from its http(s) `src`.
- A clip marked `x-kde-passwordManagerHint: secret` (what wl-paste's `CLIPBOARD_STATE=sensitive` was) is never recorded.
- Deduplicated by content (the copy moves to the top), capped at `Launcher.providers.clipboard.maxEntries` (the daemon reads it).
- In memory only, never on disk: an image is a file in `$XDG_RUNTIME_DIR/axiom/clipboard/` (tmpfs; the folder 0700, files 0600) for the shell to show, at most 256 MiB of them (the oldest go first), removed with its entry, when the history is turned off, and when the daemon starts and stops. A restart or re-exec starts the history empty.
- **To the shell:** `clipboard.state` (the `clipboard` topic) and `clipboard.get` give the entries with their text cut to 1000 characters; `clipboard.text {id}` gives one whole. Every `clipboard.*` method answers the shell only.

#### Rows and copying
- Launcher row text is `Text.PlainText`, since clips can hold markup.
- `copy` is `clipboard.copy {id}`: the daemon becomes the clipboard's source and serves the clip from memory (an image from its file, as its own type). Text never passes through argv.
- Every other text copy in axiom goes through `copyText(text)` (`clipboard.copy {text}`); a screenshot through `copyFile(path, "image/png")`. They work with the history off too.
- The chat's paste asks `clipboard.types`, then `clipboard.save {mimes, path}` writes the image into the conversation's folder.
- Without data control (`WaylandManager.clipboard` is ""), the launcher and the module say so.
- Shift+Enter on a row `remove`s it.

#### Pins
- `pins` are text clips only: `{ id, text, preview, time, pinned: true }`.
- They are the one part written to disk: `~/.local/state/axiom/ui/clipboardPins.json`. They are kept through `clear()` and restarts.
- `pin` fetches the clip whole first (`clipboard.text`), since a row holds only its start; `preview` keeps the row's text, which is how the row is matched.
- `unpin` goes by text.
- A pin copies with `copyText`.
- The launcher and the ClipboardHistory module list `shown`: pins first, then the history without them. Both name a clip with `labelOf(entry)` (its first line, or what an image is) and `detailOf(entry)` (line count and time, or format and size, or "HTML"); the launcher adds an HTML image's url, the module "Pinned".

### EmojiManager
- **Opening it:** the launcher's emoji are `;` or `/emoji`. `Launcher.providers.emoji` is on by default.
- **Data:** `entries()` reads `qml/config/json/emoji.json` on first use.
  - Each entry is `{ e, n: name, g: group, k: [keywords] }`.
  - The list holds fully-qualified emoji without skin tones, in Unicode's order.
  - It is generated by `scripts/generate_emoji.py` (stdlib; downloads emoji-test.txt and CLDR's English annotations) and committed, so nothing downloads at runtime.
- **Search:** `search(query, limit, group)` serves the launcher and the EmojiPicker module, scored with `methods/Search`:
  - the name first, then keywords and group, which count only on a real match;
  - plus frecency from `usage` (`Search.useBonus`), stored in `~/.local/state/axiom/ui/emoji.json`;
  - with no query, the most used come first.
  - `recent(limit)` is also provided (the EmojiPicker's recent row).
- **Enter / Shift+Enter:**
  - Enter `copy`s it (`ClipboardManager.copyText`).
  - Shift+Enter also `type`s the emoji, 150 ms later, once the launcher has let go of the keyboard: `input.type`, the daemon's virtual keyboard (`wayland/vkbd`). `canType` is `WaylandManager.typing`: the compositor offers `zwp_virtual_keyboard_manager_v1`.
- **Binds:** a bind opens it with the `launcherSearch` action and the argument `;`.

### FileSearchManager
- **Opening it:** the launcher's files are `~` or `/files` (alias `/find`); `Launcher.providers.files.enabled` is on by default. The main search shows the best `inSearch` files (0–5, default 3) below the apps.
- **Asks the daemon only** (`filesearch.*`, every method the shell's alone): `search(query, dir, limit, done)`, `browse(path, query, limit, done)` and `recent(limit, done)` share one rising id (`_seq`): an answer to anything older than the newest asked is dropped, and `filesearch.query` carries the id, so the daemon stops an older search early (newest wins). The three are `repeatable`: one a lost connection cut off is sent again after the next hello (the id still drops it when something newer was asked). Nothing is polled: the index's `state` comes from the `filesearch.state` push (the `fileSearch` hello topic) and `filesearch.get` after each hello.
- **Acting on a file:** `open(path)` (`DefaultAppsManager.open`, then `filesearch.used`, which ranks it up and lists it in the recent files), `reveal(path)` (`filesearch.reveal`: the file manager shows it selected, else its folder opens), `copyPath(path)` (`ClipboardManager.copyText`).
- **Icons:** `iconFor(item)`: the first of the item's `icons` (its type's, most specific first) the icon theme holds, then `folder` or `text-x-generic`; worked out once per type.
- **Thumbnails:** a row showing a file asks for it with `want(key, path)` and lets go with `unwant(key)` (`LauncherRow`, so only rows the list has built ask); the key is the path and mtime, so a changed file is asked again. At most 4 `filesearch.thumbnail` calls are out at once; a queued one no row wants by its turn is skipped. `thumbnails` (key → url, "" for none, a failure included) is replaced on each answer and trimmed to the wanted ones past 400. The calls are `repeatable`, so one a lost connection cut off is sent again after the next hello.
- **Rows:** `LauncherFiles` (LauncherManager's part) turns the typed text into a request (`FilePaths.parse`) and the answers into rows; see [file search](file-search.md) › The shell.
