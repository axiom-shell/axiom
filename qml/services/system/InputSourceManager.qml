pragma Singleton
import QtQuick
import qs.config
import qs.components.methods
import qs.services.compositor
import qs.services.core
import qs.services.session

// The input sources (Input.keyboard.sources: xkb layouts and input method engines)
// and which one is in use, for every surface that shows or switches them:
// the KeyboardLayout widget and its popout, the module, the OSD's
// keyboardLayout status, keybinds and IPC (docs/dev/features/
// input-sources.md). It joins the compositor's xkb state (withKeyboard,
// again on every keyboardLayoutChanged or config reload, no polling) and
// the daemon's input method framework (the inputMethod topic: fcitx5 or
// ibus), through methods/InputSources. Switching sets the compositor's
// layout first, then the framework's input method. While axiom manages
// the input method (Input.keyboard.method.enabled) it gives the framework the
// sources (inputMethod.push), its choice (inputMethod.framework) and
// the method's options; off, only the xkb sources count and the
// framework is left alone. On the login screen no framework runs: only the
// xkb sources, nothing pushed.
QtObject {
  id: root

  // --- The compositor's keyboard ---

  // Its layouts' codes (["us", "de"]) and the active one's index
  property var layouts: []
  property int layoutIndex: 0
  // The xkb registry (the daemon's input.layouts: { layouts: [{ name,
  // short, description, languages, variants }] }), null until read: the
  // codes of layouts niri and sway name in full, the names of layouts
  readonly property var registry: _registry
  property var _registry: null

  // --- The framework (the daemon's inputMethod.state) ---

  // axiom manages the input method (Input.keyboard.method.enabled, as shown):
  // off, the engine sources are left out everywhere
  readonly property bool enabled: !root._inert && InputConfig.methodEnabled
  // fcitx5 or ibus runs, whether axiom manages it or not (the settings
  // card's "let axiom manage it?")
  readonly property bool detected: !root._inert && root._im?.running === true
  readonly property string detectedFramework: root.detected ? String(root._im.framework ?? "") : ""
  // fcitx5 or ibus runs and axiom manages it
  readonly property bool running: root.enabled && root.detected
  // "fcitx5", "ibus", or "" while none runs (or axiom doesn't manage it)
  readonly property string framework: root.running ? root.detectedFramework : ""
  // The engines installed: [{ name, label, displayName, icon, lang }]
  readonly property var available: root.running ? root._im.available ?? [] : []
  // The framework's list was changed outside axiom (fcitx5-configtool,
  // ibus-setup) since axiom gave it the sources
  readonly property bool outsideEdit: root.running && root._im?.outsideEdit === true

  // Whether the running framework's list (managed or not) is `sources`':
  // the settings card asks which list wins before axiom manages one that
  // isn't. True while none runs
  function matches(sources) {
    return !root.detected || InputSources.groupMatches(root.detectedFramework, sources, root.registry, root._im);
  }

  // --- The sources ---

  // Every source to switch between ({ id, kind, layout, variant, engine
  // }, of _counted); on the login screen, and while axiom doesn't manage
  // the input method or no framework runs (an engine can't be switched to
  // then), the xkb ones alone; an engine the framework hasn't installed is
  // left out too (switching to it fails, so stepping would stop there)
  readonly property var sources: root._counted.filter(s => s.kind !== "ime" || root._engine(s) !== null)
  // The compositor's layouts, in its order: what a password field types
  // through (the lock screen's and the greeter's module offer only
  // these), an engine's typing layout no xkb source has (Mozc's jp, while
  // the method is on) among them (InputSources.compositorLayouts)
  readonly property var xkbSources: InputSources.compositorLayouts(root._counted, InputConfig.methodEnabled)
  // The id of the source in use ("" for none): the framework's input
  // method, else the compositor's layout (also while no text field had
  // focus yet, when the framework's current is "")
  readonly property string current: {
    const id = InputSources.current(root._counted, root.layoutIndex, root.running ? String(root._im.current ?? "") : "", root.framework, root.registry);
    return root._source(id) ? id : "";
  }
  // The compositor's layout it types on (of xkbSources, by its index)
  readonly property string currentXkb: root.xkbSources[root.layoutIndex]?.id ?? ""

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

  // When axiom last switched (set, next, prev: ms, 0 for never): the
  // OSD tells it from a window's own input method coming back on focus
  property double switchedAt: 0

  // Switches to the source `id` (of sources, or of xkbSources: the
  // compositor's layout alone): the compositor's layout, then the
  // framework's input method. False when no source has that id
  function set(id) {
    const layout = root.xkbSources.findIndex(s => s.id === id);
    const target = root.sources.some(s => s.id === id) ? InputSources.target(root._counted, id, root.framework, root.registry) : layout >= 0 ? {
      "xkbIndex": layout,
      "im": ""
    } : null;
    if (!target)
      return false;
    root.switchedAt = Date.now();
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
    root._step(xkbOnly, 1);
  }

  function prev(xkbOnly) {
    root._step(xkbOnly, -1);
  }

  function _step(xkbOnly, direction) {
    root.set(InputSources.step(root.sourcesFor(xkbOnly), root.currentFor(xkbOnly), direction));
  }

  // The framework's list as sources (InputSources.fromGroup), for a
  // draft of Input.keyboard.sources (the settings card's "Use fcitx5's list");
  // [] while none runs
  function importFromFramework() {
    return root.detected ? InputSources.fromGroup(root.detectedFramework, root._im) : [];
  }

  // Gives the framework the sources again, over an edit made outside axiom
  // (the settings card's "Use axiom's")
  function useOwn() {
    root._lastGroup = "";
    root._sync(true);
  }

  // The surfaces showing the source in use (the widget, its popout, the
  // module, the OSD's status) hold it: fcitx5 tells of a switch made in
  // fcitx5 itself only through its tray item, which it registers only
  // while a tray watcher runs (a bar's SystemTray), so while one holds
  // it and fcitx5 runs the daemon reads its current input method about
  // once a second whenever that item is missing (the inputMethodPoll
  // topic; nothing is read while the item is there)
  function acquire(owner) {
    root._consumers.acquire(owner, {});
  }

  function release(owner) {
    root._consumers.release(owner);
  }

  function refresh() {
    CompositorManager.withKeyboard(keyboard => {
      if (!keyboard)
        return;
      root.layouts = keyboard.layouts;
      root.layoutIndex = keyboard.index;
    }, root._registry);
  }

  // --- Internals ---

  // Every source the compositor's xkb list is written from (InputSources.
  // effective: the compositor's own layouts while axiom doesn't set the
  // keyboard), engines no framework runs too: their typing layouts are in
  // that list while the method is on, so an xkb index is read
  // against these, never against `sources`
  readonly property var _counted: InputSources.effective(InputConfig.sources, root.layouts, InputConfig.methodEnabled)
  // The login screen: no framework, nothing pushed
  readonly property bool _inert: Paths.greeter
  property ConsumerRegistry _consumers: ConsumerRegistry {}
  // Held while a surface holds it and a framework runs (the daemon reads
  // only fcitx5, and only without its tray item)
  readonly property bool _polls: !root._inert && root._consumers.active && root.running
  on_PollsChanged: {
    if (root._polls)
      BackendManager.acquire("inputMethodPoll", {});
    else
      BackendManager.release("inputMethodPoll");
  }
  // The daemon's inputMethod state, null until it said
  property var _im: null
  // Pushes follow the saved config, never an editor's preview: the
  // settings card asks which list wins before Save turns managing on
  readonly property bool _pushes: !root._inert && InputConfig.savedMethodEnabled && root.running
  // The framework running is the one chosen: just after the choice
  // changed (or managing turned on) the daemon's state can still be the
  // framework it followed before, whose list must not be built and pushed
  readonly property bool _chosen: InputConfig.savedFramework === "auto" || InputConfig.savedFramework === root.framework
  // What was pushed last, so a framework keeping a list its own way isn't
  // pushed again and again; cleared when it stops
  property string _lastGroup: ""
  property string _lastOptions: ""
  property string _lastImCurrent: ""
  // The saved sources as text: a change is the user's (an edit, a restore)
  readonly property string _sourcesJson: JSON.stringify(InputConfig.savedSources)
  readonly property string _frameworkKey: root.running ? root.framework : ""

  on_SourcesJsonChanged: {
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
    function onSavedMethodOptionsChanged() {
      root._pushOptions();
    }
    function onSavedFrameworkChanged() {
      root._pushFramework();
    }
    // Turned on (saved): the framework's choice, then the list (the card
    // asked which wins first) and the options, once the bindings follow
    function onSavedMethodEnabledChanged() {
      root._lastGroup = "";
      root._lastOptions = "";
      root._pushFramework();
      Qt.callLater(() => root._sync(true));
    }
  }

  // A source of `sources`, else a layout of xkbSources
  function _source(id) {
    return root.sources.find(s => s.id === id) ?? root.xkbSources.find(s => s.id === id) ?? null;
  }

  // The framework's engine a source is (available's entry), or null
  function _engine(source) {
    if (source?.kind !== "ime")
      return null;
    const name = InputSources.imName(source, root.framework, root.registry);
    return root.available.find(a => a.name === name) ?? null;
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

  // The state changed: the list given while axiom manages the framework
  // (`edited`: the user changed the sources or turned managing on, given
  // even over an outside edit), the options, and the compositor's layout
  // following an input method switched in the framework itself
  function _sync(edited) {
    if (!root.running)
      return;
    root._pushGroup(edited);
    root._pushOptions();
    root._followIm();
  }

  // rpc: inputMethod.push
  function _pushGroup(edited) {
    if (!root._pushes || !root._chosen || (root.outsideEdit && !edited))
      return;
    const sources = InputConfig.savedSources;
    // ibus names xkb layouts by their language, from the registry
    if (root.framework === "ibus" && root._registry === null)
      return;
    // Until the engines installed are read: a list pushed then would
    // drop every engine
    if (!InputSources.installedKnown(root._im))
      return;
    if (InputSources.groupMatches(root.framework, sources, root.registry, root._im))
      return;
    // The installed engines alone (as groupMatches compares): one fcitx5
    // or ibus lacks would be dropped from its list, read back unlike the
    // push and taken for an outside edit
    const group = root.framework === "ibus" ? {
      "defaultLayout": "",
      "items": InputSources.ibusEngines(sources, root.registry, root._im.available).map(name => ({
            "name": name,
            "layout": ""
          }))
    } : InputSources.fcitx5Group(sources, root._im.available);
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
    if (!root._pushes || !root._chosen)
      return;
    const options = InputConfig.savedMethodOptions;
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
    if (root._inert || !InputConfig.savedMethodEnabled)
      return;
    BackendManager.call("inputMethod.framework", {
      "name": InputConfig.savedFramework
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
    const index = source ? InputSources.xkbIndex(root._counted, source) : -1;
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
    BackendManager.listen("inputMethod.state", state => root._showIm(state));
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready) {
      root._pushFramework();
      root._fetchIm();
    }
  }

  // `axiom ipc inputSources next|prev|set <id>|list` (the keybind actions
  // inputSourceNext / inputSourcePrev, which work while locked: the xkb
  // sources alone then, as the lock screen's module offers)
  property IpcTarget _ipc: IpcTarget {
    target: "inputSources"

    function next(): void {
      root.next(LockManager.builtinLocked);
    }

    function prev(): void {
      root.prev(LockManager.builtinLocked);
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
