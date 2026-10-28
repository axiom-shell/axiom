pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods
import qs.services.core

// The Keybinds page's view state, kept past the page (it's rebuilt each
// time the overlay opens): the reference's search, chips and how it's
// shown (remembered, and followed by the Cheatsheet), the combo looked
// up, the editor's search and chips and what they leave showing, and the
// key map's modifiers. Not a singleton: KeybindManager holds one as
// `page`, beside its `editor` (KeybindEditor), whose binds it reads.
QtObject {
  id: root

  // The editor whose binds the editor's chips and list show
  // (KeybindManager.editor)
  property KeybindEditor editor

  // The reference's search and filter chips (KeybindFilter): section keys (KeybindFilter.sectionKey),
  // modifier names, sources ("axiom" | "user")
  property string query: ""
  property var sectionFilter: []
  property var modFilter: []
  property var sourceFilter: []
  readonly property bool filtering: sectionFilter.length > 0 || modFilter.length > 0 || sourceFilter.length > 0

  // The modifier chips: the modifiers the binds use, in
  // KeybindManager.modifierNames order
  readonly property var modOptions: {
    const used = {};
    for (const section of KeybindManager.keybindings)
      for (const row of section.binds)
        for (const combo of row.combos)
          for (const mod of combo.mods)
            used[mod] = true;
    return KeybindManager.modifierNames.filter(name => used[name]);
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
  // like a bind's key, into the editor's lookupIndex
  property string lookupCombo: ""

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

  // Numbered runs shown bind by bind (BindGroups.runKey of their first
  // bind -> true), for this session
  property var expandedRuns: ({})

  function toggleRun(key) {
    const next = Object.assign({}, root.expandedRuns);
    next[key] = !next[key];
    root.expandedRuns = next;
  }

  // An editor bind's section on the Keybinds page: its description's
  // "Section:" prefix, else its action's
  function _bindSection(bind) {
    return BindActions.hasOwnSection(bind.description) ? String(bind.description).split(":")[0] : BindActions.sectionFor(KeybindManager.actionTable, bind.action);
  }

  // An editor bind's modifiers, by the names the compositor's binds decode to
  function _bindMods(bind) {
    const id = BindKeys.keyId(bind.key);
    return id === "" ? [] : KeybindManager.decodeMods(parseInt(id));
  }

  // The editor's chips: [{ key, title, count }] per section (actionSections
  // order, then any others), and the modifiers its binds use
  readonly property var editSectionOptions: {
    const counts = {};
    for (const bind of root.editor.binds) {
      const section = root._bindSection(bind);
      counts[section] = (counts[section] ?? 0) + 1;
    }
    const others = Object.keys(counts).filter(section => !KeybindManager.actionSections.includes(section)).sort();
    return KeybindManager.actionSections.filter(section => counts[section]).concat(others).map(section => ({
          "key": section,
          "title": section,
          "count": counts[section]
        }));
  }
  readonly property var editModOptions: {
    const used = {};
    for (const bind of root.editor.binds)
      for (const mod of root._bindMods(bind))
        used[mod] = true;
    return KeybindManager.modifierNames.filter(name => used[name]);
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
    const state = index => (!issuesOnly && !pausedOnly) || (issuesOnly && root.editor.hasIssue(root.editor.issues[index])) || (pausedOnly && root.editor.binds[index].paused === true);
    return root.editor.binds.map((bind, index) => {
      const key = String(bind.key ?? "").trim();
      const label = KeybindManager.actionLabels[bind.action] ?? String(bind.action ?? "");
      return {
        "index": index,
        "section": root._bindSection(bind),
        "mods": root._bindMods(bind),
        "text": [key, KeybindManager.displayCombo(key), label, root._bindSection(bind), bind.argument ?? "", bind.description ?? "", BindActions.defaultLabel(KeybindManager.actionTable, bind)].join("\n").toLowerCase()
      };
    }).filter(row => (query === "" || row.text.includes(query)) && (sections.length === 0 || sections.includes(row.section)) && mods.every(mod => row.mods.includes(mod)) && state(row.index)).map(row => row.index).join(",");
  }
  readonly property int pausedCount: root.editor.binds.filter(bind => bind.paused === true).length
  readonly property var visibleIndices: visibleKey === "" ? [] : visibleKey.split(",").map(Number)

  // The shown binds by section, with numbered runs folded
  // (BindGroups.groups): [{ key, indices, rows: [[index]] }]. Through a
  // string, like visibleKey, so the sections only rebuild when it changes.
  readonly property string _layoutKey: JSON.stringify(BindGroups.groups(KeybindManager.actionTable, root.editor.binds, root.visibleIndices, root.editor.binds.map(bind => root._bindSection(bind)), KeybindManager.actionSections))
  readonly property var editLayout: JSON.parse(_layoutKey)

  // The modifiers the key map shows the keys under
  property var keyMapMods: ["SUPER"]

  function toggleKeyMapMod(mod) {
    root.keyMapMods = KeyNames.modifiers.filter(m => m === mod ? !root.keyMapMods.includes(m) : root.keyMapMods.includes(m));
  }

  Component.onCompleted: root._loadRefState()
}
