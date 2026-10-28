pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

// The Keybinds page's editor of axiom's own binds (Keybinds.binds): a
// draft saved with save(), the selected bind, undo, per-bind issues,
// conflicts and merges with the user's compositor config, presets, and
// recording a key combo (CompositorManager.captureKeys meanwhile, so the
// compositor's binds don't swallow the keys being recorded). Not a
// singleton: KeybindManager holds one as `editor`; what the page shows of
// it is its `page` (KeybindsPageState).
QtObject {
  id: root

  // The page's view state (KeybindManager.page): the editor clears its
  // chips to show a bind, and opens the page's editing mode
  property KeybindsPageState page

  // The bind the inspector edits, or -1 (the key map shows instead)
  property int selectedIndex: -1

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
    if (!root.page.visibleIndices.includes(index)) {
      root.page.editQuery = "";
      root.page.clearEditFilters();
    }
    root.page.editing = true;
    stopRecording();
    root.selectedIndex = index;
    root.reveal(index);
  }

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: ["Keybinds", "binds"]
  }
  // [{ key, action, argument, description }]
  readonly property var binds: draft.local ?? []
  readonly property alias isDirty: draft.isDirty

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    draft.loadIfStale();
    KeybindManager.refresh();
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
    return KeybindManager.displayCombo(bind?.key) || (KeybindManager.actionLabels[bind?.action] ?? String(bind?.action ?? ""));
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
    root.page.editQuery = "";
    root.page.clearEditFilters();
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
    root.page.editing = true;
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
      const options = KeybindManager.argumentOptions(value);
      if (!KeybindManager.needsArgument(value) || (options && !options.includes(bind.argument)))
        bind.argument = BindActions.argumentDefaults[value] ?? "";
      if (!BindActions.hasCalls(value))
        bind.call = "toggle";
      const flags = BindActions.actionFlags[value] ?? [];
      for (const flag of BindActions.flagNames)
        bind[flag] = flags.includes(flag);
    }
    draft.changed();
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
      if (KeybindManager.needsArgument(bind.action) && String(bind.argument ?? "").trim() === "")
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
          "text": I18n.tr("{0} only does this on {1}", CompositorManager.displayName, KeybindManager.displayCombo(builtIn))
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
      if (ids[i] !== "" && KeybindManager.userKeyCounts[ids[i]] > 0)
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
    return id !== "" && KeybindManager.userKeyCounts[id] > 0 ? index : -1;
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
      KeybindManager.refreshSoon();
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
    const count = Math.min(10, KeybindManager.workspaceKeys);
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

  // The bind whose key is being recorded, or -1; lookupIndex while
  // recording the page's lookup combo (KeybindsPageState.lookupCombo)
  property int recordingIndex: -1
  readonly property int lookupIndex: -2

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
      root.page.lookupCombo = combo;
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
}
