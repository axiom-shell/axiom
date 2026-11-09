# Known issues

> **Files:** this file only
> **Config:** none
> **Related:** [Developer docs](README.md), [testing](testing.md)

Problems found while working on something else: not fixed yet, but recorded so they aren't lost. **Add an entry whenever you find a problem outside the task at hand** rather than fixing it unasked or only mentioning it. Remove the entry in the change that fixes it. Before starting work in an area, check here for what's already known about it. This is a working list for coding agents and the maintainer, meant to move to GitHub over time: it's not where to report or look up problems, which is [GitHub issues](https://github.com/axiom-shell/axiom/issues). Agents never open a GitHub issue themselves; the maintainer moves an entry there.

Every entry is linked from the phase of the [cleanup roadmap](roadmap.md) that resolves it: add the link with a new entry, and remove it with the entry (`scripts/check_docs.py` fails on a link to an entry that's gone and warns about an entry the roadmap doesn't link).

Entries are grouped by the shell system they're in, one `##` heading per area (Bar and border, Popouts and edge menus, … Tooling, tests and CI); everything after the first `##` heading is entries. A new entry goes under its area's heading (`.claude/skills/review-system/scope.py --apply` appends to the end of the file: move what it filed to its area). Each entry is a `###` heading plus these four bullets, in this order (`scripts/check_docs.py` checks the shape and that cited paths and members exist), optionally followed by indented `**Decided** (maintainer, <date>, …): "<their words>"` lines:

```
### <Short title>
- **Where:** `path/File.qml` (symbol, or several paths)
- **What:** what's wrong and the evidence (log line, grep count, failing case); quote a log warning's message in backticks so verify.sh marks it known (when it comes from a file **Where** cites, by its `@path` or a `[Name]` tag; one from Qt or Quickshell that names no file: quote its category too, `quickshell.I3.ipc`)
- **Size:** trivial | small | needs a plan (designed first: the roadmap's Items that need a plan)
- **Found:** YYYY-MM-DD, while <task>
```

## Bar and border

### "Colour the text by state" does nothing on a bar whose widgets have no fill
- **Where:** `qml/components/methods/BarWidgetStyle.qml` (`textByState`, `_make`); the same test in `qml/components/bar/widgets/Markets/Markets.qml` (`rich`: the change coloured inline, so on an unfilled bar it isn't, and on a tinted one it is)
- **What:** `textByState` asks `colors.fill.a < 1`, but `colors()` gives an unfilled style (outline, underline, accentText, plain, and a merged run's widgets) the string `"transparent"` as its fill, whose `.a` is undefined (checked in qmltestrunner: `"transparent".a` is `undefined`, `Qt.color("transparent").a` is 0). So `appearance.colorText` takes effect only on a tinted bar, where display-styles.md says it colours the text wherever it isn't the background's fill. Fix: `Qt.color(colors.fill).a < 1`, with a test row; but a merged run on a filled bar then puts the state colour on the run's own fill (its widgets' fill is transparent, the run's isn't), so whether that counts as a fill is a look choice for the maintainer.
  **Decided** (maintainer, 2026-11-06, on a) a merged run's fill counts as a fill (its text not coloured), b) colour the text in merged runs too; recommended a)): "defer"
- **Size:** trivial
- **Found:** 2026-11-06, while sharing SystemStats' text-by-state rule (row 20)

### A pill bar stacked inside another pill bar grows its pills out of nothing
- **Where:** `qml/components/bar/BarContainer.qml` (`borderOpening`), `qml/components/methods/BarEnds.qml` (`placeStack`)
- **What:** A pill bar's pills grow out of a stroke at its outer edge: the border's, which they cover and open. Stacked inside another pill bar (`offBorder`: pill bars are the first kind inside the border), there is no such stroke. Its outer edge lies on the far side of the bar outside it, which only that bar's pills stroke. Where an inner pill sits under an outer pill it joins that pill's far stroke and looks right; seen in a nested niri (two top pill bars, the inner one's end pills under the outer one's). Under a gap between the outer bar's pills, its outer side is open and its fillets curve into nothing. Since `offBorder`, it opens no border stroke (it used to cut the border's under the outer bar), and merged popouts on it open none either. Open for the plan: draw an inner pill bar's pills closed on their outer side (as islands), stretch the outer bar's pills over them, or leave pills inside the border's first bar to the user.
- **Size:** needs a plan
- **Found:** 2026-11-01, while adding stacked bars

### The border's stroke row is left unfilled where two pill bars meet at its corner, unbacked
- **Where:** `qml/components/bar/BarContainer.qml` (`borderOpening`, `joinOpening`), `qml/components/surfaces/border/RoundedBorders.qml`
- **What:** The border leaves its inner stroke open under a joined surface whenever `Appearance.translucent`, not only while the blur window backs it. In nested niri with a top and a left pill bar meeting at the top-left corner (translucency 80%, the look's blur off, so nothing is backed), the top frame's stroke row (y = 7) is bare wallpaper across the left frame's width (x 0–6): nothing fills it there, as the keepFill row was before compositor-20. Backed, the blur window fills it. Which opening takes that stretch (the left pill's `joinOpening` or the top pill's `borderOpening`) wasn't traced.
- **Size:** small
- **Found:** 2026-11-04, while fixing a keepFill opening's unfilled row (compositor-20)

## Popouts and edge menus

### EdgePlacement logs a binding loop on _layout
- **Where:** `qml/components/hosts/popout/EdgePlacement.qml` (`_layout`), `qml/components/hosts/popout/BarPopouts.qml`, `qml/components/hosts/popout/EdgePopout.qml`
- **What:** The live shell logged `Binding loop detected for property "_layout"` (`@components/hosts/popout/BarPopouts.qml[215:3]` and `@components/hosts/popout/EdgePopout.qml[314:3]`) several times after a reload on 2026-11-06, running the markets branch, which changes none of these files. The cycle isn't traced: PLAUSIBLE, settled by finding which of `_layout`'s inputs (`frame`, `_params`) reads a value derived from `_layout` itself.
- **Size:** small
- **Found:** 2026-11-06, while reviewing the Markets branch

### A hover-opened held edge menu closes before the pointer crosses from its edge to its box
- **Where:** `qml/components/hosts/popout/EdgePopout.qml` (`keepAlive`, `surfaceWindow.mask`, `attachAt`), `qml/components/surfaces/edgemenu/FloatingEdgeMenu.qml` (`dismissDelay`)
- **What:** A floating edge menu held off its edge (`detached`, with `distance` up to 50% of the free screen) opens from its hover strip at the screen edge, but its window starts a connector gap short of its box (`attachAt`) and its input mask is the box alone (`boxArea`), so nothing of it lies between the strip and the box. Leaving the strip drops `keepAlive` (`surface.hovered || trigger.containsMouse || …`), and `PopoutWrapperBase` starts its dismiss timer at the menu's `close.delay` (default 250 ms); `_grace` from `engage()` only feeds `engaged` (the claim's rank), not `keepAlive`. So unless the pointer crosses the gap, which can be half the screen, within that delay, the menu closes on the way to it. The dock solves the same path by taking the gap into its mask until the pointer first reaches the box (`DockWindow._reachedBox`), which the maintainer's answer on the dock suggested for all popouts.
- **Size:** small
- **Found:** 2026-11-06, while reviewing the dock gaps batch (row 20)

### A menu at the screen-size cap can still lose a bar's depth
- **Where:** `qml/config/EdgeMenusConfig.qml` (`scaleOf`)
- **What:** `scaleOf` shrinks a menu's Module size so its depth across its edge fits the screen less its padding (`GridPlacement.fitModuleScale`). Worked out from config alone, it doesn't take off what the bars and border reserve across that edge (EdgeMenuManager's frame, `frame.across`), so a menu at the cap sits past them and loses about their depth at the far screen edge (a nested niri run, 2026-11-05: a top menu at Module size 200 reached the screen's bottom edge). Fix: take the frame's `across` off the room too, from the hosts (which know the frame), or leave it (rare: it takes a card size and Module size high enough to reach the cap). Kept as built by the coordinator (2026-11-05): rare path, no product stake.
  **Decided** (maintainer, 2026-11-06, on a) fix it from the hosts, b) defer; recommended b)): "defer"
- **Size:** small
- **Found:** 2026-11-05, while fixing bar-popouts-07 (row 20)

### Submenus don't always get their blur backing
- **Where:** `qml/components/hosts/popout/SubPopout.qml` (the surface's `backed`, `parentOrigin`)
- **What:** The maintainer sees submenus (a popout's or an edge menu's) open without the blur behind them some of the time; not reproduced yet. A lead: `backed` also needs `parentOrigin` (`slot.popupScreenOrigin`, where the parent's window is on screen), so a submenu opened before that's known stays unbacked until something re-evaluates it; `onOverlayLayer` follows its host too.
- **Size:** small
- **Found:** 2026-10-29, while building custom widgets (reported by the maintainer)

### A popout taller than the screen runs off it
- **Where:** `qml/components/hosts/popout/BarPopouts.qml` (`popoutRoom`), `qml/components/content/Calendar/Calendar.qml`
- **What:** Nothing keeps a bar popout's content within the screen: content taller than the room past the bar (the Calendar popout with its event editor open on a short screen, 1080 px or less with a top bar) draws its box past the screen's far side, and what's there is cut off. `popoutRoom` measures the room left, and only `StyledComboEntry`'s inline list keeps to it. A general guard would hand the content a most height (as `SubPopout.maxContentHeight` does for submenus) for it to scroll within. The tray's own menu (`content/SystemTray`, a `TrayMenuList` given no `maxHeight`) is another case (popouts audit, 2026-10-30); `TrayMenuList` has a `maxHeight` (its submenus pass `SubPopout.maxContentHeight`) this guard could set.
- **Size:** needs a plan
- **Found:** 2026-10-20, while making dropdowns in popouts open inline

### A dropdown in an edge menu card with nothing scrolling gets two rows
- **Where:** `qml/components/reusable/StyledComboEntry.qml` (`_roomBelow`), `qml/components/content/parts/PomodoroDial.qml`
- **What:** In a floating edge menu a `StyledComboEntry` opens inline, capped by the Flickable around it. A card with no Flickable (Pomodoro as a card, its task picker) gets the two-row minimum (`_roomBelow` is 0 with no Flickable and `popoutRoom` null), and the card's rows below it are pushed out of view while it's open. Since PomodoroDial became a DialControls (row 20, features-05) the picker is the card's last row and the ring fills what's left, so there the open list shrinks the ring instead; it still gets two rows. Open question: how much room should such a list take (shrink the parts above it, or more rows over them)?
  Not as traced (row 20's autopilot, 2026-11-06): every edge menu card sits in `EdgeMenuBody`'s Flickable, so `_roomBelow` isn't 0 there; in nested niri the Pomodoro card's list opened inline with a 553 px cap. Which card gets the two-row minimum is still to find.
  **Decided** (maintainer, 2026-11-06, on a) open the list over the card's content (up to the card's height), b) more rows inline, shrinking the parts above, c) keep two rows; recommended a)): "rec"
