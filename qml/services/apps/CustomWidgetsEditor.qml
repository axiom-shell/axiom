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
  // The selected definition's module elements on their lattice, edited as
  // the layouts editor edits a submenu's modules: moves, resizes, pushes,
  // the selection and undo (GridEditor; kept from the top left, so the
  // module's box fits its elements, and inside a module's largest,
  // module.size's maximum of 8 units, so the definition can be saved)
  readonly property GridEditor elements: GridEditor {
    modulesOf: () => root._elements()
    host: "overlay"
    area: ({
        "cols": 8 * CustomWidgetData.subCells,
        "rows": 8 * CustomWidgetData.subCells
      })
    shiftsBack: true
    scopeKey: root.selectedId
    // The definition's own keys go with each snapshot (every one but the
    // elements, which the history keeps as modules), so undo covers an
    // edit to a format or an option as well as a move
    snapshotExtra: () => root._definitionSnapshot()
    restoreExtra: extra => root._restoreDefinition(extra)
    factory: ({
        "make": (type, place) => CustomWidgetsConfig.newElement(type, Utils.newId(type, root._elements()), place),
        "size": type => CustomWidgetsConfig.elementKind(type)?.size ?? [4, 4]
      })
    onEdited: {
      root._fitSize();
      root._apply();
    }
  }

  // The page's tab: 0 data, 1 bar, 2 module (selectTab)
  property int tab: 0

  function selectTab(index) {
    root.tab = index;
  }

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

  // Starts the module from the elements drawn while it has none
  function useDefaultElements() {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return;
    const fields = CustomWidgetsManager.fields[def.id];
    root._elements().splice(0, Infinity, ...CustomWidgetsConfig.defaultElements(def.module?.size, (fields?.ratio ?? -1) >= 0));
    root.elements.clearHistory();
    root._fitSize();
    root._apply();
  }

  // Sets a key of the selected element: `path` a list of keys into it
  // (["options", "color"])
  function setElement(path, value) {
    const index = root.elements.selected;
    if (index < 0)
      return;
    const keys = ["module", "elements", index].concat(path);
    if (Utils.deepEqual(root._valueAt(keys), value))
      return;
    // One undo step per field, typing in it included
    root.elements.recordField("el:" + index + ":" + path.join("."));
    root._write(keys, value);
  }

  // Whether a definition differs from its saved version (matched by id)
  function changed(index) {
    const item = root.items[index];
    const saved = (_draft.saved?.items ?? []).find(i => i.id === item?.id);
    return !saved || !Utils.deepEqual(saved, item);
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
    const keys = Array.isArray(path) ? path : [path];
    if (Utils.deepEqual(root._valueAt(keys), value))
      return;
    root.elements.recordField("def:" + keys.join("."));
    root._write(keys, value);
  }

  // The selected definition's command as a file to show, when its first
  // word is a path (~ and $HOME read); "" otherwise
  function scriptPath(command) {
    const first = String(command ?? "").trim().split(/\s+/)[0] ?? "";
    const path = first.replace(/^\$HOME\b|^\$\{HOME\}/, "~");
    return path.startsWith("/") || path.startsWith("~/") ? Paths.expandHome(path) : "";
  }

  // -- Private --

  // The selected definition's value at `keys`, undefined when absent
  function _valueAt(keys) {
    return keys.reduce((v, key) => v === null || typeof v !== "object" ? undefined : v[key], root._local().items[root.selectedIndex]);
  }

  // Sets the value at `keys` of the selected definition (undefined removes
  // it), making the objects on the way
  function _write(keys, value) {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return;
    let target = def;
    for (const key of keys.slice(0, -1)) {
      if (target[key] === null || typeof target[key] !== "object")
        target[key] = {};
      target = target[key];
    }
    const last = keys[keys.length - 1];
    if (value === undefined)
      delete target[last];
    else
      target[last] = value;
    root._apply();
  }

  // The selected definition for the undo history: all of it, its module's
  // elements left out (null; the history keeps them as modules)
  function _definitionSnapshot() {
    const def = root._local()?.items[root.selectedIndex];
    if (!def)
      return null;
    return Object.assign({}, def, {
      "module": Object.assign({}, def.module, {
        "elements": null
      })
    });
  }

  // Puts a snapshot's keys back into the selected definition in place
  // (its elements are spliced back by the history already)
  function _restoreDefinition(extra) {
    const def = root._local()?.items[root.selectedIndex];
    if (!def || !extra)
      return;
    const put = (target, from, keep) => {
      Object.keys(target).filter(key => key !== keep && !(key in from)).forEach(key => delete target[key]);
      Object.keys(from).filter(key => key !== keep).forEach(key => target[key] = Utils.clone(from[key]));
    };
    const module = extra.module;
    put(def, extra, "module");
    if (module)
      put(def.module, module, "elements");
  }

  property ConfigDraft _draft: ConfigDraft {
    path: ["CustomWidgets"]
    onRefused: root._apply()
  }

  // The draft (the CustomWidgets section, every default filled)
  function _local() {
    return _draft.local;
  }

  // The selected definition's elements in the draft, or null without one
  function _elements() {
    return root._local().items[root.selectedIndex]?.module.elements ?? null;
  }

  // The size a page starts the module at follows its elements
  function _fitSize() {
    const def = root._local().items[root.selectedIndex];
    if (def?.module && def.module.elements?.length)
      def.module.size = CustomWidgetData.pageSize(def.module.elements, def.module.size);
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
