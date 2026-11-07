# Screenshots and screen recording

> **Files:** `qml/services/apps/ScreenshotManager.qml`, `qml/services/apps/ScreenshotPickState.qml`, `qml/components/methods/ScreenRegion.qml`, `backend/internal/screenshot/screenshot.go` (`screenshot.stitch`), `qml/shell/Screenshot.qml`, `qml/components/surfaces/screenshot/ScreenshotPickerWindow.qml`, `qml/components/content/ScreenRecord/ScreenRecord.qml`, `qml/components/bar/widgets/ScreenRecord/ScreenRecord.qml`, `qml/config/Screenshots.qml`
> **Config:** `Screenshots` (`folder`, `recordingFolder`, `notify`; reader `qml/config/Screenshots.qml`); the picker's choices persist in `~/.local/state/axiom/ui/screenshot.json`
> **Related:** [Keybinds](../hyprland/keybinds.md), [Chat](chat.md) (region attachments), [Utility modules](../overlay/utility-modules.md)

Screenshots and wf-recorder recordings, both in `ScreenshotManager`, with one picker surface for both. Slurp is not used; grim only takes the picker's frame under niri (below).

Name clash: `KeybindManager.editor.startRecording(index)` is the key recorder on the Keybinds page. It has nothing to do with screen recording.

### Entry points (screenshots)
- The `screenshot` bind action, with an argument `region` / `window` / `screen`.
- IPC `screenshot`: `take <kind>` and `cancel`.
- Launcher `/screenshot`.
- The Screenshot card.
- The chat's region attachments use `pick(path, callback)`. It saves to `path` and calls back instead of copying (see [Chat](chat.md)).
- The screen-share picker's Region uses `pickArea(callback)`: the same region drag, kept to one screen (below), handing back the screen and the rect (its logical pixels from the screen's top left; `finishArea`) instead of a picture, and a cancel as no screen ([Screen sharing](screen-sharing.md)).

### The picker
- While `picking`, `qml/shell/Screenshot` shows `surfaces/screenshot/ScreenshotPickerWindow`:
  - one frozen frame per screen: a `ScreencopyView`, or grim's picture (below);
  - layer rule `axiom-screenshot` with `no_anim`;
  - the window under the cursor is highlighted from the start (`CompositorManager.withCursorPos`).
- Kinds:
  - **`region`:** drag a region, or click a window; clicking off any window takes the screen.
  - **`window`:** click a window.
  - **`screen`:** grabs at once, on one screen.
- **Cropping:** a `ShaderEffectSource` + `grabToImage`, at the buffer's resolution.

