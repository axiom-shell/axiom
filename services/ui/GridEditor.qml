pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

/* Editing of one grid of modules (each with a `place` { x, y, w, h } in
 * quarter cards), shared by the layouts editor's overlay pages and edge
 * menus. Not a singleton: OverlayManager and its EdgeMenuEditor each own one,
 * point `modulesOf` at the live modules array in their draft and run their
 * draft's changed() on `edited`.
 *
 * Also holds the selection, since the editor page is unloaded whenever the
 * overlay closes. Every edit keeps the selection on its module and shifts
 * the grid so its top left module sits at 0, 0: a place left of or above
 * the grid (negative x or y) makes room there. A grid with an `area` (the
 * lock screen's) is bounded instead: places are absolute, inside it.
 * Required module types (`x-required`) are never removed or duplicated.
 *
 * Drops, moves and resizes are worked out first as a plan (planAdd,
 * planMove, planResize), which the canvas shows while dragging and
 * applyPlan() makes: a module put onto others pushes them along `pushDir`.
 * Every edit can be undone (undo/redo; the owner calls clearHistory()
 * when it reloads the modules). */
QtObject {
  id: root

  // Returns the modules array being edited (mutated in place), or null
  property var modulesOf: () => null
  // Where the modules are shown: "overlay", "edgeMenu" or "lockscreen"
  // (x-hosts)
  property string host: "overlay"
  // A bounded grid ({ cols, rows }): modules stay inside it where they
  // are put, and the grid never shifts. null: it grows and shifts back
  // to 0, 0 after every edit
  property var area: null
  // An edge menu's screen around its grid (GridPlacement.screenBox) and
  // its edge: the screen along the edge is what its modules are centred
  // on (guideFrame). null for a page or a submenu
  property var screenBox: null
  property string edge: ""
  // How many of this grid's units make one of a card's quarters (2 on a
  // doubled lock screen grid): new modules' default sizes scale by it
  property int sizeScale: 1
  // Axes ({ x, y }, each optional) on which a gap before the modules
  // stays rather than being shifted away after an edit (a whole-edge
  // menu's, along its edge: the gap is part of where it sits)
  property var hold: ({})
  // Which way modules a drop lands on are pushed ({ x, y }, one of them 1
  // or -1): down on a page, along an edge menu's edge
  property var pushDir: ({
      "x": 0,
      "y": 1
    })
  // What's being edited (a page, a menu): forms are rebuilt when it changes
  property string scopeKey: ""

  // Called in every edit, as the grid shifts back to 0, 0: with the shift
  // taken off ({ x, y } grid units, a place left of or above the grid
  // being negative) and how far the modules reached before the edit
  // (GridPlacement.bounds), so an owner can keep them where they were
  property var shifted: (shift, boundsBefore) => {}

  // After every edit: the owner marks its draft changed
  signal edited

  // Index of the selected module, -1 for none (or for a group)
  readonly property int selected: root._selected
  property int _selected: -1
  // Indices of a group of modules selected together (two or more; a box
  // dragged on the canvas, or Shift/Ctrl+click), else []: moved, nudged
  // and removed together
  readonly property var group: root._group
  property var _group: []

  // Why these modules can't be saved as is, each prefixed with `name`, on
  // a bounded grid of `area` ({ cols, rows }; this one's when left out)
  function problemsFor(modules, name, area) {
    const out = [];
    const bounds = area ?? root.area;
    // I18n.tr("an overlay page") I18n.tr("an edge menu") I18n.tr("the lock screen") I18n.tr("the login screen") I18n.tr("the desktop")
    const hostName = I18n.tr(({
        "overlay": "an overlay page",
        "edgeMenu": "an edge menu",
        "lockscreen": "the lock screen",
        "greeter": "the login screen",
        "desktop": "the desktop"
      })[root.host] ?? root.host);
    (modules ?? []).forEach((module, i) => {
      const type = module?.type;
      if (type && !OverlayConfig.allowedIn(type, root.host))
        out.push(I18n.tr("{0}: {1} can't be placed on {2}", name, type, hostName));
      if (!GridPlacement.canPlace(modules.slice(0, i), module?.place, -1))
        out.push(I18n.tr("{0}: {1} overlaps another module", name, type));
      else if (bounds && !GridPlacement.within(module.place, bounds.cols, bounds.rows))
        out.push(I18n.tr("{0}: {1} is outside the grid", name, type));
    });
    OverlayConfig.requiredFor(root.host).forEach(type => {
      if (!(modules ?? []).some(module => module?.type === type))
        out.push(I18n.tr("{0}: needs its {1} module", name, type));
    });
    return out;
  }

  // A new `type` module's [w, h] on this grid
  function defaultSize(type) {
    return OverlayConfig.defaultSize(type).map(n => Math.min(GridPlacement.maxSpan, n * root.sizeScale));
  }

  // The least [w, h] a new `type` module dropped into a gap shrinks to
  function minSize(type) {
    return OverlayConfig.minSize(type).map(n => Math.min(GridPlacement.maxSpan, n * root.sizeScale));
  }

  // --- Selection ---

  function select(index) {
    root._group = [];
    root._selected = index;
  }

  function clearSelection() {
    root._group = [];
    root._selected = -1;
  }

  // Selects `indices` together: one is a plain selection
  function selectGroup(indices) {
    const unique = indices.filter((i, n) => indices.indexOf(i) === n && root.module(i));
    if (unique.length > 1) {
      root._selected = -1;
      root._group = unique;
    } else {
      root.select(unique.length === 1 ? unique[0] : -1);
    }
  }

  // Adds module `index` to the selection, or takes it out
  function toggleSelected(index) {
    const current = root._group.length > 0 ? root._group : root._selected >= 0 ? [root._selected] : [];
    root.selectGroup(current.includes(index) ? current.filter(i => i !== index) : current.concat([index]));
  }

  function isSelected(index) {
    return root._selected === index || root._group.includes(index);
  }

  // The selection as indices: the group, the one selected, or []
  function selection() {
    return root._group.length > 0 ? root._group : root._selected >= 0 ? [root._selected] : [];
  }

  function module(index) {
    return root._modules()?.[index] ?? null;
  }

  function selectedModule() {
    return root.module(root.selected);
  }

  // --- Reading ---

  function _modules() {
    return root.modulesOf() ?? null;
  }

  // A free w × h spot: in the area, else null; else the grid's first
  // (GridPlacement.firstFree)
  function _freeSpot(modules, w, h) {
    return root.area ? GridPlacement.firstFreeIn(modules, w, h, root.area.cols, root.area.rows) : GridPlacement.firstFree(modules, w, h);
  }

  // Whether module `index` may be removed or duplicated (not a required
  // one)
  function canRemove(index) {
    const type = root.module(index)?.type;
    return !!type && !OverlayConfig.isRequired(type);
  }

  function _place(x, y, w, h) {
    return {
      "x": x,
      "y": y,
      "w": w,
      "h": h
    };
  }

  // The module whose place is exactly `place` (a swap partner), else -1
  function _sameSpot(modules, place, ignore) {
    return (modules ?? []).findIndex((module, i) => i !== ignore && module?.place && module.place.x === place.x && module.place.y === place.y && module.place.w === place.w && module.place.h === place.h);
  }

  // Inside the `area` when there is one: moved in from past its sides
  // (it may still not fit, when bigger than the area)
  function _intoArea(place) {
    if (!root.area)
      return place;
    return root._place(Math.max(0, Math.min(place.x, root.area.cols - place.w)), Math.max(0, Math.min(place.y, root.area.rows - place.h)), place.w, place.h);
  }

  function _placesOf(modules) {
    return (modules ?? []).map(module => module?.place ?? null);
  }

  // A plan for an edit: what dropping, moving or resizing would do,
  // worked out without changing anything, so the canvas can show it
  // before it's made and applyPlan() make it. { kind ("add" | "move" |
  // "resize"), index (the module edited; -1 for a new one), type (a new
  // one's), place (where it lands), places (every module's place after,
  // a new one last; null when invalid), valid, noop (nothing changes) }
  function _plan(kind, index, type, place, places) {
    return {
      "kind": kind,
      "index": index,
      "type": type,
      "place": place,
      "places": places,
      "valid": places !== null,
      "noop": false
    };
  }

  // `place` taken by the module at `index` (-1: a new one): onto free
  // cells as is, else pushing what it lands on along pushDir
  function _putOrPush(places, index, place) {
    if (GridPlacement.clearOf(places, place, index, root.area)) {
      const out = places.slice();
      out[index < 0 ? out.length : index] = place;
      return out;
    }
    return GridPlacement.push(places, index, place, root.pushDir, root.area);
  }

  // A new `type` module dropped at `place` (its default size, held by its
  // middle unit, as GridPlacement.canvasDropPlace gives it): on a free
  // cell, the most of its default size that fits there (down to its
  // minSize); on a module, at its default size, pushing what it lands on
  function planAdd(type, place) {
    const modules = root._modules();
    if (!modules || !place || !OverlayConfig.allowedIn(type, root.host) || OverlayConfig.isRequired(type))
      return root._plan("add", -1, type, place, null);
    const places = root._placesOf(modules);
    const cell = {
      "x": place.x + Math.floor((place.w - 1) / 2),
      "y": place.y + Math.floor((place.h - 1) / 2)
    };
    const fitted = GridPlacement.fitPlace(places, cell, [place.w, place.h], root.minSize(type), root.area);
    if (fitted)
      return root._plan("add", -1, type, fitted, places.concat([fitted]));
    const at = root._intoArea(place);
    return root._plan("add", -1, type, at, root._putOrPush(places, -1, at));
  }

  // Module `index` moved with its top left to x, y: exactly onto a module
  // of its size they swap, else it pushes what it lands on
  function planMove(index, x, y) {
    const modules = root._modules();
    const module = modules?.[index];
    if (!module?.place)
      return root._plan("move", index, "", null, null);
    const place = root._intoArea(root._place(x, y, module.place.w, module.place.h));
    const places = root._placesOf(modules);
    if (place.x === module.place.x && place.y === module.place.y) {
      const plan = root._plan("move", index, "", place, places);
      plan.noop = true;
      return plan;
    }
    const other = root._sameSpot(modules, place, index);
    if (other >= 0) {
      const out = places.slice();
      out[other] = root._place(module.place.x, module.place.y, module.place.w, module.place.h);
      out[index] = place;
      return root._plan("move", index, "", place, out);
    }
    return root._plan("move", index, "", place, root._putOrPush(places, index, place));
  }

  // Module `index` resized to `place` (GridPlacement.resizeFrom: any side
  // may move), pushing what it grows onto
  function planResize(index, place) {
    const modules = root._modules();
    const module = modules?.[index];
    if (!module?.place || !place || place.w > GridPlacement.maxSpan || place.h > GridPlacement.maxSpan)
      return root._plan("resize", index, "", place, null);
    const places = root._placesOf(modules);
    const was = module.place;
    if (place.x === was.x && place.y === was.y && place.w === was.w && place.h === was.h) {
      const plan = root._plan("resize", index, "", place, places);
      plan.noop = true;
      return plan;
    }
    return root._plan("resize", index, "", place, root._putOrPush(places, index, place));
  }

  // The modules at `indices` moved together by `dx`, `dy` units (kept
  // inside the `area`), pushing what they land on
  function planMoveGroup(indices, dx, dy) {
    const modules = root._modules();
    const members = (indices ?? []).filter(i => modules?.[i]?.place);
    if (members.length === 0)
      return root._plan("group", -1, "", null, null);
    const before = GridPlacement.cover(members.map(i => modules[i].place));
    if (root.area) {
      dx = Math.max(-before.x, Math.min(dx, root.area.cols - before.x - before.w));
      dy = Math.max(-before.y, Math.min(dy, root.area.rows - before.y - before.h));
    }
    const places = root._placesOf(modules);
    const puts = members.map(i => [i, root._place(places[i].x + dx, places[i].y + dy, places[i].w, places[i].h)]);
    const after = root._place(before.x + dx, before.y + dy, before.w, before.h);
    if (dx === 0 && dy === 0) {
      const plan = root._plan("group", -1, "", after, places);
      plan.noop = true;
      plan.members = members;
      return plan;
    }
    let out = places.slice();
    puts.forEach(([i, place]) => out[i] = place);
    const clear = puts.every(([i, place]) => GridPlacement.clearOf(out.map((p, j) => members.includes(j) ? null : p), place, -1, root.area));
    if (!clear)
      out = GridPlacement.pushGroup(places, puts, root.pushDir, root.area);
    const plan = root._plan("group", -1, "", after, out);
    plan.members = members;
    return plan;
  }

  // What the modules at `exclude` are aligned and centred against, among
  // `places` (GridPlacement.guideFrame): the `area`, else the other
  // modules, an edge menu's screen along its edge
  function guideFrame(places, exclude) {
    return GridPlacement.guideFrame(root.area, places, exclude, root.screenBox, root.edge);
  }

  // The selection centred across (`axis` "x") or down ("y") in its frame
  // (guideFrame), as a plan (planMove / planMoveGroup; noop when it's
  // centred already). Invalid with `offCentre` when it'd sit between
  // units; null with nothing selected or nothing to centre it in
  function planCentre(axis) {
    const members = root.selection();
    const places = root._placesOf(root._modules());
    const box = GridPlacement.cover(members.map(i => places[i] ?? null));
    const frame = root.guideFrame(places, members);
    if (!box || !frame)
      return null;
    const at = GridPlacement.centredIn(box, frame, axis);
    if (at === null) {
      const plan = root._plan(members.length > 1 ? "group" : "move", -1, "", null, null);
      plan.offCentre = true;
      return plan;
    }
    const dx = axis === "x" ? at - box.x : 0;
    const dy = axis === "y" ? at - box.y : 0;
    return members.length > 1 ? root.planMoveGroup(members, dx, dy) : root.planMove(members[0], box.x + dx, box.y + dy);
  }

  function centreSelection(axis) {
    root.applyPlan(root.planCentre(axis));
  }

  // Whether a new module of `type` may be dropped at `place`
  function canAdd(type, place) {
    return root.planAdd(type, place).valid;
  }

  // Whether module `index` may move with its top left to x, y
  function canMove(index, x, y) {
    return root.planMove(index, x, y).valid;
  }

  // Whether module `index` may take the size w × h (top left kept)
  function canResize(index, w, h) {
    const place = root.module(index)?.place;
    return !!place && root.planResize(index, root._place(place.x, place.y, w, h)).valid;
  }

  // --- History ---

  // Snapshots of the edited modules (plus the owner's `snapshotExtra()`)
  // before each edit, newest last
  property var _undo: []
  property var _redo: []
  property int _undoCount: 0
  property int _redoCount: 0
  readonly property bool canUndo: root._undoCount > 0
  readonly property bool canRedo: root._redoCount > 0
  // What a property edit last snapshotted ("index:key"): more edits to
  // the same field (typing) join it
  property string _lastField: ""
  readonly property int _historyLimit: 50

  // Owner state that edits change besides the modules (an edge menu's
  // offset, which keeps it in place as its grid shifts): taken with
  // every snapshot and put back with it
  property var snapshotExtra: () => null
  property var restoreExtra: extra => {}

  onScopeKeyChanged: root.clearHistory()

  function _snapshot() {
    return {
      "modules": Utils.clone(root._modules() ?? []),
      "extra": Utils.clone(root.snapshotExtra())
    };
  }

  function _restore(snap) {
    const modules = root._modules();
    if (!modules)
      return;
    modules.splice(0, modules.length, ...Utils.clone(snap.modules));
    root.restoreExtra(snap.extra);
    root._group = [];
    if (root._selected >= modules.length)
      root._selected = -1;
    root._lastField = "";
    root.edited();
  }

  function _record(snap) {
    root._undo = root._undo.concat([snap]).slice(-root._historyLimit);
    root._redo = [];
    root._undoCount = root._undo.length;
    root._redoCount = 0;
  }

  function undo() {
    if (root._undo.length === 0 || !root._modules())
      return;
    const snap = root._undo[root._undo.length - 1];
    root._redo = root._redo.concat([root._snapshot()]);
    root._undo = root._undo.slice(0, -1);
    root._undoCount = root._undo.length;
    root._redoCount = root._redo.length;
    root._restore(snap);
  }

  function redo() {
    if (root._redo.length === 0 || !root._modules())
      return;
    const snap = root._redo[root._redo.length - 1];
    root._undo = root._undo.concat([root._snapshot()]);
    root._redo = root._redo.slice(0, -1);
    root._undoCount = root._undo.length;
    root._redoCount = root._redo.length;
    root._restore(snap);
  }

  // When the edited modules are reloaded (the draft loaded or reset)
  function clearHistory() {
    root._undo = [];
    root._redo = [];
    root._undoCount = 0;
    root._redoCount = 0;
    root._lastField = "";
  }

  // --- Editing ---

  // Runs an edit. `edit` returns the module to select, false for no
  // change, or undefined to keep the selection on its module. Then
  // shifts the grid so nothing sits at a negative place, or past 0, 0
  // (unless it's bounded by an `area`).
  function _edit(edit) {
    const modules = root._modules();
    if (!modules)
      return;
    const snap = root._snapshot();
    const before = modules[root.selected] ?? null;
    const groupBefore = root._group.map(i => modules[i]);
    const boundsBefore = GridPlacement.bounds(modules);
    const focus = edit(modules);
    if (focus === false)
      return;
    root._record(snap);
    root._lastField = "";
    if (!root.area)
      root.shifted(GridPlacement.normalize(modules, root.hold), boundsBefore);
    if (groupBefore.length > 0 && focus === undefined) {
      root.selectGroup(groupBefore.map(m => modules.indexOf(m)).filter(i => i >= 0));
    } else {
      const target = focus ?? before;
      root.select(target ? modules.indexOf(target) : -1);
    }
    root.edited();
  }

  // A new module of `type` at `place`, its id new in the modules
  function _newModule(type, place) {
    const module = ConfigManager.withDefaults({
      "id": Utils.newId(type, root._modules()),
      "type": type
    }, "OverlayModule");
    module.place = place;
    return module;
  }

  // Makes a plan (planAdd, planMove, planResize), if it's still valid for
  // the modules as they are
  function applyPlan(plan) {
    if (!plan || !plan.valid || plan.noop)
      return;
    root._edit(modules => {
      const adding = plan.kind === "add";
      if (plan.places.length !== modules.length + (adding ? 1 : 0))
        return false;
      if (adding)
        modules.push(root._newModule(plan.type, null));
      plan.places.forEach((place, i) => {
        if (place)
          modules[i].place = Object.assign({}, place);
      });
      if (plan.kind === "group")
        return undefined;
      return modules[adding ? modules.length - 1 : plan.index];
    });
  }

  // A new module at its schema defaults: dropped at `place` when given
  // (planAdd), else at its default size in the first free spot (refused
  // when a bounded grid has none)
  function addModule(type, place) {
    if (place) {
      root.applyPlan(root.planAdd(type, place));
      return;
    }
    if (!OverlayConfig.allowedIn(type, root.host) || OverlayConfig.isRequired(type))
      return;
    root._edit(modules => {
      const size = root.defaultSize(type);
      const at = root._freeSpot(modules, size[0], size[1]);
      if (!at)
        return false;
      const module = root._newModule(type, Object.assign({}, at));
      modules.push(module);
      return module;
    });
  }

  function moveModule(index, x, y) {
    root.applyPlan(root.planMove(index, x, y));
  }

  // To `place` ({ x, y, w, h }: a resize may move any side)
  function resizeModule(index, place) {
    root.applyPlan(root.planResize(index, place));
  }

  // The selected module (or group) moved `dx`, `dy` units (the
  // keyboard's arrows)
  function nudge(dx, dy) {
    if (root._group.length > 0) {
      root.applyPlan(root.planMoveGroup(root._group, dx, dy));
      return;
    }
    const place = root.selectedModule()?.place;
    if (place)
      root.moveModule(root.selected, place.x + dx, place.y + dy);
  }

  // The selected module's bottom right moved `dx`, `dy` units
  function grow(dx, dy) {
    const place = root.selectedModule()?.place;
    if (place)
      root.resizeModule(root.selected, GridPlacement.resizeFrom(place, "se", dx, dy));
  }

  // A copy at the same size in the first free spot
  function duplicateModule(index) {
    if (!root.canRemove(index))
      return;
    root._edit(modules => {
      const module = modules[index];
      const place = root._freeSpot(modules, module.place.w, module.place.h);
      if (!place)
        return false;
      const copy = Utils.clone(module);
      copy.place = place;
      copy.id = Utils.newId(module.type, modules);
      modules.push(copy);
      return copy;
    });
  }

  // Every module selected (the group, or the one) but required ones
  function removeSelection() {
    const doomed = root.selection().filter(i => root.canRemove(i)).sort((a, b) => b - a);
    if (doomed.length === 0)
      return;
    root._edit(modules => {
      doomed.forEach(i => modules.splice(i, 1));
      root._group = [];
      return null;
    });
  }

  function removeModule(index) {
    if (!root.canRemove(index))
      return;
    root._edit(modules => {
      if (!modules[index])
        return false;
      // A removed selection isn't found again, so it clears
      modules.splice(index, 1);
    });
  }

  // Records an undo step before an edit to `field` (a module's property,
  // or an owner's own setting kept in snapshotExtra); more edits to the
  // same field (typing, a stepper) join it
  function recordField(field) {
    if (root._lastField === field)
      return;
    root._record(root._snapshot());
    root._lastField = field;
  }

  function updateModuleProperty(index, key, value) {
    const module = root.module(index);
    if (!module || JSON.stringify(module.properties?.[key]) === JSON.stringify(value))
      return;
    root.recordField(`${index}:${key}`);
    if (!module.properties)
      module.properties = {};
    module.properties[key] = value;
    root.edited();
  }
}
