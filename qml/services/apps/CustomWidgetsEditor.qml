pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.services.ui

// The Custom widgets page's editor (CustomWidgetsManager.editor): a draft of
// the CustomWidgets section, the selected definition, the layer being
// edited (the base elements, or one screen: module.views) and element, and
// the edits. Unsaved edits show live on the bars and modules through a preview,
// and the selected definition stays acquired while the page is shown, so
// its sample (CustomWidgetsManager.outputs) is there to bind from.
// Not a singleton: CustomWidgetsManager owns it, so what reads the manager
// waits for `pageShown`.
QtObject {
  id: root

  // --- The draft ---
  readonly property var items: _draft.local?.items ?? []
  readonly property bool isDirty: _draft.isDirty

  property int selectedIndex: 0
  readonly property var selected: items[selectedIndex] ?? null
  readonly property string selectedId: selected?.id ?? ""
  // The layer edited: -1 the base elements, else an index in module.views
  // (the page calls them screens)
  property int viewIndex: -1
  // The elements of the layer edited: what the canvas shows and edits
  readonly property var layerElements: root.selected?.module?.views?.[root.viewIndex]?.elements ?? (root.viewIndex >= 0 ? [] : root.selected?.module?.elements ?? [])
  // The selected element, or null
  readonly property var element: root.elements.selected >= 0 ? (root.layerElements[root.elements.selected] ?? null) : null

  // The selected definition's module elements on their lattice, edited as
  // the layouts editor edits a submenu's modules: moves, resizes, pushes,
  // the selection and undo (GridEditor; kept from the top left while the
  // definition has no screens, so the module's box fits its elements; with
  // screens every layer is placed absolutely, as they share one lattice;
  // and inside a module's largest, module.size's maximum of 8 units, so the
  // definition can be saved)
  readonly property GridEditor elements: GridEditor {
    modulesOf: () => root._elements()
    host: "overlay"
    area: ({
        "cols": 8 * CustomWidgetData.subCells,
        "rows": 8 * CustomWidgetData.subCells
      })
    shiftsBack: (root.selected?.module?.views?.length ?? 0) === 0
    scopeKey: root.selectedId + "/" + root.viewIndex
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

  // --- Samples (D1): one per screen, kept in the definition ---

  // The most samples and bytes (as JSON) a definition keeps
  readonly property var sampleLimits: ({
      "entries": 16,
      "bytes": 65536
    })
  // View key ("" none) -> the last live sample that picked it, and the
  // distinct `state` values seen live (the first 8): what the page has
  // watched since the definition was selected (never saved)
  property var seen: ({})
  property var seenStates: []
  // The live sample, the one Keep would save
  readonly property var liveSample: root.pageShown ? (CustomWidgetsManager.fields[root.selectedId]?.sample ?? null) : null
  // The key the edited layer's sample is kept under
  readonly property string sampleKey: CustomWidgetData.viewKey(root.selected?.module, root.viewIndex)
  // Why the live sample can't be kept ("count", "size"), or ""
  readonly property string keepRefused: root.liveSample === null ? "" : CustomWidgetData.keepSample(root.selected?.samples, root.sampleKey, root.liveSample, root.sampleLimits).refused
  // What the previews draw: the edited layer's sample, resolved (null: none yet)
  readonly property var previewFields: !root.pageShown ? null : CustomWidgetsManager.resolveSample(root.selectedId, root.previewSampleSource)

  // Keeps the live sample as the edited layer's. Returns why it couldn't
  // ("count", "size"), or ""
  function keepSample() {
    if (root.liveSample === null)
      return "";
    const kept = CustomWidgetData.keepSample(root.selected?.samples, root.sampleKey, root.liveSample, root.sampleLimits);
    if (kept.refused === "")
      root.set(["samples"], kept.samples);
    return kept.refused;
  }

  // Keeps `text` (JSON, an object) as the edited layer's sample. Returns why
  // it couldn't: "json" (not an object), "count", "size", or ""
  function saveSample(text) {
    let sample;
    try {
      sample = JSON.parse(text);
    } catch (e) {
      return "json";
    }
    if (sample === null || typeof sample !== "object" || Array.isArray(sample))
      return "json";
    const kept = CustomWidgetData.keepSample(root.selected?.samples, root.sampleKey, sample, root.sampleLimits);
    if (kept.refused === "")
      root.set(["samples"], kept.samples);
    return kept.refused;
  }

  // The sample the edited layer is previewed with, as JSON text to edit
  readonly property string sampleText: root.previewSampleSource === null ? "{}" : JSON.stringify(root.previewSampleSource, null, 2)
  readonly property var previewSampleSource: root.pageShown ? CustomWidgetData.sampleForView(root.selected, root.viewIndex, root.seen, CustomWidgetsManager.fields[root.selectedId] ?? null) : null
  // Where it comes from: "saved", "live" or "none"
  readonly property string sampleSource: root.pageShown ? CustomWidgetData.sampleSource(root.selected, root.viewIndex, root.seen, CustomWidgetsManager.fields[root.selectedId] ?? null) : "none"

  // --- Actions (the definition's actions.items; elements and the bar pick one by id) ---

  // What a trigger's combo offers: Nothing, each action of the definition
  // and "New action…" (value "__new", which newActionFor answers)
  readonly property var actionChoices: {
    const out = [
      {
        "value": "",
        "label": I18n.tr("Nothing")
      }
    ];
    for (const item of root.selected?.actions?.items ?? [])
      out.push({
        "value": item.id,
        "label": item.name || item.id,
        "icon": item.kind === "axiom" ? "bolt" : "terminal"
      });
    out.push({
      "value": "__new",
      "label": I18n.tr("New action…"),
      "icon": "add"
    });
    return out;
  }

  // The values an Axiom action takes, each with its label (the shell's
  // actions: never a session or destructive one, none that takes an
  // argument). Runtime keys: I18n.tr("Refresh this widget")
  // I18n.tr("Restart this widget") I18n.tr("Go to screen: Base")
  // I18n.tr("Go to screen: {0}")
  readonly property var axiomChoices: {
    const refused = ActionsManager.sessionActions.concat(KeybindManager.actions.filter(id => ActionsManager.destructive(id)));
    const views = root.selected?.module?.views ?? [];
    const shell = KeybindManager.actions.slice().sort((a, b) => ActionsManager.label(a).localeCompare(ActionsManager.label(b)));
    return CustomWidgetData.axiomValues(shell, refused, id => KeybindManager.needsArgument(id), views.map(v => v.id)).map(value => {
      let label;
      if (value === "refresh")
        label = I18n.tr("Refresh this widget");
      else if (value === "restart")
        label = I18n.tr("Restart this widget");
      else if (value === "screen:")
        label = I18n.tr("Go to screen: Base");
      else if (value.startsWith("screen:")) {
        const view = views.find(v => v.id === value.slice(7));
        label = I18n.tr("Go to screen: {0}", view?.name || view?.id || value.slice(7));
      } else
        label = ActionsManager.label(value);
      return {
        "value": value,
        "label": label
      };
    });
  }

  // The action ids of the page (an inline editor of one is open under its
  // trigger: page-only, never saved)
  property string editingAction: ""
  // The action whose row takes the focus in its name once it exists: the one
  // just added (the row clears it)
  property string focusAction: ""

  // How many triggers (elements' and the bar's) use action `id`
  function actionUses(id) {
    return CustomWidgetData.actionRefs(root.selected, id);
  }

  // A new action made of `fields` (name, kind, command…), added last, one
  // undo step. Returns its id ("" without a definition). Its name defaults
  // to "Action {n}"
  function addAction(fields) {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return "";
    const items = def.actions.items;
    const name = fields?.name || I18n.tr("Action {0}", items.length + 1);
    const item = ConfigManager.withDefaults(Object.assign({}, fields, {
      "id": Utils.newId(Utils.slug(name) || "action", items),
      "name": name
    }), "CustomWidgetAction");
    root._recordStructure();
    root.focusAction = item.id;
    items.push(item);
    root._apply();
    return item.id;
  }

  // Sets `key` of action `index` (typing in one field is one undo step)
  function setAction(index, key, value) {
    const item = root.selected?.actions?.items?.[index];
    if (!item || Utils.deepEqual(item[key], value))
      return;
    root.elements.recordField("def:action:" + item.id + ":" + key);
    root._write(["actions", "items", index, key], value);
  }

  // Removes action `index` and clears every trigger that named it, as one step
  function removeAction(index) {
    const def = root._local().items[root.selectedIndex];
    const item = def?.actions.items[index];
    if (!item)
      return;
    root._beforeStructure();
    const cleared = CustomWidgetData.withoutActionRefs(def, item.id);
    cleared.actions.items.splice(index, 1);
    // In place: the draft keeps its object
    root._restoreInto(def, cleared, []);
    if (root.editingAction === item.id)
      root.editingAction = "";
    root._apply();
  }

  // "New action…" in a trigger's combo: a command action named `name` (""
  // numbers it), picked through `writeRun(id)` (an element's trigger or the
  // bar's) and opened for editing under the trigger
  function newActionFor(name, writeRun) {
    const id = root.addAction(name !== "" ? {
      "name": name
    } : {});
    if (id === "")
      return;
    writeRun(id);
    root.editingAction = id;
  }

  // The paths the page offers to bind from (the saved samples, then what
  // was seen live, then the output now), each once
  readonly property var bindPaths: root.pageShown ? CustomWidgetData.bindChoices(Object.values(root.selected?.samples ?? ({})).concat(Object.values(root.seen), [root.liveSample]), 200) : []

  // Forgets the sample kept under `key`
  function removeSample(key) {
    const next = Object.assign({}, root.selected?.samples);
    delete next[key];
    root.set(["samples"], next);
  }

  // The last 20 action commands the selected definition ran or had refused
  // (CustomWidgetsManager.actionRan entries), oldest first: page-only, cleared
  // when another definition is selected
  property var actionLog: []

  // Test mode (D2): the module's preview runs its actions, keys and Entries
  // for real, against the real commands. Never saved; off each time the
  // page shows and for each definition
  property bool testMode: false

  // The page's tab: 0 data, 1 bar, 2 module, 3 help (selectTab)
  property int tab: 0
  // The Help section open ("output", "actions", "examples", "slots",
  // "lifetime", "failure", "waybar"; "" none)
  property string helpSection: "output"

  // Opens the Help tab at `section`
  function openHelp(section) {
    root.helpSection = section;
    root.selectTab(3);
  }

  function selectTab(index) {
    root.tab = index;
    root.focusAction = "";
  }

  // While the page shows, the selected definition runs
  property bool pageShown: false
  onPageShownChanged: root.testMode = false

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
    root.importing = false;
    root.gallery = false;
    root.copyNote = "";
    root.actionLog = [];
    root.editingAction = "";
    root.focusAction = "";
    root.viewIndex = -1;
    root.testMode = false;
    root.seen = {};
    root.seenStates = [];
    root.elements.clearSelection();
    root.elements.clearHistory();
  }

  // Edits screen `index` (-1: the base elements): its history and
  // selection start over
  function selectView(index) {
    const count = root.selected?.module?.views?.length ?? 0;
    root.viewIndex = index >= 0 && index < count ? index : -1;
    root.elements.clearSelection();
    root.elements.clearHistory();
  }

  // The screen just added: its form takes the focus in the name once it
  // exists (the form clears it; page-only)
  property bool focusScreenName: false

  // A new screen over the base, selected: shown only by a Go to screen
  // action unless `when` ({ key, test, values }) says otherwise; `base`
  // false draws it alone (without the base elements under it)
  function addView(name, when, base) {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return;
    const views = def.module.views;
    views.push({
      "id": Utils.newId(Utils.slug(name) || "screen", views),
      "name": name ?? "",
      "base": base !== false,
      "when": Object.assign({
        "key": "",
        "test": "is",
        "values": []
      }, when ?? {}),
      "elements": []
    });
    root._apply();
    root.selectView(views.length - 1);
  }

  function removeView(index) {
    const def = root._local().items[root.selectedIndex];
    if (!def || !def.module.views[index])
      return;
    const id = def.module.views[index].id;
    def.module.views.splice(index, 1);
    if (def.samples && id in def.samples)
      delete def.samples[id];
    root._apply();
    root.selectView(-1);
  }

  // The screens' structure edited from a chip's menu or an element's: one
  // undo step each, recorded under its own key (the history keeps the
  // whole definition but the edited layer's elements, so the base is the
  // layer edited while the screens' order or number changes)
  property int _structureSeq: 0
  function _recordStructure() {
    root.elements.recordField("def:structure:" + (++root._structureSeq));
  }
  function _beforeStructure() {
    if (root.viewIndex >= 0)
      root.selectView(-1);
    root._recordStructure();
  }

  // A copy of screen `index`, named "<name> (copy)", right after it (its
  // sample is not copied)
  function duplicateView(index) {
    const def = root._local().items[root.selectedIndex];
    const source = def?.module.views[index];
    if (!source)
      return;
    const copy = CustomWidgetData.viewCopy(def.module.views, index, I18n.tr("{0} (copy)", source.name || source.id));
    root._beforeStructure();
    def.module.views.splice(index + 1, 0, copy);
    root._fitSize();
    root._apply();
  }

  // Moves screen `from` to place `to` (they are tried in order: the first
  // whose condition holds is drawn)
  function moveView(from, to) {
    const def = root._local().items[root.selectedIndex];
    if (!def)
      return;
    const moved = CustomWidgetData.moveItem(def.module.views, from, to);
    if (moved === def.module.views)
      return;
    root._beforeStructure();
    def.module.views.splice(0, Infinity, ...moved);
    root._apply();
  }

  // The selected element, copied into the layer `target` (-1: the base,
  // else a screen's index) at the same place: a new id when it has one
  // there. Returns whether it was copied
  function copyElementToView(target) {
    const def = root._local().items[root.selectedIndex];
    const element = root.element;
    const list = target < 0 ? def?.module.elements : def?.module.views[target]?.elements;
    if (!element || !list || target === root.viewIndex)
      return false;
    root._recordStructure();
    list.push(CustomWidgetData.elementCopy(list, element));
    root._fitSize();
    root._apply();
    return true;
  }

  // Sets a key of the edited screen (`path` a key or a list of keys into it)
  function setView(path, value) {
    if (root.viewIndex < 0)
      return;
    const keys = ["module", "views", root.viewIndex].concat(path);
    if (Utils.deepEqual(root._valueAt(keys), value))
      return;
    root.elements.recordField("view:" + root.viewIndex + ":" + keys.slice(3).join("."));
    root._write(keys, value);
  }

  // Screen `index`'s condition key (an empty one: only a Go to screen
  // action shows it). The key "error" also sets the test to set and draws
  // the screen alone, as one undo step
  function setViewKey(index, key) {
    const view = root._local().items[root.selectedIndex]?.module.views[index];
    if (!view || view.when.key === key)
      return;
    if (key === "error") {
      root._recordStructure();
      root._write(["module", "views", index, "when", "key"], "error");
      root._write(["module", "views", index, "when", "test"], "set");
      root._write(["module", "views", index, "base"], false);
      return;
    }
    root._write(["module", "views", index, "when", "key"], key);
  }

  // Starts the module from the elements drawn while it has none (the base
  // of a definition with no screens)
  function useDefaultElements() {
    const def = root._local().items[root.selectedIndex];
    if (!def || root.viewIndex >= 0 || def.module.views.length > 0)
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
    const keys = root.layerPath().concat([index], path);
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
  // selected; `translate` false keeps its texts (an import's)
  function add(preset, translate) {
    const local = root._local();
    const base = Object.assign({
      "name": I18n.tr("Custom widget")
    }, translate === false ? preset : root.translated(preset ?? {}));
    // A gallery entry's own keys aren't a definition's
    delete base.template;
    delete base.description;
    base.id = Utils.newId(Utils.slug(base.name) || "widget", local.items);
    local.items.push(ConfigManager.withDefaults(base, "CustomWidget"));
    root._apply();
    root.selectDefinition(local.items.length - 1);
  }

  // A preset's English texts in the user's language: the typed texts, labels and
  // placeholders of its elements, and its actions' and screens' names (the keys
  // are listed in CustomWidgetData.presets' comment). A definition with no
  // such text, or a name no key matches, comes back as it is
  function translated(preset) {
    // The actions' names first (their keys are in the same comment)
    const def = !preset.actions?.items ? preset : Object.assign({}, preset, {
      "actions": Object.assign({}, preset.actions, {
        "items": preset.actions.items.map(action => Object.assign({}, action, {
            "name": action.name ? I18n.tr(action.name) : ""
          }))
      })
    });
    if (!def.module)
      return def;
    const elements = list => (list ?? []).map(element => {
        const bind = Object.assign({}, element.bind);
        for (const slot of ["text", "label", "placeholder"]) {
          if (typeof bind[slot] === "string" && bind[slot] !== "" && bind[slot].indexOf("{") < 0)
            bind[slot] = I18n.tr(bind[slot]);
        }
        return Object.assign({}, element, {
          "bind": bind
        });
      });
    const module = Object.assign({}, def.module, {
      "elements": elements(def.module.elements),
      "views": (def.module.views ?? []).map(view => Object.assign({}, view, {
          "name": view.name ? I18n.tr(view.name) : "",
          "elements": elements(view.elements)
        }))
    });
    return Object.assign({}, def, {
      "module": module
    });
  }

  // The Import form (ImportForm) or the template gallery (GalleryForm) is
  // open in the inspector pane, instead of the tabs
  property bool importing: false
  property bool gallery: false
  readonly property bool formOpen: root.importing || root.gallery

  function openImport() {
    root.gallery = false;
    root.importing = true;
  }

  function openGallery() {
    root.importing = false;
    root.gallery = true;
  }

  // The New flow's ends (the chooser, DefinitionsPanel): a blank widget for
  // a bar text from a script, on the Data tab
  function addBlank() {
    root.add({
      "bar": {
        "style": "label"
      }
    });
    root.selectTab(0);
  }

  // A known script's preset, on the Data tab
  function addScript(preset) {
    root.add(Object.assign({}, preset, {
      "name": I18n.tr(preset.name)
    }));
    root.selectTab(0);
  }

  // A gallery template, on the Module tab at its first screen
  function addTemplate(template) {
    root.add(Object.assign({}, template, {
      "name": I18n.tr(template.name)
    }));
    root.selectTab(2);
    if ((root.selected?.module?.views?.length ?? 0) > 0)
      root.selectView(0);
  }
  // What Copy just said ("" none), shown under the header until dismissed
  // or another definition is selected
  property string copyNote: ""

  // Adds the definitions an Import form read and confirmed (a shared
  // widget's, or a Waybar module's: CustomWidgetData.readImport), each with
  // a fresh id and as it is (no translation of its texts), selecting the
  // last, and closes the form. A schema error shows when the page saves
  function importDefinitions(definitions) {
    definitions.forEach(def => root.add(def, false));
    root.importing = false;
  }

  // Puts the selected definition on the clipboard as Copy's wrapper
  // (CustomWidgetData.exportOf: the definition less its id), and says what
  // it runs when that is a file outside this shell's tree, which the
  // receiver must be given by hand
  function copyDefinition() {
    const def = root.selected;
    if (!def)
      return;
    ClipboardManager.copyText(CustomWidgetData.exportOf(def));
    const outside = [];
    for (const c of CustomWidgetData.commandsOf(def)) {
      const path = root.scriptPath(c.command);
      if (path !== "" && !path.startsWith(Paths.treePath) && !outside.includes(path))
        outside.push(path);
    }
    root.copyNote = outside.length ? I18n.tr("Copied. It runs {0}: send those files by hand.", outside.join(", ")) : I18n.tr("Copied.");
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

  // Where the edited layer's elements are in the definition
  function layerPath() {
    return root.viewIndex >= 0 ? ["module", "views", root.viewIndex, "elements"] : ["module", "elements"];
  }

  // -- Private --

  // Each new output of the selected definition is the last one seen for the
  // screen it picks, and its state is one to offer a screen for
  property Connections _live: Connections {
    // Only while the page shows (the manager creates this editor)
    target: root.pageShown ? CustomWidgetsManager : null
    function onActionRan(id, entry) {
      if (id === root.selectedId)
        root.actionLog = CustomWidgetData.pushLog(root.actionLog, entry, 20);
    }
    function onFieldsChanged() {
      const fields = CustomWidgetsManager.fields[root.selectedId];
      const module = root.selected?.module;
      if (!fields || !module)
        return;
      const pick = CustomWidgetData.pickView(module, fields);
      // A failure no screen draws has no sample of its own
      if (pick.builtinError)
        return;
      const key = CustomWidgetData.viewKey(module, pick.index);
      if (!Utils.deepEqual(root.seen[key], fields.sample))
        root.seen = Object.assign({}, root.seen, {
          [key]: fields.sample
        });
      if (fields.state !== "" && root.seenStates.length < 8 && !root.seenStates.includes(fields.state))
        root.seenStates = root.seenStates.concat([fields.state]);
    }
  }

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

  // The selected definition for the undo history: all of it, the edited
  // layer's elements left out (null; the history keeps them as modules)
  function _definitionSnapshot() {
    const def = root._local()?.items[root.selectedIndex];
    if (!def)
      return null;
    const copy = Utils.clone(def);
    const path = root.layerPath();
    const holder = path.slice(0, -1).reduce((v, key) => v?.[key], copy);
    if (holder)
      holder[path[path.length - 1]] = null;
    return copy;
  }

  // Puts a snapshot's keys back into the selected definition in place (the
  // edited layer's elements are spliced back by the history already)
  function _restoreDefinition(extra) {
    const def = root._local()?.items[root.selectedIndex];
    if (!def || !extra)
      return;
    root._restoreInto(def, extra, root.layerPath());
  }

  // `from`'s keys into `target` (objects or lists), but for the array at
  // `skip` (a path of keys)
  function _restoreInto(target, from, skip) {
    const isList = Array.isArray(from);
    if (isList)
      target.length = from.length;
    else
      Object.keys(target).filter(key => !(key in from)).forEach(key => delete target[key]);
    for (const key of Object.keys(from)) {
      if (String(key) === String(skip[0]) && skip.length > 1 && target[key] !== null && typeof target[key] === "object")
        root._restoreInto(target[key], from[key], skip.slice(1));
      else if (!(String(key) === String(skip[0]) && skip.length === 1))
        target[key] = Utils.clone(from[key]);
    }
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
    const keys = root.layerPath();
    return keys.reduce((v, key) => v?.[key], root._local().items[root.selectedIndex]) ?? null;
  }

  // The size a page starts the module at follows its elements
  function _fitSize() {
    const def = root._local().items[root.selectedIndex];
    const all = CustomWidgetData.allElements(def?.module);
    if (def?.module && all.length)
      def.module.size = CustomWidgetData.pageSize(all, def.module.size);
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