- **Size:** small
- **Found:** 2026-10-20, while making dropdowns in popouts open inline

### A side edge's submenus always open away from the edge
- **Where:** `qml/components/hosts/popout/SubmenuSide.qml` (`openToLeft`)
- **What:** On a left or right edge a submenu always opens away from that edge (`openToLeft` is `edge === ScreenEdge.Right`), so a floating menu on the right edge opens every submenu to its left, across the menu's own content side. The maintainer finds that unexpected for a right-edge menu: which way it should open there (and whether by the box's place on screen, as top and bottom edges do) needs deciding. Seen with a `Submenu` module in a right-edge floating menu in nested niri.

  **Decided** (maintainer, 2026-11-01, on a) toward the edge, b) away as now, c) by the box's place on screen; recommended c): "defer - This takes quite a bit of thought to make consistent without an option."
- **Size:** small
- **Found:** 2026-10-18, while checking shadow seams on side-edge menus

### A pill bar's end reach trails a sliding popout's wall
- **Where:** `qml/components/hosts/popout/PillBarJoin.qml`, `qml/components/hosts/popout/EdgePlacement.qml` (`_slideLead`), `qml/components/bar/BarContainer.qml` (`_endReach`)
- **What:** Seen on niri with a solid bottom bar (border off) whose SystemStats popout joins the left pill bar: while the popout slides in or out, the left bar's end pill, run on to the popout's top wall, trails it by about 8px for two or three frames (below the wall while opening, above it while closing), so the two strokes and their shadows step at the left bar's inner edge. At rest they line up. Probably the other bar's window committing a frame or so after the popout's (as `AttachedSurface`'s fillet opening is taken a stroke ahead for). The end pill leads the wall by a stroke there (niri has no `supports.layerFrameSync`, `EdgePlacement._slideLead`), which helps but doesn't close the gap; sway and Hyprland move the two as one without it.

  **Decided** (maintainer, 2026-11-01, on the recommendation "defer"): "defer".
- **Size:** small
- **Found:** 2026-10-18, while fixing shadow seams where a wall runs on into another surface

### On Hyprland a click back in an older popout closes it with the newer one
- **Where:** `qml/services/compositor/FocusGrab.qml` (`dismissed`, `_outside`), `qml/services/ui/BackdropManager.qml` (`clickedOutside`)
- **What:** Hyprland has one native grab at a time, and its `cleared` doesn't say where the click landed. So while a newer keyboard popout (Todo, Calculator) holds the native grab over an older edge or floating popout (the launcher, a floating edge menu), a click back inside the older one clears the newer grab, which sends `BackdropManager.clickedOutside(null, null)`, and the older one is dismissed and closes too. Rare: hover popouts close once the pointer leaves them, so the pointer reaches the older popout only after the newer grab ended with no click, except where the two overlap or the newer one is held open. Accepted as is by the leader (bar-popouts-02, round 4); fixing it needs the click's position (a backdrop that takes clicks on Hyprland too).
  **Decided** (maintainer, 2026-11-06, on a) a backdrop that takes clicks on Hyprland, b) defer; recommended b)): "defer"
- **Size:** small
- **Found:** 2026-11-01, while reviewing bar-popouts-02 (edge and floating popouts closing on an outside click)

