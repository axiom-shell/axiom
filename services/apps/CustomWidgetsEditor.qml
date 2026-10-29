pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

// The Custom widgets page's editor (CustomWidgetsManager.editor): a draft of
// the CustomWidgets section, the selected definition and element, and the
// edits. Unsaved edits show live on the bars and modules through a preview,
// and the selected definition stays acquired while the page is shown, so
// its sample (CustomWidgetsManager.outputs) is there to bind from.
// Not a singleton: CustomWidgetsManager owns it.
QtObject {
  id: root

  // --- The draft ---
  readonly property var items: _draft.local?.items ?? []
  readonly property bool isDirty: _draft.isDirty

  property int selectedIndex: 0
  readonly property var selected: items[selectedIndex] ?? null
  readonly property string selectedId: selected?.id ?? ""
  // The selected definition's module elements on their lattice: moves,
  // resizes, the selection and undo (GridEditor, bounded to the design size)
  readonly property GridEditor elements: GridEditor {
    modulesOf: () => root._elements()
    area: CustomWidgetData.lattice(root.selected?.module?.size)
    host: "overlay"
    scopeKey: root.selectedId
    factory: ({
        "make": (kind, place) => ({
              "id": Utils.newId(kind, root._elements()),
              "kind": kind,
              "place": place,
              "bind": {},
              "options": {},
              "actions": {}
            }),
        "size": kind => CustomWidgetData.elementKind(kind)?.size ?? [4, 4]
      })
    onEdited: root._apply()
  }

  // The page's tab: 0 data, 1 bar, 2 module
  property int tab: 0

  // While the page shows, the selected definition runs
  property bool pageShown: false

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    if (!_draft.isDirty)
      root._load();
  }

  function save() {
    if (!_draft.save())
      return false;
    ConfigManager.clearPreview("CustomWidgets");
    return true;
  }

  function reset() {
    root._load();
  }

  function selectDefinition(index) {
    root.selectedIndex = Math.max(0, Math.min(index, root.items.length - 1));
    root.elements.clearSelection();
    root.elements.clearHistory();
  }

  // The module's design size [w, h] in grid units: its elements scaled to
  // the new lattice
  function setDesignSize(size) {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return;
    const from = def.module?.size ?? [4, 2];
    const to = [Math.max(1, Math.min(8, size[0])), Math.max(1, Math.min(8, size[1]))];
    if (from[0] === to[0] && from[1] === to[1])
      return;
    def.module = Object.assign({}, def.module, {
      "size": to,
      "elements": CustomWidgetData.scaleElements(def.module?.elements ?? [], from, to)
    });
    root.elements.clearHistory();
    root._apply();
  }

  // Starts the module from the elements drawn while it has none
  function useDefaultElements() {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return;
    const fields = CustomWidgetsManager.fields[def.id];
    root._elements().splice(0, Infinity, ...CustomWidgetData.defaultElements(def.module?.size, (fields?.ratio ?? -1) >= 0));
    root.elements.clearHistory();
    root._apply();
  }

  // Sets a key of the selected element: `path` a list of keys into it
  // (["options", "color"])
  function setElement(path, value) {
    const index = root.elements.selected;
    if (index < 0)
      return;
    root.set(["module", "elements", index].concat(path), value);
  }

  // Whether a definition differs from its saved version (matched by id)
  function changed(index) {
    const item = root.items[index];
    const saved = (_draft.saved?.items ?? []).find(i => i.id === item?.id);
    return !saved || JSON.stringify(saved) !== JSON.stringify(item);
  }

  // A new definition (from `preset`, a partial definition, when given),
  // selected
  function add(preset) {
    const local = root._local();
    const base = Object.assign({
      "name": I18n.tr("Custom widget")
    }, preset ?? {});
    base.id = Utils.newId(Utils.slug(base.name) || "widget", local.items);
    local.items.push(ConfigManager.withDefaults(base, "CustomWidget"));
    root._apply();
    root.selectDefinition(local.items.length - 1);
  }

  // Adds the Waybar module(s) in `text` (CustomWidgetData.fromWaybar),
  // selecting the last. Returns how many, or the reason it couldn't read it
  // ({ count, error })
  function importWaybar(text) {
    let defs;
    try {
      defs = CustomWidgetData.fromWaybar(text);
    } catch (e) {
      return {
        "count": 0,
        "error": e.message
      };
    }
    defs.forEach(def => root.add(def));
    return {
      "count": defs.length,
      "error": defs.length ? "" : I18n.tr("No custom module (an \"exec\") in it.")
    };
  }

  function duplicate(index) {
    const local = root._local();
    const source = local.items[index];
    if (!source)
      return;
    const copy = Utils.clone(source);
    copy.id = Utils.newId(source.id, local.items);
    copy.name = I18n.tr("{0} (copy)", source.name);
    local.items.splice(index + 1, 0, copy);
    root._apply();
    root.selectDefinition(index + 1);
  }

  function remove(index) {
    const local = root._local();
    if (!local.items[index])
      return;
    local.items.splice(index, 1);
    root._apply();
    root.selectDefinition(Math.min(root.selectedIndex, local.items.length - 1));
  }

  // Sets a key of the selected definition: `path` a key or a list of keys
  // into it (["bar", "style"])
  function set(path, value) {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return;
    const keys = Array.isArray(path) ? path : [path];
    let target = def;
    for (const key of keys.slice(0, -1)) {
      if (target[key] === null || typeof target[key] !== "object")
        target[key] = {};
      target = target[key];
    }
    const last = keys[keys.length - 1];
    if (JSON.stringify(target[last]) === JSON.stringify(value))
      return;
    if (value === undefined)
      delete target[last];
    else
      target[last] = value;
    root._apply();
  }

  // The selected definition's command as a file to show, when its first
  // word is a path (~ and $HOME read); "" otherwise
  function scriptPath(command) {
    const first = String(command ?? "").trim().split(/\s+/)[0] ?? "";
    const path = first.replace(/^\$HOME\b|^\$\{HOME\}/, "~");
    return path.startsWith("/") || path.startsWith("~/") ? Paths.expandHome(path) : "";
  }

  // -- Private --
  property ConfigDraft _draft: ConfigDraft {
    path: ["CustomWidgets"]
  }

  function _local() {
    if (!_draft.local)
      _draft.local = {
        "items": []
      };
    if (!Array.isArray(_draft.local.items))
      _draft.local.items = [];
    return _draft.local;
  }

  // The selected definition's elements in the draft (made when missing),
  // or null without one
  function _elements() {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return null;
    if (!def.module || typeof def.module !== "object")
      def.module = {
        "size": [4, 2],
        "lockscreen": false,
        "elements": []
      };
    if (!Array.isArray(def.module.elements))
      def.module.elements = [];
    return def.module.elements;
  }

  function _load() {
    root.elements.clearHistory();
    _draft.load();
    ConfigManager.clearPreview("CustomWidgets");
    root.selectDefinition(root.selectedIndex);
  }

  // After an edit in place: shown live while the draft differs
  function _apply() {
    _draft.changed();
    if (_draft.isDirty)
      ConfigManager.setPreview("CustomWidgets", _draft.local);
    else
      ConfigManager.clearPreview("CustomWidgets");
  }

  // The selected definition runs while the page shows (its sample is
  // what the page binds from)
  readonly property string _running: root.pageShown ? root.selectedId : ""
  on_RunningChanged: CustomWidgetsManager.acquire(root, root._running)
}
