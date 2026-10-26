pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.services.ui

// Screenshots (the `screenshot` keybind action, IPC `screenshot take <kind>`,
// launcher `/screenshot`, the Screenshot card), taken natively: while
// `picking`, shell/Screenshot shows a frozen frame (ScreencopyView, or
// grim's picture where Quickshell can't capture safely: `grimFrames`) on
// each screen, where a region is dragged or a window clicked (`region`), or a
// window clicked (`window`), and crops it at the screen's own resolution.
// `screen` captures the focused monitor at once. The picture is saved in
// `folder` (the Screenshots section), or only to a scratch file
// with `copyOnly`, copied to the clipboard (ClipboardManager.copyFile:
// Quickshell's clipboard is text only) and either notified (click opens
// it) or opened in an annotator (satty or swappy; its notification also has an "Edit in …"
// button). Recording (IPC `screenRecord`, the
// `screenRecord` bind, launcher `/record`, or R / the Record switch in an
// open picker) picks its area in the same picker (kind `record`), or takes
// the focused screen at once (`mode: "screen"`, the ScreenRecord card), and
// runs wf-recorder on it until stopped, with the system's sound (through
// pactl: `hasSystemAudio`) or the microphone if asked (`audio`), into
// `recordingFolder`, whose newest recordings `recordings` lists for the
// ScreenRecord cards.
QtObject {
  id: root

  readonly property string _desktopEntry: "axiom-screenshot"
  property string _lastPath: ""

  // The picker is open (or an immediate capture is running)
  property bool picking: false
  // Picking, or waiting for the launcher to close first (or for grim)
  readonly property bool busy: root.picking || root._delay.running || root._grim.running
  // { kind, screen: the screen an immediate `screen` capture takes }
  property var request: null
  // Keep nothing on disk, only copy (saved in Paths.statePath screenshot.json)
  property bool copyOnly: false
  // The sound the ScreenRecord card records with: "none" | "system" |
  // "mic" (saved with copyOnly)
  property string recordAudio: "none"
  // Open the next capture in the annotator (set in the picker)
  property bool annotate: false
  // "satty" | "swappy" | "": what annotating opens
  readonly property string annotator: DependencyManager.found["satty"] ? "satty" : DependencyManager.found["swappy"] ? "swappy" : ""
  // Its name as shown ("Satty")
  readonly property string annotatorName: root.annotator === "" ? "" : root.annotator[0].toUpperCase() + root.annotator.slice(1)
  readonly property bool hasRecorder: DependencyManager.found["wf-recorder"] === true
  // Whether the system's sound can be recorded: pactl finds the default
  // output's monitor. Undefined until checked (by a ScreenRecord card)
  readonly property var hasSystemAudio: DependencyManager.found.pactl
  property bool recording: false
  // When the running recording started (ms), 0 when unknown (started
  // before a reload)
  property real recordingSince: 0
  // Seconds recorded so far, ticking only while recording
  property int recordingElapsed: 0
  property string _recordPath: ""
  // "none" | "system" (the default output's monitor) | "mic" (the default
  // input), for the recording being started
  property string _recordAudio: "none"
  // The newest recordings in recordingFolder ([{ path, name, time, size }],
  // newest first), once refreshRecordings has listed it
  readonly property var recordings: root._recordings
  property var _recordings: []
  // Where screenshots are saved: the Screenshots setting, else
  // <Pictures>/Screenshots
  readonly property string folder: Screenshots.folder || root._picturesDir + "/Screenshots"
  // Where recordings are saved and listed from: the setting, else with the
  // screenshots
  readonly property string recordingFolder: Screenshots.recordingFolder || root.folder

  property string _picturesDir: Quickshell.env("HOME") + "/Pictures"
  property string _directory: ""
  readonly property string _scratchDir: Paths.runtimePath.replace(/\/$/, "")

  readonly property var _state: StateManager.createStateHandler("screenshot")

  // The picker's frozen frames are grim's pictures, taken just before it
  // opens, not Quickshell's own capture (ScreencopyView): where the
  // compositor has no capture Quickshell does safely (CompositorManager.
  // supports.outputCapture). niri has only wlr-screencopy, and Quickshell's
  // capture through it crashes the shell once a surface then unmaps
  // (docs/dev/issues.md).
  readonly property bool grimFrames: CompositorManager.supports.outputCapture !== true
  // { screen name: picture path } while picking with grimFrames
  readonly property var frames: root._frames
  property var _frames: ({})

  // The kinds take() offers: "window" only where the compositor knows
  // where windows are (CompositorManager.supports.windowGeometry)
  readonly property var kinds: ["region"].concat(CompositorManager.supports.windowGeometry === true ? ["window"] : [], ["screen"])

  // kind: "region" | "window" | "screen" ("window" is "region" where it
  // isn't in `kinds`)
  function take(kind) {
    if (root.busy)
      return;
    root._target = null;
    root._start(kind);
  }

  // A region for another feature (the chat): saved to `path` as a PNG,
  // with no clipboard or notification, then callback(ok). Returns false
  // (and never calls back) when a capture is already running.
  function pick(path, callback) {
    if (root.busy)
      return false;
    root._target = {
      "path": path,
      "callback": callback
    };
    Quickshell.execDetached(["mkdir", "-p", path.replace(/\/[^/]*$/, "")]);
    root._start("region");
    return true;
  }

  // { path, callback } while pick() runs
  property var _target: null
  readonly property bool forCaller: root._target !== null

  function _start(kind) {
    if (!["region", "window", "screen", "record", "recordScreen"].includes(kind)) {
      console.warn(`[ScreenshotManager] Unknown screenshot kind "${kind}" (region, window, screen or record)`);
      return;
    }
    if (kind === "window" && !root.kinds.includes("window"))
      kind = "region";
    root._directory = kind.startsWith("record") ? root.recordingFolder : root.folder;
    Quickshell.execDetached(["mkdir", "-p", root._directory, root._scratchDir]);
    root.annotate = false;
    // The screen is taken as it is (an open overlay included), but the
    // launcher closes itself after running a command: let it go first
    root._delay.kind = kind;
    // A whole-screen recording waits for the overlay too (the card that
    // started it closes it), so it isn't in the first frames
    root._delay.interval = SurfaceManager.surfaceOpen("launcher") || (kind === "recordScreen" && SurfaceManager.surfaceOpen("overlay")) ? Appearance.animSlow + 150 : 1;
    root._delay.restart();
  }

  function cancel() {
    root.picking = false;
    root.request = null;
    root._delay.stop();
    root._watchdog.stop();
    root._callBack(false);
  }

  function _callBack(ok) {
    const target = root._target;
    root._target = null;
    target?.callback(ok);
  }

  function setCopyOnly(value) {
    root.copyOnly = value;
    root._saveState();
  }

  function setRecordAudio(value) {
    root.recordAudio = ["system", "mic"].includes(value) ? value : "none";
    root._saveState();
  }

  function _saveState() {
    root._state.save({
      "copyOnly": root.copyOnly,
      "recordAudio": root.recordAudio
    });
  }

  // Called by the picker with the cropped capture (a grabToImage result),
  // or null when grabbing failed
  function finish(result) {
    root.picking = false;
    root.request = null;
    root._watchdog.stop();
    if (root._target) {
      root._callBack(!!result && result.saveToFile(root._target.path));
      return;
    }
    const name = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".png";
    const path = (root.copyOnly ? root._scratchDir + "/screenshot-" : root._directory + "/") + name;
    if (!result || !result.saveToFile(path)) {
      root.fail(I18n.tr("Couldn't save the picture in {0}.", root.copyOnly ? root._scratchDir : root._directory));
      return;
    }
    root._lastPath = path;
    ClipboardManager.copyFile(path, "image/png");
    if (root.annotate && root.annotator !== "") {
      root.annotate = false;
      root.edit(path);
      return;
    }
    root.annotate = false;
    const summary = I18n.tr("Screenshot saved");
    const body = root.copyOnly ? I18n.tr("Copied to the clipboard.") : I18n.tr("Copied to the clipboard. Click to open it.");
    if (root.annotator === "") {
      NotificationManager.sendNotification("axiom", summary, body, {
        "desktopEntry": root._desktopEntry,
        "icon": path
      });
      return;
    }
    // With an "Edit in …" button: notify-send waits for it and prints the
    // action. Only the latest notification's button stays live.
    root._nextNotice = {
      "path": path,
      "command": ["notify-send", "-a", "axiom", "-i", path, "-h", "string:desktop-entry:" + root._desktopEntry, "-A", "edit=" + I18n.tr("Edit in {0}", root.annotatorName), "--", summary, body]
    };
    // The previous one is stopped first; its exit starts this one
    if (root._savedNotice.running)
      root._savedNotice.running = false;
    else
      root._startNotice();
  }

  function _startNotice() {
    const next = root._nextNotice;
    if (!next)
      return;
    root._nextNotice = null;
    root._noticePath = next.path;
    root._savedNotice.command = next.command;
    root._savedNotice.running = true;
  }

  // Opens a picture in the annotator, which saves over it
  function edit(path) {
    if (root.annotator === "")
      return;
    Quickshell.execDetached(root.annotator === "satty" ? ["satty", "--filename", path, "--output-filename", path] : ["swappy", "-f", path, "-o", path]);
  }

  // Switches an open picker between taking a screenshot and recording
  function setRecordMode(on) {
    if (!root.picking || root.forCaller || !root.request || root.request.kind === "screen" || (on && !root.hasRecorder))
      return;
    root.annotate = false;
    root.request = Object.assign({}, root.request, {
      "kind": on ? "record" : "region"
    });
  }

  function fail(reason) {
    root.picking = false;
    root.request = null;
    root.annotate = false;
    root._watchdog.stop();
    console.warn("[ScreenshotManager]", reason);
    if (root._target) {
      root._callBack(false);
      return;
    }
    NotificationManager.sendNotification("axiom", I18n.tr("Screenshot failed"), reason);
  }

  // Recording: an area picked in the picker (kind `record`), recorded by
  // wf-recorder until stopRecording(). Kept here, since the card that
  // starts it is gone once the overlay closes.
  // options: { mode: "pick" (the picker, the default) | "screen" (the
  // focused screen, at once), audio: "none" | "system" | "mic" }
  function startRecording(options) {
    if (root.recording || root.busy || !root.hasRecorder)
      return;
    root._target = null;
    root._recordAudio = root._audioFor(options?.audio);
    root._start(options?.mode === "screen" ? "recordScreen" : "record");
  }

  // A sound choice that can be recorded: anything else, or the system's
  // without pactl, is none
  function _audioFor(audio) {
    if (audio === "system")
      return root.hasSystemAudio === true ? "system" : "none";
    return audio === "mic" ? "mic" : "none";
  }

  // Ours gets SIGINT (wf-recorder finishes the file on it). One started
  // before a reload isn't ours to signal or see exit: only then does it
  // go by name, which would stop any wf-recorder.
  function stopRecording() {
    if (root._recorder.running) {
      root._recorder.signal(2);
      return;
    }
    Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder"]);
    root.recording = false;
  }

  function toggleRecording() {
    if (root.recording)
      root.stopRecording();
    else if (root.busy && root.request?.kind === "record")
      root.cancel();
    else
      root.startRecording();
  }

  // Called by the picker with the area to record: global logical pixels,
  // or a whole screen by name
  function record(area, screenName) {
    root.picking = false;
    root.request = null;
    root._watchdog.stop();
    const path = root._directory + "/Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
    const target = screenName ? ["-o", screenName] : ["-g", `${Math.round(area.x)},${Math.round(area.y)} ${Math.round(area.width)}x${Math.round(area.height)}`];
    root._recordPath = path;
    const args = target.concat(["-f", path]);
    // The system's sound is the default output's monitor, looked up as it
    // starts (exec, so stopping signals wf-recorder itself)
    if (root._recordAudio === "system")
      root._recorder.command = ["sh", "-c", 'exec wf-recorder --audio="$(pactl get-default-sink).monitor" "$@"', "sh"].concat(args);
    else
      root._recorder.command = ["wf-recorder"].concat(root._recordAudio === "mic" ? ["--audio"] : [], args);
    root._recordAudio = "none";
    root._recorder.running = true;
    root.recording = true;
    root.recordingSince = Date.now();
    root.recordingElapsed = 0;
  }

  property Timer _delay: Timer {
    property string kind: ""
    onTriggered: {
      if (kind === "recordScreen") {
        root.record(null, CompositorManager.focusedOutput);
        return;
      }
      root.request = {
        "kind": kind,
        "screen": CompositorManager.focusedOutput
      };
      if (root.grimFrames) {
        root._grabFrames();
        return;
      }
      root.picking = true;
      root._watchdog.restart();
    }
  }

  // grim's picture of each screen the picker shows (only the captured one
  // for an immediate `screen` shot), at the screen's own scale, then the
  // picker. PPM: quick to write and to read back
  function _grabFrames() {
    const stamp = Date.now();
    const frames = {};
    const args = [];
    General.outputs.filter(s => root.request.kind !== "screen" || s.name === root.request.screen).forEach(s => {
      const path = `${root._scratchDir}/frame-${s.name}-${stamp}.ppm`;
      frames[s.name] = path;
      args.push(s.name, String(s.devicePixelRatio), path);
    });
    root._pendingFrames = frames;
    root._grim.command = ["sh", "-c", 'command -v grim >/dev/null || exit 127; while [ $# -gt 0 ]; do grim -t ppm -s "$2" -o "$1" "$3" || exit 1; shift 3; done', "sh"].concat(args);
    root._grim.running = true;
  }
  property var _pendingFrames: ({})

  property Process _grim: Process {
    stderr: StdioCollector {
      id: grimErrors
    }
    onExited: code => {
      const frames = root._pendingFrames;
      root._pendingFrames = {};
      // Cancelled meanwhile
      if (!root.request) {
        root._dropFrames(frames);
        return;
      }
      if (code !== 0) {
        root._dropFrames(frames);
        root.fail(code === 127 ? I18n.tr("Screenshots here need grim.") : I18n.tr("grim couldn't take a picture of the screen: {0}", grimErrors.text.trim()));
        return;
      }
      root._frames = frames;
      root.picking = true;
      root._watchdog.restart();
    }
  }

  function _dropFrames(frames) {
    const paths = Object.keys(frames).map(name => frames[name]);
    if (paths.length > 0)
      Quickshell.execDetached(["rm", "-f"].concat(paths));
  }

  // Gone with the picker
  onPickingChanged: {
    if (root.picking || Object.keys(root._frames).length === 0)
      return;
    root._dropFrames(root._frames);
    root._frames = {};
  }

  // Called by a picker when its frame is in. A picker keeps waiting on the
  // user from then on; an immediate capture still has to report back.
  function frameArrived() {
    if (root.request?.kind !== "screen")
      root._watchdog.stop();
  }

  // A picker that never gets its frame (no screencopy support), or an
  // immediate capture that never reports back, gives up rather than
  // blocking every later one
  property Timer _watchdog: Timer {
    interval: 3000
    onTriggered: {
      if (root.picking)
        root.fail(I18n.tr("The compositor sent no picture of the screen."));
    }
  }

  property Timer _recordTick: Timer {
    running: root.recording && root.recordingSince > 0
    interval: 1000
    repeat: true
    onTriggered: root.recordingElapsed = Math.floor((Date.now() - root.recordingSince) / 1000)
  }

  property Process _recorder: Process {
    stderr: StdioCollector {
      id: recorderErrors
    }
    onExited: {
      root.recording = false;
      root.recordingSince = 0;
      root.recordingElapsed = 0;
      root._recordCheck.command = ["test", "-s", root._recordPath];
      root._recordCheck.running = true;
    }
  }

  // Whether the recording left a file: saved, else it failed
  property Process _recordCheck: Process {
    onExited: code => {
      const path = root._recordPath;
      if (code !== 0) {
        const reason = recorderErrors.text.trim().split("\n").pop() || I18n.tr("wf-recorder stopped without writing a file.");
        console.warn("[ScreenshotManager] Recording failed:", reason);
        NotificationManager.sendNotification("axiom", I18n.tr("Recording failed"), reason);
        return;
      }
      root._lastPath = path;
      // If a card lists them
      if (root._listed)
        root.refreshRecordings();
      NotificationManager.sendNotification("axiom", I18n.tr("Recording saved"), I18n.tr("Saved in {0}. Click to open it.", path.replace(/\/[^/]*$/, "")), {
        "desktopEntry": root._desktopEntry
      });
    }
  }

  // Lists the newest recordings in recordingFolder into `recordings`
  function refreshRecordings() {
    root._listed = true;
    if (root._lister.running) {
      root._relist = true;
      return;
    }
    root._listingFolder = root.recordingFolder;
    root._lister.command = ["sh", "-c", 'find "$1" -maxdepth 1 -type f -name "Recording_*.mp4" -printf "%T@\t%s\t%p\n" 2>/dev/null | sort -rn | head -n 12', "sh", root._listingFolder];
    root._lister.running = true;
  }
  onRecordingFolderChanged: {
    if (!root._listed)
      return;
    root._recordings = [];
    root.refreshRecordings();
  }

  // Moves a recording to the trash, then lists the folder again
  function deleteRecording(path) {
    if (!root._recordings.some(r => r.path === path))
      return;
    root._recordings = root._recordings.filter(r => r.path !== path);
    CommandManager.run(["gio", "trash", "--", path], () => root.refreshRecordings());
  }

  // A card has listed the recordings: they're listed again as one is saved
  // or the folder changes
  property bool _listed: false
  // Asked again while listing
  property bool _relist: false
  // The folder the running listing is of
  property string _listingFolder: ""

  property Process _lister: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        // Of a folder since changed: the list that follows replaces it
        if (root._listingFolder !== root.recordingFolder)
          return;
        root._recordings = text.split("\n").filter(line => line !== "").map(line => {
          const [time, size, path] = line.split("\t");
          return {
            "path": path,
            "name": path.replace(/^.*\//, ""),
            "time": Math.round(Number(time) * 1000),
            "size": Number(size)
          };
        });
      }
    }
    onExited: {
      if (!root._relist)
        return;
      root._relist = false;
      Qt.callLater(root.refreshRecordings);
    }
  }

  // The picture the live "Edit in …" button opens
  property string _noticePath: ""
  // { path, command } waiting for the previous notice to stop
  property var _nextNotice: null

  property Process _savedNotice: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() === "edit")
          root.edit(root._noticePath);
      }
    }
    onExited: root._startNotice()
  }

  property Process _probe: Process {
    command: ["sh", "-c", 'xdg-user-dir PICTURES 2>/dev/null; pgrep -x wf-recorder >/dev/null && echo rec; true']
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n").map(line => line.trim()).filter(line => line !== "");
        if (lines[0]?.startsWith("/"))
          root._picturesDir = lines[0];
        // A recording from before a reload: only stopping it is offered
        root.recording = root.recording || lines.includes("rec");
      }
    }
  }

  Component.onCompleted: {
    const saved = root._state.load({});
    root.copyOnly = saved.copyOnly === true;
    root.recordAudio = ["system", "mic"].includes(saved.recordAudio) ? saved.recordAudio : "none";
    DependencyManager.check(["satty", "swappy", "wf-recorder"].concat(root.grimFrames ? ["grim"] : []));
    root._probe.running = true;
    NotificationManager.registerHandler(_desktopEntry, () => {
      if (root._lastPath !== "")
        Quickshell.execDetached(["xdg-open", root._lastPath]);
    });
  }

  property IpcTarget _ipc: IpcTarget {
    target: "screenshot"

    function take(kind: string): void {
      root.take(kind);
    }

    function cancel(): void {
      root.cancel();
    }
  }

  property IpcTarget _recordIpc: IpcTarget {
    target: "screenRecord"

    function toggle(): void {
      root.toggleRecording();
    }

    function enable(): void {
      if (!root.recording)
        root.startRecording();
    }

    function disable(): void {
      root.stopRecording();
    }

    function status(): bool {
      return root.recording;
    }
  }
}
