# Screenshots and screen recording

> **Files:** `services/apps/ScreenshotManager.qml`, `shell/Screenshot.qml`, `components/surfaces/screenshot/ScreenshotPickerWindow.qml`, `components/content/ScreenRecord/ScreenRecord.qml`, `components/bar/widgets/ScreenRecord/ScreenRecord.qml`
> **Config:** `Screenshots` (`folder`, `recordingFolder`; reader `config/Screenshots.qml`); the picker's choices persist in `~/.local/state/axiom/ui/screenshot.json`
> **Related:** [Keybinds](../hyprland/keybinds.md), [Chat](chat.md) (region attachments), [Utility modules](../overlay/utility-modules.md)

Screenshots and wf-recorder recordings, both in `ScreenshotManager`, with one picker surface for both. Slurp is not used; grim only takes the picker's frame under niri (below).

Name clash: `KeybindManager.startRecording(index)` is the key recorder on the Keybinds page. It has nothing to do with screen recording.

### Entry points (screenshots)
- The `screenshot` bind action, with an argument `region` / `window` / `screen`.
- IPC `screenshot`: `take <kind>` and `cancel`.
- Launcher `/screenshot`.
- The Screenshot card.
- The chat's region attachments use `pick(path, callback)`. It saves to `path` and calls back instead of copying (see [Chat](chat.md)).

### The picker
- While `picking`, `shell/Screenshot` shows `surfaces/screenshot/ScreenshotPickerWindow`:
  - one frozen frame per screen: a `ScreencopyView`, or grim's picture (below);
  - layer rule `axiom-screenshot` with `no_anim`;
  - the window under the cursor is highlighted from the start (`CompositorManager.withCursorPos`).
- Kinds:
  - **`region`:** drag a region, or click a window; clicking off any window takes the screen.
  - **`window`:** click a window.
  - **`screen`:** grabs at once, on one screen.
- **Cropping:** a `ShaderEffectSource` + `grabToImage`, at the buffer's resolution.

### The frame from grim (niri)
- **When:** `ScreenshotManager.grimFrames`, on wherever the backend leaves out `CompositorManager.supports.outputCapture` (niri; sway and Hyprland keep the `ScreencopyView`).
- **Why:** niri 26.04 has only wlr-screencopy, and Quickshell's capture through it binds a `wl_output` of its own that Qt takes for a screen. The shell then crashes the next time a surface leaves or enters an output, at once with a popout open (it unmaps as the picker opens). The upstream bug and its trace are in [issues](../issues.md) › *Quickshell's wlr screencopy crashes the shell on niri*.
- **How:**
  - `_grabFrames` runs grim before the picker opens: one picture per screen the picker shows (only the captured one for `screen`), `grim -t ppm -s <devicePixelRatio> -o <screen>`, into `Paths.runtimePath`. The picker opens once grim exits; `busy` covers the wait.
  - Each picker shows its screen's picture (`ScreenshotManager.frames`) as an `Image`; `frozen`, the crop and `frameArrived()` work as with the `ScreencopyView`, whose `captureSource` stays null.
  - The pictures are removed when the picker closes, or when it's cancelled while grim runs.
- **Without grim:** the screenshot fails with a notification (`Screenshots here need grim.`). grim is an optional dependency for niri (install.sh, `Packages`, the AUR optdepends, the onboarding's checks).
- **Remove it** when Quickshell's wlr screencopy no longer binds its own `wl_output`: then niri can declare `outputCapture`, or the key can go.

### After a capture
- **Saving:** to `folder`: `Screenshots.folder`, else `<Pictures>/Screenshots` (`xdg-user-dir PICTURES`). With `copyOnly` it is only a runtime file.
- The folders are global settings (General → Screenshots & recordings), not the cards': every entry point saves to the same place. Recordings go to `recordingFolder`: `Screenshots.recordingFolder`, else `folder`.
- **Copying:** to the clipboard through the daemon (`ClipboardManager.copyFile`, `clipboard.copy {path, mime}`).
- Then one of:
  - **A notification** with an "Edit in Satty/Swappy" button. This is a waiting `notify-send -A` (`CommandManager.run`), so each one's button stays live until its notification closes.
  - **Opened in satty/swappy straight away** with `annotate`: the picker's "Edit in …" switch, the E key, or holding Shift on release.
- **Watchdog:** a single 3 s watchdog in the service fails any capture that gets no frame, so nothing can wedge it.
  - A picker reports its frame with `frameArrived()`.
  - An immediate `screen` capture must report back too.

### Recording
Recording lives in the service, not in the card, because the overlay destroys the card when it closes.

**Pick-based (`toggleRecording()`):**
- Opens the same picker with kind `record`. That kind has no save or annotate controls.
- R, or the picker's Screenshot / Record switch (`setRecordMode`), flips an open picker between screenshot and record.
- The pick goes to `record(area, screenName)`:
  - a region is passed as global logical `-g`;
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
- wf-recorder runs in axiom (`CommandManager.run`) until `stopRecording()` sends SIGINT to the wf-recorder whose parent is the daemon (`pkill -P "$PPID"` in a `sh` axiom also runs), never another one; one left from before a reload is found the same way and marked stopped at once.
- On exit it notifies with the saved file (a click opens it) or with the failure.
- While it runs, `recordingElapsed` ticks for the `ScreenRecord` bar widget. That widget is hidden otherwise; a click on it stops the recording.
- The Privacy widget's screen indicator shows the recording. wf-recorder uses screencopy, so Pipewire never sees it.

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
