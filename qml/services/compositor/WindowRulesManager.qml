pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.core

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
  // The while-effects in force, for their owners (PRs 10-13)
  readonly property var holds: root._state ? root._state.holds : null
  // What sway's per-window look leaves to the rules
  readonly property var look: root._state ? root._state.look : null

  property var _state: null

  // Apply to open windows: gives every open window what the saved rules
  // would give it (the compositor's written rules too); `callback` (optional)
  // gets how many windows it moved
  // rpc: windowRules.applyNow
  function applyNow(callback) {
    BackendManager.call("windowRules.applyNow", {}, (error, result) => callback?.(error ? 0 : result.windows));
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