### An integrated top or bottom menu's zone follows its growing modules
- **Where:** `qml/components/surfaces/edgemenu/IntegratedEdgeMenu.qml:49` (`depth`), `qml/components/surfaces/edgemenu/IntegratedEdgeMenu.qml:135` (`exclusiveZone`), `qml/components/surfaces/edgemenu/EdgeMenuBody.qml` (`maxGrownHeight`)
- **What:** hosts.md says of an integrated menu: "The zone is set once while it's open (windows retile in one step)". But `depth` is `Math.ceil(root.bodyDepth + root.pad * 2 + root.innerStroke)`, with `bodyDepth` the body's live `implicitHeight` on a top or bottom edge: `ModuleGrid.sizes.height`, from the grown places (`ModuleGrid.places`). `exclusiveZone` and the window's `implicitHeight` follow it. So a top menu holding a module with `grow` (Notifications, AudioMixer, WifiNetworks, …: nine modules have it) changes its exclusive zone each time that module grows or shrinks, e.g. when a notification arrives: the windows retile again, and the shown layer window grows (the squeezed flash growing popout windows show). FloatingEdgeMenu avoids this by reserving the most up front (`maxContentDepth: root._body.maxGrownHeight`). Proposed fix (not decided): reserve `maxGrownHeight` on a top or bottom integrated menu, so the zone is set once.

  **On hold** (maintainer, 2026-10-31): "put this on hold - note that growing modules kinda needs a re-work or removal". Growing modules as a whole (`grow`, [grow-expand](overlay/grow-expand.md)) need a rework or removal; this entry waits for that and is [deferred](roadmap.md#deferred). No design is recorded.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the edge-menus system

## Docks, toasts and the OSD

### A detached dock and toasts don't slide in from under the bars
- **Where:** `qml/components/surfaces/dock/DockWindow.qml` (`_detachedBox`, `slide`), `qml/components/surfaces/notifications/ToastStack.qml` (`area`)
- **What:** Every other detached box slides in from off the screen under the bars on Hyprland ([Held off an edge › Sliding in from off the screen](popouts/held-off-edge.md#sliding-in-from-off-the-screen)), but these two don't. A detached dock slides out from its window's edge at the reserved line: its window is always mapped (`axiom-dock`, ordered over the bars), and when held and reserving, its exclusive zone ends at its box, so a window reaching back to the screen edge needs its own design. The toasts' area window is always mapped on the Overlay layer, so a detached toast slides from that window's edge, over the bars, or from the screen edge over a fullscreen window. Going under the bars needs a Top window under them that moves to Overlay over a fullscreen window, and Hyprland reads a layer rule's `order` only as a surface maps: measure that in a nested Hyprland first.
- **Size:** needs a plan
- **Found:** 2026-11-05, while making every floating popout slide in from off the screen

### The dock's menu and drag state outlive the icons they point at
- **Where:** `qml/components/surfaces/dock/DockWindow.qml:216` (`dragIndex`), `qml/components/surfaces/dock/DockWindow.qml:357` (`menuIndex`), `qml/components/surfaces/dock/DockWindow.qml:574` (`anchorItem`), `qml/components/surfaces/dock/DockItem.qml:100` (the hover Timer)
- **What:** The menu is held as `menuKey`/`menuFull` and anchored on `repeater.itemAt(root.menuIndex)`; a drag as `dragIndex`. Both are cleared only by the icon or the menu itself (`closeMenu()` from DockItem's press, click and drag start, DockMenu's FocusGrab `onCleared`, `conceal()`; `dragIndex = -1` only in DockItem's `_endDrag`). Two paths leave them set:
  - (1) The app goes while its full menu is open: an unpinned app's last window closes by itself (an app quitting, a dialog finishing). `menuIndex` becomes -1, `anchorItem` null, the menu hides, and its FocusGrab (`active: root.visible && root.full`) goes inactive without `cleared`. `menuFull` stays true, so DockItem's hover Timer (`running: … && !root.dockWindow.menuFull && …`) never opens an app's name and windows again; a press doesn't clear it either (`if (!root.dockWindow.menuFull) closeMenu()`). Only a left click or drag on an icon, or the dock being put away, ends it; if the app comes back, its full menu pops open again unasked.
  - (2) Any app appears or goes while a menu is open or an icon is carried: `model: root.keys` is a new JS array, and the Repeater rebuilds every DockItem (the comment at line 84: "they only rebuild when the set of apps changes"). The menu's anchor is destroyed; `anchorItem` isn't re-read when `menuIndex` keeps its value (a pinned app's index doesn't move when a running app is added), so the menu hides with `menuKey` still set (the hover Timer's `menuKey !== root.key` keeps that icon's names shut). A carried icon's delegate is destroyed with its press, so no drop or cancel reaches `_endDrag`: `dragIndex` stays ≥ 0, `engaged` stays true, and a hover or intellihide dock never hides again, magnification stays off and the icon now at that index draws without its indicator. PLAUSIBLE for (2): settle in a nested session (hover a pinned icon until its menu shows, open a window of an app not on the dock by a bind; the menu goes and doesn't come back on that icon) and the same while carrying an icon.
  Fix: clear both whenever the set of apps changes, in DockWindow: `onKeysChanged: { root.closeMenu(); root.dragIndex = -1; }` (4 lines; a hover menu reopens after its 450 ms rest). Keeping the menu across a change instead means anchoring it by key (`menuKey`) on the rebuilt delegate.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:dock system

### A dock beside another edge's reserving dock is laid out as if that dock weren't there
- **Where:** `qml/components/surfaces/dock/DockWindow.qml:467` (`margins`), `qml/components/surfaces/dock/DockWindow.qml:102` (`length`), `qml/components/hosts/popout/EdgePlacement.qml:161` (`innerStart`)
- **What:** A dock window is a Normal-exclusion layer anchored to both ends of its edge, so the compositor starts it past every exclusive zone at those ends, another dock's included (an always-shown, reserving left dock for a bottom dock). Its layout along the edge doesn't: `length` is `placement.innerEnd - placement.innerStart`, and EdgePlacement's inner sides are `ScreenEdgeManager.reservedWithMenusOn` (bars and integrated menus, no docks). Its margins along the edge are only `-root.startStrokeInset` / `-root.endStrokeInset`. EdgePopout, under the same compositor rule, reaches past docks there (`-root.startStrokeInset - DockManager.zoneOn(surfaceWindow.screenName, "left")`, EdgePopout.qml:414–415; comment "Docks reserving space inside the border don't push it in: it reaches past them, on its own edge and at both ends"). So with a reserving left dock of zone Z, the bottom dock's box is drawn Z px right of where `centre`/`insetStart`/`insetEnd` put it in a window Z px shorter than `length`: at `position` 100, or a dock as long as the edge, its far end runs Z px past the window and is cut off, and an attached dock's start end is worked out as joining the border's left stroke while it actually sits past the left dock. The trigger and intellihide rect (`DockManager.reservedOf`, the compositor's reserved) follow the shifted box, not the computed one. Which dock is pushed depends on the compositor's order when both reserve. PLAUSIBLE: settle in a nested session with a left reserving dock and a bottom dock at position 100. Open product question: should a dock keep clear of another edge's dock at its ends (subtract those zones from its inner sides, the box beside it) or reach past it as edge popouts do (the margins above, the box may meet the corner under it)?
  Fix: make the layout and the window agree: reaching past, subtract `DockManager.zoneOn(<screen>, <end side>)` in the along-edge margins as EdgePopout does (2 lines, the dock's own edge excluded).

  **Decided** (maintainer, 2026-11-01, on the recommendation "b) reach past it as edge popouts do"): "agree".
- **Size:** small
- **Found:** 2026-11-01, while reviewing the feature:dock system

### The OSD's hover strip opens an empty bars slot when every bar is left out
- **Where:** `qml/components/surfaces/osd/OSDHost.qml` (`_expose`, `_levelEntries`)
- **What:** `_expose` opens the "level" part whenever `_levelEntries` is non-empty, even when every bar in it is left out (Brightness alone on a monitor with no controller, `available` false), so hovering the strip or the Show button opens an empty slot instead of the icons or the preview card. The old `levelItems.length > 0` check did the same. PLAUSIBLE: settled by an OSD with only Brightness on a monitor without DDC. Fix: count only the bars shown (their system's state not hidden) in the check.
- **Size:** small
- **Found:** 2026-11-07, while reviewing the OSD engine branch

### An OSD on a screen that isn't the target opens its parts while shut and then stays open
- **Where:** `qml/components/surfaces/osd/OSDHost.qml` (`_showLevel`, `_showTile`, `_showCard`, `_due`, `preview`, `onHostOpenChanged`), `qml/components/surfaces/osd/OSDTriggers.qml` (`poke`), `qml/components/hosts/popout/PopoutWrapperBase.qml` (`hide`)
- **What:** With two monitors and an OSD whose `screen` is the focused one, screen B's host still opens its parts while shut (`force`), but `poke` doesn't show B. At the parts' due time `collapse` calls `hide()`, a no-op on a closed popout, so the parts stay open. Later, with B focused, `onHostOpenChanged` sees the stale open parts and skips `_expose`, their deadlines are past and the due timer is stopped, so the OSD on B stays open until the pointer crosses it. The OSD content before the engine had the same structure (`_openBox`). PLAUSIBLE: two monitors, an OSD on the focused screen, a change while the other is focused, then focusing it settles it. The settings' Preview (`OSDHost.pinned`) takes the same path on the other monitors. Fix: in each `_show*`, drop the change when the host is shut on a screen `ShellManager.showsOn` rejects; `preview()` the same.
- **Size:** small
- **Found:** 2026-11-08, while reviewing the OSD engine branch

### An OSD tile pops in on its own easing curve
- **Where:** `qml/components/surfaces/osd/design/OSDTile.qml` (`pop`)
- **What:** The tile's pop as it becomes the change runs `Appearance.animNormal` with `Easing.OutBack`, neither `Appearance.easing` nor marked `// behaviour timing: <reason>`, which AGENTS.md › Animation asks of a `duration:` (`check_structure` checks only the duration). Moved unchanged from the old `OSDStatusRow`. Fix: `Appearance.easing`, or keep the overshoot and mark it with its reason (a look choice).
- **Size:** trivial
- **Found:** 2026-11-08, while reviewing the OSD engine branch

### The OSD's drive tooltip names the last drive an event came from, even one removed
- **Where:** `qml/components/surfaces/osd/systems/Drives/Drives.qml` (`tile`)
- **What:** The drive tile's name is `state?.event?.name`, the drive of the last event, so with two drives plugged in and the second one ejected and removed, the tile (still shown for the first) names the drive that's gone. The old OSD items did the same. Fix: name a drive still plugged in (or none).
- **Size:** small
- **Found:** 2026-11-08, while reviewing the OSD engine branch

### The OSD's System volume bar stays enabled with no audio sink
- **Where:** `qml/components/surfaces/osd/systems/Audio/design/VolumeBar.qml` (`enabled`)
- **What:** `enabled` is `root.isMaster || …`, so the System volume bar takes drags and the mute click with no default sink (nothing to set), where the Microphone bar is disabled with no source and an App bar with no stream. The old volume bar did the same (enabled with the system volume in use). Fix: `AudioManager.defaultSink !== null` for the master bar.
- **Size:** trivial
- **Found:** 2026-11-08, while reviewing the OSD engine branch

### The OSD's Wi-Fi Connected card goes blank when the network drops while it's out
- **Where:** `qml/components/surfaces/osd/systems/Wifi/Wifi.qml` (`card`, `tile`, `onRemove`)
- **What:** A host re-reads a card out against the state now, and Wi-Fi's `card` takes its name from `tile("wifi", state.wifi)`, which names the network only while joined. Leaving a network is `onRemove: "none"` and the radio stays on, so `retractsCardWhenOff` doesn't fold the card: if the network drops while its Connected card is out, the card stays with an empty title and no signal. The OSD before the engine did the same. Fix: retract the card on leaving, or read the name the change carried.
- **Size:** small
- **Found:** 2026-11-08, while reviewing the OSD engine branch

### An OSD showing only Now playing opens an empty card from its hover strip or Show button when nothing plays
- **Where:** `qml/components/surfaces/osd/OSDHost.qml` (`_previewChange`, `_expose`)
- **What:** With no bars or icons, `_expose` opens the card `_previewChange` gives, and that picks the first system whose `exposes` has a `preview` entry (Now playing's) with its cards on, never asking whether anything plays: so hovering the strip or the Show button with no player opens an empty media card. The OSD before the engine did the same (`OSDContent._expose`: `hasMedia` alone). Fix: skip a preview key whose state in the host's snapshot is empty, leaving the host's own countdown.
- **Size:** trivial
- **Found:** 2026-11-08, while reviewing the OSD engine branch

### A headset's low-battery card gives way to Audio switching to that headset
- **Where:** `qml/components/surfaces/osd/systems/Bluetooth/Bluetooth.qml` (`absorbs`), `qml/components/methods/DeviceBatteries.qml` (`step`)
- **What:** A headset at 15% connecting: its "connected" card, then its low-battery card (`step`: a device newly connected with a low battery is a drop from "none"), replacing it, then Audio's Output card for the same address. `absorbs` takes Audio's switch in only under a "connected" event (`own.tile?.event !== "connected"`), so against the low card arbitration says "replace": the battery alert is covered, and routed to the OSD it has no notification either. PLAUSIBLE: a log of `BluetoothManager.lastEvent` kinds against `AudioManager.defaultSink` changes while connecting a low-battery headset settles the order. Fix if it shows: absorb under any device event but a disconnect (`["connected", "low", "critical"].includes(own.tile?.event)`), osd.md › Bluetooth's `absorbs` line, a Cross.js row.
- **Size:** small
- **Found:** 2026-11-08, while reviewing the OSD engine branch

## Overlay, modules and custom widgets

### A custom element sees another kind's element as its slot changes kind
- **Where:** `qml/components/content/parts/custom/CustomElement.qml` (`_load`), `qml/components/content/parts/custom/elements/Button/CustomButton.qml` (`label`, `icon`), `qml/components/content/parts/custom/elements/Toggle/CustomToggle.qml` (`label`)
- **What:** When a slot's element changes kind (the default Ring + Text giving way to a definition's own elements, or an element removed in the editor), the loaded item's bound `element` takes the new kind's element before `onKindChanged` reloads it: what overlay-modules-09 gave CustomRing's `inside` a `?? ""` for. Only Ring was quieted; a Button or Toggle handed another kind's options assigns an undefined `options.label` (and Button's `options.icon`) to a string the same way. PLAUSIBLE: a Button slot turning into another kind with the log open settles it. Fix at the cause: bind the item's `element` only while its kind matches the one loaded (keep the last matching element otherwise), then drop Ring's `?? ""`.
- **Size:** small
- **Found:** 2026-11-05, while reviewing the overlay and custom widgets minor sweep (overlay-modules-09)

### The overlay's gaps can't be adjusted
- **Where:** `qml/components/methods/GridPlacement.qml` (`cardSpacing`, `baseCard`, `gapOf`), `qml/config/OverlayConfig.qml` (`boxPadding`)
- **What:** The maintainer's note: "the overlay's gaps become adjustable". The gaps are one design value, `GridPlacement.cardSpacing` = 20: the gap between modules, the margin around the grid, the overlay box's padding and the tool pages' spacing; through `baseCard` and `gapOf` edge menus, the desktop, the lock screen and the greeter are drawn as the overlay's grid scaled. Answered so far (2026-10-29): "one setting, gaps between modules and edges of the overlay page look the same". Open: the overlay's alone, or one Look & Feel setting for the overlay, lock screen, greeter and desktop with edge menus kept at today's value (the maintainer: "Menus already seem smaller"); a bigger gap shrinks the cards on a page fitted to its screen. Deferred: "defer for now, still unsure".
  **Decided** (maintainer, 2026-11-06, on a) one Look & Feel setting for the overlay, lock screen, greeter and desktop with edge menus kept, b) the overlay alone, c) keep it deferred; recommended a)): "defer"
- **Size:** small
- **Found:** 2026-10-29, while splitting Phase 13 step 2 (row 16)

### Compact cards still build their full layout
- **Where:** `qml/components/content/base/Card.qml` (`full`), `qml/components/content/base/Panel.qml` (`column`, `background`)
- **What:** A module's children go into `Card.full` / `Panel.column` (a default property alias), which is only hidden while `compactContent` shows, so a compact card builds its whole layout as well as its figure. On the Tiny page (34 modules in quarter-card slots) this is most of what's left of its build: WifiNetworks about 65 ms, each ClockCalendar about 45 ms (`Built overlay module <Type> in X ms` with `--debug`). It also slows the bar popouts using those panels. A fix is an optional `fullContent: Component` on both roots, loaded only while not compact, then moving the heavy modules to it one by one (their ids are referenced from the module root, so each needs its own pass): see [streamed-building](core/streamed-building.md). The modules review (2026-10-31) found the same in Tailscale, VpnConnections, BluetoothDevices, AudioMixer, Palette, Pomodoro, Focus, Todo, Battery and TopProcesses; Notes always builds both its `tiny` figure and its editor; Disks, SystemGraphs and VolumeDials already skip part of their layout while compact. Parts hidden by mode rather than by compactness are Loaders on their mode (row 20).
- **Size:** needs a plan
- **Found:** 2026-10-21, while benchmarking the overlay's opening (overlay performance overhaul)

### A model of size -1 when the overlay grid resizes
- **Where:** `qml/components/hosts/overlay/OverlayPages.qml` (around the `grid` unit change; the model itself not found yet)
- **What:** The log shows `Model size of -1 is less than 0` right after `Overlay card unit 572 for 3376x1231` (the overlay's first sizing on a monitor), five times in one session. Opening the Themes or Settings page again didn't repeat it, so it's likely a Repeater or Grid whose count is worked out from a size that is still 0 or unset at that moment.
- **Size:** small
- **Found:** 2026-10-18, while adding the community setups gallery

### Typing in modules on the overlay and the desktop
- **Where:** `qml/components/hosts/overlay/OverlayPanel.qml` (`keyboardFocus`), `qml/components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`, `wantsKeyboard`)
- **What:** From the maintainer's notes: modules that take typing can't be used while they're on the overlay, and a click outside a desktop module stops its typing.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Modules inside borders aren't sized evenly
- **Where:** `qml/components/content/base/Card.qml`, `qml/components/content/ColorSwatch/ColorSwatch.qml`, `qml/components/content/KeyboardLayout/KeyboardLayout.qml`, `qml/components/content/Greeting/Greeting.qml`, `qml/components/content/Session/Session.qml`
- **What:** From the maintainer's notes: module sizing within borders isn't even (the space around modules framed by a border differs from side to side or between modules). Of the two likely causes the overlay review saw (2026-10-31), the first, slots and `Card`'s border on fractional pixels under `contentZoom`, was shown in a nested niri (page scaled 0.697: module borders smeared over two pixels at uneven strengths, crisp and even at zoom 1) and fixed in row 20 (`GridPlacement.rectPx` on whole drawn px, `OverlayGrid.drawnZoom`). The second is left: `Card` doesn't pad its content (`full` fills the box), while `Panel`'s column takes `pad`, so each `Card` module applies `pad` itself: ColorSwatch not at all, KeyboardLayout width only, Greeting `anchors.margins`, Session its own `margin` (0 when tight). PLAUSIBLE: not shown as uneven on screen (the swatch fills its box and KeyboardLayout centres its row by design), and padding every `Card` module changes how 25 modules look, a maintainer's call.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### Eight modules' full layouts need more room than their fullMin sizes, even inside the padding
- **Where:** `qml/components/content/Palette/Palette.qml:17` (`columns`), `qml/components/content/Pomodoro/Pomodoro.qml:20` (`fullMinHeight`), `qml/components/content/Focus/Focus.qml:30` (`fullMinHeight`), `qml/components/content/Disks/Disks.qml:25` (`columns`), `qml/components/content/Tailscale/Tailscale.qml:54` (`fullMinHeight`), `qml/components/content/WifiNetworks/WifiNetworks.qml:75` (`fullMinHeight`), `qml/components/content/Updates/Updates.qml:44` (`fullMinHeight`), `qml/components/content/NowPlaying/NowPlaying.qml:32` (`short`, `mini`)
- **What:** Contract (writing-modules.md): a module sets `fullMinWidth` / `fullMinHeight`, "the px its full layout needs inside its padding". These don't cover it. All figures are inner px at font 14, normal density.
  - **Palette** picks 2, 4 or 8 columns from width alone. `fullMinHeight` 12f (168 px) covers only 8 columns. 4 columns need about 266 px and 2 about 502 px (16 chips of about 57 px each with one role line). The default `[8, 4]` on a card under about 300 px tall cuts the bottom rows. Fix: choose the columns from both axes, and set the minimum from the chip count.
  - **Pomodoro**: the dial is at least 4f (56 px) plus 86.8 px of dots, play button and task picker, so it needs 142.8 px. `fullMinHeight` is 9f (126 px). Fix: about 13f, or derive the dial's reserve and the minimum from one `controlsHeight`.
  - **Focus**, stacked (under 34f wide): timer row 84 + separators 9 + todo field 30 + 4 + `DayPane`'s `Layout.minimumHeight` 8f (112) = 239 px, with no todo row showing. `fullMinHeight` is 14f (196 px).
  - **Disks**: a second column needs `innerWidth >= 12f`, but a disk lays out down to 7f. Two paths in a 4x1 strip at a 60 px unit (204×24 inside) stack 65 px into 24 px rather than going side by side. Its `fullMinHeight` 3f (42 px) is also under one disk (29.6 px) plus the pad.
  - **Tailscale**, connected with `actions` on (default): header 28 + this machine 47 + three folds 84 + separator + gaps 60 is about 220 px before one peer row. `fullMinHeight` is 11f (154 px), and a 4×2 card at 1080p (179 px inside) gives the device list 0 px. Fix: drop the folds in a short card (S4), or raise the minimum.
  - **WifiNetworks**: `fullMinHeight` 12f leaves about 23 px for the list (one row is 37 px). With VPNs, the controls alone need 146 px.
  - **Updates**: by its own `maxRows` terms, one section needs about 109 px and two need 180 px. `fullMinHeight` is 6f (84 px), and `Math.max(1, …)` forces one row. A 4x2 at a 50 px unit with AUR updates cuts off the AUR section entirely, with nothing to show it exists. Fix: derive `fullMinHeight` from the same terms.
  - **NowPlaying**: only the side-by-side layout sheds parts (`short` requires `sideBySide`). Stacked needs about 152 px but is used from `mini`'s 7f (98 px). Side by side and short needs about 86 px, so the schema's own `defaultSize: [4, 2]` at a 50 px unit (64 px inside) is about 22 px short. The strip at `fullMinHeight` 3.5f has 13 px for a 17 px title. Fix: let `short` apply when stacked too, raise `mini` to about 9f, and set the strip's minimum to its title line.

  These are arithmetic from the code, not screenshots. PLAUSIBLE in the exact px (font metrics vary), but each is more than 20 px over; re-measure in a nested shell at the sizes named.
- **Size:** small
- **Found:** 2026-10-31, while reviewing the modules system

### A stale exec-if check can block a widget after its exec-if changed
- **Where:** `qml/services/apps/CustomWidgetsManager.qml:163` (`_checkIf`)
- **What:** The check's callback only asks whether the id is still watched (`if (!(id in root._watching))`), not whether its `execIf` is still the one checked. Editing Run only if on the page re-checks on every keystroke (`_wanted` changes, `_sync` calls `_checkIf`), and clearing it watches at once (`_watch`). A check that ends after a newer one, e.g. typing `ping -c1 -W1 myhost` (the partial `ping -c1 -W1 myh` waits its second to fail while the full one answers in milliseconds), sets `_blocked`, releases the watch the newer check started and shows `"ping -c1 -W1 myh" failed` until the next refresh. PLAUSIBLE: the order the checks end in; a slow failing prefix settles it. Fix: `if (root._watching[id]?.execIf !== def.execIf) return;` in place of the `in` check (`_watching` holds each id's `execIf`).
- **Size:** trivial
- **Found:** 2026-10-31, while reviewing the custom-widgets system

## Settings, keybinds and editor pages

### Text clips on 1080p screens
- **Where:** `qml/components/views/Layouts/MenuOpening.qml` (the Show on screen / Show other menus buttons)
- **What:** On a 1920×1080 monitor at the default Interface scale, the edge menu editor's two buttons side by side ("Show on screen", "Show other menus", and their Hide labels) don't fit their halves of the inspector and their labels clip. Likely not the only place: much of the UI was laid out on a 1440 px screen, and since the sizing revamp text keeps its size on every monitor while panels and cards follow the screen. Wants a pass over the overlay pages and inspectors at 1080p (`scripts/dev/nested.sh` with a 1080p output), wrapping or stacking what doesn't fit.
- **Size:** needs a plan
- **Found:** 2026-10-21, while checking the sizing revamp on 1080p (overlaySettingsRevamp)

### A number field in the bar editor logs a polish loop
- **Where:** `qml/components/forms/SchemaNumberField.qml`, `qml/components/forms/SchemaField.qml` (`spinField`)
- **What:** With the bar editor's widget inspector open on the Workspaces widget, the live log repeats `SchemaNumberField called polish() inside updatePolish() of SchemaNumberField` and `possible QQuickItem::polish() loop` (220 lines over one session on 2026-11-09, before and after the inspector's change to one column, so not caused by it). A stepper's layout appears to change its own size during polish; which binding feeds back is untraced.
- **Size:** small
- **Found:** 2026-11-09, while making the widget inspector one column (PR #398)

### Setting names that still confuse
- **Where:** `qml/config/schema/sections/`
- **What:** From the maintainer's notes: "still confusing option names in settings" (after the look-and-feel renames). The plan lists the settings whose titles or keys read wrong, with a proposed name for each, for the maintainer to decide; a renamed key is a migration step.
- **Size:** needs a plan
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The monitor editor shows changes nobody made
- **Where:** `qml/services/compositor/MonitorManager.qml` (`draft`, `ensureLoaded`), `qml/components/views/Monitors/Monitors.qml`
- **What:** From the maintainer's notes: the monitors page shows unsaved changes when nothing was changed (likely a value the draft normalises on load differing from the saved one).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### The keybinds page on a small monitor with large binds
- **Where:** `qml/components/views/Keybinds/BindListRow.qml`, `qml/components/views/Keybinds/BindSection.qml`
- **What:** From the maintainer's notes: the keybinds page needs checking on a small monitor with long binds (combos and commands): rows that don't fit. Take it with the 1080p pass of [Text clips on 1080p screens](#text-clips-on-1080p-screens).
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### A type library's search matches the "Other" heading of every ungrouped type
- **Where:** `qml/components/methods/LibraryOrder.qml` (`filtered`), `qml/components/reusable/TypeLibrary.qml` (`headingOf`), `qml/components/reusable/TypePickerPopup.qml` (`headingOf`)
- **What:** `filtered` matches a type by its group's heading, and an ungrouped type's heading is "Other" (each picker's `headingOf` gives it, translated), so a query such as "th" lists every ungrouped type. The bar library already did it; the OSD Add picker and the bar editor's + picker now share it. Fix: match `headingOf(type.group)` only for a type with a group.
- **Size:** trivial
- **Found:** 2026-11-07, while reviewing the OSD engine branch

## Shell-wide: windows, screens, reloads and actions

### The screen-share picker repeats the shared prompt's modal frame
- **Where:** `qml/components/surfaces/screenshare/ScreenSharePickerWindow.qml`, `qml/components/surfaces/prompt/PromptWindow.qml`
- **What:** The picker draws its own copy of the frame `PromptWindow` now holds for the shared prompt: a `PanelWindow` per screen dimmed (`dim`, its `BoxBlurRegion` through `BlurManager.backdropRegionsOn`), the card only on the picked screen (`hasCard`), `WlrLayer.Overlay` with exclusive keyboard focus only there, and `SurfaceManager.registerModal`. Two copies of one pattern (AGENTS.md › UI conventions): the frame could be one shared piece both load their card into, or the picker could become a `PromptManager` request with content of its own (it would then queue behind a polkit or pairing prompt instead of stacking under it by layer order).
- **Size:** small
- **Found:** 2026-11-06, while lifting polkit's window into the shared prompt (Full Bluetooth's second part)

### Quick actions can't hold custom toggles or commands
- **Where:** `qml/components/content/QuickActions/QuickActions.qml`, `qml/services/ui/ActionsManager.qml`
- **What:** A tile can be any action of the catalogue, and the Button widget can run a command, but there's no tile of the user's own: a toggle with an on and an off command and a status command (exit 0 = on), or an action with a module as its detail. A plan was drafted on the unified-actions branch (a `CustomActions` section of items, `custom:<id>` tile ids run and judged by ActionsManager, a card to add them) and set aside by the maintainer (2026-11-06) as more than that branch needed. Its open questions: a toggle's state lags its command (hold the expected state until the status command agrees?); status commands poll while a tile shows (cost, a slow script makes the tile slow); the lock screen and greeter must never run them; a detail opens only in overlay pages and edge menus; a detail module's own settings nested in the item's form; a deleted item leaves `custom:x` in modules and Buttons; whether keybinds, hot corners and the launcher reach them too (`customActions run <id>`).
- **Size:** needs a plan
- **Found:** 2026-11-06, while finishing the unified-actions branch

### BlurManager.paused and WallpaperManager.rotationHeld read undefined on a reload
- **Where:** `qml/services/ui/BlurManager.qml` (`paused`), `qml/services/ui/WallpaperManager.qml` (`rotationHeld`), `qml/services/compositor/HyprlandManager.qml` (`activeWindowId`), `qml/components/content/WifiNetworks/WifiNetworks.qml` (`showsVpn`)
- **What:** A hot reload logged `@services/ui/BlurManager.qml[36:3]: Unable to assign [undefined] to bool` once (2026-10-30, after saving QML files under `qml/components/content/`; neither file the binding reads had changed). `paused` is a `&&` chain whose last term is `General.outputs.some(…)`; something in it (likely a singleton not ready yet during the reload, or `Appearance.blurPauseFullscreen`) reads undefined for a moment. Harmless (it settles at once), but it's log noise; `=== true` on the term that can be undefined, or `!!` on the chain, would silence it once the term is found. `WallpaperManager.rotationHeld`, the same shape (`&&`/`||` chains ending in `General.outputs.some(…)` and service reads), logged `@services/ui/WallpaperManager.qml[271:3]: Unable to assign [undefined] to bool` on a reload (2026-11-01, switching the checkout to a branch). `HyprlandManager.activeWindowId` (`"0x" + Hyprland.activeToplevel.address`, the toplevel there but its address not yet) logged `@services/compositor/HyprlandManager.qml[38:3]: Unable to assign [undefined] to QString` three times on a reload (2026-11-04, saving page window files). Reloads on 2026-11-08 logged `@services/ui/WallpaperManager.qml[301:3]: Unable to assign [undefined] to bool` (`rotationHeld`, moved down) and `WifiNetworks.qml[47:3]: Unable to assign [undefined] to bool` (`qml/components/content/WifiNetworks/WifiNetworks.qml` `showsVpn`, whose embedded branch reads `root.properties.showVpn` before the card's properties are in).
- **Size:** trivial
- **Found:** 2026-10-30, while building the network popout's VPN fold and connection details

### A hot corner can't close what covers it
- **Where:** `qml/shell/HotCorners.qml` (its layer, `LayerStack`), `docs/dev/features/hot-corners.md`
- **What:** Hot corners sit on the Top layer, so a surface on the `Overlay` layer (axiom's workspace overview, a full-screen overlay page) covers the corner pixel: a toggling action opens it from a corner but can't close it there. niri's own corner toggles its overview; the migrated corner (v82) does that only while `WorkspaceOverlay.compositorOverview` is on. Whether a corner should stay live over Overlay-layer surfaces is the maintainer's call.
  Not as traced (row 20's autopilot, 2026-11-06): moving the corner to the Overlay layer orders it over those surfaces only on Hyprland (layer rules). On niri and sway the stack follows map order, and the overlay page and workspace overview are outside `LayerSlot` ordering, so they'd still cover a corner mapped before them.
  **Decided** (maintainer, 2026-11-06, on a) corners stay live over Overlay-layer surfaces (never over a fullscreen window), b) keep it; recommended a)): "rec"
