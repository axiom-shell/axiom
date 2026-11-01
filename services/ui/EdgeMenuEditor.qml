pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

// The layouts editor's working copy of EdgeMenus (the pinned Layouts
// overlay page), as BarManager is the bar editor's. Not a singleton:
// OverlayManager holds one as `menus`, beside its own GridEditor. Edits
// show live on the running menus (ConfigManager.previews) until saved or
// reset, and `previewing` holds one menu open to try them on
// (EdgeMenuManager opens and closes it). The selected menu's modules are
// edited through `layout` (GridEditor).
QtObject {
  id: root

  // Where a menu's modules sit on its screen, in px
  // (GridPlacement.menuPlacement, plus its `screen`), or null without a
  // screen. With `bounds`, for modules reaching that far (an edit's,
  // before it).
  function placementOf(menu, bounds) {
    const screen = EdgeMenusConfig.screenFor(menu);
    if (!menu || !screen || EdgeMenusConfig.isSubmenu(menu))
      return null;
    const place = GridPlacement.menuPlacement(menu, bounds ?? GridPlacement.bounds(menu.layout.modules), EdgeMenusConfig.cardUnitOf(menu), EdgeMenuManager.frameOf(menu), screen.width, screen.height, EdgeMenusConfig.gapOf(menu));
    place.screen = screen;
    return place;
  }

  // A menu as it sits on its screen, in screen px
  // (GridPlacement.menuOnScreen), with its `name`. `index`: its place in
  // the draft, for its label.
  function screenRectsOf(menu, index) {
    const place = root.placementOf(menu);
    if (!place)
      return null;
    const onScreen = GridPlacement.menuOnScreen(menu, place, EdgeMenusConfig.cardUnitOf(menu), EdgeMenusConfig.gapOf(menu));
    onScreen.name = root.menuLabel(menu, index);
    return onScreen;
  }

  // A menu's screen around its grid, in grid units from its origin
  // (GridPlacement.screenBox), for the layouts editor; null without one
  function screenBoxOf(menu) {
    const place = root.placementOf(menu);
    if (!place)
      return null;
    return GridPlacement.screenBox(place.screenWidth, place.screenHeight, EdgeMenusConfig.cardUnitOf(menu), GridPlacement.bounds(menu.layout.modules), menu.edge, place.along, place.across, EdgeMenusConfig.gapOf(menu));
  }

  // The draft's other enabled menus on the screen of the one at `index`,
  // as they sit on it (screenRectsOf)
  function othersOn(index) {
    const screenName = EdgeMenusConfig.screenFor(root.localMenus?.[index])?.name;
    if (!screenName)
      return [];
    return (root.localMenus ?? []).map((other, i) => i !== index && other.enabled && EdgeMenusConfig.screenFor(other)?.name === screenName ? root.screenRectsOf(other, i) : null).filter(other => other !== null);
  }

  // Moves the selected menu `step` cells along its lattice (negative:
  // towards the start), from where it is (an offset past the lattice
  // counts as its end's)
  function nudgeSelected(step) {
    const menu = root.selectedMenu();
    const place = menu ? root.placementOf(menu) : null;
    if (!place || place.cell === null)
      return;
    const range = GridPlacement.offsetRange(place.lattice, place.units);
    const offset = GridPlacement.offsetFor(place.lattice, place.cell, place.units) + step;
    root.updateMenuField("offset", Math.max(range.min, Math.min(offset, range.max)));
  }

  function centreSelected() {
    root.updateMenuField("offset", 0);
  }

  // How far a menu's lattice can be moved, in px either way: half a cell,
  // as a whole one is what the arrows do
  function gridOffsetLimit(menu) {
    return menu ? Math.floor(GridPlacement.stepOf(EdgeMenusConfig.cardUnitOf(menu), EdgeMenusConfig.gapOf(menu)) / 2) : 0;
  }

  function setGridOffset(px) {
    const limit = root.gridOffsetLimit(root.selectedMenu());
    root.updateMenuField("gridOffset", Math.max(-limit, Math.min(px, limit)));
  }

  // After an edit to the selected menu's grid, which then shifted by
  // `shift` grid units ({ x, y }: GridPlacement.normalize) from modules
  // reaching `boundsBefore`: keeps its modules on the lattice cells they
  // were on, so edits never move them on the screen
  function _keepPlace(menu, shift, boundsBefore) {
    const was = menu ? root.placementOf(menu, boundsBefore) : null;
    if (!was || was.cell === null)
      return;
    const vertical = menu.edge === "left" || menu.edge === "right";
    const units = GridPlacement.unitsAlong(menu);
    const range = GridPlacement.offsetRange(was.lattice, units);
    const offset = GridPlacement.offsetFor(was.lattice, was.cell + (vertical ? shift.y : shift.x), units);
    menu.offset = Math.max(range.min, Math.min(offset, range.max));
  }

  // The editor draws the other menus on the selected one's screen
  readonly property bool showingOthers: root._showingOthers
  property bool _showingOthers: false

  function toggleShowingOthers() {
    root._showingOthers = !root._showingOthers;
  }

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: ["EdgeMenus", "items"]
  }
  readonly property alias localMenus: draft.local
  readonly property alias savedMenus: draft.saved
  readonly property alias isDirty: draft.isDirty
  property int selectedMenuIndex: 0

  // The selected menu's modules (see GridEditor)
  property GridEditor layout: GridEditor {
    host: "edgeMenu"
    sizeScale: root.localMenus?.[root.selectedMenuIndex]?.layout?.grid?.fine ? 2 : 1
    modulesOf: () => root.selectedMenu()?.layout.modules ?? null
    // A submenu has no edge: just its grid
    readonly property var _onEdge: EdgeMenusConfig.isSubmenu(root.selectedMenu()) ? null : root.selectedMenu()
    edge: _onEdge?.edge ?? ""
    screenBox: _onEdge ? root.screenBoxOf(_onEdge) : null
    shifted: (shift, boundsBefore) => root._keepPlace(root.selectedMenu(), shift, boundsBefore)
    // Along the menu's edge: down a side menu, right along a top or
    // bottom one, so a drop at its start makes room in its run
    pushDir: {
      const edge = root.localMenus?.[root.selectedMenuIndex]?.edge;
      const side = edge === "left" || edge === "right";
      return {
        "x": side ? 0 : 1,
        "y": side ? 1 : 0
      };
    }
    // A whole-edge floating menu starts at its edge's start whatever its
    // modules reach, so a gap before them along the edge is kept
    // (GridPlacement.menuKeepsLead; a content-length menu keeps its
    // modules in place through its offset instead: _keepPlace, and an
    // integrated one starts at its first module: menuModules)
    hold: {
      const menu = root.localMenus?.[root.selectedMenuIndex];
      const side = menu?.edge === "left" || menu?.edge === "right";
      return menu && GridPlacement.menuKeepsLead(menu) ? {
        "x": !side,
        "y": side
      } : {};
    }
    // Its offset moves with edits (_keepPlace), so undo puts it back too
    snapshotExtra: () => root.selectedMenu()?.offset ?? null
    restoreExtra: offset => {
      const menu = root.selectedMenu();
      if (menu && offset !== null && offset !== undefined)
        menu.offset = offset;
    }
    scopeKey: String(root.selectedMenuIndex)
    onEdited: root.applyChanges()
  }

  // The menu the editor holds open to try edits on ("" for none). A
  // submenu menu (EdgeMenusConfig.isSubmenu) shows beside the first
  // floating menu with a Submenu module opening it (`previewParent`, held
  // open too), whose module opens it and holds it (content/Submenu)
  readonly property string previewing: root._previewing
  property string _previewing: ""
  readonly property string previewParent: root._previewParent
  property string _previewParent: ""

  // The first enabled floating menu (in the draft, else saved) with a
  // Submenu module opening menu `id`, else null
  function submenuParentOf(id) {
    return (root.localMenus ?? EdgeMenusConfig.menus).find(menu => menu.id !== id && menu.enabled && menu.mode === "floating" && (menu.layout.modules ?? []).some(module => module?.type === "Submenu" && module.properties?.menu === id)) ?? null;
  }

  // Why the draft can't be saved as is (empty = savable)
  readonly property var problems: {
    const out = [];
    const menus = root.localMenus ?? [];
    menus.forEach((menu, m) => {
      const name = root.menuLabel(menu, m);
      if (!menu.id)
        out.push(I18n.tr("{0} has no id", name));
      else if (menus.findIndex(other => other.id === menu.id) !== m)
        out.push(I18n.tr("{0}: another menu has the id {1}", name, menu.id));
      out.push(...root.layout.problemsFor(menu.layout.modules, name));
      if ((menu.layout.modules ?? []).some(module => module?.type === "Submenu" && module.properties?.menu === menu.id))
        out.push(I18n.tr("{0}: a Submenu module opens the menu it's in", name));
    });
    return out;
  }

  function menuLabel(menu, index) {
    return menu?.name || menu?.id || I18n.tr("Menu {0}", index + 1);
  }

  // Keeps the selected menu where it still exists
  function loadConfig() {
    draft.load();
    ConfigManager.clearPreview("EdgeMenus");
    root.selectedMenuIndex = Math.max(0, Math.min(root.selectedMenuIndex, (root.localMenus?.length ?? 1) - 1));
    root.layout.clearSelection();
    root.layout.clearHistory();
    root._followPreview();
  }

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    if (!draft.isDirty)
      root.loadConfig();
  }

  // Call after mutating localMenus in place: shows the edit on the running
  // menus while the draft differs from the saved config
  function applyChanges() {
    draft.changed();
    if (draft.isDirty)
      ConfigManager.setPreview("EdgeMenus", {
        "items": draft.local
      });
    else
      ConfigManager.clearPreview("EdgeMenus");
  }

  // Whether a menu differs from its saved version (matched by id)
  function menuChanged(index) {
    const menu = root.localMenus?.[index];
    const saved = (root.savedMenus ?? []).find(m => m.id === menu?.id);
    return JSON.stringify(menu) !== JSON.stringify(saved);
  }

  function selectedMenu() {
    return root.localMenus?.[root.selectedMenuIndex] || null;
  }

  function selectMenu(index) {
    if (index === root.selectedMenuIndex)
      return;
    root.selectedMenuIndex = index;
    root.layout.clearSelection();
    root._followPreview();
  }

  function _uniqueId(base) {
    const taken = (root.localMenus ?? []).map(menu => menu.id);
    let n = 1;
    while (taken.includes(`${base}-${n}`))
      n++;
    return `${base}-${n}`;
  }

  // A menu's field by dotted path ("open.onHover", "layout.grid.fine")
  function _fieldOf(menu, key) {
    return key.split(".").reduce((value, part) => value?.[part], menu);
  }

  // A new menu at the schema defaults, opening on hover, and held open on
  // screen so edits show as they're made
  function addMenu() {
    const id = root._uniqueId("menu");
    const menu = ConfigManager.withDefaults({
      "id": id,
      "name": I18n.tr("Menu {0}", id.split("-").pop()),
      "open": {
        "onHover": true
      },
      "layout": {
        "modules": []
      }
    }, "EdgeMenu");
    root.localMenus.push(menu);
    root.applyChanges();
    root.selectMenu(root.localMenus.length - 1);
    root.startPreviewing();
  }

  function duplicateMenu(index) {
    const menu = root.localMenus?.[index];
    if (!menu)
      return;
    const copy = Utils.clone(menu);
    copy.id = root._uniqueId(menu.id || "menu");
    if (copy.name)
      copy.name = I18n.tr("{0} (copy)", copy.name);
    root.localMenus.splice(index + 1, 0, copy);
    root.applyChanges();
    root.selectMenu(index + 1);
  }

  // The selected menu stays selected wherever it ends up
  function moveMenu(from, to) {
    const selected = root.selectedMenu();
    if (GridPlacement.moveTo(root.localMenus, from, to) < 0)
      return;
    root.selectedMenuIndex = Math.max(0, root.localMenus.indexOf(selected));
    root.applyChanges();
  }

  function removeMenu(index) {
    const menu = root.localMenus?.[index];
    if (!menu)
      return;
    if (root.previewing === menu.id)
      root._showPreview("");
    // The selected menu stays selected unless it's the one removed
    const selected = root.selectedMenu();
    root.localMenus.splice(index, 1);
    const kept = root.localMenus.indexOf(selected);
    if (kept >= 0) {
      root.selectedMenuIndex = kept;
    } else {
      root.selectedMenuIndex = Math.max(0, Math.min(root.selectedMenuIndex, root.localMenus.length - 1));
      root.layout.clearSelection();
    }
    root.applyChanges();
    root._followPreview();
  }

  // One of the selected menu's own fields (not its columns), by key or
  // dotted path into its groups ("open.onHover", "layout.grid.fine")
  function updateMenuField(key, value) {
    const menu = root.selectedMenu();
    if (key === "fineGrid")
      key = "layout.grid.fine";
    if (!menu || JSON.stringify(root._fieldOf(menu, key)) === JSON.stringify(value))
      return;
    const wasPreviewing = root.previewing !== "" && root.previewing === menu.id;
    if (wasPreviewing && key === "id")
      root._showPreview("");
    // Doubling the grid rescales the modules' places and the offset (in
    // cells), so they stay put; the grid offset (px) keeps within half a
    // cell
    if (key === "layout.grid.fine") {
      (menu.layout.modules ?? []).forEach(module => {
        if (module?.place)
          module.place = GridPlacement.scalePlace(module.place, value);
      });
      menu.offset = value ? menu.offset * 2 : Math.round(menu.offset / 2);
      // Older snapshots are on the other grid
      root.layout.clearHistory();
    }
    const parts = key.split(".");
    const holder = parts.slice(0, -1).reduce((value, part) => {
      if (value[part] === undefined || value[part] === null)
        value[part] = {};
      return value[part];
    }, menu);
    holder[parts[parts.length - 1]] = value;
    if (key === "layout.grid.fine") {
      const limit = root.gridOffsetLimit(menu);
      menu.gridOffset = Math.max(-limit, Math.min(menu.gridOffset, limit));
    }
    root.applyChanges();
    // A renamed (or re-enabled) menu is a new window: open that one
    if (wasPreviewing || (root._wantPreview && key === "enabled"))
      Qt.callLater(root._followPreview);
  }

  // --- How a menu opens ---

  // What opens menu `id` besides hovering its edge: bar Buttons and
  // widgets opening it as their popout (in the bar editor's draft) and
  // keybinds (in the keybind editor's).
  // [{ kind: "bar" | "bind" | "submenu", label, and where it is: bar,
  // zone, index (a bar widget), index (a bind), menu (a submenu's menu) }]
  function references(id) {
    if (!id)
      return [];
    const out = [];
    (BarManager.localConfig ?? BarsConfig.savedBars).forEach((bar, b) => Object.keys(bar?.widgets ?? {}).forEach(zone => (bar.widgets[zone] ?? []).forEach(widget => {
          if (!EdgeMenusConfig.menusOpenedBy(widget).includes(id))
            return;
          const barLabel = bar.id || I18n.tr("Bar {0}", b + 1);
          const type = BarsConfig.availableWidgetTypes.find(t => t?.type === widget.type);
          out.push({
            "kind": "bar",
            "label": widget.type === "Button" && !(widget.properties?.popout?.enabled && widget.properties.popout.menu === id) ? I18n.tr("Button on {0}", barLabel) : I18n.tr("{0} popout on {1}", I18n.tr(type?.label ?? widget.type), barLabel),
            "bar": b,
            "zone": zone,
            "index": bar.widgets[zone].indexOf(widget)
          });
        })));
    (root.localMenus ?? EdgeMenusConfig.menus).forEach((menu, m) => {
      if (menu.id !== id && (menu.layout.modules ?? []).some(module => module?.type === "Submenu" && module.properties?.menu === id))
        out.push({
          "kind": "submenu",
          "label": I18n.tr("Submenu module in {0}", root.menuLabel(menu, m)),
          "menu": m
        });
    });
    (KeybindManager.editor.isDirty ? KeybindManager.editor.binds : KeybindsConfig.binds).forEach((bind, i) => {
      if (bind?.action === "edgeMenu" && bind.argument === id)
        out.push({
          "kind": "bind",
          "label": bind.key ? I18n.tr("Keybind {0}", KeybindManager.displayKey(bind.key)) : I18n.tr("Keybind (no key yet)"),
          "index": i
        });
    });
    return out;
  }

  // Goes to where a reference is: the bar editor on its widget, the
  // keybind editor on its bind (as links: the navigator offers the way
  // back), or the menu holding the Submenu module
  function goToReference(ref) {
    if (ref.kind === "bar") {
      BarManager.ensureLoaded();
      BarManager.selectBar(ref.bar);
      BarManager.selectWidget(ref.zone, ref.index);
      ShellManager.followLink("BarEditor");
    } else if (ref.kind === "bind") {
      KeybindManager.editor.ensureLoaded();
      KeybindManager.editor.selectBind(ref.index);
      ShellManager.followLink("Keybinds");
    } else if (ref.kind === "submenu") {
      root.selectMenu(ref.menu);
    }
  }

  // Whether `menu` is saved under its id: bar buttons and keybinds are
  // saved by other editors, so they may only point at a saved menu
  function isSaved(menu) {
    return !!menu?.id && (root.savedMenus ?? []).some(saved => saved.id === menu.id);
  }

  // Adds a Button that toggles the selected menu to bar `barIndex`'s
  // `zone`, in the bar editor's draft (saved from there or with Save all),
  // then opens the bar editor on that bar
  function addBarButton(barIndex, zone) {
    const menu = root.selectedMenu();
    if (!root.isSaved(menu))
      return;
    BarManager.addWidgetTo(barIndex, zone, {
      "type": "Button",
      "properties": {
        "action": "edgeMenu",
        "menu": menu.id,
        "icon": Utils.edgeArrow(menu.edge),
        "tooltip": menu.name || menu.id
      }
    });
    ShellManager.openOverlayPage("BarEditor");
  }

  // Adds a keybind that toggles the selected menu, then opens the keybinds
  // page's editor recording its key
  function addKeybind() {
    const menu = root.selectedMenu();
    if (!root.isSaved(menu))
      return;
    KeybindManager.editor.addAndRecord({
      "action": "edgeMenu",
      "argument": menu.id,
      "call": "toggle"
    });
  }

  // --- Trying a menu out ---

  // Whether the editor wants the selected menu held open; stays set while
  // switching menus, so the preview follows the selection
  property bool _wantPreview: false

  function canPreview(menu) {
    if (!menu?.id || menu.enabled === false)
      return false;
    return !EdgeMenusConfig.isSubmenu(menu) || root.submenuParentOf(menu.id) !== null;
  }

  function startPreviewing() {
    root._wantPreview = true;
    root._followPreview();
  }

  function stopPreviewing() {
    root._wantPreview = false;
    root._showPreview("");
  }

  function togglePreviewing() {
    if (root._wantPreview)
      root.stopPreviewing();
    else
      root.startPreviewing();
  }

  function _followPreview() {
    if (!root._wantPreview)
      return;
    const menu = root.selectedMenu();
    root._showPreview(root.canPreview(menu) ? menu.id : "");
  }

  function _showPreview(id) {
    const menu = id !== "" ? EdgeMenusConfig.menuById(id) ?? root.localMenus?.find(m => m.id === id) : null;
    const parentId = menu && EdgeMenusConfig.isSubmenu(menu) ? (root.submenuParentOf(id)?.id ?? "") : "";
    if (root.previewing === id && root.previewParent === parentId)
      return;
    // What was shown closes: a submenu with the menu it opened from
    const shown = root.previewParent !== "" ? root.previewParent : root.previewing;
    if (shown !== "" && shown !== (parentId || id))
      EdgeMenuManager.close(shown);
    root._previewing = id;
    root._previewParent = parentId;
    // After the preview reaches EdgeMenusConfig, so a new menu exists
    if (id !== "")
      Qt.callLater(() => {
        if (root.previewing === id)
          EdgeMenuManager.open(root.previewParent || id, null);
      });
  }

  function saveChanges() {
    if (root.problems.length > 0)
      return false;
    if (!draft.save())
      return false;
    ConfigManager.clearPreview("EdgeMenus");
    return true;
  }

  function resetChanges() {
    root.loadConfig();
  }
}
