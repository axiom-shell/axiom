pragma Singleton
import QtQuick
import qs.config
import qs.components.methods
import qs.services.compositor
import qs.services.core

// The input sources (Input.sources: xkb layouts and input method engines)
// and which one is in use, for every surface that shows or switches them:
// the KeyboardLayout widget and its popout, the module, the OSD's
// keyboardLayout status, keybinds and IPC (docs/dev/features/
// input-sources.md). It joins the compositor's xkb state (withKeyboard,
// again on every keyboardLayoutChanged or config reload, no polling) and
// the daemon's input method framework (the inputMethod topic: fcitx5 or
// ibus), through methods/InputSources. Switching sets the compositor's
// layout first, then the framework's input method. It gives the framework
// the sources (inputMethod.push) once axiom owns its list (_owned), its
// choice (inputMethod.framework) and Input.method's options. On the login
// screen no framework runs: only the xkb sources, nothing pushed.
QtObject {
  id: root

  // --- The compositor's keyboard ---

  // Its layouts' codes (["us", "de"]), the active one's index and name
  property var layouts: []
  property int layoutIndex: 0
  property string keymapName: ""
  // The xkb registry (the daemon's input.layouts: { layouts: [{ name,
  // short, description, languages, variants }] }), null until read: the
  // codes of layouts niri and sway name in full, the names of layouts
  readonly property var registry: _registry
  property var _registry: null

  // --- The framework (the daemon's inputMethod.state) ---

  // fcitx5 or ibus runs and is followed
  readonly property bool running: !root._inert && root._im?.running === true
  // "fcitx5", "ibus", or "" while none runs
  readonly property string framework: root.running ? String(root._im.framework ?? "") : ""
  // The engines installed: [{ name, label, displayName, icon, lang }]
  readonly property var available: root.running ? root._im.available ?? [] : []
  // The framework's list was changed outside axiom (fcitx5-configtool,
  // ibus-setup) since axiom gave it the sources
  readonly property bool outsideEdit: root.running && root._im?.outsideEdit === true
  // The framework's list isn't the sources' (on a first run axiom gives
  // it the sources only once it owns the list: keepOwn())
  readonly property bool differs: root.running && !InputSources.groupMatches(root.framework, InputConfig.savedSources, root.registry, root._im)

  // --- The sources ---

  // Every source to switch between ({ id, kind, layout, variant, engine
  // }, InputSources.effective: the compositor's own layouts while axiom
  // doesn't set the keyboard); on the login screen the xkb ones alone
  readonly property var sources: InputSources.effective(root._inert ? InputSources.xkbOnly(InputConfig.sources) : InputConfig.sources, root.layouts)
  // The xkb ones: what a password field types through (the lock screen's
  // and the greeter's module offer only these)
  readonly property var xkbSources: InputSources.xkbOnly(root.sources)
  // The id of the source in use ("" for none): the framework's input
  // method, else the compositor's layout (also while no text field had
  // focus yet, when the framework's current is "")
  readonly property string current: InputSources.current(root.sources, root.layoutIndex, root.running ? String(root._im.current ?? "") : "", root.framework, root.registry)
  // The xkb source the compositor types on
  readonly property string currentXkb: InputSources.current(root.xkbSources, root.layoutIndex, "", "none", null)

  // The sources a surface offers: the xkb ones alone with `xkbOnly`
  function sourcesFor(xkbOnly) {
    return xkbOnly ? root.xkbSources : root.sources;
  }

  function currentFor(xkbOnly) {
    return xkbOnly ? root.currentXkb : root.current;
  }

  // A source's short text: "full" its full name, else an xkb source's
  // code in capitals ("DE"); an engine shows its own label ("あ"), else
  // its name
  function labelFor(id, format) {
    const source = root._source(id);
    if (!source)
      return "";
    const full = format === "full";
    const text = InputSources.label(source, full ? "name" : "code", root.registry, root._engine(source)?.label ?? "");
    return source.kind === "xkb" && !full ? text.toUpperCase() : text;
  }

  // A source's name for a list: the layout's full name, the engine's
  // display name
  function nameFor(id) {
    const source = root._source(id);
    if (!source)
      return "";
    if (source.kind === "xkb")
      return InputSources.describe(root.registry, source.layout, source.variant);
    return root._engine(source)?.displayName || source.engine;
  }

  // A source's kind as an icon
  function iconFor(id) {
    return root._source(id)?.kind === "ime" ? "translate" : "keyboard";
  }

  // Switches to the source `id`: the compositor's layout, then the
  // framework's input method. False when no source has that id
  function set(id) {
    const target = InputSources.target(root.sources, id, root.framework, root.registry);
    if (!target)
      return false;
    const im = () => {
      if (target.im !== "" && root.running)
        root._setIm(target.im);
    };
    if (target.xkbIndex >= 0 && target.xkbIndex !== root.layoutIndex)
      CompositorManager.setKeyboardLayout(target.xkbIndex, () => {
        root.refresh();
        im();
      });
    else
      im();
    return true;
  }

  // The next or previous source (of the xkb ones alone with `xkbOnly`)
  function next(xkbOnly) {
    root.set(InputSources.step(root.sourcesFor(xkbOnly), root.currentFor(xkbOnly), 1));
  }

  function prev(xkbOnly) {
    root.set(InputSources.step(root.sourcesFor(xkbOnly), root.currentFor(xkbOnly), -1));
  }

  // The framework's list as sources (InputSources.fromGroup), for a
  // draft of Input.sources (the settings card's "Use fcitx5's list");
  // [] while none runs
  function importFromFramework() {
    return root.running ? InputSources.fromGroup(root.framework, root._im) : [];
  }

  // Gives the framework the sources, over its own list: axiom owns the
  // list from now on (the settings card's "Keep axiom's")
  function keepOwn() {
    root._own();
    root._lastGroup = "";
    root._sync(true);
  }

  function refresh() {
    CompositorManager.withKeyboard(keyboard => {
      if (!keyboard)
        return;
      root.layouts = keyboard.layouts;
      root.layoutIndex = keyboard.index;
      root.keymapName = keyboard.keymap;
    }, root._registry);
  }

  // --- Internals ---

  // The login screen: no framework, nothing pushed
  readonly property bool _inert: Paths.greeter
  // The daemon's inputMethod state, null until it said
  property var _im: null
  // Whether axiom owns the framework's list: set once the sources are
  // saved changed, or by keepOwn(); kept in state (inputSources.json).
  // Until then a framework's own list is left alone (differs says so)
  property bool _owned: false
  property var _state: StateManager.createStateHandler("inputSources")
  // What was pushed last, so a framework keeping a list its own way isn't
  // pushed again and again; cleared when it stops
  property string _lastGroup: ""
  property string _lastOptions: ""
  property string _lastImCurrent: ""
  // The saved sources as text: a change is the user's (an edit, a restore)
  readonly property string _sourcesJson: JSON.stringify(InputConfig.savedSources)
  readonly property string _frameworkKey: root.running ? root.framework : ""

  on_SourcesJsonChanged: {
    if (root._inert)
      return;
    root._own();
    root._lastGroup = "";
    root._sync(true);
  }

  on_FrameworkKeyChanged: {
    root._lastGroup = "";
    root._lastOptions = "";
    root._lastImCurrent = "";
    root._sync(false);
  }

  property Connections _config: Connections {
    target: InputConfig
    enabled: !root._inert
    function onMethodOptionsChanged() {
      root._pushOptions();
    }
    function onFrameworkChanged() {
      root._pushFramework();
    }
  }

  function _source(id) {
    return root.sources.find(s => s.id === id) ?? null;
  }

  // The framework's engine a source is (available's entry), or null
  function _engine(source) {
    if (source?.kind !== "ime")
      return null;
    const name = InputSources.imName(source, root.framework, root.registry);
    return root.available.find(a => a.name === name) ?? null;
  }

  function _own() {
    if (root._owned)
      return;
    root._owned = true;
    root._state.save({
      "owned": true
    });
  }

  // rpc: inputMethod.set
  function _setIm(name) {
    BackendManager.call("inputMethod.set", {
      "name": name
    }, error => {
      if (error && error.kind !== "unavailable")
        console.warn("[InputSourceManager] Could not switch the input method:", error.message);
    });
  }

  // The state changed: the list given once axiom owns it (`edited`: the
  // user changed the sources, given even over an outside edit), the
  // options, and the compositor's layout following an input method
  // switched in the framework itself
  function _sync(edited) {
    if (!root.running)
      return;
    root._pushGroup(edited);
    root._pushOptions();
    root._followIm();
  }

  // rpc: inputMethod.push
  function _pushGroup(edited) {
    if (!root._owned || (root.outsideEdit && !edited))
      return;
    const sources = InputConfig.savedSources;
    // ibus names xkb layouts by their language, from the registry
    if (root.framework === "ibus" && root._registry === null)
      return;
    if (InputSources.groupMatches(root.framework, sources, root.registry, root._im))
      return;
    const group = root.framework === "ibus" ? {
      "defaultLayout": "",
      "items": InputSources.ibusEngines(sources, root.registry).map(name => ({
            "name": name,
            "layout": ""
          }))
    } : InputSources.fcitx5Group(sources);
    if (group.items.length === 0)
      return;
    const key = root.framework + JSON.stringify(group);
    if (key === root._lastGroup)
      return;
    root._lastGroup = key;
    BackendManager.call("inputMethod.push", {
      "defaultLayout": group.defaultLayout,
      "items": group.items
    }, error => {
      if (error && error.kind !== "unavailable")
        console.warn("[InputSourceManager] Could not give", root.framework, "the input sources:", error.message);
    });
  }

  // rpc: inputMethod.options
  function _pushOptions() {
    if (!root.running)
      return;
    const options = InputConfig.methodOptions;
    const key = root.framework + JSON.stringify(options);
    if (key === root._lastOptions)
      return;
    root._lastOptions = key;
    BackendManager.call("inputMethod.options", {
      "shareState": options.shareState,
      "verticalCandidates": options.verticalCandidates,
      "candidateFont": options.candidateFont,
      "showSwitchPopup": options.showSwitchPopup
    }, error => {
      if (error && error.kind !== "unavailable")
        console.warn("[InputSourceManager] Could not set", root.framework + "'s options:", error.message);
    });
  }

  // rpc: inputMethod.framework
  function _pushFramework() {
    if (root._inert)
      return;
    BackendManager.call("inputMethod.framework", {
      "name": InputConfig.framework
    }, error => {
      if (error && error.kind !== "unavailable")
        console.warn("[InputSourceManager] Could not pick the input method framework:", error.message);
    });
  }

  // An input method switched in the framework itself (its hotkey, its
  // tray menu): the compositor follows to the layout it types on, so a
  // password field (where no input method types) types on it too
  function _followIm() {
    const im = String(root._im?.current ?? "");
    if (im === root._lastImCurrent)
      return;
    root._lastImCurrent = im;
    if (im === "")
      return;
    const source = root.sources.find(s => InputSources.imName(s, root.framework, root.registry) === im);
    const index = source ? InputSources.xkbIndex(root.sources, source) : -1;
    if (index >= 0 && index !== root.layoutIndex)
      CompositorManager.setKeyboardLayout(index, root.refresh);
  }

  function _showIm(state) {
    root._im = state;
    root._sync(false);
  }

  // rpc: inputMethod.get
  function _fetchIm() {
    BackendManager.call("inputMethod.get", {}, (error, state) => {
      if (!error)
        root._showIm(state);
    });
  }

  // rpc: input.layouts
  function _readRegistry() {
    BackendManager.call("input.layouts", {}, (error, result) => {
      if (error) {
        if (error.kind !== "unavailable")
          console.warn("[InputSourceManager] Could not read the xkb registry:", error.message);
        return;
      }
      root._registry = result;
      root.refresh();
      root._sync(false);
    }, {
      "repeatable": true
    });
  }

  property Connections _events: Connections {
    target: CompositorManager
    function onKeyboardLayoutChanged() {
      Qt.callLater(root.refresh);
    }
    function onConfigReloaded() {
      Qt.callLater(root.refresh);
    }
  }

  property Connections _backend: Connections {
    target: BackendManager
    enabled: !root._inert
    function onGreeted() {
      root._pushFramework();
      root._fetchIm();
    }
  }

  Component.onCompleted: {
    refresh();
    _readRegistry();
    if (root._inert)
      return;
    root._owned = root._state.load({}).owned === true;
    BackendManager.listen("inputMethod.state", state => root._showIm(state));
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready) {
      root._pushFramework();
      root._fetchIm();
    }
  }

  // `axiom ipc inputSources next|prev|set <id>|list` (the keybind actions
  // inputSourceNext / inputSourcePrev)
  property IpcTarget _ipc: IpcTarget {
    target: "inputSources"

    function next(): void {
      root.next(false);
    }

    function prev(): void {
      root.prev(false);
    }

    // Switches to the source with that id; an unknown one is the caller's
    // mistake
    function set(id: string): void {
      if (!root.set(id))
        throw {
          "kind": "bad_request",
          "message": "no input source " + id
        };
    }

    // The sources as JSON: [{ id, kind, label, name, current }]
    function list(): string {
      return JSON.stringify(root.sources.map(s => ({
            "id": s.id,
            "kind": s.kind,
            "label": root.labelFor(s.id, "short"),
            "name": root.nameFor(s.id),
            "current": s.id === root.current
          })));
    }
  }
}
