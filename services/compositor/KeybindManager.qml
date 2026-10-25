pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

/*
 * KeybindManager reads the keybinds the compositor has registered
 * (CompositorManager.withBinds). Each bind's `description` is its label (on
 * Hyprland's Lua config every action is an opaque `__lua` dispatcher). A
 * "Section: Label" prefix picks the overlay section.
 *
 * Also the Keybinds page's editor for axiom's own binds (Keybinds.binds): a
 * draft saved with save(), per-bind issues, presets, and recording a key
 * combo (CompositorManager.captureKeys meanwhile, so the compositor's binds
 * don't swallow the keys being recorded).
 */
QtObject {
  id: root

  // [{ title, undescribed, binds: [{ label, combos: [{ mods: ["SUPER", "SHIFT"], keys: ["H", "←"] }], axiom, user, ids, action, overrides }] }]
  // `title` is "" for binds with no section (shown as "Other"); `undescribed`
  // marks the section of binds without a description (label ""). A row's
  // `axiom` / `user` say whether any of its binds are axiom's own (applied
  // from Keybinds.binds) / from the user's compositor config; `ids` are its
  // keys (BindKeys.keyId), `action` the first axiom bind's action and
  // `overrides` the label of an axiom bind skipped because the row holds
  // its key. Numbered runs and direction sets are folded (BindRows).
  readonly property var keybindings: root._buildKeybindings(root._entries, root._axiomIds, root._skippedLabels)
  // How many binds the compositor reported
  property int count: 0
  // The Keybinds page's search and filter chips (KeybindFilter), here so
  // they survive the page reloading: section keys (KeybindFilter.sectionKey),
  // modifier names, sources ("axiom" | "user")
  property string query: ""
  property var sectionFilter: []
  property var modFilter: []
  property var sourceFilter: []
  readonly property bool filtering: sectionFilter.length > 0 || modFilter.length > 0 || sourceFilter.length > 0

  // The modifier chips: the modifiers the binds use, in _modifiers order
  readonly property var modOptions: {
    const used = {};
    for (const section of root.keybindings)
      for (const row of section.binds)
        for (const combo of row.combos)
          for (const mod of combo.mods)
            used[mod] = true;
    return root._modifiers.map(m => m.name).filter(name => used[name]);
  }

  // group: "section" | "mod" | "source", or the editor's "editSection" |
  // "editMod"
  function toggleFilter(group, value) {
    const name = group + "Filter";
    const current = root[name];
    root[name] = current.includes(value) ? current.filter(v => v !== value) : current.concat([value]);
  }

  function clearFilters() {
    root.sectionFilter = [];
    root.modFilter = [];
    root.sourceFilter = [];
  }

  function clearEditFilters() {
    root.editSectionFilter = [];
    root.editModFilter = [];
    root.editIssuesOnly = false;
    root.editPausedOnly = false;
  }
  // The Keybinds page shows the editor instead of the list
  property bool editing: false

  // --- The reference (the page's list, the Cheatsheet) ---

  // How it's shown, remembered: "list" | "keyboard", "comfortable" |
  // "compact", and modifiers as glyphs (⇧ ⌃ ⌥) or words
  readonly property string refView: root._refView
  readonly property string refDensity: root._refDensity
  readonly property bool refGlyphs: root._refGlyphs
  property string _refView: "list"
  property string _refDensity: "comfortable"
  property bool _refGlyphs: true
  // Folded modifier groups, by "<section key>|<mods>" (refGroupKey)
  readonly property var refFolded: root._refFolded
  property var _refFolded: []
  readonly property var _refState: StateManager.createStateHandler("keybindsReference")

  function setRefView(value) {
    root._refView = value === "keyboard" ? "keyboard" : "list";
    root._saveRefState();
  }

  function setRefDensity(value) {
    root._refDensity = value === "compact" ? "compact" : "comfortable";
    root._saveRefState();
  }

  function setRefGlyphs(value) {
    root._refGlyphs = value === true;
    root._saveRefState();
  }

  function refGroupKey(section, mods) {
    return KeybindFilter.sectionKey(section) + "|" + mods.join("+");
  }

  function toggleRefFold(key) {
    root._refFolded = root._refFolded.includes(key) ? root._refFolded.filter(k => k !== key) : root._refFolded.concat([key]);
    root._saveRefState();
  }

  function _saveRefState() {
    root._refState.save({
      "view": root._refView,
      "density": root._refDensity,
      "glyphs": root._refGlyphs,
      "folded": root._refFolded
    });
  }

  function _loadRefState() {
    const saved = root._refState.load({});
    root._refView = saved.view === "keyboard" ? "keyboard" : "list";
    root._refDensity = saved.density === "compact" ? "compact" : "comfortable";
    root._refGlyphs = saved.glyphs !== false;
    root._refFolded = Array.isArray(saved.folded) ? saved.folded : [];
  }

  // A combo pressed to look up what it does ("SUPER + Q"), or "": recorded
  // like a bind's key, into lookupIndex
  readonly property int lookupIndex: -2
  property string lookupCombo: ""

  // --- The editor ---

  // The editor's search, here so it survives the page reloading. It only
  // changes what's shown: the saved order stays as it is.
  property string editQuery: ""
  // The editor's chips: sections, modifier names, and binds with issues or
  // paused ones (either, when both are on)
  property var editSectionFilter: []
  property var editModFilter: []
  property bool editIssuesOnly: false
  property bool editPausedOnly: false
  readonly property bool editFiltering: editSectionFilter.length > 0 || editModFilter.length > 0 || editIssuesOnly || editPausedOnly
  // Rows can be dragged into another order only while every bind shows
  readonly property bool reorderable: editQuery.trim() === "" && !editFiltering

  // The bind the inspector edits, or -1 (the key map shows instead)
  property int selectedIndex: -1
  readonly property var selectedBind: root.binds[root.selectedIndex] ?? null

  // Selects a bind; the list scrolls to it unless `reveal` is false (a
  // click on its own row, which shows already)
  function selectBind(index, reveal) {
    if (index === root.selectedIndex)
      return;
    stopRecording();
    root.selectedIndex = index >= 0 && index < root.binds.length ? index : -1;
    if (root.selectedIndex >= 0 && reveal !== false)
      root.reveal(root.selectedIndex);
  }

  // Asks the list to unfold and scroll to a bind, centred
  signal revealRequested(int index)
  // The bind asked for, until its row has scrolled to it, or -1: a row
  // built after the ask (the editor opening, a run unfolding) scrolls to
  // itself when it's this one
  readonly property int revealIndex: root._revealIndex
  property int _revealIndex: -1

  function reveal(index) {
    root._revealIndex = index;
    root.revealRequested(index);
  }

  // A row has scrolled to bind `index`
  function revealDone(index) {
    if (root._revealIndex === index)
      root._revealIndex = -1;
  }

  // Opens the editor on a bind (a click on it in the reference, the
  // keyboard, a Cheatsheet), showing it even if the search or chips hid it
  function editBind(index) {
    if (index < 0 || index >= root.binds.length)
      return;
    if (!root.visibleIndices.includes(index)) {
      root.editQuery = "";
      clearEditFilters();
    }
    root.editing = true;
    stopRecording();
    root.selectedIndex = index;
    root.reveal(index);
  }

  // Numbered runs shown bind by bind (BindGroups.runKey of their first
  // bind -> true), for this session
  property var expandedRuns: ({})

  function toggleRun(key) {
    const next = Object.assign({}, root.expandedRuns);
    next[key] = !next[key];
    root.expandedRuns = next;
  }

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: ["Keybinds", "binds"]
  }
  // [{ key, action, argument, description }]
  readonly property var binds: draft.local ?? []
  readonly property alias isDirty: draft.isDirty

  readonly property var _actionSchema: ConfigManager.configSchema?.definitions?.Keybind?.properties?.action ?? ({})
  readonly property var actions: _actionSchema.enum ?? []
  // Action -> its label (translated; the schema's labels are keys already)
  readonly property var _actionLabelSchema: _actionSchema["x-enumLabels"] ?? ({})
  readonly property var actionLabels: Object.keys(_actionLabelSchema).reduce((labels, action) => {
    const english = _actionLabelSchema[action];
    labels[action] = I18n.tr(english);
    return labels;
  }, {})

  // The action picker's categories, in tab order ("" is All). `exec` is
  // filed under Apps there; everything else by its section on the page.
  // I18n.tr("Axiom") I18n.tr("Apps") I18n.tr("Media") I18n.tr("Window")
  // I18n.tr("Workspace") I18n.tr("Special") I18n.tr("Custom")
  readonly property var actionSections: ["Axiom", "Apps", "Media", "Window", "Workspace", "Special", "Custom"]

  // Material Symbols per reference section, by title ("" is Other)
  function sectionIcon(title) {
    return root._sectionIcons[title] ?? "keyboard";
  }
  readonly property var _sectionIcons: ({
      "Axiom": "dashboard",
      "Apps": "apps",
      "Media": "music_note",
      "Window": "select_window",
      "Workspace": "grid_view",
      "Special": "star",
      "Custom": "tune",
      "": "more_horiz"
    })

  // Material Symbols per action (the picker and its button)
  readonly property var _actionIcons: ({
      "launcher": "apps",
      "launcherSearch": "search",
      "overlay": "dashboard",
      "overlayPage": "web_stories",
      "edgeMenu": "side_navigation",
      "dock": "dock_to_bottom",
      "workspaceOverview": "grid_view",
      "powerMenu": "power_settings_new",
      "lock": "lock",
      "toggleDnd": "do_not_disturb_on",
      "clearNotifications": "clear_all",
      "idleInhibit": "coffee",
      "nightLight": "nightlight",
      "nextWallpaper": "wallpaper",
      "workspaceStep": "swap_horiz",
      "moveWindowStep": "move_item",
      "moveWindowStepSilent": "send",
      "workspaceNth": "counter_1",
      "moveWindowNth": "move_item",
      "moveWindowNthSilent": "send",
      "scrollStep": "mouse",
      "focusDir": "center_focus_strong",
      "moveWindowDir": "open_with",
      "resizeWindow": "open_in_full",
      "closeWindow": "close",
      "fullscreen": "fullscreen",
      "toggleFloat": "picture_in_picture",
      "pin": "push_pin",
      "centerWindow": "center_focus_weak",
      "toggleGroup": "tab_group",
      "pseudo": "picture_in_picture_alt",
      "toggleSplit": "splitscreen_right",
      "stripSwapColumn": "swap_horiz",
      "stripWider": "width_wide",
      "stripNarrower": "width_normal",
      "stripFit": "fit_screen",
      "stripConsume": "move_group",
      "stripCenter": "vertical_align_center",
      "windowSwitcher": "tab",
      "windowSwitcherReverse": "tab",
      "mouseDrag": "drag_pan",
      "mouseResize": "drag_handle",
      "toggleSpecial": "star",
      "moveToSpecial": "star_half",
      "restartShell": "restart_alt",
      "volumeUp": "volume_up",
      "volumeDown": "volume_down",
      "toggleMute": "volume_off",
      "toggleMicMute": "mic_off",
      "brightnessUp": "brightness_high",
      "brightnessDown": "brightness_low",
      "mediaPlayPause": "play_pause",
      "mediaNext": "skip_next",
      "mediaPrevious": "skip_previous",
      "mediaStop": "stop",
      "terminal": "terminal",
      "fileManager": "folder",
      "browser": "language",
      "screenshot": "screenshot_region",
      "screenRecord": "videocam",
      "exitSession": "logout",
      "exec": "code",
      "raw": "data_object"
    })

  // [{ action, label, section, icon }], one per action, in schema order
  // The actions the running compositor can do (BindActions.needs); a saved
  // bind with another keeps it, flagged in `issues`
  readonly property var actionInfo: root.actions.filter(action => BindActions.supported(action, CompositorManager.supports)).map(action => ({
        "action": action,
        "label": root.actionLabels[action] ?? action,
        "section": action === "exec" ? "Apps" : BindActions.sectionFor(action),
        "icon": root._actionIcons[action] ?? "keyboard"
      }))

  function actionIcon(action) {
    return root._actionIcons[action] ?? "keyboard";
  }

  // The argument an action starts with when picked (else empty)
  readonly property var _argumentDefaults: BindActions.argumentDefaults

  // What an action's free-text argument is, for its placeholder
  function argumentKind(action) {
    return BindActions.argumentKind(action);
  }

  function needsArgument(action) {
    return BindActions.needsArgument(action);
  }

  // How many workspaces a number can name: the layout's, or ten where the
  // compositor makes them itself (CompositorManager.dynamicWorkspaces)
  readonly property int _workspaceKeys: CompositorManager.dynamicWorkspaces ? 10 : WorkspacesConfig.size

  // The choices for an action's argument, or null for free text
  function argumentOptions(action) {
    switch (BindActions.argumentKind(action)) {
    case "direction":
      return ["left", "right", "up", "down"];
    case "workspace":
      return Array.from({
        "length": root._workspaceKeys
      }, (_, i) => String(i + 1));
    case "screenshot":
      return ["region", "window", "screen"];
    case "edgeMenu":
      return EdgeMenusConfig.menus.map(menu => menu.id).filter(id => id);
    case "dock":
      return DockConfig.docks.map(dock => dock.id);
    case "view":
      return OverlayConfig.views.filter(view => view.visible !== false).map(view => view.name || view.type).concat(["Layouts"]).filter((name, i, all) => all.indexOf(name) === i);
    }
    return null;
  }

  // The choices for an action's call, or null when it has none
  function callOptions(action) {
    return BindActions.hasCalls(action) ? ["toggle", "open", "close"] : null;
  }

  // A call's label for an action (a caffeine or night light bind turns it
  // on or off, a recording bind starts or stops it)
  function callLabels(action) {
    const onOff = action === "idleInhibit" || action === "nightLight";
    const record = action === "screenRecord";
    return {
      "toggle": I18n.tr("Toggle"),
      "open": record ? I18n.tr("Start") : onOff ? I18n.tr("Turn on") : I18n.tr("Open"),
      "close": record ? I18n.tr("Stop") : onOff ? I18n.tr("Turn off") : I18n.tr("Close")
    };
  }

  // An editor bind's section on the Keybinds page: its description's
  // "Section:" prefix, else its action's
  function _bindSection(bind) {
    return BindActions.hasOwnSection(bind.description) ? String(bind.description).split(":")[0] : BindActions.sectionFor(bind.action);
  }

  // An editor bind's modifiers, by the names the compositor's binds decode to
  function _bindMods(bind) {
    const id = BindKeys.keyId(bind.key);
    return id === "" ? [] : root._decodeMods(parseInt(id));
  }

  // The editor's chips: [{ key, title, count }] per section (actionSections
  // order, then any others), and the modifiers its binds use
  readonly property var editSectionOptions: {
    const counts = {};
    for (const bind of root.binds) {
      const section = root._bindSection(bind);
      counts[section] = (counts[section] ?? 0) + 1;
    }
    const others = Object.keys(counts).filter(section => !root.actionSections.includes(section)).sort();
    return root.actionSections.filter(section => counts[section]).concat(others).map(section => ({
          "key": section,
          "title": section,
          "count": counts[section]
        }));
  }
  readonly property var editModOptions: {
    const used = {};
    for (const bind of root.binds)
      for (const mod of root._bindMods(bind))
        used[mod] = true;
    return root._modifiers.map(m => m.name).filter(name => used[name]);
  }

  // The shown binds' indices, filtered by editQuery and the chips, in the
  // saved order, joined: a string only notifies when it changes, so the
  // rows survive edits that leave the list alone
  readonly property string visibleKey: {
    const query = root.editQuery.trim().toLowerCase();
    const sections = root.editSectionFilter;
    const mods = root.editModFilter;
    const issuesOnly = root.editIssuesOnly;
    const pausedOnly = root.editPausedOnly;
    const state = index => (!issuesOnly && !pausedOnly) || (issuesOnly && root.hasIssue(root.issues[index])) || (pausedOnly && root.binds[index].paused === true);
    return root.binds.map((bind, index) => {
      const key = String(bind.key ?? "").trim();
      const label = root.actionLabels[bind.action] ?? String(bind.action ?? "");
      return {
        "index": index,
        "section": root._bindSection(bind),
        "mods": root._bindMods(bind),
        "text": [key, root.displayCombo(key), label, root._bindSection(bind), bind.argument ?? "", bind.description ?? "", BindActions.defaultLabel(bind)].join("\n").toLowerCase()
      };
    }).filter(row => (query === "" || row.text.includes(query)) && (sections.length === 0 || sections.includes(row.section)) && mods.every(mod => row.mods.includes(mod)) && state(row.index)).map(row => row.index).join(",");
  }
  readonly property int pausedCount: root.binds.filter(bind => bind.paused === true).length
  readonly property var visibleIndices: visibleKey === "" ? [] : visibleKey.split(",").map(Number)

  // The shown binds by section, with numbered runs folded
  // (BindGroups.groups): [{ key, indices, rows: [[index]] }]. Through a
  // string, like visibleKey, so the sections only rebuild when it changes.
  readonly property string _layoutKey: JSON.stringify(BindGroups.groups(root.binds, root.visibleIndices, root.binds.map(bind => root._bindSection(bind)), root.actionSections))
  readonly property var editLayout: JSON.parse(_layoutKey)

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    draft.loadIfStale();
    refresh();
    CompositorConfigManager.previewMerge();
  }

  // Binds added, duplicated, merged or restored from a preset have no id
  // of their own yet (or another's): each gets one as it's saved
  function save() {
    stopRecording();
    draft.local = BindKeys.withIds(draft.local);
    draft.save();
  }

  function reset() {
    stopRecording();
    draft.load();
  }

  // A bind with every field, its flags from its action unless given
  function _completeBind(bind) {
    const action = bind?.action ?? "launcher";
    const flags = BindActions.actionFlags[action] ?? [];
    const full = {
      "key": "",
      "action": action,
      "argument": "",
      "call": "toggle",
      "description": ""
    };
    for (const flag of BindActions.flagNames)
      full[flag] = flags.includes(flag);
    full.paused = false;
    return Object.assign(full, bind ?? {});
  }

  // A bind's name in a sentence: its combo, else its action
  function _bindName(bind) {
    return root.displayCombo(bind?.key) || (root.actionLabels[bind?.action] ?? String(bind?.action ?? ""));
  }

  // --- Where each bind came from, and undo ---

  // Per draft bind, its index in the saved list, or -1 for a new one: what
  // a row's unsaved dot and Revert compare with. Every edit that adds,
  // removes or moves binds keeps it; it's matched afresh when the draft
  // loads or saves.
  property var _origins: []
  // Edits that can be undone, latest last: [{ text, local, origins, selected }]
  property var _undo: []
  // What Undo would take back, or ""
  readonly property string undoText: _undo.length > 0 ? _undo[_undo.length - 1].text : ""

  property Connections _draftWatch: Connections {
    target: draft

    function onSavedChanged() {
      root._matchOrigins();
      root._undo = [];
      if (root.selectedIndex >= (draft.local ?? []).length)
        root.selectedIndex = -1;
    }
  }

  function _matchOrigins() {
    const saved = (draft.saved ?? []).map(bind => JSON.stringify(bind));
    const used = saved.map(() => false);
    root._origins = (draft.local ?? []).map(bind => {
      const text = JSON.stringify(bind);
      const at = saved.findIndex((entry, i) => !used[i] && entry === text);
      if (at >= 0)
        used[at] = true;
      return at;
    });
  }

  // Per bind, whether it's new or differs from the bind it was when saved
  readonly property var changedBinds: {
    const saved = draft.saved ?? [];
    const origins = root._origins;
    return root.binds.map((bind, i) => {
      const origin = origins[i] ?? -1;
      return origin < 0 || JSON.stringify(bind) !== JSON.stringify(saved[origin]);
    });
  }

  // Puts a bind back as it was saved, or removes it if it's new
  function revertBind(index) {
    const origin = root._origins[index] ?? -1;
    if (origin < 0) {
      removeBind(index);
      return;
    }
    stopRecording();
    draft.local[index] = Utils.clone(draft.saved[origin]);
    draft.changed();
  }

  // Before an edit Undo can take back
  function _remember(text) {
    root._undo = root._undo.slice(-19).concat([
      {
        "text": text,
        "local": Utils.clone(draft.local),
        "origins": root._origins.slice(),
        "selected": root.selectedIndex
      }
    ]);
  }

  function undo() {
    const last = root._undo[root._undo.length - 1];
    if (!last)
      return;
    stopRecording();
    root._undo = root._undo.slice(0, -1);
    draft.local = last.local;
    root._origins = last.origins;
    root.selectedIndex = last.selected;
    draft.changed();
  }

  function dismissUndo() {
    root._undo = [];
  }

  // Inserts a bind (its saved index `origin`, -1 when new), keeping the
  // selection on the same bind
  function _insertAt(index, bind, origin) {
    draft.local.splice(index, 0, bind);
    const origins = root._origins.slice();
    origins.splice(index, 0, origin);
    root._origins = origins;
    if (root.selectedIndex >= index)
      root.selectedIndex++;
  }

  function _removeAt(index) {
    draft.local.splice(index, 1);
    const origins = root._origins.slice();
    origins.splice(index, 1);
    root._origins = origins;
    if (root.selectedIndex === index)
      root.selectedIndex = -1;
    else if (root.selectedIndex > index)
      root.selectedIndex--;
  }

  // --- Editing ---

  // Adds a bind at the end and selects it. Returns its index.
  function addBind(bind) {
    // So the new row shows
    editQuery = "";
    clearEditFilters();
    stopRecording();
    const index = draft.local.length;
    _insertAt(index, _completeBind(bind), -1);
    draft.changed();
    root.selectedIndex = index;
    root.reveal(index);
    return index;
  }

  // Adds a bind and records its key
  function addAndStartRecording(bind) {
    const index = addBind(bind);
    Qt.callLater(() => root.startRecording(index));
    return index;
  }

  // Adds `bind`, then opens the Keybinds page's editor recording its key
  // (the layouts editor's Add a keybind)
  function addAndRecord(bind) {
    ensureLoaded();
    root.editing = true;
    ShellManager.openOverlayPage("Keybinds");
    addAndStartRecording(bind);
  }

  // A copy of a bind after it, with no key yet, selected and recording
  function duplicateBind(index) {
    const bind = draft.local[index];
    if (!bind)
      return;
    stopRecording();
    const copy = Utils.clone(bind);
    copy.key = "";
    _insertAt(index + 1, copy, -1);
    draft.changed();
    root.selectedIndex = index + 1;
    Qt.callLater(() => root.startRecording(index + 1));
  }

  function removeBind(index) {
    const bind = draft.local[index];
    if (!bind)
      return;
    _remember(I18n.tr("Removed {0}", root._bindName(bind)));
    stopRecording();
    _removeAt(index);
    draft.changed();
  }

  // Moves a bind to `to` (its index after the move)
  function moveBind(from, to) {
    if (from === to || to < 0 || to >= draft.local.length || from < 0 || from >= draft.local.length)
      return;
    const selected = root.selectedIndex === from;
    const origin = root._origins[from] ?? -1;
    const bind = draft.local[from];
    _removeAt(from);
    _insertAt(to, bind, origin);
    if (selected)
      root.selectedIndex = to;
    draft.changed();
  }

  // Pauses or resumes binds (a section's, a run's, one)
  function setPaused(indices, on) {
    const changing = indices.filter(index => draft.local[index] && (draft.local[index].paused === true) !== on);
    if (changing.length === 0)
      return;
    if (changing.length > 1)
      _remember(on ? I18n.tr("Paused {0} binds", changing.length) : I18n.tr("Resumed {0} binds", changing.length));
    for (const index of changing)
      draft.local[index].paused = on;
    draft.changed();
  }

  function setField(index, field, value) {
    const bind = draft.local[index];
    if (!bind || bind[field] === value)
      return;
    bind[field] = value;
    // An argument meant for the old action rarely fits the new one, and
    // the flags follow the new action
    if (field === "action") {
      // A raw command is written for the compositor running now
      if (value === "raw")
        bind.compositor = CompositorManager.kind || "hyprland";
      const options = argumentOptions(value);
      if (!needsArgument(value) || (options && !options.includes(bind.argument)))
        bind.argument = _argumentDefaults[value] ?? "";
      if (!BindActions.hasCalls(value))
        bind.call = "toggle";
      const flags = BindActions.actionFlags[value] ?? [];
      for (const flag of BindActions.flagNames)
        bind[flag] = flags.includes(flag);
    }
    draft.changed();
  }

  // Keys the compositor binds outside axiom, by BindKeys.keyId: every bind
  // it reports, less the saved axiom binds the layer applied
  readonly property var _userKeyCounts: BindKeys.userKeyCounts(root._entries, root._appliedBinds)
  readonly property var userKeyCounts: root._userKeyCounts

  // The modifiers the key map shows the keys under
  property var keyMapMods: ["SUPER"]

  function toggleKeyMapMod(mod) {
    root.keyMapMods = KeyNames.modifiers.filter(m => m === mod ? !root.keyMapMods.includes(m) : root.keyMapMods.includes(m));
  }

  // The saved axiom binds the runtime layer applied (the rest it skipped)
  readonly property var _appliedBinds: {
    const skipped = CompositorConfigManager.skippedKeys.map(key => BindKeys.keyId(key));
    return KeybindsConfig.activeBinds.filter(bind => CompositorConfigManager.isComplete(bind) && !skipped.includes(BindKeys.keyId(bind.key)));
  }

  // Their keys, by BindKeys.keyId: { "64:return": bind }
  readonly property var _axiomIds: root._appliedBinds.reduce((ids, bind) => {
    const id = BindKeys.keyId(bind.key);
    if (id !== "")
      ids[id] = bind;
    return ids;
  }, {})

  // The saved axiom binds skipped because the user's config holds their
  // key, their labels by key: { "64:q": "Close window" }
  readonly property var _skippedLabels: {
    const skipped = CompositorConfigManager.skippedKeys.map(key => BindKeys.keyId(key));
    return KeybindsConfig.activeBinds.reduce((labels, bind) => {
      const id = BindKeys.keyId(bind.key);
      if (id !== "" && skipped.includes(id) && labels[id] === undefined)
        labels[id] = root.bindLabel(bind);
      return labels;
    }, {});
  }

  // A bind's label: its own (less a "Section:" prefix), else its action's
  function bindLabel(bind) {
    const own = String(bind?.description ?? "").trim();
    if (own !== "")
      return BindActions.hasOwnSection(own) ? own.slice(own.indexOf(":") + 1).trim() : own;
    return BindActions.defaultLabel(bind) || (root.actionLabels[bind?.action] ?? "");
  }

  // The first of the editor's binds (not paused) on one of `ids` (a
  // reference row's keys), or -1
  function bindIndexFor(ids) {
    return root.binds.findIndex(bind => !bind.paused && (ids ?? []).includes(BindKeys.keyId(bind.key)));
  }

  // Per bind: [{ level: "error" | "warning" | "info", text }]; only errors
  // and warnings are issues (issueCount, the issues filter, a row's border)
  readonly property var issues: {
    const ids = root.binds.map(bind => BindKeys.keyId(bind.key));
    // Paused binds hold no key, so they clash with nothing
    const counts = {};
    ids.forEach((id, i) => {
      if (id !== "" && !root.binds[i].paused)
        counts[id] = (counts[id] ?? 0) + 1;
    });
    const runtime = CompositorConfigManager.status !== "loaded";
    return root.binds.map((bind, i) => {
      if (bind.paused)
        return [
          {
            "level": "info",
            "text": I18n.tr("Paused, so it isn't bound")
          }
        ];
      const found = [];
      const key = String(bind.key ?? "").trim();
      if (key === "")
        found.push({
          "level": "warning",
          "text": I18n.tr("No key yet, so it isn't bound")
        });
      else if (ids[i] === "")
        found.push({
          "level": "error",
          "text": I18n.tr("Unknown modifier in \"{0}\"", key)
        });
      if (root.needsArgument(bind.action) && String(bind.argument ?? "").trim() === "")
        found.push({
          "level": "warning",
          "text": I18n.tr("Needs an argument, so it isn't bound")
        });
      // The switcher picks when its modifier is released
      if (BindActions.switcherSteps[bind.action] !== undefined && key !== "" && BindActions.switcherHeld(KeyNames.split(key).mods).length === 0)
        found.push({
          "level": "warning",
          "text": I18n.tr("Needs a modifier to hold, like ALT + Tab")
        });
      // A bind the compositor carries out itself (niri's Mod + drag) isn't
      // bound by axiom, but works on the compositor's own combo
      const builtIn = CompositorManager.builtInBinds[bind.action];
      if (builtIn !== undefined && key !== "")
        found.push(BindKeys.keyId(builtIn) === ids[i] ? {
          "level": "info",
          "text": I18n.tr("{0} does this itself, on this combo", CompositorManager.displayName)
        } : {
          "level": "warning",
          "text": I18n.tr("{0} only does this on {1}", CompositorManager.displayName, root.displayCombo(builtIn))
        });
      else if (!BindActions.keySupported(key, CompositorManager.supports))
        found.push({
          "level": "warning",
          "text": I18n.tr("{0} can't bind a modifier on its own", CompositorManager.displayName)
        });
      else if (!BindActions.appliesUnder(bind, CompositorManager.kind, CompositorManager.supports))
        found.push({
          "level": "warning",
          "text": bind.action === "raw" ? I18n.tr("Written for another compositor, so it does nothing here") : I18n.tr("This compositor can't do this, so it isn't bound")
        });
      else
      // Binds the layout leaves doing nothing: the strip ones with no strip,
      // Hyprland's split toggle (dwindle's) on its scrolling layout
      if (bind.action.startsWith("strip") && CompositorManager.supports.stripsAlways !== true && !WorkspacesConfig.hasStrips)
        found.push({
          "level": "info",
          "text": I18n.tr("Only does something on the scrolling layout")
        });
      else if (bind.action === "toggleSplit" && WorkspacesConfig.scrolling && CompositorManager.supports.strips === true && CompositorManager.supports.splitToggle === true)
        found.push({
          "level": "info",
          "text": I18n.tr("Does nothing on the scrolling layout")
        });
      // A modifier on its own fires when it's let go with no other key
      // between, whatever the bind's release flag says
      if (KeyNames.tapModifier(key) !== "" && BindActions.keySupported(key, CompositorManager.supports))
        found.push({
          "level": "info",
          "text": I18n.tr("Fires when tapped on its own")
        });
      if (ids[i] !== "" && counts[ids[i]] > 1)
        found.push({
          "level": "error",
          "text": I18n.tr("Bound more than once here")
        });
      if (ids[i] !== "" && root._userKeyCounts[ids[i]] > 0)
        found.push({
          "level": "warning",
          "text": runtime ? I18n.tr("Your compositor config uses this key, so it's skipped") : I18n.tr("Your compositor config binds this key too")
        });
      return found;
    });
  }

  readonly property int issueCount: issues.filter(found => root.hasIssue(found)).length

  // Whether a bind's `issues` hold an error or warning, not only notes
  function hasIssue(found) {
    return (found ?? []).some(issue => issue.level !== "info");
  }

  // The binds on keys the user's compositor config binds too
  readonly property var userConflicts: root.binds.map((bind, index) => {
    const id = bind.paused ? "" : BindKeys.keyId(bind.key);
    return id !== "" && root._userKeyCounts[id] > 0 ? index : -1;
  }).filter(index => index >= 0)

  // Removes every bind on a key the user's compositor config binds too (until
  // Save, like any edit). Returns how many.
  function removeUserConflicts() {
    const indices = root.userConflicts;
    if (indices.length === 0)
      return 0;
    _remember(I18n.tr("Removed {0} binds", indices.length));
    stopRecording();
    for (let i = indices.length - 1; i >= 0; i--)
      _removeAt(indices[i]);
    draft.changed();
    return indices.length;
  }

  // Managed mode moves the user's binds into axiom instead of dropping
  // axiom's (CompositorConfigManager.mergeUserBinds)
  readonly property bool canMerge: CompositorConfigManager.mode === "managed"
  // How many binds in user/ a Merge would move (0 until looked at,
  // when the page opens): not every bind there can (a Lua function, a
  // shared module's, one in a submap), so it's not the conflict count
  readonly property int mergeableCount: Math.max(0, CompositorConfigManager.mergeable)

  function mergeUserBinds() {
    stopRecording();
    CompositorConfigManager.mergeUserBinds();
  }

  // Moved binds are saved at once: a draft with unsaved edits takes them
  // too (so its Save keeps them), else it starts over from the config
  property Connections _mergeWatch: Connections {
    target: CompositorConfigManager

    function onBindsMerged(binds) {
      if (!draft.isDirty) {
        draft.load();
        return;
      }
      const complete = binds.map(bind => root._completeBind(bind));
      draft.local = BindKeys.mergeBinds(draft.local, complete);
      draft.saved = BindKeys.mergeBinds(draft.saved, complete);
      draft.changed();
    }

    function onLastMergeChanged() {
      root.refreshSoon();
    }
  }

  // --- Presets ---

  // Presets leave descriptions empty: each bind gets its action's label
  // and section (BindActions.descriptionFor)
  function _workspaceBind(key, action, argument) {
    return {
      "key": key,
      "action": action,
      "argument": argument,
      "description": ""
    };
  }

  // [{ id, title, description, binds }], for the current workspace layout.
  readonly property var presets: {
    const count = Math.min(10, root._workspaceKeys);
    const numbers = Array.from({
      "length": count
    }, (_, i) => i + 1);
    const digit = n => n === 10 ? "0" : String(n);
    const list = [
      {
        "id": "essentials",
        "title": I18n.tr("Essentials"),
        "description": I18n.tr("Launcher, overlay, workspace overview, power menu, lock"),
        "binds": [root._workspaceBind("SUPER + space", "launcher", ""), root._workspaceBind("SUPER + Tab", "overlay", ""), root._workspaceBind("SUPER + SHIFT + space", "workspaceOverview", ""), root._workspaceBind("SUPER + Escape", "powerMenu", ""), root._workspaceBind("SUPER + CTRL + L", "lock", "")]
      },
      {
        "id": "numbers",
        "title": I18n.tr("Workspaces 1–{0}", count),
        "description": I18n.tr("SUPER + a number, with SHIFT to take the window"),
        "binds": [].concat(...numbers.map(n => [root._workspaceBind("SUPER + " + digit(n), "workspaceNth", String(n)), root._workspaceBind("SUPER + SHIFT + " + digit(n), "moveWindowNth", String(n))]))
      }
    ];
    // A grid goes four ways; so do dynamic workspaces, up and down the
    // output's list and left and right to the next output
    const grid = CompositorManager.workspaceGrid;
    const dynamic = CompositorManager.dynamicWorkspaces;
    const directions = grid || dynamic ? [["Up", "W", "up"], ["Left", "A", "left"], ["Down", "S", "down"], ["Right", "D", "right"]] : [["Left", "A", "left"], ["Right", "D", "right"]];
    const stepBinds = (mods, keyIndex) => [].concat(...directions.map(d => [root._workspaceBind(mods + d[keyIndex], "workspaceStep", d[2]), root._workspaceBind(mods + "SHIFT + " + d[keyIndex], "moveWindowStep", d[2])]));
    if (grid || dynamic)
      list.push({
        "id": "wasd",
        "title": grid ? I18n.tr("Grid with WASD") : I18n.tr("Workspaces with WASD"),
        "description": grid ? I18n.tr("Around the grid with SUPER + W A S D") : I18n.tr("Workspaces on SUPER + W S, monitors on A D"),
        "binds": stepBinds("SUPER + ", 1)
      });
    list.push({
      "id": "arrows",
      "title": grid ? I18n.tr("Grid with arrows") : dynamic ? I18n.tr("Workspaces with arrows") : I18n.tr("Previous and next"),
      "description": grid ? I18n.tr("Around the grid with SUPER + CTRL + arrows") : dynamic ? I18n.tr("Workspaces and monitors with SUPER + CTRL + arrows") : I18n.tr("Workspaces with SUPER + CTRL + left and right"),
      "binds": stepBinds("SUPER + CTRL + ", 0)
    });
    // Along the strip where there is one, else through the workspaces
    const scrollBinds = [root._workspaceBind("SUPER + mouse_down", "scrollStep", "right"), root._workspaceBind("SUPER + mouse_up", "scrollStep", "left")];
    const vim = [["h", "left"], ["j", "down"], ["k", "up"], ["l", "right"]];
    const resize = {
      "h": "-50 0",
      "j": "0 50",
      "k": "0 -50",
      "l": "50 0"
    };
    list.push({
      "id": "windows",
      "title": I18n.tr("Window management"),
      "description": I18n.tr("Focus, move and resize on H J K L; close, fullscreen, float, mouse"),
      "binds": [].concat(...vim.map(d => [root._workspaceBind("SUPER + " + d[0], "focusDir", d[1]), root._workspaceBind("SUPER + SHIFT + " + d[0], "moveWindowDir", d[1]), root._workspaceBind("SUPER + ALT + " + d[0], "resizeWindow", resize[d[0]])])).concat([root._workspaceBind("SUPER + C", "closeWindow", ""), root._workspaceBind("SUPER + F", "fullscreen", ""), root._workspaceBind("SUPER + Z", "toggleFloat", ""), root._workspaceBind("SUPER + mouse:272", "mouseDrag", ""), root._workspaceBind("SUPER + mouse:273", "mouseResize", "")]).concat(scrollBinds)
    });
    // Workspaces on the left hand's W S and the right's H L, focus on the
    // other keys of each: [key, a workspace step, direction]. It rebinds
    // those keys (`replaces`), which the defaults give other actions
    const southpaw = [["W", true, "up"], ["S", true, "down"], ["A", false, "left"], ["D", false, "right"], ["H", true, "left"], ["L", true, "right"], ["J", false, "down"], ["K", false, "up"]];
    if (grid || dynamic)
      list.push({
        "id": "southpaw",
        "title": I18n.tr("Southpaw"),
        "description": I18n.tr("Workspaces on W S and H L, focus on A D and J K"),
        "replaces": true,
        "binds": [].concat(...southpaw.map(b => [root._workspaceBind("SUPER + " + b[0], b[1] ? "workspaceStep" : "focusDir", b[2]), root._workspaceBind("SUPER + SHIFT + " + b[0], b[1] ? "moveWindowStep" : "moveWindowDir", b[2])]))
      });
    if (WorkspacesConfig.hasStrips)
      list.push({
        "id": "strips",
        "title": I18n.tr("Strips"),
        "description": I18n.tr("Swap, widen, narrow and fit columns; scroll along the strip"),
        "binds": [root._workspaceBind("SUPER + bracketleft", "stripSwapColumn", "left"), root._workspaceBind("SUPER + bracketright", "stripSwapColumn", "right"), root._workspaceBind("SUPER + equal", "stripWider", ""), root._workspaceBind("SUPER + minus", "stripNarrower", ""), root._workspaceBind("SUPER + CTRL + F", "stripFit", "")].concat(scrollBinds)
      });
    list.push({
      "id": "switcher",
      "title": I18n.tr("Window switcher"),
      "description": I18n.tr("ALT + Tab through your windows, most recent first"),
      "binds": [root._workspaceBind("ALT + Tab", "windowSwitcher", ""), root._workspaceBind("ALT + SHIFT + Tab", "windowSwitcherReverse", "")]
    });
    list.push({
      "id": "media",
      "title": I18n.tr("Media keys"),
      "description": I18n.tr("Volume, brightness and playback keys, with the OSD"),
      "binds": [root._workspaceBind("XF86AudioRaiseVolume", "volumeUp", ""), root._workspaceBind("XF86AudioLowerVolume", "volumeDown", ""), root._workspaceBind("XF86AudioMute", "toggleMute", ""), root._workspaceBind("XF86AudioMicMute", "toggleMicMute", ""), root._workspaceBind("XF86MonBrightnessUp", "brightnessUp", ""), root._workspaceBind("XF86MonBrightnessDown", "brightnessDown", ""), root._workspaceBind("XF86AudioPlay", "mediaPlayPause", ""), root._workspaceBind("XF86AudioPause", "mediaPlayPause", ""), root._workspaceBind("XF86AudioNext", "mediaNext", ""), root._workspaceBind("XF86AudioPrev", "mediaPrevious", ""), root._workspaceBind("XF86AudioStop", "mediaStop", "")]
    });
    return list;
  }

  // The saved presets (Keybinds.presets), shaped like the built-in ones:
  // [{ id ("saved:" + its own), title, binds, saved }]
  readonly property var savedPresets: KeybindsConfig.presets.map(preset => ({
        "id": "saved:" + preset.id,
        "title": preset.name,
        "description": "",
        "binds": preset.binds,
        "saved": true
      }))

  function _presetById(id) {
    return root.presets.find(p => p.id === id) ?? root.savedPresets.find(p => p.id === id) ?? null;
  }

  // What a preset would do, bind by bind: [{ bind, id (its key's
  // BindKeys.keyId), status, takenBy, chosen }]. `status` is "new", "same"
  // (a bind already does just this), "taken" (`takenBy` holds the binds on
  // that key, which applying it pauses) or "resume" (a paused bind does
  // just this: `takenBy` holds it); paused binds hold no key, so they take
  // nothing. `chosen` is the default, taken keys only for a preset that
  // `replaces`.
  function presetPlan(id) {
    const preset = root._presetById(id);
    if (!preset)
      return [];
    const ids = draft.local.map(bind => BindKeys.keyId(bind.key));
    const same = (a, b) => a.action === b.action && String(a.argument ?? "") === String(b.argument ?? "");
    return preset.binds.map(bind => {
      const id = BindKeys.keyId(bind.key);
      const on = ids.map((each, i) => each === id ? i : -1).filter(i => i >= 0);
      const active = on.filter(i => draft.local[i].paused !== true);
      const resumable = on.filter(i => draft.local[i].paused === true && same(draft.local[i], bind));
      let status = "new";
      let takenBy = [];
      if (active.some(i => same(draft.local[i], bind)))
        status = "same";
      else if (active.length > 0) {
        status = "taken";
        takenBy = active;
      } else if (resumable.length > 0) {
        status = "resume";
        takenBy = resumable.slice(0, 1);
      }
      return {
        "bind": bind,
        "id": id,
        "status": status,
        "takenBy": takenBy,
        "chosen": status === "new" || status === "resume" || (status === "taken" && preset.replaces === true)
      };
    });
  }

  // Applies a preset's binds whose keys (BindKeys.keyId) are in `ids`: new
  // ones at the end, taken ones after the binds on their key, which pause.
  // Returns { added, paused, resumed }.
  function applyPreset(id, ids) {
    const plan = presetPlan(id).filter(step => step.status !== "same" && ids.includes(step.id));
    const preset = root._presetById(id);
    const done = {
      "added": 0,
      "paused": 0,
      "resumed": 0
    };
    if (plan.length === 0)
      return done;
    _remember("");
    stopRecording();
    // Pauses and resumes first, while the indices hold
    for (const step of plan) {
      if (step.status === "resume") {
        draft.local[step.takenBy[0]].paused = false;
        done.resumed++;
      } else if (step.status === "taken") {
        for (const index of step.takenBy)
          draft.local[index].paused = true;
        done.paused += step.takenBy.length;
      }
    }
    // A taken key's new bind goes after the last bind it pauses, the
    // furthest first so the nearer positions still hold
    const inserts = plan.filter(step => step.status === "taken").map(step => ({
          "at": Math.max(...step.takenBy) + 1,
          "bind": _completeBind(Utils.clone(step.bind))
        })).sort((a, b) => b.at - a.at);
    for (const insert of inserts)
      _insertAt(insert.at, insert.bind, -1);
    for (const step of plan.filter(step => step.status === "new"))
      _insertAt(draft.local.length, _completeBind(Utils.clone(step.bind)), -1);
    done.added = inserts.length + plan.filter(step => step.status === "new").length;
    // Undo's strip says what it did
    const last = root._undo[root._undo.length - 1];
    if (done.resumed > 0)
      last.text = I18n.tr("{0}: added {1}, paused {2}, resumed {3}", preset.title, done.added, done.paused, done.resumed);
    else if (done.paused > 0)
      last.text = I18n.tr("{0}: added {1}, paused {2}", preset.title, done.added, done.paused);
    else
      last.text = I18n.tr("{0}: added {1}", preset.title, done.added);
    root._undo = root._undo.slice();
    draft.changed();
    return done;
  }

  // Puts a saved preset's binds in place of all of them (an unsaved edit,
  // like any other)
  function restorePreset(id) {
    const preset = root._presetById(id);
    if (!preset)
      return;
    _remember(I18n.tr("Restored {0}", preset.title));
    stopRecording();
    draft.local = preset.binds.map(bind => _completeBind(Utils.clone(bind)));
    root.selectedIndex = -1;
    root._matchOrigins();
    draft.changed();
  }

  // Saves the binds as they are in the editor (unsaved edits too) as a
  // preset, in place of the one by that name if there is one. Saved at
  // once, apart from the draft. Returns its id ("saved:…"), or "".
  function savePreset(name) {
    const title = String(name ?? "").trim();
    if (title === "")
      return "";
    const list = Utils.clone(KeybindsConfig.presets);
    const binds = BindKeys.withIds(Utils.clone(draft.local));
    let entry = list.find(preset => preset.name === title);
    if (entry)
      entry.binds = binds;
    else {
      entry = {
        "id": Date.now().toString(36),
        "name": title,
        "binds": binds
      };
      list.push(entry);
    }
    return root._commitPresets(list) ? "saved:" + entry.id : "";
  }

  function renamePreset(id, name) {
    const title = String(name ?? "").trim();
    if (title === "")
      return false;
    return root._commitPresets(KeybindsConfig.presets.map(preset => "saved:" + preset.id === id ? Object.assign({}, preset, {
        "name": title
      }) : preset));
  }

  function deletePreset(id) {
    return root._commitPresets(KeybindsConfig.presets.filter(preset => "saved:" + preset.id !== id));
  }

  function _commitPresets(list) {
    return SettingsManager.commitValues({
      "Keybinds.presets": list
    });
  }

  // --- Recording a key combo ---

  // The bind whose key is being recorded, or -1
  property int recordingIndex: -1

  // Meanwhile every key reaches the recorder instead of a bind
  // (CompositorManager.captureKeys)
  function startRecording(index) {
    if (root.recordingIndex === index)
      return;
    if (root.recordingIndex === -1)
      CompositorManager.captureKeys(true);
    root.recordingIndex = index;
    _recordTimeout.restart();
  }

  function finishRecording(combo) {
    if (root.recordingIndex === root.lookupIndex)
      root.lookupCombo = combo;
    else if (root.recordingIndex >= 0) {
      setField(root.recordingIndex, "key", combo);
      if (KeyNames.tapModifier(combo) !== "")
        setField(root.recordingIndex, "release", true);
    }
    stopRecording();
  }

  function stopRecording() {
    if (root.recordingIndex === -1)
      return;
    root.recordingIndex = -1;
    _recordTimeout.stop();
    CompositorManager.captureKeys(false);
  }

  property Timer _recordTimeout: Timer {
    interval: 25000
    onTriggered: root.stopRecording()
  }

  readonly property var _modifiers: [
    {
      name: "SUPER",
      mask: 64
    },
    {
      name: "CTRL",
      mask: 4
    },
    {
      name: "ALT",
      mask: 8
    },
    {
      name: "SHIFT",
      mask: 1
    },
    {
      name: "MOD2",
      mask: 16
    },
    {
      name: "MOD3",
      mask: 32
    },
    {
      name: "MOD5",
      mask: 128
    },
    {
      name: "CAPS",
      mask: 2
    },
  ]

  readonly property var _keyNames: ({
      "mouse:272": "LMB",
      "mouse:273": "RMB",
      "mouse:274": "MMB",
      "mouse_up": "Scroll ↑",
      "mouse_down": "Scroll ↓",
      "mouse_left": "Scroll ←",
      "mouse_right": "Scroll →",
      "super_l": "Super L",
      "super_r": "Super R",
      "control_l": "Ctrl L",
      "control_r": "Ctrl R",
      "alt_l": "Alt L",
      "alt_r": "Alt R",
      "shift_l": "Shift L",
      "shift_r": "Shift R",
      "left": "←",
      "right": "→",
      "up": "↑",
      "down": "↓"
    })

  // Every bind the compositor reported (CompositorManager.withBinds)
  property var _entries: []

  function refresh() {
    if (!CompositorManager.supports.bindMerge)
      return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    CompositorManager.withBinds(binds => {
      root._reading = false;
      if (binds) {
        root._entries = binds;
        root.count = binds.length;
      }
      if (root._readAgain) {
        root._readAgain = false;
        root.refresh();
      }
    });
  }

  property bool _reading: false
  property bool _readAgain: false

  // After binds were applied at runtime, which no compositor announces
  function refreshSoon() {
    _refreshDelay.restart();
  }

  property Timer _refreshDelay: Timer {
    interval: 500
    onTriggered: root.refresh()
  }

  function _buildKeybindings(entries, axiomIds, skippedLabels) {
    const sections = [];
    const sectionByTitle = {};
    const rowByKey = {};
    let undescribed = null;

    for (const entry of entries) {
      const description = (entry.description || "").trim();
      const split = description.indexOf(": ");
      let title;
      let label;

      if (!description) {
        title = null;
        label = "";
      } else if (split > 0) {
        title = description.slice(0, split).trim();
        label = description.slice(split + 2).trim();
      } else {
        title = entry.submap || "";
        label = description;
      }

      let section = title === null ? undescribed : sectionByTitle[title];
      if (!section) {
        section = {
          title: title ?? "",
          undescribed: title === null,
          binds: []
        };
        if (title === null)
          undescribed = section;
        else {
          sectionByTitle[title] = section;
          sections.push(section);
        }
      }

      const mods = root._decodeMods(entry.modmask);
      const key = root._formatKey(entry.key);
      const rowKey = `${section.title}\u0000${label}`;
      const id = BindKeys.entryId(entry);
      // Axiom's runtime binds are never in a submap
      const axiomBind = entry.submap ? undefined : axiomIds[id];
      const isAxiom = !!axiomBind;

      // Undescribed binds each get their own row, since they share an empty label.
      // Alternatives with the same modifiers share a combo: Super + H / ←.
      const row = label ? rowByKey[rowKey] : undefined;
      if (row) {
        row.axiom = row.axiom || isAxiom;
        row.user = row.user || !isAxiom;
        row.ids.push(id);
        row.action = row.action || (axiomBind?.action ?? "");
        row.overrides = row.overrides || (isAxiom ? "" : skippedLabels[id] ?? "");
        const combo = row.combos.find(c => c.mods.join("+") === mods.join("+"));
        if (!combo)
          row.combos.push({
            mods: mods,
            keys: [key]
          });
        else if (!combo.keys.includes(key))
          combo.keys.push(key);
        continue;
      }
      const newRow = {
        label: label,
        combos: [
          {
            mods: mods,
            keys: [key]
          }
        ],
        axiom: isAxiom,
        user: !isAxiom,
        ids: [id],
        action: axiomBind?.action ?? "",
        overrides: isAxiom ? "" : skippedLabels[id] ?? ""
      };
      if (label)
        rowByKey[rowKey] = newRow;
      section.binds.push(newRow);
    }

    if (undescribed)
      sections.push(undescribed);
    for (const section of sections)
      section.binds = BindRows.collapseDirections(BindRows.collapseNumbered(section.binds));
    return sections;
  }

  function _decodeMods(modmask) {
    return root._modifiers.filter(m => (modmask & m.mask) !== 0).map(m => m.name);
  }

  // A combo as shown on the page ("SUPER + mouse:272" -> "SUPER + LMB")
  function displayCombo(combo) {
    const key = String(combo ?? "").trim();
    return key === "" ? "" : key.split("+").map(part => root.displayKey(part.trim())).join(" + ");
  }

  // A key name as shown on a keycap ("space" -> "Space", "left" -> "←")
  function displayKey(key) {
    return _formatKey(String(key ?? ""));
  }

  function _formatKey(key) {
    if (root._keyNames[key.toLowerCase()] !== undefined)
      return root._keyNames[key.toLowerCase()];
    const mapped = KeyMap.labelOf(key);
    if (mapped !== "")
      return mapped;
    // XF86AudioPause -> Pause, XF86MonBrightnessUp -> Brightness Up
    if (key.startsWith("XF86"))
      return Utils.spaceWords(key.slice(4).replace(/^(Audio|Mon)(?=[A-Z])/, ""));
    if (key.length === 1)
      return key.toUpperCase();
    return key.charAt(0).toUpperCase() + key.slice(1);
  }

  property Connections _compositorEvents: Connections {
    target: CompositorManager

    function onConfigReloaded() {
      root.refresh();
    }
  }

  // Read as soon as the compositor is known to list its binds: created
  // early in the shell's start, this can come before
  // CompositorManager.supports is filled in, and a refresh then does nothing
  readonly property bool _canRead: CompositorManager.supports.bindMerge === true
  on_CanReadChanged: refresh()
  Component.onCompleted: {
    _loadRefState();
    refresh();
  }
}
