pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

// Which edge menus (EdgeMenusConfig) are open and which are pinned. The
// menus themselves (shell/EdgeMenus) follow this and report back when they
// close on their own. Kept across QML reloads, so a reload doesn't close an
// integrated menu and reflow the windows. Pins are also saved to
// $XDG_STATE_HOME/axiom/ui/edgemenus.json, and a pinned menu opens again when qs starts.
//
// Also the layouts editor's working copy of EdgeMenus (the pinned Layouts
// overlay page), as BarManager is the bar editor's: edits
// show live on the running menus (ConfigManager.previews) until saved or
// reset, and `previewing` holds one menu open to try them on.
//
//   axiom ipc edgeMenu toggle <id>
Singleton {
  id: root

  // { id: true } for each open / pinned menu
  readonly property var openMenus: root._parse(_run.open)
  readonly property var pinnedMenus: root._parse(_run.pinned)

  // What opened each menu (a bar button), which keeps a floating menu open
  // while hovered, as a bar popout's anchor does. Not kept across reloads.
  property var anchors: ({})
  // How each open menu ranks in PopoutManager (its PopoutClaim's kind):
  // "bar" when a widget's PopoutAnchor opened it as that widget's popout,
  // else "menu". Set with its anchor, as it opens.
  property var claimKinds: ({})

  // Where each running menu's modules can sit on its screen, by id, as the
  // menu reports it (IntegratedEdgeMenu, FloatingEdgeMenu), for the
  // layouts editor. In px: { screen (its name), startPad, endPad (the
  // least room between the modules and the edge's ends), across (from the
  // screen edge to the modules), before (across, taken by what's on the
  // edge outside the menu: bars, the border), after (from the modules to
  // the menu's inner side), reserves (whether the menu reserves its strip) }
  readonly property var frames: root._frames
  property var _frames: ({})

  function setFrame(id, frame) {
    if (id && JSON.stringify(root._frames[id]) !== JSON.stringify(frame))
      root._frames = Utils.withEntry(root._frames, id, frame);
  }

  function clearFrame(id, screenName) {
    if (root._frames[id]?.screen === screenName)
      root._frames = Utils.withEntry(root._frames, id, undefined);
  }

  // A menu's frame (see `frames`): its running one's, else (a disabled
  // menu, or one not yet reported) its padding all round
  function frameOf(menu) {
    const screenName = EdgeMenusConfig.screenFor(menu)?.name ?? "";
    const live = root.frames[menu?.id ?? ""];
    if (live && live.screen === screenName)
      return live;
    const pad = Appearance.borderWidth + EdgeMenusConfig.paddingOf(menu);
    return {
      "screen": screenName,
      "startPad": pad,
      "endPad": pad,
      "across": pad,
      "before": 0,
      "after": pad,
      "reserves": menu?.mode === "integrated"
    };
  }

  // Where a menu's modules sit on its screen, in px
  // (GridPlacement.menuPlacement, plus its `screen`), or null without a
  // screen. With `bounds`, for modules reaching that far (an edit's,
  // before it).
  function placementOf(menu, bounds) {
    const screen = EdgeMenusConfig.screenFor(menu);
    if (!menu || !screen || EdgeMenusConfig.isSubmenu(menu))
      return null;
    const place = GridPlacement.menuPlacement(menu, bounds ?? GridPlacement.bounds(menu.layout.modules), root.cardUnitOf(menu), root.frameOf(menu), screen.width, screen.height, root.gapOf(menu));
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
    const onScreen = GridPlacement.menuOnScreen(menu, place, root.cardUnitOf(menu), root.gapOf(menu));
    onScreen.name = root.menuLabel(menu, index);
    return onScreen;
  }

  // A menu's screen around its grid, in grid units from its origin
  // (GridPlacement.screenBox), for the layouts editor; null without one
  function screenBoxOf(menu) {
    const place = root.placementOf(menu);
    if (!place)
      return null;
    return GridPlacement.screenBox(place.screenWidth, place.screenHeight, root.cardUnitOf(menu), GridPlacement.bounds(menu.layout.modules), menu.edge, place.along, place.across, root.gapOf(menu));
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
    return menu ? Math.floor(GridPlacement.stepOf(root.cardUnitOf(menu), root.gapOf(menu)) / 2) : 0;
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

  PersistentProperties {
    id: _run
    reloadableId: "axiomEdgeMenus"
    // JSON lists of ids
    property string open: "[]"
    property string pinned: "[]"
    // False only on the first load after qs starts
    property bool started: false

    onLoaded: {
      if (_run.started)
        return;
      _run.started = true;
      const pinned = root._state.load({}).pinned;
      if (!Array.isArray(pinned))
        return;
      const ids = pinned.filter(id => EdgeMenusConfig.menuById(id));
      _run.pinned = JSON.stringify(ids);
      _run.open = JSON.stringify(ids);
    }
  }

  readonly property var _state: StateManager.createStateHandler("edgemenus")

  function _parse(json) {
    try {
      return JSON.parse(json).reduce((map, id) => {
        map[id] = true;
        return map;
      }, {});
    } catch (e) {
      return {};
    }
  }

  function _set(map, id, on) {
    const ids = Object.keys(map).filter(key => key !== id);
    if (on)
      ids.push(id);
    return JSON.stringify(ids);
  }

  // True for a menu held open by the editor: it ignores closeOnLeave and
  // outside clicks, as a pinned one does (previewing a submenu menu holds
  // the menu it opens from, previewParent)
  function isHeld(id) {
    return root.isPinned(id) || (id !== "" && (root.previewing === id || root.previewParent === id));
  }

  function isOpen(id) {
    return root.openMenus[id] === true;
  }
  function isPinned(id) {
    return root.pinnedMenus[id] === true;
  }

  // A module's host (Card/Panel.host) is an edge menu it can pin
  function canPin(host) {
    return host?.kind === "edgeMenu" && !!host.id && !host.submenu;
  }

  function _exists(id) {
    if (EdgeMenusConfig.menuById(id))
      return true;
    console.warn("[EdgeMenuManager] No edge menu with id", id);
    return false;
  }

  // `kind`: how it ranks (claimKinds), "menu" when left out
  function open(id, anchor, kind) {
    if (!root._exists(id))
      return;
    const anchors = Object.assign({}, root.anchors);
    anchors[id] = anchor ?? null;
    root.anchors = anchors;
    const kinds = Object.assign({}, root.claimKinds);
    kinds[id] = kind ?? "menu";
    root.claimKinds = kinds;
    if (root.isOpen(id))
      root.engageRequested(id);
    _run.open = root._set(root.openMenus, id, true);
  }

  // Asked for while already open (a keybind, a bar Button, IPC): its host
  // takes it as engaged (EdgePopout.engage), so a pinned one ranks as a
  // menu again and comes forward over what covered it (PopoutManager)
  signal engageRequested(string id)
  // Open, but given way to a popout over it (pinned or previewing)
  function covered(id) {
    return PopoutManager.entry("menu:" + id)?.phase === "yielded";
  }

  // Menus opened for something outside them (the launcher, IPC) that take
  // the cursor: the menu warps it into its box once shown
  // (CompositorManager.warpCursorToLayer), and doesn't close on leave until
  // it has been hovered. Not kept across reloads.
  property var revealing: ({})

  // Opens a menu and moves the cursor into it, so one that closes when the
  // pointer leaves stays open
  function reveal(id) {
    if (!root._exists(id))
      return;
    root.revealing = root._parse(root._set(root.revealing, id, true));
    root.open(id, null);
  }

  // The menu was hovered, or closed
  function revealDone(id) {
    if (root.revealing[id] === true)
      root.revealing = root._parse(root._set(root.revealing, id, false));
  }

  function close(id) {
    if (!root.isOpen(id))
      return;
    _run.open = root._set(root.openMenus, id, false);
  }

  function toggle(id, anchor) {
    // Covered, it's brought forward rather than closed
    if (root.covered(id))
      root.open(id, anchor);
    else if (root.isOpen(id))
      root.close(id);
    else
      root.open(id, anchor);
  }

  function setPinned(id, pinned) {
    _run.pinned = root._set(root.pinnedMenus, id, pinned);
    root._state.save({
      "pinned": JSON.parse(_run.pinned)
    });
  }

  function togglePinned(id) {
    root.setPinned(id, !root.isPinned(id));
  }

  // --- Editor ---

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
    modulesOf: () => root.selectedMenu()?.modules ?? null
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
    // A whole-edge menu starts at its edge's start whatever its modules
    // reach, so a gap before them along the edge is kept (a content-length
    // menu keeps its modules in place through its offset instead:
    // _keepPlace)
    hold: {
      const menu = root.localMenus?.[root.selectedMenuIndex];
      const side = menu?.edge === "left" || menu?.edge === "right";
      return menu?.length === "edge" ? {
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

  // A menu's card size: the card size on its screen (OverlayConfig.
  // cardUnitOn, the card size setting's, not the overlay's own Module
  // size), scaled by the menu's moduleScale. A submenu's is on the screen
  // of the menu it opens from (`screen`)
  function cardUnitOf(menu, screen) {
    screen = screen ?? EdgeMenusConfig.screenFor(menu);
    const unit = screen ? OverlayConfig.cardUnitOn(screen.width, screen.height) : GridPlacement.cardUnit;
    // A double grid (fineGrid) splits each unit in two each way
    return GridPlacement.gridUnitOf(unit * menu.layout.moduleScale / 100, menu.layout.grid.fine, root.gapOf(menu));
  }

  // The px between a menu's cards: the layout's gap drawn at the menu's
  // zoom (GridPlacement.gapOf), so the menu is an overlay page's grid
  function gapOf(menu) {
    return GridPlacement.gapOf(root.zoomOf(menu));
  }

  // What a menu's modules are drawn at: its moduleScale
  // (GridPlacement.zoomOf), so it scales their text and controls with
  // its cards, while the screen only changes how big the cards are
  function zoomOf(menu) {
    return GridPlacement.zoomOf(menu.layout.moduleScale / 100);
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
    (BarManager.localConfig ?? Bar.savedBars).forEach((bar, b) => Object.keys(bar?.widgets ?? {}).forEach(zone => (bar.widgets[zone] ?? []).forEach(widget => {
          if (!EdgeMenusConfig.menusOpenedBy(widget).includes(id))
            return;
          const barLabel = bar.id || I18n.tr("Bar {0}", b + 1);
          const type = Bar.availableWidgetTypes.find(t => t?.type === widget.type);
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
    (KeybindManager.isDirty ? KeybindManager.binds : KeybindsConfig.binds).forEach((bind, i) => {
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
      KeybindManager.ensureLoaded();
      KeybindManager.selectBind(ref.index);
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
    KeybindManager.addAndRecord({
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
      root.close(shown);
    root._previewing = id;
    root._previewParent = parentId;
    // After the preview reaches EdgeMenusConfig, so a new menu exists
    if (id !== "")
      Qt.callLater(() => {
        if (root.previewing === id)
          root.open(root.previewParent || id, null);
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

  property IpcTarget _ipc: IpcTarget {
    target: "edgeMenu"

    function open(id: string): void {
      root.open(id, null);
    }

    function close(id: string): void {
      root.close(id);
    }

    function toggle(id: string): void {
      root.toggle(id, null);
    }

    function pin(id: string): void {
      root.setPinned(id, true);
    }

    function unpin(id: string): void {
      root.setPinned(id, false);
    }

    // Opens the layouts editor on the edge menus
    function edit(): void {
      OverlayManager.editMenus();
      ShellManager.openOverlayPage("Layouts");
    }

    function list(): string {
      return EdgeMenusConfig.menus.map(menu => `${menu.id}${root.isOpen(menu.id) ? " (open)" : ""}${root.isPinned(menu.id) ? " (pinned)" : ""}`).join("\n");
    }
  }
}