- **Size:** small
- **Found:** 2026-10-29, while reviewing the hot corners branch (row 16)

### Nineteen windows stay mapped on one monitor
- **Where:** `qml/components/surfaces/border/RoundedBorders.qml`, `qml/components/surfaces/border/BorderPanel.qml`, `qml/components/surfaces/backdrop/ScreenBackdrop.qml`, `qml/shell/BlurBackingWindow.qml`, `qml/components/hosts/popout/SubmenuHost.qml`, `qml/components/hosts/popout/EdgePopout.qml`, `qml/components/hosts/overlay/OverlayPanel.qml`
- **What:** Each window has its own render thread and GL context (19 `QSGRenderThread`s on one niri monitor). 9 are the border (4 strips, 4 corners, the shadow); the backdrop, blur backing and border shadow are `held` only for niri's map-order stacking. About 25 more (overlay, launcher, a submenu per popout host, edge-popout bodies, power menu, overview, switcher, prompts) keep their context for the session once shown. Options: strips drawing their own corners, windows unloaded a while after they hide, one stacking anchor instead of three held windows ([layer arrangement](compositor/layer-arrangement.md)).
- **Size:** needs a plan
- **Found:** 2026-10-27, while measuring the shell's memory

### Surfaces touch a dead screen after the outputs go away
- **Where:** every host building a surface per screen (`qml/shell/*.qml`, `screen: modelData`), and the ~40 reads of a surface's `screen` without `?.` (`root.screen.width`, …) in `qml/components/`
- **What:** An output that comes within a few tens of ms of another going (seen with `hyprctl output remove <primary>`, 30 ms, then `output create headless <name>` on a nested Hyprland; likely the DPMS and undock bursts that logged 68 lines on a real session) logs `attempted to use dangling screen object` about 200 times. Traced 2026-11-07: Variants deletes a gone screen's surfaces a tick late, its ShellScreen dangling meanwhile, and the new output's change re-evaluates their bindings (ScreenEdgeManager's, EdgePlacement's, ToastStack's, RoundedBorders', Launcher's `isTarget`, direct `screen.width` reads), which read it. (The plain unplug of the primary, 10 lines from SubPopout's `screenFrom`/`screenTo`, is fixed.) Fix: hosts pass `screen: General.connected(modelData)` (a new helper), null once the screen leaves `General.outputs` (tried on Notifications: its share went, no errors), after making every `screen.` read in the surfaces null-safe (else each logs a TypeError instead). Harmless (a warning).
- **Size:** needs a plan
- **Found:** 2026-10-20, while reviewing the popouts system