### Across monitors
- **One selection for every screen:** the drag, the window under the pointer and the screen that has it live in `ScreenshotManager.picker` (a `ScreenshotPickState`), in global logical pixels. The picker a press lands on feeds it (`press`, `dragTo`, `hover`, `release`) with its mouse position plus its screen's `x`/`y`: the compositor keeps sending the pointer to the surface the press started on, even past its edge, so a drag goes on into the next monitor. Each picker draws its dimming and border from its own part of `picker.selection` (`ScreenRegion.local`); the size label shows on the screen with the pointer, in the picture's pixels (`pixelSize`: at the largest scale among the screens it covers).
- **Windows snap whole:** `picker.windows` is every screen's shown workspaces' windows (topmost first per screen), as global boxes clipped to the screens' bounding box, taken as the picker opens. `ScreenRegion.boxAt` takes the window under the pointer, the pointer's own screen's windows before one spilling over from another, so a window across two monitors highlights and captures whole.
- **Capture:** a selection on one screen is cropped by that screen's picker as before. One over several (`captureGlobal` → `ScreenshotManager.captureAcross`) sets `pieceRequest`: each covered picker crops its part from its own frozen frame at its own scale and hands it to `pieceDone`, which saves it as a PNG in `Paths.runtimePath` (`piece-<screen>-<stamp>.png`). Once all are in, the pickers close and the daemon's `screenshot.stitch` (`{ pieces: [{ path, x, y, width, height }], area, out }`, global logical rects; `backend/internal/screenshot`) lays them out at the largest scale among them, scaling lower-scale pieces up (Catmull-Rom), and writes `out`: the same path a single-screen capture saves to (`_outPath`: `pick()`'s path, the folder, or the scratch file with `copyOnly`), so it goes on the same way (`_saved`: clipboard, notification or annotator, or `pick()`'s callback). The pieces are removed after. `busy` covers the stitch (`_stitching`); the watchdog covers the pieces.
- **Gaps are transparent:** where the selection covers no monitor (monitors of different sizes or offsets), the PNG is transparent, not black: nothing was there to capture.
- **One screen only** (`picker.oneScreen`): a region to share (`pickArea`: xdph's `region:<output>@x,y,w,h` names one output) and a recording (wf-recorder records one output; below). The selection is then clamped to the screen with the pointer (where the drag started).

### The frame from grim (niri)
- **When:** `ScreenshotManager.grimFrames`, on wherever the backend leaves out `CompositorManager.supports.outputCapture` (niri; sway and Hyprland keep the `ScreencopyView`).
- **Why:** niri 26.04 has only wlr-screencopy, and Quickshell's capture through it binds a `wl_output` of its own that Qt takes for a screen. The shell then crashes the next time a surface leaves or enters an output, at once with a popout open (it unmaps as the picker opens). The upstream bug and its trace are in [issues](../issues.md) › *Quickshell's wlr screencopy crashes the shell on niri*.
- **How:**
  - `_grabFrames` runs grim before the picker opens: one picture per screen the picker shows (only the captured one for `screen`), `grim -t ppm -s <devicePixelRatio> -o <screen>`, into `Paths.runtimePath`. The picker opens once grim exits; `busy` covers the wait.
  - Each picker shows its screen's picture (`ScreenshotManager.frames`) as an `Image`; `frozen`, the crop and `frameArrived()` work as with the `ScreencopyView`, whose `captureSource` stays null. A picture it can't read (`Image.Error`) fails the shot at once. `_onFrame` runs on `onFrozenChanged`, never on the Image's or view's own change signal, which fire before `frozen` updates (so the frame was missed and the watchdog failed a picker in use).
  - The pictures are removed when the picker closes, or when it's cancelled while grim runs.
- **Without grim:** the screenshot fails with a notification (`Screenshots here need grim.`). grim is an optional dependency for niri (install.sh, `Packages`, the AUR optdepends, the onboarding's checks).
- **Remove it** when Quickshell's wlr screencopy no longer binds its own `wl_output`: then niri can declare `outputCapture`, or the key can go.

### After a capture
- **Saving:** to `folder`: `Screenshots.folder`, else `<Pictures>/Screenshots` (`xdg-user-dir PICTURES`). With `copyOnly` it is only a runtime file.
- The folders are global settings (General → Screenshots & recordings), not the cards': every entry point saves to the same place. Recordings go to `recordingFolder`: `Screenshots.recordingFolder`, else `folder`.
- **Copying:** to the clipboard through the daemon (`ClipboardManager.copyFile`, `clipboard.copy {path, mime}`).
- Then one of:
  - **Said** (`_sayTaken`, through `NotificationManager.announce("screenshot", Screenshots.notify, …)`): on an OSD listing `screenshot`, its card with the picture (`lastShot`; a click opens it, `open`); else, with `Screenshots.notify` (the default), a notification (a click opens it) with an "Edit in Satty/Swappy" button. Sent through `sendNotification` with an `edit` action, so each one's button stays live until its notification closes. Off, with no such OSD, nothing ([OSD](osd.md) › Where events go).
  - **Opened in satty/swappy straight away** with `annotate`: the picker's "Edit in …" switch, the E key, or holding Shift on release.
- **Watchdog:** a single 3 s watchdog in the service fails any capture that gets no frame, so nothing can wedge it.
  - A picker reports its frame with `frameArrived()`.
  - An immediate `screen` capture must report back too.

### Recording
Recording lives in the service, not in the card, because the overlay destroys the card when it closes. IPC `screenRecord` (`toggle` / `enable` / `disable` / `status`; binds, hot corners, `axiom record`) says on the OSD that wf-recorder is missing instead of doing nothing (`_canRecord`).

**Pick-based (`toggleRecording()`):**
- Opens the same picker with kind `record`. That kind has no save or annotate controls.
- R, or the picker's Screenshot / Record switch (`setRecordMode`), flips an open picker between screenshot and record. Each kind still saves to its own folder, and the sound is what the start asked for (`_start`'s `audio`: none but from `startRecording`), so no picker keeps an earlier one's.
- The pick goes to `record(area, screenName)`:
  - a region is passed as global logical `-g`, always on one screen: wf-recorder picks the one output that wholly contains the region (`detect_output_from_region`) and captures only on it, so a region over two fails with "Failed to detect output based on geometry (is your geometry overlapping outputs?)". The picker keeps a recording's selection to the screen where the drag started (`picker.oneScreen`);
  - a whole screen as `-o <screen>`.

**Direct (`startRecording({ mode, audio })`):**
- `mode` is `"pick"` or `"screen"`.
- `screen` records the focused monitor at once, after the overlay or launcher has gone.
- `audio` is `"none"`, `"system"` or `"mic"`:
  - **`system`** is `--audio=$(pactl get-default-sink).monitor`. It runs through `sh -c 'exec wf-recorder …'` so SIGINT still reaches wf-recorder.
  - **`mic`** is the default source.
  - pactl is optional (`hasSystemAudio`, `DependencyManager.found.pactl`, checked by the ScreenRecord card). Without it the card dims System, and a `system` request records no sound.
- `recordAudio` (the ScreenRecord card's choice) is saved with `copyOnly` in `~/.local/state/axiom/ui/screenshot.json`.

**Running and stopping:**
- wf-recorder runs in axiom (`CommandManager.run`) until `stopRecording()` sends SIGINT to the wf-recorder whose parent is the daemon (`pkill -P "$PPID"` in a `sh` axiom also runs), never another one; one left from before a reload (found the same way) or whose answer an axiom re-exec lost is marked stopped at once. One killed by a signal is treated as exited.
- On exit it notifies with the saved file (a click opens it) or with the failure. Screenshot and recording notifications share the `axiom-screenshot` handler, which opens the newest path of the clicked one's key (`_paths`): each key holds one notification.
- While it runs, `recordingElapsed` ticks for the `ScreenRecord` bar widget. That widget is hidden otherwise; a click on it stops the recording.
- The Privacy widget's screen indicator shows the recording (the OSD has its own `recording` status). wf-recorder uses screencopy, so Pipewire never sees it, and `PrivacyManager.screenCaptures` doesn't list it.

**Recording entry points:**
- IPC `screenRecord`: `toggle` / `enable` / `disable` / `status`.
- The `screenRecord` bind action (with a call).
- Launcher `/record`.
- The Screenshot card's Record tile.
- The `ScreenRecord` overlay module: region or screen, the sound, and recent recordings.

### Recent recordings
- `refreshRecordings()` lists the newest 12 `Recording_*.mp4` in `recordingFolder` into `recordings` (`[{ path, name, time, size }]`, newest first).
  - Once a card has asked, they're listed again whenever a recording is saved or `recordingFolder` changes.
  - One `find` at a time: asked again meanwhile, it lists once more after; a list of a folder since changed is dropped.
- `deleteRecording` moves a recording to the trash, then lists the folder again.
