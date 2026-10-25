pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui

/*
 * The first-run onboarder (shell/Onboarding): a series of pages that set
 * the essentials up (the compositor, monitors, apps and keys, workspaces,
 * the look, integrations), each applying as the user goes, with the
 * compositor mode applied on Finish.
 *
 * It opens by itself when there was no config.json (ConfigManager.firstRun),
 * and again after a reload or restart until it's finished or skipped:
 * ui/onboarding.json (Paths.statePath) keeps { completedVersion, step }. Existing
 * setups (a config, no state file) are never prompted. IPC `onboarding`
 * (open, close, reset) and the launcher's /welcome run it again.
 * Created from shell.qml's `_services`.
 */
Singleton {
  id: root

  // Bump when the onboarding gains a page worth showing to existing users
  readonly property int version: 1

  // The pages, in order: { id, title, icon }
  // I18n.tr("Welcome") I18n.tr("Compositor") I18n.tr("Monitors") I18n.tr("Apps & keys")
  // I18n.tr("Workspaces") I18n.tr("Look") I18n.tr("Integrations") I18n.tr("Checks") I18n.tr("Finish")
  // The Compositor page sets the compositor up (its config mode), where
  // axiom can (configModes); the Monitors page needs the compositor's
  // monitors
  readonly property var pages: _pages.filter(page => (page.id !== "compositor" || CompositorManager.supports.configModes) && (page.id !== "monitors" || CompositorManager.supports.monitors))
  readonly property var _pages: [
    {
      "id": "welcome",
      "title": "Welcome",
      "icon": "waving_hand"
    },
    {
      "id": "compositor",
      "title": "Compositor",
      "icon": "deployed_code"
    },
    {
      "id": "monitors",
      "title": "Monitors",
      "icon": "monitor"
    },
    {
      "id": "apps",
      "title": "Apps & keys",
      "icon": "keyboard"
    },
    {
      "id": "workspaces",
      "title": "Workspaces",
      "icon": "grid_view"
    },
    {
      "id": "look",
      "title": "Look",
      "icon": "palette"
    },
    {
      "id": "integrations",
      "title": "Integrations",
      "icon": "extension"
    },
    {
      "id": "checks",
      "title": "Checks",
      "icon": "checklist"
    },
    {
      "id": "finish",
      "title": "Finish",
      "icon": "flag"
    }
  ]

  readonly property bool shown: _run.shown
  readonly property int step: _run.step
  readonly property string pageId: pages[step]?.id ?? ""
  readonly property bool isLast: step === pages.length - 1

  // --- The compositor ---

  // Hyprland's version ("0.56.2"), and whether it has the Lua config axiom
  // needs (0.55+); "" until read, and elsewhere
  property string hyprlandVersion: ""
  readonly property bool hyprlandSupported: {
    const [major, minor] = hyprlandVersion.split(".").map(Number);
    return major > 0 || minor >= 55;
  }
  // Whether axiom can set the compositor up: an older Hyprland can't
  readonly property bool compositorSupported: CompositorManager.kind !== "hyprland" || hyprlandSupported
  // What the compositor's config folder holds: "none" (no config), "stock"
  // (the compositor's example config), "custom" (the user's own), "ours"
  // (axiom's managed file), "blocked" (a symlink or git repository: never
  // taken over) or "legacy" (Hyprland: only a hyprland.conf); "" until
  // checked
  readonly property string configState: {
    switch (CompositorConfigManager.managedCheck) {
    case "new":
      return _hasLegacyConfig ? "legacy" : "none";
    case "adopt":
      return "custom";
    // The file leaving managed wrote: nothing of the user's
    case "released":
      return "ours";
    case "stock":
    case "ours":
    case "blocked":
      return CompositorConfigManager.managedCheck;
    }
    return "";
  }
  property bool _hasLegacyConfig: false

  // Why managed can't be picked ("" when it can), for its option card
  readonly property string blockedReason: {
    const dir = Paths.shortenHome(CompositorConfigManager.configDir).replace(/\/$/, "");
    if (CompositorConfigManager.managedBlockedBy === "link")
      return I18n.tr("{0} or its config is a symlink (dotfiles?), so axiom won't replace it.", dir);
    if (CompositorConfigManager.managedBlockedBy === "git")
      return I18n.tr("{0} is inside the git repository at {1}, so axiom won't take it over. Move or remove that repository's .git to allow it.", dir, Paths.shortenHome(CompositorConfigManager.managedBlockedRepo));
    return configState === "blocked" ? I18n.tr("Your {0} config is a symlink or in a git repository, so axiom won't take it over.", CompositorManager.displayName) : "";
  }
  // Whether the compositor's config already starts axiom (install.sh's
  // line, or the Compositor page's Apply); false until checked
  readonly property bool autostartDone: IntegrationHookupManager.isDone("compositorAutostart")
  // Whether the compositor's config loads axiom's module (included mode)
  readonly property bool includeDone: (IntegrationHookupManager.status.compositorInclude?.targets ?? [])[0]?.done === true

  // The mode the Compositor page starts on: the one set up already (run
  // again, Finish shouldn't quietly leave it, giving back its module or
  // takeover); else managed only when there's nothing of the user's to take
  // over (the compositor's example config, none, or axiom's already); a
  // config of their own (custom, legacy, blocked) starts detached, which
  // changes none of it
  readonly property string recommendedMode: CompositorConfig.mode !== "detached" ? CompositorConfig.mode : ["stock", "none", "ours"].includes(configState) ? "managed" : "detached"
  // The mode picked on the Compositor page, applied on Finish ("" follows
  // the recommendation)
  readonly property string chosenMode: _run.chosenMode !== "" ? _run.chosenMode : recommendedMode
  readonly property bool modeAllowed: configState !== "blocked" || chosenMode !== "managed"

  function chooseMode(mode) {
    _run.chosenMode = mode;
  }

  // What the Compositor page shows: the config folder, the include and
  // autostart lines, and on Hyprland its version and an old hyprland.conf
  function detectCompositor() {
    if (!CompositorManager.supports.configModes)
      return;
    CompositorConfigManager.checkManaged();
    IntegrationHookupManager.check("compositorInclude");
    IntegrationHookupManager.check("compositorAutostart");
    if (CompositorManager.kind !== "hyprland")
      return;
    root._hasLegacyConfig = FileManager.read(Paths.hyprlandPath + "hyprland.conf") !== null;
    HyprlandManager.withVersion(version => root.hyprlandVersion = /^\d+\.\d+/.test(version) ? version : "");
  }

  // --- Navigation ---

  function open() {
    _run.shown = true;
    _save(false);
    detectCompositor();
  }

  function goTo(index) {
    _run.step = Math.max(0, Math.min(pages.length - 1, index));
    _save(false);
  }

  function next() {
    if (isLast)
      finish();
    else
      goTo(step + 1);
  }

  function back() {
    goTo(step - 1);
  }

  // Applies the compositor mode (which may take over its config) and closes
  function finish() {
    if (pages.some(page => page.id === "compositor") && compositorSupported && modeAllowed && chosenMode !== CompositorConfig.mode)
      SettingsManager.commitValues({
        "Compositor.mode": chosenMode
      });
    close();
  }

  // Closes for good (until /welcome): finishing and skipping alike
  function close() {
    _run.shown = false;
    _run.step = 0;
    _run.chosenMode = "";
    _save(true);
  }

  // Forgets that it ran, so the next qs start opens it (IPC reset)
  function reset() {
    root._saved = {
      "completedVersion": 0,
      "step": 0
    };
    _state.save(root._saved);
  }

  readonly property var _state: StateManager.createStateHandler("onboarding")

  function _save(completed) {
    _state.save({
      "completedVersion": completed ? root.version : (_saved.completedVersion ?? 0),
      "step": root.step
    });
    if (completed)
      _saved.completedVersion = root.version;
  }

  property var _saved: ({})

  // Survives hot reloads (a theme, config or compositor change mid-way)
  PersistentProperties {
    id: _run
    reloadableId: "axiomOnboarding"
    property bool shown: false
    property int step: 0
    property string chosenMode: ""
  }

  // The compositor's example config on a first run: no fractional scales
  onConfigStateChanged: {
    if (shown && ConfigManager.firstRun && (configState === "stock" || configState === "none"))
      MonitorManager.useWholeScale();
  }

  Connections {
    target: ConfigManager
    function onFirstRunChanged() {
      if (ConfigManager.firstRun && !root.shown)
        root.open();
    }
  }

  Component.onCompleted: {
    root._saved = root._state.load({});
    // A restart in the middle of it (the state says it isn't done), one
    // finished before `version` was bumped, or a first run already seen
    // before this was created
    const unfinished = root._saved.step !== undefined && (root._saved.completedVersion ?? 0) < root.version;
    if (ConfigManager.firstRun || (unfinished && !_run.shown)) {
      _run.step = root._saved.step ?? 0;
      root.open();
    } else if (_run.shown) {
      root.detectCompositor();
    }
  }

  IpcTarget {
    target: "onboarding"

    function open(): void {
      root.open();
    }

    function close(): void {
      root.close();
    }

    // Opens on a step (0 is Welcome)
    function goTo(index: int): void {
      root.open();
      root.goTo(index);
    }

    function reset(): void {
      root.reset();
    }
  }
}
