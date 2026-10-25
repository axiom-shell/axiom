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
 * user's binds in and applying the runtime layer. This sends it what the
 * layer is made of, as the shell's readers resolve it (compositor.inputs:
 * the binds, the window look and input, monitors, strips, the session,
 * theme colors), and shows what it pushes back (compositor.state): the
 * status, the problem, the takeover, the merge. Notifications are sent
 * from here, translated.
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

  readonly property string mode: CompositorConfig.mode

  // --- What the daemon pushes (compositor.state) ---

  property var _state: ({})
  // Why the chosen mode isn't in effect, or ""
  readonly property string problem: _state.problem ?? ""
  // "runtime" (detached), "loaded" (the file is in effect), "fallback"
  // (it isn't: see `problem`) or "pending" (still checking)
  readonly property string status: mode === "detached" ? "runtime" : (_state.status ?? "pending")
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
  // The binds a merge moved in for good (KeybindManager adds them to a
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
  // integration_hookup.py targets, or null. Their texts, as
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
  // everything it needs to be bound, as the daemon says for the binds sent
  function isComplete(bind) {
    return root._complete[JSON.stringify(bind)] === true;
  }

  property var _complete: ({})
  property var _sentBinds: []

  // --- What the layer is made of (compositor.inputs) ---

  // Whether axiom's surfaces blur: as saved for a file, and at runtime as
  // now (BlurManager.active, paused over a fullscreen window)
  function _surfacesBlur(forFile) {
    return forFile === true ? Appearance.blur : BlurManager.active;
  }

  // The window look and the input that are on, for a file (`forFile`) or
  // for now: { look (CompositorLayer.look), surfaces ({ blur,
  // throughWindows, backdrops, threshold }), input (CompositorLayer.input) }
  function spec(forFile) {
    const surfacesBlur = _surfacesBlur(forFile);
    return {
      "look": CompositorLayer.look(WindowLookConfig.look, {
        "activeHex": CompositorLayer.hex(WindowLookConfig.activeBorder),
        "inactiveHex": CompositorLayer.hex(WindowLookConfig.inactiveBorder),
        "borderWidth": WindowLookConfig.borderWidth,
        "radius": WindowLookConfig.radius,
        "surfacesBlur": surfacesBlur,
        "shadow": WindowLookConfig.shadowOn ? {
          "size": WindowLookConfig.shadowSize,
          "color": WindowLookConfig.shadowThemed ? CompositorLayer.hex(WindowLookConfig.shadowColor) : "",
          "alpha": WindowLookConfig.shadowAlpha,
          // Spread evenly, as axiom's own
          "offset": 0,
          "soft": WindowLookConfig.shadowSoft,
          "strength": WindowLookConfig.shadowStrength
        } : null
      }),
      "surfaces": {
        "blur": surfacesBlur,
        "throughWindows": Appearance.blurThroughWindows,
        "backdrops": Appearance.blurBackdrops,
        "threshold": Appearance.blurThreshold
      },
      "input": CompositorLayer.input(InputConfig.input, CursorThemeManager.xcursorTheme)
    };
  }

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

  // The managed Hyprland options with the shared ones
  // reads: Compositor.hyprland.*, WindowBehaviour.*
  readonly property var _managed: Object.assign({}, HyprlandConfig.managed, WindowBehaviourConfig.behaviour)

  // The theme colors the managed options name, as "rrggbb" (every string
  // is tried: one that isn't a color, a curve's name, is left out)
  function _colors(values) {
    const out = {};
    const walk = v => {
      if (typeof v === "string") {
        const hex = CompositorLayer.hex(Theme.resolveColor(v));
        if (/^[0-9a-fA-F]{6}$/.test(hex))
          out[v] = hex;
      } else if (v !== null && typeof v === "object")
        for (const key in v)
          walk(v[key]);
    };
    walk(values);
    return out;
  }

  // Everything the layer is made of but the look, the input and the blur;
  // a change re-applies it (in the file modes, rewriting the file, which
  // reloads the compositor)
  readonly property string _layerKey: [mode, KeybindsConfig._bindsJson, MonitorsConfig._profilesJson, SessionConfig._sessionJson, ThemeIntegrations.qt, WorkspacesConfig._stripsJson, CompositorConfig.requiredSettings, HyprlandConfig._managedJson, WindowBehaviourConfig._behaviourJson, SwayConfig._optionsJson, NiriConfig._optionsJson, Theme.baseColorNames.map(name => Theme.resolveColor(name)).join(","), Appearance.animFast, Appearance.animations, Apps.terminalCommand, Apps.fileManagerCommand, Apps.browserCommand, Idle.enabled, PolkitConfig.enabled, JSON.stringify(_outputRules)].join("|")

  // The window look, the input and the blur behind axiom (paused over a
  // fullscreen window too): only evaluated at runtime as they change, in
  // every mode (a reload on every step of a setting stalls the desktop)
  readonly property string _liveKey: [WindowLookConfig._lookJson, InputConfig._inputJson, CursorThemeManager.xcursorTheme, Appearance.blur, BlurManager.active, Appearance.blurBackdrops, Appearance.blurThroughWindows, WindowLookConfig.activeBorder, WindowLookConfig.inactiveBorder, WindowLookConfig.radius, WindowLookConfig.borderWidth, WindowLookConfig.shadowOn, WindowLookConfig.shadowSize, WindowLookConfig.shadowColor, WindowLookConfig.shadowAlpha, WindowLookConfig.shadowStrength].join("|")

  function _inputs() {
    const live = root.spec(false);
    // sway sets the look a window at a time as windows open (SwayManager)
    if (CompositorManager.backend.setLiveLook)
      CompositorManager.backend.setLiveLook(live.look);
    return {
      "kind": CompositorManager.kind,
      "supports": CompositorManager.supports,
      "fx": CompositorManager.backend.fx === true,
      "binds": KeybindsConfig.activeBinds,
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
      "requiredSettings": CompositorConfig.requiredSettings,
      "specFile": root.spec(true),
      "specLive": live,
      "profiles": MonitorsConfig.profiles,
      "strips": WorkspacesConfig.strips,
      "stripOptions": WorkspacesConfig.stripOptions,
      "stripsKey": WorkspacesConfig._stripsJson,
      "outputRules": root._outputRules,
      "session": SessionConfig.session,
      "qt": ThemeIntegrations.qt,
      "managed": root._managed,
      "behaviour": WindowBehaviourConfig.behaviour,
      "swayOptions": SwayConfig.options,
      "niriOptions": NiriConfig.options,
      "colors": root._colors(root._managed),
      // The shell's motion (Look & Feel → Motion), for the managed
      // animations
      "motion": {
        "fast": Appearance.animFast,
        "normal": Appearance.animNormal,
        "slow": Appearance.animSlow,
        "enabled": Appearance.animations
      },
      "idle": Idle.enabled,
      "polkit": PolkitConfig.enabled,
      "layerKey": root._layerKey,
      "liveKey": root._liveKey
    };
  }

  // What was last sent, to send only a change
  property string _sent: ""

  function _send() {
    if (!root.live)
      return;
    const inputs = root._inputs();
    const text = JSON.stringify(inputs);
    if (text === root._sent)
      return;
    root._sent = text;
    root._sentBinds = inputs.binds;
    BackendManager.call("compositor.inputs", inputs, err => {
      if (err)
        console.warn("[CompositorConfigManager] The daemon didn't take the layer:", err.message);
    });
  }

  property Timer _sendSoon: Timer {
    interval: 100
    onTriggered: root._send()
  }

  on_LayerKeyChanged: _sendSoon.restart()
  on_LiveKeyChanged: _sendSoon.restart()
  onLiveChanged: {
    root._sent = "";
    if (live)
      _sendSoon.restart();
  }

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

  function _setState(state) {
    root._state = state ?? {};
    const complete = {};
    (state?.complete ?? []).forEach((ok, i) => {
      if (i < root._sentBinds.length)
        complete[JSON.stringify(root._sentBinds[i])] = ok === true;
    });
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
      Quickshell.execDetached(["xdg-open", root.configDir]);
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
