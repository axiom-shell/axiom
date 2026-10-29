# Overlay and popouts close or break each other

> **Issue:** [Overlay and popouts close or break each other](../issues.md#overlay-and-popouts-close-or-break-each-other)
> **Status:** proposed

### Problem
The maintainer: popouts should be "usable as expected while the overlay is open, without closing the overlay", "nothing should close the overlay (i.e. after installing greetd and the polkit prompt closes, the overlay closes)", and "currently open popouts break when overlay is opened". The launcher is the one possible exception ("although it can also just open over the overlay and be usable").

Three causes, read from the code (the exact compositor behaviour is confirmed in item 1):

1. **Close on outside click rides on the focus grab.** `OverlayPanel`'s `FocusGrab` closes the overlay on `cleared` when `Overlay.closeOnOutsideClick` is on (off by default, on in the maintainer's config). But `cleared` means "keyboard focus left the grab's windows", not "a click outside":
   - *Native grab (Hyprland, `HyprlandGrab`):* only one grab is active at a time (`components/reusable/SurfaceGroup.qml`'s comment). Any other surface whose grab starts while the overlay is open ends the overlay's: a bar popout with a text field (`BarPopouts`' `focusGrab`, active on `wantsKeyboardFocus`), an `EdgePopout` or `FloatingPopout` with `grabEnabled` (the launcher, edge popouts), the dock menu, the power menu. So opening any of these over the overlay closes it.
   - *Polkit prompt:* `PolkitWindow` is in `SurfaceManager.modalWindows` while visible (`registerModal`), so the grab survives the prompt opening. When it closes, `onVisibleChanged` drops it from the grab's windows, and keyboard focus goes back to the last focused app window, not to the overlay (which asks `OnDemand` while a modal is up). That ends the grab: natively, focus left the windows; without one (sway, niri), `FocusGrab`'s watcher sees `_focused` go false after `_held` and fires `cleared` 100 ms later. The greeter install from Settings (`GreeterManager._runElevated`, axiom as polkit agent) is this path.
2. **Callers closing it on purpose** (`ShellManager.closeOverlay`): `ScreenLayoutEditor.startPreview` (the lock screen / greeter preview needs the screen; it reopens the Layouts page after), `OnboardingCard` (opens the onboarder, the same Overlay-layer `ReservedAreaWindow` kind), `ScreenRecord.start("screen")` (so the recording doesn't show the overlay), `Favourites` (after launching an app). Plus the user's own: Escape (`closeOnEscape`), the background `MouseArea`, the toggle, IPC.
3. **An open popout doesn't follow the overlay opening.** A popout that slides under a transparent bar (`axiom-popout-under`, `EdgePlacement.slidesUnder`) is on a layer the overlay covers. While the overlay is open a new one opens over it instead (`overOverlay`, `SurfaceContext.layout`), but the choice is latched while the popout is open (`BarPopouts._under` and `EdgePopout._overlayLatch`, both `ClosedLatch`), so a popout already open when the overlay opens ends up under it: drawn under the dimmed backdrop, its clicks taken by the overlay. Separately, the overlay takes the keyboard as it opens (`slideContainer.forceActiveFocus()`, `Exclusive` without a native grab), which ends an open popout's text-field grab (`focusLost`).

### Options
#### A. Patch the grab's false clears
Keep the grab as the outside-click detector, and ignore the `cleared` that isn't a click: skip it for a moment after a modal unregisters and give the overlay the keyboard back; for the native single grab, have a grab that starts over the overlay include the overlay's windows and hand the grab back when it ends. Small, but each surface with a grab needs the handover, the "one grab at a time" race stays, and a new grabbing surface reintroduces the bug.

#### B. The overlay closes only on what the user did, without a focus grab (recommended)
The overlay stops closing from its `FocusGrab` at all. Close on outside click becomes a real click: on the overlay's own empty background (already `backgroundClicks`), on the screen backdrop (`BackdropManager.clickedOutside`, the catcher every non-native grab already uses), or on another monitor's backdrop. A click on a bar, a popout, the launcher or a prompt is not outside. The grab, or plain `OnDemand` focus, is only kept for the keyboard. Every other surface's grab can then start and end over the overlay without touching it, the polkit case is gone, and launcher, popouts and the dock menu open over the overlay and are usable. Popouts follow the overlay opening (item 3). Costs: `Overlay.closeOnOutsideClick`'s description changes ("on a bar" no longer closes); on Hyprland the backdrop must catch clicks while the overlay is open (today it only does for non-native grabs), which is the same window and mask, gated differently.

#### C. A surface policy in SurfaceManager
B, plus one table of which surface may close or cover which (overlay, launcher, popouts, onboarder, previews), every `closeOverlay` caller replaced by a declared rule, and closing for a preview or the onboarder done by stepping aside (`SurfaceManager.beginStepAside`, which keeps the page and its state). The most uniform, but a new mechanism for four callers, and the same rules could live in each caller.

### Recommendation
B. The bugs all come from one thing: "keyboard focus left" is read as "the user clicked outside". Making the close an actual click, and leaving keyboard focus to the grabs, fixes the polkit case and the popouts-close-it case together, needs no handover between grabs, and stays fixed when a new grabbing surface is added. The four `closeOverlay` callers are kept or changed one by one (item 4) rather than through a new policy table.

### Items
1. **Confirm the causes** (small): trace logs on `OverlayPanel`'s `grab.onCleared` and `FocusGrab`'s clears, run on Hyprland and in a nested niri: a text-field popout, the launcher, the dock menu over the overlay, and a polkit prompt closing (`pkexec true` with a scratch agent, or the nested session's). Record which close each step and adjust items 2–3 if a cause differs. Logs removed after.
2. **Close on a real click only** (small): `OverlayPanel` closes from `backgroundClicks` and `BackdropManager.clickedOutside` (the backdrop catches clicks while an overlay with `closeOnOutsideClick` is open, natively too), never from `grab.onCleared`; the setting's description and `docs/dev/overlay/pages-and-grid.md` say what counts as outside. A test row if `BackdropManager`'s gating moves into a helper.
3. **An open popout follows the overlay** (small): when the overlay opens on its screen, an open popout latched under the bar re-opens over it (`BarPopouts._under`, `EdgePopout._overlayLatch`); and the overlay doesn't take the keyboard as it opens while a popout on its screen holds a grab. Whether "re-open" means closing it or switching its window in place is decided in the item; an open popout still never moves along the bar.
4. **The `closeOverlay` callers** (small): per the answers below. Likely: the layouts preview and the onboarder step aside instead of closing (the overlay keeps its page and comes back); screen recording keeps closing; Favourites keeps closing after a launch.

### Open questions
- Should a click on a bar (or a bar popout) still close the overlay with `closeOnOutsideClick` on? B says no: it's how popouts stay usable.
- Launcher: open over the overlay and leave it open (B gives this for free), or close the overlay when the launcher opens?
- Launching an app from Favourites (or the launcher over the overlay): close the overlay, or keep it open?
- The onboarder and the layouts preview: step aside (overlay comes back after) or close as today?