## Workspaces and monitors

### A remap runs at startup, from the layout before the config loaded
- **Where:** `qml/services/compositor/WorkspaceRemap.qml` (`_applied`, `_timer`, `onBlockSizeChanged`)
- **What:** Seen 2026-10-30 under Hyprland with a 3×3 grid: the session came up on workspace 10, with `[CompositorManager] remapping workspaces: 0 windows, outputs to DP-1:10` in the debug log. The 10 was the block a `desc:` profile rule gave DP-1 before its description arrived (fixed in row 20's compositor-11), so that symptom is gone, but what restarted the 200 ms timer at the shell's start is still unknown: `begin()` records `_applied` from the config snapshot, which `ConfigManager` reads synchronously, and Qt emits no change signal for a `blockSize`, `perMonitorBlocks` or `workspaceGrid` binding re-evaluated to the same value, so a guard skipping an unchanged layout would catch only a value that changed and changed back within the 200 ms. Either a value really changed after `begin()` (the snapshot differing from the config axiom answers `config.get` with, or a value read before the backend's `supports` settled), and the remap then ran from a layout the workspaces were never in, or something else called `remap`. The log line now carries the `from` and `to` layouts: the next time it shows at a start, they say which value moved. Fix: once that's known, record `_applied` after that value settles.
- **Size:** small
- **Found:** 2026-10-30, while investigating Hyprland starting on workspace 10

### Hyprland's default workspace doesn't highlight its first window
- **Where:** `qml/components/bar/widgets/Workspaces/StripWindows.qml` (`focused`), `qml/services/compositor/HyprlandManager.qml`
- **What:** From the maintainer's notes: on the workspace Hyprland starts on, the first window opened isn't highlighted as focused until a workspace move. Checked 2026-10-29 (code read, nested Hyprland): Hyprland's own data is right (the first window on workspace 1 has `focusHistoryID` 0 and is `activewindow`), and `StripWindows` highlights `CompositorManager.lastFocused` of the workspace's windows, which for one window is always it; so the cause isn't in either. Which highlight it is (bar strip, dock `DockManager.focusedId`, overview `WindowPreview.focused`) and under which layout (`StripWindows` shows only under scrolling, whose workspace ids `DynamicWorkspaces` renumbers until `_compaction` runs) needs the maintainer to reproduce it.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

## Compositors: niri and sway

### A bar popout's stroke flashes off its fill switching content on niri
- **Where:** `qml/components/hosts/popout/BarPopouts.qml` (`shownBoxWidth`/`shownBoxHeight`, the box gliding to new content), `qml/shell/BlurBackingWindow.qml` (its fill), `qml/components/hosts/popout/SwitchStill.qml`
- **What:** With blur on under niri, a bar popout switching to another widget's content in the same window shows its old stroke cutting into the box for a frame or two as it resizes: the stroke is the popout's window's, the fill the blur window's, and niri shows the two windows' frames out of step (no `supports.layerFrameSync`). Tried and reverted (2026-10-18), neither changing what the maintainer saw: holding the switch until the popout's window had drawn the new content twice (`SwitchStill`, its window's `frameSwapped`), and drawing the popout's stroke in the blur window with its fill (a stroke-only `AttachedSurfaceCopy` over the fills, the popout's own stroke transparent). That the second didn't help suggests the stroke isn't what's late: perhaps the popout's content, its clip, or the blur region. Next: log each window's `frameSwapped` with what it drew, during a switch.
- **Size:** small
- **Found:** 2026-10-18, while adding niri's blur

### Quickshell's wlr screencopy crashes the shell on niri
- **Where:** `qml/services/apps/ScreenshotManager.qml` (`grimFrames`, the workaround), `qml/components/surfaces/screenshot/ScreenshotPickerWindow.qml` (its `ScreencopyView`); the bug is Quickshell's
- **What:** Without ext-image-copy-capture (niri 26.04 has only wlr-screencopy), Quickshell's wlr screencopy binds a second `wl_output` of its own (`WlrScreencopyContext::OutputTransformQuery`, a `QtWayland::wl_output`; still so in upstream master). niri then sends `wl_surface.enter` for it to every surface; Qt takes it for one of its screens (`QWaylandScreen::fromWlOutput` casts it) and keeps a bogus screen in each surface's list. The next `enter`/`leave` on such a surface crashes in `QWaylandWindow::handleScreensChanged` → `QPlatformScreen::screen()` (at once with a popout open, which unmaps as the picker opens). WAYLAND_DEBUG: `bind(46, "wl_output", 3, …)` beside `zwlr_screencopy_manager_v1.capture_output`, `wl_surface.enter(wl_output#198)` on every surface, then `axiom-edge-popout`'s surface `leave(wl_output#19)` and the crash. Worked around: niri has no `supports.outputCapture`, so the picker's frame is grim's. Left: report it upstream (awaiting a second person to confirm), then drop the workaround once fixed. Sway and Hyprland 0.55 keep `outputCapture` (Hyprland checked by hand: no crash with a popout open).
- **Size:** small
- **Found:** 2026-10-18, while debugging the screenshot crash with a popout open

### Quickshell's I3 socket warns on every reload
- **Where:** `qml/services/compositor/SwayManager.qml` (Quickshell.I3)
- **What:** Under sway every reload of the shell logs `I3 event socket disconnected` twice (category `quickshell.I3.ipc`); events still arrive afterwards (checked in nested sway). Both come from Quickshell 0.3.2's `I3IpcListener` deleting its own connected socket, which its `stateChanged` handler reports as a disconnect: once when the old generation's listener is destroyed, once when the new one, already connected by setting `subscriptions` at creation, starts over in its `onPostReload` (so a cold start logs it once too). Axiom can't avoid it: any teardown of a connected listener logs it, and `I3.rawEvent` (the process-wide connection, which survives reloads) subscribes only to `workspace` and `output`. Nor is a log rule honest: the category also carries real faults, and sway drops an IPC client whose buffer fills, which Quickshell never reconnects, so this warning is then the only sign the event stream is dead. The fix is upstream: `I3Ipc` disconnecting its socket's signals before deleting it, and `I3IpcListener` not restarting with unchanged subscriptions.
- **Size:** trivial
- **Found:** 2026-10-16, while writing the sway backend

### niri reports no position for a tiled window, nor other apps' layers
- **Where:** `qml/components/methods/NiriState.qml` (`windows`, `outputs`)
- **What:** niri's IPC gives no layer surface geometry, so an output's `reserved` counts only axiom's own layers (`LayerArrange.arrange`): another app's bar on niri isn't in it, and the dock centres as if it weren't there. Nor, in 26.04, does it give a position for a tiled window (`tile_pos_in_workspace_view` is null; only floating windows have one; checked 2026-10-28). So tiled windows are laid out from their column and place in it from the output's edge, without niri's scroll (`windowGeometry` stays off: no screenshot window mode; the dock hides behind a window's `cover`, its column or the whole output, which ignores struts, reserved space and `center-focused-column`).
- **Size:** small
- **Found:** 2026-10-17, while adding the niri backend

### Shift+Enter on an emoji doesn't type it on niri
- **Where:** `qml/components/surfaces/launcher/LauncherPanel.qml` (`activate`), `qml/services/apps/EmojiManager.qml` (`type`)
- **What:** From the maintainer's notes: under niri, Shift+Enter on an emoji in the launcher doesn't type it into the focused window (typing goes through `input.type` on the daemon's virtual keyboard). Not reproduced (2026-10-28): in a nested niri on the live binary, `axiom launcher search ";grinning"` then Shift+Enter typed it into foot, kitty and a GTK entry every time, with fcitx5 and mozc running too; the live logs show no typing error, and the last emoji uses predate typing moving to the daemon. Untested: a physical Shift+Enter, Electron or Xwayland windows, the live focus-follows-mouse. Waits for the maintainer: which app, and does it still fail.
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

### A window takes the keyboard from a desktop module on niri
- **Where:** `qml/components/surfaces/desktop/DesktopWindow.qml` (`keyboardFocus`), `qml/services/ui/DesktopManager.qml`
- **What:** From the maintainer's notes: under niri, as soon as the mouse leaves a desktop module that takes typing, the window under the pointer takes the keyboard focus (niri's focus follows the mouse onto it), so typing in the module stops. How to hold the focus there is still open ("idk how to handle this").
- **Size:** small
- **Found:** 2026-10-28, while filing the maintainer's notes into the roadmap

## Config, takeovers and the daemon

### The daemon's other own commands still start outside command.Children
- **Where:** `backend/internal/sysmon/nvidia.go`, `backend/internal/theme/integrate.go`, `backend/internal/compositor/manager/niri.go`, `backend/internal/daemon/cursor.go`
- **What:** Row 20 moved `checkupdates`, `ddcutil` and `tailscale` to `command.Run` with the daemon's `Children`, but other commands the daemon runs for itself still start through their own `exec.Command` (`grep -rln 'exec.Command' backend/internal` lists them), so one in flight at a re-exec isn't handed on and stays a zombie until the daemon quits, as the three did. Not yet sorted into which run often enough to matter (a polled or streamed one) and which run once (a build, an install), which a re-exec doesn't meet.
- **Size:** small
- **Found:** 2026-11-06, while moving the daemon's own commands to command.Run (row 20)

### axiom config validate checks the install's config with the binary's schema under dev mode
- **Where:** `backend/internal/cli/config.go` (`configValidateCommand`, `offlinePipeline`)
- **What:** With no FILE and no `--tree`, `axiom config validate` reads `configDir(e)`'s config.json and checks it against the schema embedded in the binary it runs as. While dev mode runs the dev tree, the daemon runs the dev config through the dev tree's schema, so validate checks another file with another schema: a config using the dev tree's new types is called invalid though the daemon accepts it. Split out of the config watch's entry (row 20), where it was noted as related.
- **Size:** small
- **Found:** 2026-10-29, while testing custom widgets on the live config

### With no takeovers kept, a broken config.json can still release the compositor's config
- **Where:** `backend/internal/store/store.go` (`loadInitial`, `write`, `holdTakeovers`), `backend/internal/compositor/manager/manager.go` (`ConfigChanged`)
- **What:** The store reads the takeover values from `$XDG_STATE_HOME/axiom/takeovers.json` when config.json isn't JSON at the start. With none kept (the first start of this version on a file already broken, the state folder wiped) they're unknown: a restore, import or reset is refused (`write`; decided 2026-10-28: "Refuse, clearer message", which the Saved configs page shows), and the first hand fix that loads sets them as it reads, so a fix saying detached gives back a managed config applied before. The compositor manager's own hold, deleted in row 12, kept the mode applied in that case (`AppliedMode`, or `configIsOurs` / `moduleLoaded` after a reboot) and saved it back. Accepted by the maintainer (2026-10-28, #163): with no takeovers kept, a restore is refused and a hand fix sets the takeovers as it reads.
- **Size:** needs a plan
- **Found:** 2026-10-28, while reviewing row 12's third batch

### Leaving managed, the runtime layer can go on before the given-back config reloads
- **Where:** `backend/internal/compositor/manager/manager.go` (`SetInputs`, `liveChanged`, `apply`)
- **What:** The shell's first inputs arm both `debounce` and `liveDebounce` (300 ms each). When the live one fires first, `liveChanged` sees `AppliedMode != mode` and calls `apply`, which releases the managed config and asks for a reload; the layer debounce's `apply` then runs `runtimeApply` before that reload lands, so the runtime layer reads the managed config's binds (every axiom key looks taken, each logged once) and goes on over it. It's corrected after the reload (`configReloaded` applies again). Holding `runtimeApply` until `configReloaded` after a release that reloads would close it, but a missed reload event would then leave no runtime layer.
  **Decided** (maintainer, 2026-11-06, on keep it deferred (it corrects itself; the fix could leave no runtime layer); recommended keeping it deferred): "defer"
- **Size:** small
- **Found:** 2026-10-24, while reviewing the Go backend branch

### Readers read files through a service
- **Where:** `qml/config/Paths.qml` (`packagedVersion`), `qml/config/I18n.qml`
- **What:** Readers read only the data owners and each other (AGENTS.md › Layering), but `Paths.packagedVersion` calls `FileManager.read`, and `I18n` reads with both `FileManager.read` and a FileView of its own. Either the rule names `FileManager` as allowed in readers, or the reads move to a data owner.
  **Decided** (maintainer, 2026-11-06, on a) the rule allows `FileManager.read` in readers, b) the reads move to a data owner; recommended a)): "defer"
- **Size:** small
- **Found:** 2026-10-26, while reviewing the repository's organization

## Lock screen and greeter

### The lock screen has no settings for allowing or viewing notifications
- **Where:** `qml/config/schema/sections/Lockscreen.yaml`, `docs/dev/features/lockscreen.md`
- **What:** Asked by the maintainer (2026-10-31) beside the x-lockActions decision: "there should be settings for allowing/viewing notifications as well" on the lock screen. Not designed yet.

  **Decided** (maintainer, 2026-11-01, on the recommendation "defer"): "defer".
- **Size:** needs a plan
- **Found:** 2026-11-01, while recording the maintainer's answers to the clear-out's questions

### A greeter-only module validates on any page
- **Where:** `qml/components/content/Session/schema.yaml` (`hosts`), `qml/components/content/Login/schema.yaml`, `qml/components/content/Password/schema.yaml`
- **What:** `hosts: {only: [greeter]}` keeps Session out of the layouts editor's library elsewhere, but the built schema still lists it in every host's `oneOf`: a config with Session in an edge menu and on an overlay page passed `axiom config validate`, and it drew as a bare "Session" field on an empty card. So an import, a community setup or a hand edit can put a greeter- or lock-only module (Session, Login, Password) where it can't work.
- **Size:** small
- **Needs a decision:** a review of the fix (roadmap/20-daemon-cli, 2026-11-06) found that once the built schema rejects these modules outside their hosts, a config already holding one there (Session, Login, Password or Power, only by a hand edit or an import) fails validation and won't load. Should a format-2 migration step remove such modules first? The fix (per-host `OverlayModule@<host>` kinds from `x-hosts` in `schema/yamlsrc/kinds.go`) is ready to rebuild once that is decided.
- **Found:** 2026-10-29, while building the revamped example setups

## Wallpaper and theming

### A theme can't be generated from an avif or jxl wallpaper
- **Where:** `backend/internal/theme/theme.go` (`decode`), `qml/services/core/ThemeManager.qml` (generateThemesFromWallpaper)
- **What:** The wallpaper list takes avif and jxl where Qt's image plugin reads them (`WallpaperManager.extensions`), but the theme generator decodes only what Go's `image` package and `golang.org/x/image` do (PNG, JPEG, GIF, BMP, WebP). Picking an avif or jxl wallpaper shows it, but generating its theme fails and only logs `Theme generation failed: can't read the wallpaper` (`generationFailed` has no listener), so the theme stays the last one's. Fix (a choice): a Go decoder for each (a new dependency; the pure-Go ones run libavif/libjxl as WebAssembly), or the shell handing the daemon the image Qt already decoded (saved to the cache as PNG).
- **Size:** small
- **Found:** 2026-11-06, while adding webp, avif and jxl to the wallpaper list (row 20)

### Video wallpapers
- **Where:** `qml/components/surfaces/wallpaper/WallpaperView.qml`, `qml/services/core/ThemeManager.qml` (generateThemesFromWallpaper)
- **What:** An idea from the wallpaper transitions branch, not a bug: mp4/webm wallpapers through QtMultimedia. It adds a dependency and a steady GPU and battery cost, the transitions would need a video's frame as a texture, and generating a theme needs a still frame grabbed from it. Kept out of the branch (maintainer, 2026-11-01: not picked among the wallpaper improvements).
- **Size:** needs a plan
- **Found:** 2026-11-01, while adding wallpaper transitions

## Network, Bluetooth and devices

### A VPN secret request held when the shell leaves waits for NetworkManager's timeout
- **Where:** `backend/internal/daemon/vpn.go` (`newVPN`, `OnSecret`), `backend/internal/daemon/daemon.go` (`OnClose`)
- **What:** a `vpn.secretRequest` pushed to the shell holds NetworkManager's `GetSecrets` reply until the shell answers; when the last shell leaves nothing answers it, and a shell that comes back isn't sent it again (`vpn.secretRequest` isn't a latest-wins push), so the connect hangs until NetworkManager gives up. Bluetooth's agent rejects its held requests then (`lastShellGone` → `RejectAgents`). Fix: the same for the VPN agent: cancel what's held as the last shell leaves.
- **Size:** small
- **Found:** 2026-11-07, while reviewing the Bluetooth daemon branch

### A drive card's "open" on a locked volume asks in a menu nobody opened
- **Where:** `qml/services/system/DrivesManager.qml` (`activate`, `open`)
- **What:** a card's or notification's click whose action is "open" (`DriveInfo.clickAction`) calls `open(drive)`; for a volume still locked that is `askUnlock(v.id, true)`, whose passphrase field shows only in a Drives menu row, so with no menu open nothing visible happens. The Locked card's "unlock" already asks in the shared prompt (`promptUnlock`). Fix: from `activate`, a locked volume goes to `promptUnlock` too (and opens once mounted).
- **Size:** small
- **Found:** 2026-11-07, while reviewing the Bluetooth daemon branch

### Eject may leave a USB stick powered on
- **Where:** `backend/internal/udisks/udisks.go` (`eject`)
- **What:** `eject` picks the Drive's `Eject` over `PowerOff` for any drive with `CanEject` and removable media (`case drive.Optical || drive.CanEject && drive.mediaRemovable:` before `case drive.CanPowerOff:`). If udisks2 reports a USB stick with the removable bit as Ejectable, it only gets `Eject`: it stays in udisks2 without media (hidden, `removed` sent) but powered, which contradicts `docs/dev/features/drives.md` ("locks and powers off"). A card reader's card wants `Eject` (the reader stays). PLAUSIBLE: `udisksctl info -b /dev/sdX` on a real stick (Ejectable, CanPowerOff, MediaRemovable) settles it. Fix, if it holds: `PowerOff` first when `CanPowerOff` and the drive isn't a card reader (`Optical` or a media-changing reader keeps `Eject`), the way GNOME's gvfs powers off a stick after its eject.
- **Size:** small
- **Found:** 2026-11-01, while reviewing removable drive support

### No keyboard backlight control
- **Where:** `qml/services/system/BrightnessManager.qml`
- **What:** Laptops' keyboard backlights (`kbd_backlight` LEDs) have no slider, OSD bar or keys: nothing in services reads them. Also open: whether `BrightnessManager` takes them as another device, the OSD bar kind, and writing the LED through the daemon.
- **Size:** needs a plan
- **Found:** 2026-10-30, while listing small gaps users notice at once

### The panel's relative times go stale while Tailscale's state stays the same
- **Where:** `qml/components/content/Tailscale/Tailscale.qml:46` (`now`, `keyDays`), `qml/components/content/ClaudeUsage/ClaudeUsage.qml:22` (`now`)
- **What:** `now` and `keyDays` are re-read only when `TailscaleManager.peers` is reassigned (`void TailscaleManager.peers; return Date.now();`). The daemon's topic hub pushes a state only when its JSON changed (`backend/internal/topics/topics.go:344`, `if bytes.Equal(data, t.last)`), and `Parse` keeps only the peers' online/active/relay/last seen/traffic fields. On a quiet tailnet (all peers offline or idle), nothing changes between polls. A module left on the desktop or in an edge menu then keeps saying "Offline · seen 3m ago" for hours, and the key-expiry warning appears only at the next unrelated change after the 7-day mark. ClaudeUsage's `now` is built the same way, though its accounts' `fetchedAt` changes at every fetch, so it lags by one fetch interval at most. PLAUSIBLE: what's unproven is whether an idle tailnet's parsed state really repeats byte for byte; to settle it, compare two `tailscale status --json` runs parsed a minute apart on a connected, idle tailnet. Fix: drive the times from a minute clock, as Notifications does (`SystemClock { id: clock; precision: SystemClock.Minutes }`, `readonly property real now: clock.date.getTime()`), and compute `keyDays` from `root.now`.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the tailscale system

### Tailscale's state is polled where it could be pushed
- **Where:** `backend/internal/tailscale/tailscale.go`, `qml/services/apps/TailscaleManager.qml` (acquire), `qml/services/system/VpnManager.qml` (acquire)
- **What:** Tailscale's state comes from `tailscale status --json` every `Tailscale.interval` (10 s default) while anything holds `TailscaleManager`: the Tailscale and Vpn widgets, the Network, WifiNetworks and VpnConnections cards, and now an OSD with the VPN status, which holds it for the whole session. A connect or drop shows up to 10 s late, while NetworkManager's VPNs are pushed (`vpn.state`). tailscaled's LocalAPI streams its changes (`/localapi/v0/watch-ipn-bus`, what `tailscale status --watch`-style clients use), so the daemon could watch that instead of running the CLI, with the interval left only for the peers' details if needed.
- **Size:** needs a plan
- **Found:** 2026-11-01, while adding the OSD's VPN status

### Peripherals only UPower sees aren't in the Battery widget or module
- **Where:** `qml/services/system/BatteryManager.qml` (`peripherals`)
- **What:** `peripherals` lists only the connected Bluetooth devices whose battery BlueZ reports (`Battery1`, through `BluetoothManager`). A mouse or keyboard on a Logitech Unifying or Bolt receiver, a wired gamepad or a UPS reports its charge only to UPower (its devices besides the display device, `UPower.devices`), so it isn't listed, and a Bluetooth device both report is BlueZ's alone. Reading UPower's devices too (by kind, without listing a Bluetooth device twice) would add them.
- **Size:** small
- **Found:** 2026-11-06, while adding peripheral batteries to Battery (Full Bluetooth, part 4)

## Chat

### The chat has no slash commands to control it
- **Where:** `qml/components/content/parts/chat/ChatComposer.qml` (`_send`), `qml/services/apps/ChatManager.qml` (`send`), `qml/services/ui/LauncherCommands.qml` (`chat`), `qml/services/ui/LauncherManager.qml` (`_chatRow`)
- **What:** The maintainer (2026-11-01): "add chat slash commands for control to roadmap where necessary". Today the chat's composer handles no `/` input: `_send` hands the text to `ChatManager.send`, which sends `/new` to the model like any message. Outside the chat, the launcher's `@question` (`_chatRow`) and IPC `chat ask` start a new conversation with the default preset and send the question (`ChatManager.ask`); the launcher's `/chat` (alias `/ai`) opens the chat, a new conversation or a saved one; IPC `chat` also has `open`, `newChat` and `settings`. Every other control is a button only: New conversation (the header), Stop (the send button while busy), the preset and model pick (`ModelPicker`), regenerate, copy and remove a message (`ChatMessage`), rename, open and delete a conversation (`ConversationList`), attach the clipboard or a screenshot (the composer's buttons), and the provider's key (`openSettings`). Open for the plan: which of these get a command in the composer (candidates: new, stop, preset, model, regenerate, rename, delete, attach, settings, help), how they're offered (a suggestion list while typing `/`, as the launcher does), how a message really starting with `/` is sent, and whether the launcher's `/chat` takes the same commands.
- **Size:** needs a plan
- **Found:** 2026-11-01, while filing the maintainer's notes

### An image sent without text to Anthropic carries a whitespace-only text block
- **Where:** `backend/internal/chat/send.go:284` (`anthropicRequest`)
- **What:** `send` allows a message with attachments and no text, and `anthropicRequest` always appends `{"type": "text", "text": orSpace(t.text())}`, so an image-only message sends the text `" "`. The Messages API rejects whitespace-only text blocks ("text content blocks must contain non-whitespace text"), so the reply fails as `bad_reply` where OpenAI-style and Gemini requests (which skip the text when there are images) succeed. PLAUSIBLE: one Anthropic request with an image and empty text settles it (not made: paid API). The shape came over unchanged from the old ChatProtocol. Fix: append the text block only when the text is non-empty or there's no image (`if text := t.text(); text != "" || len(content) == 0 { … orSpace(text) … }`), plus a TestBuild row with an image-only user turn.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the chat system

### Stop is ignored while chat.send still looks up the key
- **Where:** `backend/internal/chat/send.go:87` (`Send`), `backend/internal/chat/send.go:160` (`Stop`)
- **What:** `Send` looks the key up (`keyFor`: the environment, then `secret-tool lookup`, then secrets.json) before it registers its cancel in `s.running` (line 94), and `Stop` does nothing for an id not there. A Stop pressed during the lookup (a locked keyring's unlock prompt, a slow Secret Service) is lost: the request goes out afterwards and streams to the end while the shell shows it as stopping; the same for `newConversation`'s stop. PLAUSIBLE that users meet it: it needs a lookup slow enough to press Stop in. Fix: register the cancel first and do the lookup under the cancellable ctx (move `ctx, cancel := context.WithCancelCause(ctx)` and the registration above `keyFor`, and answer `Stopped` when `stopped()` after it), plus a TestStop case stopping before the lookup returns.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the chat system

## Notes, calendar and timers

### Making a note or folder creates a linked notes folder that doesn't exist
- **Where:** `qml/services/apps/NotesManager.qml` (`_create`)
- **What:** notes.md: "A linked folder is never created". With `Notes.directory` linked and missing (`directoryMissing`), the editor is now read-only, but the note list's and the header's New note and New folder buttons still call `createNote` / `createFolder`, whose `_create` runs `mkdir -p` on the folder first, so the whole path is made on the root disk (a drive not mounted yet, a typo). Found by reading. Fix: `_create` refuses while `directoryMissing` (`_fail` with "The notes folder doesn't exist"), or the buttons are disabled then.
- **Size:** trivial
- **Found:** 2026-11-06, while making the notes editor read-only while its folder is missing (row 20)

### Calendar times in a Windows zone name with no VTIMEZONE read as local time
- **Where:** `backend/internal/calendar/ical/zone.go` (`Zones.With`), `backend/internal/calendar/calendar.go` (`New`'s `Lookup`)
- **What:** A TZID the zone database doesn't know is read only from the object's own VTIMEZONE. The Python helper this replaced (icalendar's `tzp.timezone`) also mapped a Windows zone name (`Pacific Standard Time`, about 140 of them in its `WINDOWS_TO_OLSON` table) and a "globally unique" `/vendor/…/Europe/Berlin` TZID to the IANA zone without one. An event naming such a zone with no VTIMEZONE beside it (rare: Outlook's feeds and invitations carry theirs) now shows at its wall time read as local time, off by the zones' difference. A fix is the CLDR windowsZones table and the prefix strip in `Lookup`; whether the rare case is worth the table is the maintainer's call.

  **Decided** (maintainer, 2026-11-01, on the recommendation "leave it logged"): "agree".
- **Size:** small
- **Found:** 2026-10-27, while reviewing the calendar port (roadmap row 8)

### A pomodoro, timer or caffeine end due during a suspend fires up to an hour after waking
- **Where:** `qml/services/apps/DeadlineTicker.qml:133` (`_arm`), `qml/services/apps/DeadlineTicker.qml:159` (`_armWarning`)
- **What:** `_arm` sets a single-shot Timer to `Math.min(left + 50, 3600000)` and only looks at `Date.now()` again when it fires. Qt's timers run on the monotonic clock, which stops while the machine sleeps. Start a 25-minute pomodoro, suspend after 5 minutes, wake an hour later: the alarm still has 20 minutes to run, so for 20 minutes the dial and bar widget read `00:00` while still running, and when it finally fires the end is over 5 minutes late, so `_end(late)` advances silently with no notification. The same holds for the one-off timer (StopwatchManager) and caffeine's timer (IdleManager), and for the warning alarm. Nothing in the shell listens for wake (the daemon's logind watcher sees `PrepareForSleep`, but no shell code reacts to it). PLAUSIBLE: settle by suspending with a 2-minute timer for 5 minutes and watching when it ends. Fix: cap both alarms at a minute instead of an hour (`Math.min(left + 50, 60000)`), bounding the lateness to a minute at the cost of one wake-up a minute while a deadline runs; update the doc's "at most an hour at a time".
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the feature:todo-pomodoro system

## Tooling, tests and CI

### guard.py judges daemon calls and the radio only by argv
- **Where:** `.claude/hooks/guard.py` (`check_bluetooth`, `scratch_system_bus`, `axiom_live_display`)
- **What:** every daemon-RPC rule matches the method name in the command's arguments, so a request fed from stdin or a file (`socat - UNIX-CONNECT:… < req.json`, `nc -U`) or sent by another program (`node`) passes; a write straight to `/dev/rfkill` isn't judged; and `scratch_system_bus` takes `unix:path=/run/dbus/../dbus/system_bus_socket` for a scratch bus (it compares the string, not the resolved path). Neither are an axiom binary run under another name (`go run ./cmd/axiom bluetooth off`, a copy named `axiom.new`), a raw `ipc.call` written as JSON in `printf`'s arguments (judged by method, not target: `lockscreen` too), nor a `python3 -c` calling BlueZ, timedate1 or hostname1 through python-dbus or Gio. Fix: resolve the bus path before comparing; refuse writes to `/dev/rfkill`; judge a redirect or pipe into a socket client by its input file where it's one.
- **Size:** small
- **Found:** 2026-11-07, while reviewing the Bluetooth daemon branch

### guard.py doesn't judge qs ipc call
- **Where:** `.claude/hooks/guard.py` (`check_axiom`, `check_argv`)
- **What:** the rules on IPC targets read `axiom ipc …` only: `axiom ipc lockscreen lock` is refused, `qs ipc call lockscreen lock` passes `guard.check` (tried), and so does every other target a rule names (`bluetooth disable`, `onboarding`, …). Fix: judge `qs ipc call <target> <fn>` (and `qs ipc --pid … call`, `--newest`) as `axiom ipc <target> <fn>`, a test case each.
- **Size:** small
- **Found:** 2026-11-07, while reviewing the Bluetooth daemon branch

### rpc.md doesn't mark the drives methods shell only
- **Where:** `scripts/gen_docs.py` (`rpc_scan`), `backend/internal/daemon/drives.go` (`drivesMethods`)
- **What:** `rpc_scan` marks a method "shell only" when its handler's text holds `fromShell(c)`, but `drivesMethods` checks through a `refuse(c)` closure defined above its first `rpc.Handle`, so the generated rpc.md lists `drives.mount`, `drives.unlock`, `drives.eject` and the rest with no guard, though each refuses any connection but the shell's. Fix: check inline as `bluetoothMethods` does (`if !fromShell(c)`), or have `rpc_scan` follow a closure that calls `fromShell`.
- **Size:** trivial
- **Found:** 2026-11-06, while moving Bluetooth to the daemon

### A push of a named branch can land on main through git's push config
- **Where:** `.claude/hooks/guard.py` (`push_allowed`)
- **What:** The guard judges `git push origin <branch>` by the name alone, but git maps a branch named without `:<dst>` through its config: with `remote.origin.push` set to `refs/heads/x:refs/heads/main`, or `push.default=upstream` on a branch made from `origin/main` (which sets its upstream to main, as the autopilot's step 4 branches do), `git push origin x` updates main (shown on scratch repos 2026-11-06: `feature -> trunk`). That config can come from `git -c …`, `GIT_CONFIG_*` or an earlier `git config`; the global config sets neither today. Fix: refuse a push whose `-c`/`GIT_CONFIG_*` sets `push.*` or `remote.*.push`, or allow only the `<src>:<dst>` form.
- **Size:** small
- **Found:** 2026-11-06, while reviewing the guard's gh and push allowlists

### TestNotifySend failed once under verify.sh
- **Where:** `backend/internal/daemon/tools_test.go` (`TestNotifySend`)
- **What:** One `scripts/dev/verify.sh` run failed it with `pushed {ID:1 Action:}`; 20 runs of it alone right after passed. Traced: the fake server answers every `Notify` with id 1 and emits its signal from a goroutine (`go server.Emit`), so the first send's `NotificationClosed` for id 1 can arrive after the second send (the one with a button) is waiting on id 1, which then reads as closed with no button. Fix: a new id per `Notify` in the fake.
- **Size:** trivial
- **Found:** 2026-11-06, while moving Bluetooth to the daemon

### TestDiscoverCalDAV failed once under verify.sh --all
- **Where:** `backend/internal/calendar/calendar_test.go` (`TestDiscoverCalDAV`)
- **What:** One `verify.sh --all` run failed `TestDiscoverCalDAV/from_the_server's_root,_redirected` with `got {Calendars:[]}`, while the other parallel subtests passed. That message didn't print the error, but there was one: traced, `discoverCalDAV` returns no calendars without an error only when its last candidate, `/.well-known/caldav`, answers, and `davServer` 404s it. Ruled out (row 20): the shared account id `acc` (only a read-only `Secrets.Lookup` of a file no test writes); `CloseIdleConnections` on the shared `http.DefaultTransport` (the weather flake's cause), hammered beside the test for about 20 000 runs, never broke a request. Not reproduced in about 15 000 runs of the package under load (`-race`, `-cpu 1,2,4,8`). The test now prints the error: read it the next time it fails before changing anything.
- **Size:** small
- **Found:** 2026-11-05, while running verify.sh --all for row 20 (bar-popouts-06)

### TestLogindLockAndSleep failed once under verify.sh
- **Where:** `backend/internal/idle/idle_test.go` (`TestLogindLockAndSleep`)
- **What:** One `scripts/dev/verify.sh` run failed it at its first `h.rec.expect(t, "lock")` with `actions [], want [lock]`: nothing was recorded within the 3 s bound after `h.logind.Lock()`, though `until(s.Logind)` had passed. Three `go test -count=1 ./internal/idle/` runs right after and a second verify.sh run passed. PLAUSIBLE: the service reports `Logind` before its `Lock` signal match is in place, so a Lock sent at once is missed; settle by running the package under load (`-race`, `-cpu 1,2,4,8`, `-count` in the hundreds) and checking when the match is added against when `Logind` turns true.
- **Size:** small
- **Found:** 2026-11-05, while reviewing the settings chunk of the tweaks-minor-complaints branch
