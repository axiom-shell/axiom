# Page windows

> **Files:** `qml/services/ui/PageWindowManager.qml`, `qml/shell/PageWindows.qml`, `qml/components/hosts/window/PageWindow.qml`, `qml/components/hosts/overlay/PoppedOutCard.qml`, `qml/components/hosts/overlay/OverlayPages.qml`, `qml/components/hosts/overlay/OverlayPageNavigator.qml`, `qml/components/hosts/overlay/OverlayGrid.qml`, `qml/components/views/base/BaseView.qml`, `qml/services/ui/ShellManager.qml`, `data/applications/`
> **Config:** `Overlay.items`, `Overlay.screen`, `Overlay.moduleScale`
> **Related:** [Overlay pages and the module grid](pages-and-grid.md), [Editors pattern](../core/editors-pattern.md), [Shell manager targeting](../core/shell-manager-targeting.md)

How a tool page leaves the overlay for a window of its own (an xdg toplevel, Quickshell's `FloatingWindow`) and comes back. Read this before changing which pages pop out, the window's sizing, or how pages are opened by name.

### Which pages
- A view type whose `schema.yaml` says `window: true` (`x-window`): Settings, Themes, BarEditor, Keybinds, WindowRules, CustomWidgets, CalendarPage. `OverlayConfig.isWindowable(type)`, and `OverlayConfig.windowTypes` lists them.
- Monitors (it reflows the outputs under its own window) and Layouts (it previews the overlay at screen size) don't pop out.
- A page opens in a window only while it's in `Overlay.items` (`OverlayConfig.viewEntry`). Removing it from config closes its window (`PageWindowManager` drops it as `OverlayConfig.views` changes), and putting it back doesn't reopen one.

### One host at a time
- A page's state lives in singletons (`SettingsManager`, `BarManager`, `KeybindManager.editor`, `CustomWidgetsManager.editor`, `CalendarManager.page`, the drafts, `EditsManager`). Building it in the overlay and a window at once would have two views driving one editor.
- So while a page is out (`PageWindowManager.isOpen(type)`), its overlay page loads `PoppedOutCard` instead of its view (`OverlayPages`' delegate swaps `content`).
  - The card shows the page's icon and name, **Bring here** (`popIn(type, false)`: the window closes and the page builds in its place) and **Go to window** (the overlay closes and the window is focused).
- Unsaved edits are drafts, so they survive either move. The navigator's dots and Save all / Discard all still cover a page that's out.

### PageWindowManager
- `open`: the page types that are out. It's kept, with the screen each opened on, in `PersistentProperties` (`axiomPageWindows`), so a QML reload brings the windows back and a restart starts with none.
- `popOut(type)` closes the overlay and adds the page. `popIn(type, show)` takes it out, opening the overlay on it with `show` (the window's button). `closed(type)` is the window closing itself (its `closed` signal, never its destruction, which a reload does too).
- `focus(type)` finds the window in `CompositorManager.windows` by its title (`titleOf`, "<Page> — axiom") and this shell's app id (`Quickshell.appId`, one for every qs window: there's no per-window app id), then calls `CompositorManager.focusWindow`, which switches workspace first. It closes the overlay first, whoever asks (a page opened by name, Go to window, the back chip, `pages window`): the overlay would cover the window and keep the keyboard.
- `opened(key)` (a view type or a Custom page's name): when that page is out, it focuses the window and answers true. `OverlayPanel.openPage` asks it first, so everything that opens a page by name goes to the window instead: `ShellManager.openOverlayPage` (launcher commands, keybinds, `openSetting`, `CalendarManager.openPage`), `axiom ipc overlay page`, a link. A navigator tab click doesn't (it's `OverlayPages.goTo`), so it shows the card and the window stays where it is.
- Window sizes are kept for good in `StateManager` (`pageWindows.json`), written a second after a resize settles. `sizeOf` is read once as a window opens, and `keepSize` doesn't notify, so a window's own resizes never feed back into its size.
- IPC target `pages`: `window <type>` (pop out, or focus when out; case-insensitive), `close <type>`, `list`.

### The window (`hosts/window/PageWindow`)
- `qml/shell/PageWindows` makes one `PageWindow` per windowable type, each behind a `LazyLoader` active while it's out. The Variants model is `OverlayConfig.windowTypes`, from the schema, not the live list.
- The window has a header (icon, name, unsaved dot, and a `pip_exit` button back into the overlay), then the page.
- **Sizing:**
  - The page lays out on an `OverlayGrid` with `windowed: true`. The card size comes from the screen the window opened on (the overlay's there, `PageWindowManager.screenOf`), never from the window's size, so content keeps the overlay's size and doesn't stretch.
  - `BaseView.windowed` makes `pageHeight` fill the window's height (`grid.roomHeight`), and lets the main area grow wider than in the overlay: `editorWidth`'s cap rises from 2.8 to 3.4 card units, and Settings' content takes the room beside its sidebar (`BaseView.windowedWidth`), up to 3 units.
  - A window narrower than the page's least width draws the page smaller as a whole (`pageBox.fitScale`, from the width only). The grid's height is divided by that scale, so the page still fills the window's height.
  - The first size (with none kept) is room for the page at its overlay size, within 75% × 85% of the screen. Tiling compositors pick their own.
- `Window.active` on the header reports the window with the keyboard (`PageWindowManager.activeType`).

### Links from a window
- `ShellManager.followLink` notes the active page window (`linkFromWindow`) while it opens the page.
  - A link to a page that is itself out focuses that window (`opened`). A link within the same page is a jump in place: the page's state is a singleton, and focusing the window it's in changes nothing.
  - Any other link opens the overlay. `OverlayPages` sets the way back to `window:<type>`, and the navigator's back chip then names that page. `followLinkBack` closes the overlay and focuses the window.

### Desktop entries (`data/applications/`)
- `axiom-<type>.desktop`, one per windowable page. `Exec=axiom ipc pages window <type>`.
- The AUR packages install them to `/usr/share/applications`. install.sh copies them to `$XDG_DATA_HOME/applications` with `Exec` naming the binary by its path (a launcher's PATH may not have it). An install updated later keeps the copies it made then.
- They're apps like any other, in axiom's launcher too: an entry opens its page in a window, where the page's `/` command opens the overlay (or goes to the window when the page is out).
- A new windowable page needs an entry here, plus a row in the `pages` IPC line in `docs/usage.md`.

### Testing
- Test it in a nested shell (`scripts/dev/nested.sh niri`). `<scratch>/axiom --socket … ipc pages window settings` pops out a page. `ipc overlay page Settings` should then focus the window. Pop out the page the overlay is on and `ipc overlay open`: the card shows.
- `qs log --pid <nested qs>` reads the nested shell's log. `axiom log` picks the live one when both run the same tree.
