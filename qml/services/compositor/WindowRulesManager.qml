pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.system
import qs.services.ui

// The user's window rules (docs/dev/features/window-rules.md): the Window
// rules page's editor, the report on the saved rules, and the engine's
// state (windowRules.state: which open windows each rule matches, the
// while-effects in force and what the sway look leaves to the rules).
QtObject {
  id: root

  // The page's draft, selection and edits
  readonly property WindowRulesEditor editor: WindowRulesEditor {}

  // compositor.state's windowRules: the saved rules as the compositor's
  // config takes them, null until known
  readonly property var savedReport: CompositorConfigManager.windowRules

  // windowRules.state: which open windows each rule matches, the holds and
  // the look; null until known
  readonly property var state: root._state
  // The while-effects in force, for their owners; `state.overrides` the ones the user overrode
  readonly property var holds: root._state ? root._state.holds : null
  // The outputs a rule pauses OSDs on / hides the bars on (holds.pauseOsd /
  // hideBar), the same array while they are; [] until known
  readonly property var pauseOsdOn: root._outputs(root._pauseOsdKey)
  readonly property var hideBarOn: root._outputs(root._hideBarKey)
  readonly property string _pauseOsdKey: (root.holds?.pauseOsd ?? []).join("\n")
  readonly property string _hideBarKey: (root.holds?.hideBar ?? []).join("\n")
  function _outputs(key) {
    return key === "" ? [] : key.split("\n");
  }
  // Of `windows`, those no window rule hides from `place` ("dock",
  // "switcher", "workspaces", "launcher"; holds.hideFrom); all of them until
  // the daemon answers
  function shownIn(place, windows) {
    return HideFromHold.shown(windows, root.holds?.hideFrom?.[place] ?? null);
  }

  // What sway's per-window look leaves to the rules
  readonly property var look: root._state ? root._state.look : null

  property var _state: null

  // Apply to open windows: gives every open window what the saved rules
  // would give it (the compositor's written rules too); `callback` (optional)
  // gets how many windows it moved
  // rpc: windowRules.applyNow
  function applyNow(callback) {
    BackendManager.call("windowRules.applyNow", {}, (error, result) => {
      if (error)
        console.warn("WindowRulesManager: applyNow failed:", error);
      callback?.(error ? 0 : result.windows);
    });
  }

  // For each rule of an unsaved WindowRules section, the open windows it
  // matches: `callback` gets the rows ([{ rule, windows }]) or null
  // rpc: windowRules.match
  function match(section, callback) {
    BackendManager.call("windowRules.match", {
      "section": section
    }, (error, result) => callback(error ? null : result.rules));
  }

  // A built-in switch ("steamFloat", "gamesSpecial") as a rule of the user's
  // (Copy as rule), for an unsaved WindowRules section's values: `callback`
  // gets the rule ({ icon, windows, window }) or null
  // rpc: windowRules.builtin
  function builtin(key, section, callback) {
    BackendManager.call("windowRules.builtin", {
      "key": key,
      "section": section
    }, (error, result) => callback(error ? null : result.rule));
  }

  // The user's own say over a hold (the DND switch turned off by hand): it
  // wins until the rule's hold ends; the daemon keeps it (state.overrides)
  // rpc: windowRules.override
  function override(effect) {
    BackendManager.call("windowRules.override", {
      "effect": effect
    }, error => {
      if (error)
        console.warn("WindowRulesManager: override failed:", error);
    });
  }

  // The open windows as the rules see them (windowRules.windows); `callback` gets null when the daemon fails
  // rpc: windowRules.windows
  function windows(callback) {
    BackendManager.call("windowRules.windows", {}, (error, result) => callback(error ? null : result.windows));
  }

  // What a rule made from a window starts with ({ window, kind }); id ""
  // is the focused window. `callback` gets it, or null when there is none
  // rpc: windowRules.fromWindow
  function fromWindow(id, callback) {
    BackendManager.call("windowRules.fromWindow", {
      "id": id
    }, (error, result) => callback(error ? null : result));
  }

  // A new unsaved rule from the focused window, on the page's draft
  function newFromFocused() {
    root.editor.ensureLoaded();
    root.fromWindow("", result => {
      if (result)
        root.editor.addRuleFrom(result);
    });
  }

  // The installed apps matching `query` as options: { value (the desktop
  // file), label, image }. Launcher-hidden (NoDisplay) apps are skipped
  function apps(query) {
    const q = (query ?? "").trim().toLowerCase();
    const list = [];
    for (const entry of DesktopEntries.applications.values) {
      if (entry.noDisplay)
        continue;
      const score = q === "" ? 1 : Math.max(Search.score(entry.name, q) * 2, Search.score(entry.id, q));
      if (score > 0)
        list.push({
          "score": score,
          "option": {
            "value": entry.id + ".desktop",
            "label": entry.name,
            "image": AppIconManager.appIcon(entry.icon)
          }
        });
    }
    list.sort((a, b) => b.score - a.score || a.option.label.localeCompare(b.option.label));
    return (q === "" ? list : list.slice(0, 60)).map(item => item.option);
  }

  // One app's option by its desktop file name; an unknown one shows as itself
  function appOption(desktopId) {
    const entry = DesktopEntries.byId(String(desktopId).replace(/\.desktop$/, ""));
    if (!entry)
      return {
        "value": desktopId,
        "label": desktopId
      };
    return {
      "value": desktopId,
      "label": entry.name,
      "image": AppIconManager.appIcon(entry.icon)
    };
  }

  // A game signal as shown (the proper names stay as they are)
  function gameSignalLabel(signal) {
    const names = {
      "steam": "Steam",
      "proton": "Proton",
      "lutris": "Lutris",
      "heroic": "Heroic",
      "umu": "umu",
      "gamescope": "gamescope",
      "wine": "Wine"
    };
    return signal === "steamApp" ? I18n.tr("Steam game id") : names[signal] ?? signal;
  }

  // A window's second line in a picker: its app id, its process (or that it
  // isn't known) and, for a game, why it counts as one
  function windowDetail(window) {
    const parts = [window.appId || ""];
    parts.push(window.process && !window.process.bridge ? window.process.name : I18n.tr("process not known"));
    if ((window.game ?? []).length > 0)
      parts.push(I18n.tr("game: {0}", window.game.map(signal => root.gameSignalLabel(signal)).join(", ")));
    return parts.filter(part => part !== "").join(" · ");
  }

  // rpc: windowRules.get
  function _fetch() {
    BackendManager.call("windowRules.get", {}, (error, state) => {
      if (!error)
        root._state = state;
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    enabled: !Paths.greeter
    function onGreeted() {
      root._fetch();
    }
  }

  property IpcTarget _ipc: IpcTarget {
    target: "windowRules"
    enabled: !Paths.greeter

    function open(): void {
      ShellManager.openOverlayPage("WindowRules");
    }

    function fromFocused(): void {
      root.newFromFocused();
      ShellManager.openOverlayPage("WindowRules");
    }
  }

  Component.onCompleted: {
    // The login screen has no windows to match
    if (Paths.greeter)
      return;
    BackendManager.listen("windowRules.state", state => root._state = state);
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._fetch();
  }
}
