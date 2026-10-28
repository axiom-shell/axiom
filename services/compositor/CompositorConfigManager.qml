pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.session
import qs.services.system
import qs.services.ui

/*
 * The compositor set up for axiom (the Compositor section's mode,
 * CompositorConfig.mode): the axiom daemon does it (backend/internal/
 * compositor/manager, docs/dev/compositor/config-modes.md), writing the
 * compositor's config, taking it over and giving it back, moving the
 * user's binds in and applying the runtime layer, made of the config and
 * what only the shell knows, which this sends it (compositor.inputs: the
 * capabilities, paths, the look as the theme resolves it, the cursor, the
 * monitors connected, unsaved edits), and shows what it pushes back
 * (compositor.state): the status, the problem, the takeover, the merge.
 * Notifications are sent from here, translated.
 */
Singleton {
  id: root

  // Only with configModes, and never in the greeter, whose compositor is
  // its own (its binds would reach the login screen, its files the
  // session's config)
  readonly property bool enabled: !Paths.greeter && CompositorManager.supports.configModes === true
  // Only once the compositor's capabilities are final (the parts applied
  // depend on them) and the cursor theme's XCursor name is known
  readonly property bool live: enabled && CompositorManager.ready && CursorThemeManager.ready && BackendManager.ready

  // While config.json doesn't load, the shell runs on the defaults (their
  // detached) but the daemon on the file's own mode (Store.Takeovers): its
  // pushed mode, unless it holds ("", the file wasn't JSON at the start).
  // The settings draft then holds the defaults' mode, which isn't a pick
  readonly property bool modeFromDaemon: ConfigManager.savesBlocked && (_state.mode ?? "") !== ""
  readonly property string mode: modeFromDaemon ? _state.mode : CompositorConfig.mode

  // --- What the daemon pushes (compositor.state) ---

  property var _state: ({})
  // Why the chosen mode isn't in effect, or ""
  readonly property string problem: _state.problem ?? ""
  // "runtime" (detached), "loaded" (the file is in effect), "fallback"
  // (it isn't: see `problem`) or "pending" (still checking, or holding while
  // config.json's mode isn't known); the daemon's while config.json doesn't
  // load
  readonly property string status: mode === "detached" && !ConfigManager.savesBlocked ? "runtime" : (_state.status ?? "pending")
  // Configured keys the runtime layer skipped because the compositor's
  // config already binds them
  readonly property var skippedKeys: _state.skippedKeys ?? []
  readonly property bool takeoverPending: _state.takeoverPending === true
  // Why the managed config couldn't be given back on leaving managed mode
  // (the daemon tries again), or ""
  readonly property string releaseProblem: _state.releaseProblem ?? ""
  // What switching to managed would do: "ours" | "adopt" | "stock" |
  // "released" | "new" | "blocked" (by managedBlockedBy "link" or "git")
  readonly property string managedCheck: _state.managedCheck ?? ""
  readonly property string managedBlockedBy: _state.managedBlockedBy ?? ""
  readonly property string managedBlockedRepo: _state.managedBlockedRepo ?? ""
  // Managed mode: the user's files that set monitors themselves
  readonly property var monitorConflicts: _state.monitorConflicts ?? []
  readonly property bool merging: _state.merging === true
  // The last merge, or null
  readonly property var lastMerge: _state.lastMerge ?? null
  // How many binds a Merge of all the user's files would move; -1 until
  // looked
  readonly property int mergeable: _state.mergeable ?? -1
  // niri's: the config it runs now (the detached wrapper while it's
  // loaded), and whether the user's binds have been read
  readonly property string runningConfig: _state.runningConfig ?? ""
  readonly property bool userBindsRead: _state.userBindsRead === true
  // The binds a merge moved in for good (KeybindEditor adds them to a
  // draft with unsaved edits)
  signal bindsMerged(var binds)

  // --- The files and lines (for the settings page, the onboarding and
  // IntegrationHookupManager) ---

  readonly property var _files: _state.files ?? ({})
  readonly property string configDir: _files.configDir ?? ""
  readonly property string includePath: _files.includePath ?? ""
  readonly property string managedPath: _files.managedPath ?? ""
  readonly property string userDir: _files.userDir ?? ""
  readonly property string userFiles: _files.userFiles ?? ""
  readonly property string includeLines: _files.includeLines ?? ""
  readonly property string autostartLines: _files.autostartLines ?? ""
  // Hookup targets (hookup.status / hookup.apply), or null. Their texts, as
  // IntegrationHookupManager translates them:
  // I18n.tr("Load axiom's module")
  // I18n.tr("Start axiom")
  // I18n.tr("Adds the lines at the top, so your own settings after them win over axiom's.")
  // I18n.tr("Adds the line at the end: Hyprland starts axiom with every session.")
  // I18n.tr("Adds the line at the end: sway starts axiom with every session.")
  // I18n.tr("Adds the line at the end, so axiom's look wins; binds on keys your config binds stay yours.")
  // I18n.tr("Adds the line at the end: niri starts axiom with every session.")
  readonly property var includeTarget: _files.includeTarget ?? null
  readonly property var autostartTarget: _files.autostartTarget ?? null

  // Whether a configured bind (one of KeybindsConfig.activeBinds) has
  // everything it needs to be bound, as the daemon says
  function isComplete(bind) {
    return root._complete[JSON.stringify(bind)] === true;
  }

  property var _complete: ({})

  // --- What only the shell knows of the layer (compositor.inputs) ---
  // The daemon reads the rest (binds, profiles, strips, the look's and
  // input's settings, the session, the options) from the config, with the
  // unsaved edits of those sections the shell sends

  // The saved monitor profile for what's connected (MonitorLayout.
  // matchProfile, as MonitorManager applies it), for a compositor whose
  // files hold the outputs (sway's and niri's reset them on a reload); null
  // until MonitorManager has read them (a file keeps what it says)
  readonly property var _outputRules: {
    if (!root.enabled || CompositorManager.kind === "hyprland" || !MonitorManager.outputsRead)
      return null;
    const outputs = MonitorManager.outputs;
    const profiles = MonitorsConfig.profiles;
    const index = MonitorLayout.matchProfile(profiles, outputs.filter(output => !output.disabled));
    return index < 0 ? [] : profiles[index].outputs.filter(rule => MonitorLayout.find(rule.output, outputs) !== null);
  }

  // The window look's values the theme and the Appearance settings
  // resolve, colors as their text ("#rrggbb", "#aarrggbb")
  readonly property var _look: ({
      "active": String(WindowLookConfig.activeBorder),
      "inactive": String(WindowLookConfig.inactiveBorder),
      "borderWidth": WindowLookConfig.borderWidth,
      "radius": WindowLookConfig.radius,
      "shadow": WindowLookConfig.shadowOn ? {
        "size": WindowLookConfig.shadowSize,
        "color": WindowLookConfig.shadowThemed ? String(WindowLookConfig.shadowColor) : "",
        "alpha": WindowLookConfig.shadowAlpha,
        "soft": WindowLookConfig.shadowSoft,
        "strength": WindowLookConfig.shadowStrength
      } : null
    })

  // The theme's colors by name, as their text (the daemon resolves those
  // the managed options name)
  readonly property var _palette: {
    const map = Theme.stringToColorMap;
    const out = {};
    for (const name in map)
      out[name] = String(map[name]);
    return out;
  }

  // The sections the layer is made of: their unsaved edits (ConfigManager.
  // previews) show in the compositor too
  readonly property var _layerSections: ["Keybinds", "Monitors", "Workspaces", "WindowLook", "Input", "Session", "ThemeIntegrations", "Compositor", "WindowBehaviour", "Idle", "Polkit"]

  function _facts() {
    const previews = ConfigManager.previews;
    const layer = Object.keys(previews).filter(path => root._layerSections.includes(path.split(".")[0]));
    return {
      "kind": CompositorManager.kind,
      "supports": CompositorManager.supports,
      "fx": CompositorManager.backend.fx === true,
      "ctx": {
        "axiomPath": Paths.axiomPath.replace(/\/$/, ""),
        "axiomBin": Paths.axiomBin,
        "shellCommand": Paths.shellCommand,
        "restartCommand": Paths.restartCommand,
        "terminal": Apps.terminalCommand,
        "fileManager": Apps.fileManagerCommand,
        "browser": Apps.browserCommand
      },
      "startPattern": Paths.startPattern,
      "primaryMonitor": General.primaryMonitor,
      "outputRules": root._outputRules,
      "look": root._look,
      // Whether axiom's surfaces blur: as saved (for a file), and now
      // (BlurManager.active, paused over a fullscreen window)
      "blur": {
        "saved": Appearance.blur,
        "now": BlurManager.active,
        "throughWindows": Appearance.blurThroughWindows,
        "backdrops": Appearance.blurBackdrops,
        "threshold": Appearance.blurThreshold
      },
      "xcursor": CursorThemeManager.xcursorTheme,
      "palette": root._palette,
      // The shell's motion (Look & Feel → Motion), for the managed
      // animations
      "motion": {
        "fast": Appearance.animFast,
        "normal": Appearance.animNormal,
        "slow": Appearance.animSlow,
        "enabled": Appearance.animations
      },
      "previews": ConfigOps.previewOps(layer.reduce((out, path) => Object.assign(out, {
          [path]: previews[path]
        }), {}))
    };
  }

  // The facts as they are now: a change sends them (soon)
  readonly property string _factsText: live ? JSON.stringify(_facts()) : ""
  // What was last sent, to send only a change
  property string _sent: ""

  function _send() {
    if (!root.live)
      return;
    if (root._factsText === root._sent)
      return;
    root._sent = root._factsText;
    // rpc: unchecked (the facts, built by _facts() and sent as they change; the daemon decodes them strictly)
    BackendManager.call("compositor.inputs", JSON.parse(root._sent), err => {
      if (err)
        console.warn("[CompositorConfigManager] The daemon didn't take the layer's facts:", err.message);
    });
  }

  property Timer _sendSoon: Timer {
    interval: 100
    onTriggered: root._send()
  }

  on_FactsTextChanged: _sendSoon.restart()
  onLiveChanged: root._sent = ""

  // The state as soon as the daemon is there (niri's user binds and
  // running config come with it, before the layer goes live)
  readonly property bool _reachable: enabled && BackendManager.ready
  on_ReachableChanged: _fetchState()

  function _fetchState() {
    if (!root._reachable)
      return;
    BackendManager.call("compositor.state", {}, (err, state) => {
      if (!err)
        root._setState(state);
    });
  }

  // The window look the daemon set last (compositor.state's `look`), for a
  // backend that sets it a window at a time as windows open (sway:
  // SwayManager.setLiveLook)
  property string _lookSet: ""

  function _setState(state) {
    root._state = state ?? {};
    const look = state?.look ? JSON.stringify(state.look) : "";
    if (look !== root._lookSet && CompositorManager.backend.setLiveLook) {
      root._lookSet = look;
      if (look)
        CompositorManager.backend.setLiveLook(state.look);
    }
    // The binds the daemon has everything for
    const complete = {};
    (state?.complete ?? []).forEach(bind => complete[JSON.stringify(bind)] = true);
    root._complete = complete;
  }

  Component.onCompleted: {
    BackendManager.listen("compositor.state", state => root._setState(state));
    // The compositor was changed at runtime: the backend reads back what it
    // follows (Hyprland's options, sway's windows)
    BackendManager.listen("compositor.applied", () => {
      if (CompositorManager.backend.layerApplied)
        CompositorManager.backend.layerApplied();
    });
    BackendManager.listen("compositor.notify", note => {
      if (note?.what === "approval")
        root._notifyApproval();
      else if (note?.what === "included")
        root._notifyNotIncluded();
    });
    BackendManager.listen("compositor.bindsMerged", merged => root.bindsMerged(merged?.binds ?? []));
    _fetchState();
    if (live)
      _sendSoon.restart();
  }

  // --- Asking the daemon ---

  // `callback` (optional) gets managedCheck once known
  function checkManaged(callback) {
    BackendManager.call("compositor.checkManaged", {}, (err, result) => callback?.(err ? "" : result.check));
  }

  // The status card's (and the notification's) Allow
  function allowTakeover() {
    BackendManager.call("compositor.allowTakeover", {});
  }

  // `only`: one of the user's files (the adopted one), else all of them
  function mergeUserBinds(only) {
    BackendManager.call("compositor.merge", {
      "only": only ?? ""
    });
  }

  // Counts what a Merge would move, changing nothing (`mergeable`)
  function previewMerge() {
    BackendManager.call("compositor.previewMerge", {});
  }

  // Calls back with the binds in effect (the user's and axiom's), where
  // the shell can't read them from the compositor (sway, niri), or null
  function withEntries(callback) {
    BackendManager.call("compositor.entries", {}, (err, entries) => callback(err ? null : entries));
  }

  // --- For the settings page ---

  function copyIncludeLines() {
    ClipboardManager.copyText(includeLines);
  }

  function copyAutostartLines() {
    ClipboardManager.copyText(autostartLines);
  }

  // Adds the autostart line to the user's config (the autostart hookup,
  // with a backup); it takes effect with the next session, so no reload
  function addAutostartLines() {
    IntegrationHookupManager.apply("compositorAutostart");
  }

  function openConfigDir() {
    if (root.configDir !== "")
      CommandManager.runDetached(["xdg-open", root.configDir]);
  }

  // Adds the include lines to the user's config (the include hookup, with a
  // backup), then has the compositor reload so they take effect
  function addIncludeLines() {
    _includeAdded = true;
    IntegrationHookupManager.apply("compositorModule");
  }

  property bool _includeAdded: false

  property Connections _hookups: Connections {
    target: root._includeAdded ? IntegrationHookupManager : null

    function onResultsChanged() {
      const results = IntegrationHookupManager.results.compositorModule;
      if (!results)
        return;
      root._includeAdded = false;
      if (results.some(result => result.changed))
        BackendManager.call("compositor.reload", {});
    }
  }

  // --- Notifications (once per session, outliving a reload of the shell) ---

  function _notifyApproval() {
    _notifyOnce("approvalAsked", I18n.tr("{0} config needs your approval", CompositorManager.displayName), I18n.tr("axiom's Managed mode would take over {0}, moving your config to {1}. Until you allow it, axiom applies its settings at runtime.", Paths.shortenHome(root.managedPath), Paths.shortenHome(root.userDir)), [["allow", I18n.tr("Allow takeover"), () => root.allowTakeover()]]);
  }

  // Included mode with the module not loaded, offering to add the line (as
  // the onboarding's Apply does, with a backup), not while the onboarding
  // is open, which offers it itself
  function _notifyNotIncluded() {
    if (OnboardingManager.shown)
      return;
    const add = root.includeTarget ? [["add", I18n.tr("Add it for me"), () => root.addIncludeLines()]] : [];
    _notifyOnce("includeAsked", I18n.tr("{0} doesn't load axiom's module", CompositorManager.displayName), I18n.tr("axiom's Included mode needs this in your config:\n{0}\nUntil it's there, axiom applies its settings at runtime.", root.includeLines), add);
  }

  // A notification sent once per session (`flag`), with `actions` ([[id,
  // label, run]]) and Open settings
  function _notifyOnce(flag, title, body, actions) {
    if (_session[flag])
      return;
    _session[flag] = true;
    const all = actions.concat([["settings", I18n.tr("Open settings"), () => SettingsManager.openSetting("Compositor")]]);
    const command = ["notify-send", "-a", "axiom", "-u", "critical"].concat(...all.map(action => ["-A", `${action[0]}=${action[1]}`]), ["--", title, body]);
    CommandManager.run(command, (code, out) => {
      // (not `picked?.[2]()`: Qt 6.12's compiler crashes on it)
      const picked = all.find(action => action[0] === out.trim());
      if (picked)
        picked[2]();
    });
  }

  PersistentProperties {
    id: _session
    reloadableId: "axiomCompositorSession"
    property bool approvalAsked: false
    property bool includeAsked: false
  }
}
