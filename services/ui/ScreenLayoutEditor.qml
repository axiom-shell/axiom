pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

// The layouts editor's draft of one screen layout (a ScreenLayout: the
// built-in lock screen's, LockManager.editor, or the greeter's,
// GreeterManager.editor): its modules on a bounded grid, edited through
// `layout`, its own fields, and its preview on screen. What really shows
// (a lock, the greeter) only ever reads the saved layout.
// A draft can hold several layouts (the desktop's, DesktopManager.editor:
// the Desktop section): `layoutOf` picks the one edited, `layoutsOf` lists
// them all for `problems`, and with a `previewSection` the draft shows
// live while it differs from the config.
// It's edited as it shows on one screen (`screen`, inside `insets`): on
// the units that fit there at its card size, each module kept to its
// nearest edge (OverlayConfig.screenArrangement). Loading it moves its
// places onto that grid in the draft and in what it's compared with, so
// it isn't changed until it's edited.
// Not a singleton: each owner holds one.
QtObject {
  id: root

  // The layout's config path, e.g. ["Lockscreen", "layout"]
  required property var path
  // The x-hosts name its modules must list ("lockscreen", "greeter")
  required property string host
  // What it's called in problems ("Lock screen")
  required property string name
  // The layout edited in the draft (`path`'s value), or null for none: the
  // draft itself unless it holds several
  property var layoutOf: local => local
  // Every layout in the draft, [{ layout, name }] (named in problems)
  property var layoutsOf: local => [
      {
        "layout": local,
        "name": root.name
      }
    ]
  // What's being edited in the draft (a key the grid's history and forms
  // start over on)
  property string scope: ""
  // The config section the draft is shown live as (ConfigManager.setPreview)
  // while it differs from the config, "" for none
  property string previewSection: ""

  // The screen it's edited on, and the room kept clear on each side there
  // ({ left, top, right, bottom } px: the desktop's bars and border)
  property var screen: General.screensNamed("")[0] ?? null
  property var insets: ({
      "left": 0,
      "top": 0,
      "right": 0,
      "bottom": 0
    })
  // Its room there, { width, height } px
  readonly property var room: root.screen ? {
    "width": Math.max(0, root.screen.width - root.insets.left - root.insets.right),
    "height": Math.max(0, root.screen.height - root.insets.top - root.insets.bottom)
  } : {
    "width": 0,
    "height": 0
  }
  // The grid it's edited on there ({ cols, rows }): the layout's own
  // once rebased onto the screen, or as far as it reaches when its
  // modules don't fit there by their edges
  readonly property var grid: GridPlacement.layoutReach((root.localLayout?.modules ?? []).map(module => module?.place ?? null), GridPlacement.screenGrid(root.localLayout?.grid))
  // The screen's own grid at the layout's card size, and its key: a
  // change (another screen, another card size, another layout) moves the
  // places onto it (rebase). Modules being moved don't change it, so the
  // grid never jumps under an edit
  readonly property var lattice: root.localLayout && root.screen ? OverlayConfig.screenArrangement(root.localLayout, [], root.screen, root.room.width, root.room.height) : null
  // Whether its modules had to shrink below the layout's Module size to
  // fit this screen, and to how much of it (%)
  readonly property var _shown: root.localLayout && root.screen ? OverlayConfig.screenArrangement(root.localLayout, root.localLayout.modules, root.screen, root.room.width, root.room.height) : null
  readonly property var shrunk: root._shown?.shrunk ?? false
  readonly property var shrunkTo: root._shown && root.lattice ? Math.round(100 * root._shown.unit / root.lattice.unit) : 100
  readonly property var _latticeKey: root.lattice ? [root.scope, root.lattice.cols, root.lattice.rows, root.grid.cols, root.grid.rows].join(":") : ""
  on_LatticeKeyChanged: Qt.callLater(root.rebase)

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: root.path
    onLocalChanged: root._syncPreview()
    onIsDirtyChanged: root._syncPreview()
  }
  // The whole draft, and the layout edited in it
  readonly property alias local: draft.local
  readonly property var localLayout: root.layoutOf(draft.local)
  readonly property var savedLayout: root.layoutOf(draft.saved)
  readonly property alias isDirty: draft.isDirty

  property GridEditor layout: GridEditor {
    host: root.host
    area: root.grid
    sizeScale: root.localLayout?.grid?.fine ? 2 : 1
    modulesOf: () => root.localLayout?.modules ?? null
    scopeKey: root.host + ":" + root.scope
    onEdited: draft.changed()
    // The layout's own settings (its Module size, grid, background, …)
    // go with each snapshot, so undoing one puts back the places it moved
    snapshotExtra: () => {
      const layout = root.localLayout;
      if (!layout)
        return null;
      const extra = {};
      Object.keys(layout).filter(key => key !== "modules").forEach(key => extra[key] = layout[key]);
      return extra;
    }
    restoreExtra: extra => {
      const layout = root.localLayout;
      if (layout && extra)
        Object.keys(extra).forEach(key => layout[key] = Utils.clone(extra[key]));
    }
  }

  // Why the draft can't be saved as is (empty = savable)
  readonly property var problems: draft.local ? [].concat(...root.layoutsOf(draft.local).map(entry => root.layout.problemsFor(entry.layout?.modules, entry.name, entry.layout === root.localLayout ? root.grid : GridPlacement.screenGrid(entry.layout?.grid)))) : []

  // Moves the edited layout's places onto the screen's grid, each kept to
  // its nearest edge (OverlayConfig.screenArrangement, shrunk as far as
  // that needs), in the draft and in what it's compared with alike, so it
  // stays unchanged until edited
  function rebase(keepHistory) {
    if (!root.screen || !draft.local)
      return;
    const move = layout => {
      if (!layout)
        return false;
      const modules = layout.modules ?? [];
      const shown = OverlayConfig.screenArrangement(layout, modules, root.screen, root.room.width, root.room.height);
      const from = GridPlacement.screenGrid(layout?.grid);
      if (from.cols === shown.cols && from.rows === shown.rows)
        return false;
      const scale = layout.grid.fine ? 2 : 1;
      if (shown.cols % scale !== 0 || shown.rows % scale !== 0)
        return false;
      modules.forEach((module, i) => {
        if (module && shown.places[i])
          module.place = shown.places[i];
      });
      layout.grid.columns = shown.cols / scale;
      layout.grid.rows = shown.rows / scale;
      return true;
    };
    const moved = move(root.layoutOf(draft.local));
    move(root.layoutOf(draft.saved));
    if (moved) {
      if (!keepHistory)
        root.layout.clearHistory();
      draft.changed();
    }
  }

  function _syncPreview() {
    if (root.previewSection === "")
      return;
    if (draft.isDirty)
      ConfigManager.setPreview(root.previewSection, draft.local);
    else
      ConfigManager.clearPreview(root.previewSection);
  }

  // Changes the draft in place (`change(local)`), as an edit
  function edit(change) {
    if (!draft.local)
      return;
    change(draft.local);
    draft.changed();
  }

  // Loads the draft unless it holds unsaved edits
  function ensureLoaded() {
    if (!draft.isDirty)
      root.resetChanges();
  }

  // One of the layout's own fields, by key or dotted path into its groups
  // ("moduleScale", "backdrop.source", "grid.fine"). Doubling the grid
  // (grid.fine; "fineGrid" too) rescales the modules' places so they stay
  // put
  function updateLayoutField(key, value) {
    const layout = root.localLayout;
    if (key === "fineGrid")
      key = "grid.fine";
    const parts = key.split(".");
    if (!layout || JSON.stringify(parts.reduce((v, part) => v?.[part], layout)) === JSON.stringify(value))
      return;
    // One undo step with the places it moves (snapshotExtra)
    root.layout.recordField(`layout:${key}`);
    if (key === "grid.fine") {
      (layout.modules ?? []).forEach(module => {
        if (module?.place)
          module.place = GridPlacement.scalePlace(module.place, value);
      });
    }
    const holder = parts.slice(0, -1).reduce((v, part) => {
      if (v[part] === undefined || v[part] === null)
        v[part] = {};
      return v[part];
    }, layout);
    holder[parts[parts.length - 1]] = value;
    // A new Module size or grid moves the places onto this screen's grid
    // now, inside that step, not later as an outside change would
    root.rebase(true);
    draft.changed();
  }

  // Merged onto the latest real config; stays dirty if rejected
  function saveChanges() {
    if (root.problems.length > 0)
      return false;
    return draft.save();
  }

  function resetChanges() {
    draft.load();
    root.layout.clearSelection();
    root.layout.clearHistory();
    root.rebase();
  }

  // --- Preview ---

  // The draft shown on the target screen in a plain window, with every
  // field and action inert
  readonly property bool previewing: root._previewing
  property bool _previewing: false
  // The screen it shows on: the target when it started, so it stays put
  readonly property string previewScreen: root._previewScreen
  property string _previewScreen: ""

  // Closes the overlay to show it
  function startPreview() {
    if (root._previewing)
      return;
    ShellManager.closeOverlay();
    root._previewScreen = ShellManager.targetFor();
    root._previewing = true;
  }

  // Back to the layouts editor, unless `reopen` is false
  function stopPreview(reopen) {
    if (!root._previewing)
      return;
    root._previewing = false;
    if (reopen !== false)
      ShellManager.openOverlayPage("Layouts");
  }
}
