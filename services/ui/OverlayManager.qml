pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.session

/* OverlayManager holds the layouts editor's working copy of Overlay.items
 * (the editor is the pinned last page). Edits only affect localViews and
 * the editor's canvas; the real overlay pages and config.json are
 * untouched until saveChanges(). Mirrors BarManager.
 *
 * Also keeps the page's own state, since the page is unloaded whenever the
 * overlay closes: whether it's editing a page, an edge menu or the lock
 * screen (`editTarget`; the menus are `menus`' (EdgeMenuEditor) and the lock
 * screen LockManager's), the selected
 * page, and each overlay's room (for the canvas's "fits" line). The
 * selected page's modules are edited through `layout` (GridEditor, which
 * also holds the selected module). */
QtObject {
  id: root

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: ["Overlay", "items"]
  }
  readonly property alias localViews: draft.local
  readonly property alias savedViews: draft.saved
  readonly property alias isDirty: draft.isDirty
  property int selectedViewIndex: 0
  // What the layouts editor shows: "page" (selectedViewIndex), "menu"
  // (menus.selectedMenuIndex), "desktop" (DesktopManager's
  // draft), "lockscreen" (LockManager's) or "greeter" (GreeterManager's).
  // The lock screen only while the built-in locker is in use, the login
  // screen only while it's set up (their rows hide otherwise): back on the
  // pages when they stop being
  readonly property string editTarget: (root._editTarget === "lockscreen" && !root.lockscreenEditable) || (root._editTarget === "greeter" && !root.greeterEditable) ? "page" : root._editTarget
  property string _editTarget: "page"
  // The lock screen's layout shows only with the built-in locker
  readonly property bool lockscreenEditable: LockscreenConfig.mode === "quickshell"
  // The login screen's, only once it's set up
  readonly property bool greeterEditable: GreeterConfig.enabled

  // The edge menus' working copy (editTarget "menu")
  property EdgeMenuEditor menus: EdgeMenuEditor {}

  property GridEditor layout: GridEditor {
    host: "overlay"
    sizeScale: root.localViews?.[root.selectedViewIndex]?.layout?.grid?.fine ? 2 : 1
    modulesOf: () => root.selectedView()?.type === "Custom" ? root.selectedView().layout.modules : null
    scopeKey: String(root.selectedViewIndex)
    onEdited: root.applyChanges()
  }

  // Why the draft can't be saved as is (empty = savable)
  readonly property var problems: {
    const out = [];
    (root.localViews ?? []).forEach((view, v) => {
      if (view.type === "Custom")
        out.push(...root.layout.problemsFor(view.layout.modules, OverlayConfig.viewLabel(view, v)));
    });
    return out;
  }

  // Keeps the selected page where it still exists
  function loadConfig() {
    draft.load();
    root.selectedViewIndex = Math.max(0, Math.min(root.selectedViewIndex, (root.localViews?.length ?? 1) - 1));
    root.layout.clearSelection();
    root.layout.clearHistory();
  }

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    if (!draft.isDirty)
      loadConfig();
  }

  // Call after mutating localViews in place
  function applyChanges() {
    draft.changed();
  }

  // Whether a page differs from the saved page at the same position
  function viewChanged(index) {
    return JSON.stringify(root.localViews?.[index]) !== JSON.stringify(root.savedViews?.[index]);
  }

  // --- What the editor shows ---

  function editPage(index) {
    root._editTarget = "page";
    root.selectView(index);
  }

  function editMenu(index) {
    root._editTarget = "menu";
    root.menus.selectMenu(index);
  }

  function editDesktop() {
    root._editTarget = "desktop";
    DesktopManager.editor.ensureLoaded();
  }

  function editLockscreen() {
    root._editTarget = "lockscreen";
    LockManager.editor.ensureLoaded();
  }

  function editGreeter() {
    root._editTarget = "greeter";
    GreeterManager.editor.ensureLoaded();
  }

  // --- Links to a page (`x-link`'s and `x-links`' `page`) ---

  // A page link is a view type ("Themes"), or the layouts editor on what it
  // edits ("Layouts:lockscreen", "Layouts:greeter", "Layouts:desktop").
  // I18n.tr("Lock screen") I18n.tr("Login screen") I18n.tr("Desktop")
  readonly property var _linkTargets: ({
      "lockscreen": {
        "label": "Lock screen",
        "icon": "lock"
      },
      "greeter": {
        "label": "Login screen",
        "icon": "login"
      },
      "desktop": {
        "label": "Desktop",
        "icon": "wallpaper"
      }
    })

  function _linkTarget(link) {
    const parts = link.split(":");
    return parts[0] === "Layouts" ? root._linkTargets[parts[1] ?? ""] ?? null : null;
  }

  // Whether a page link leads anywhere: the page is in the overlay, and
  // what it edits can be edited
  function pageLinkAvailable(link) {
    const target = link.split(":")[1] ?? "";
    if (target === "lockscreen" && !root.lockscreenEditable)
      return false;
    if (target === "greeter" && !root.greeterEditable)
      return false;
    return OverlayConfig.hasPage(link.split(":")[0]);
  }

  function pageLinkLabel(link) {
    const target = root._linkTarget(link);
    const page = OverlayConfig.viewLabel({
      "type": link.split(":")[0]
    }, 0);
    return target ? I18n.tr("{0} in {1}", I18n.tr(target.label), page) : page;
  }

  function pageLinkIcon(link) {
    return root._linkTarget(link)?.icon ?? OverlayConfig.viewIcon(link.split(":")[0]);
  }

  // Follows a page link from the current page (the navigator offers the
  // way back), showing what it edits first
  function followPageLink(link) {
    const target = link.split(":")[1] ?? "";
    if (target === "lockscreen")
      root.editLockscreen();
    else if (target === "greeter")
      root.editGreeter();
    else if (target === "desktop")
      root.editDesktop();
    ShellManager.followLink(link.split(":")[0]);
  }

  // The pages, or the menus, keeping what was selected in each
  function editPages() {
    root._editTarget = "page";
  }

  function editMenus() {
    root._editTarget = "menu";
  }

  // --- Room on each screen ---

  // { screenName: { width, height, unit } }: the room each overlay has
  // for a page and the card size its content lays out at, in layout px
  // (OverlayGrid), as its OverlayPanel reports them
  readonly property var areas: root._areas
  property var _areas: ({})

  function reportArea(screenName, width, height, unit) {
    const old = root._areas[screenName];
    if (old && old.width === width && old.height === height && old.unit === unit)
      return;
    root._areas = Utils.withEntry(root._areas, screenName, {
      "width": width,
      "height": height,
      "unit": unit
    });
  }

  // A screen's overlay is gone (its screen was unplugged)
  function clearArea(screenName) {
    if (screenName in root._areas)
      root._areas = Utils.withEntry(root._areas, screenName, undefined);
  }

  // How much each screen's overlay shrinks a Custom page: [{ screen,
  // scale }], 1 where it fits
  function fitOf(view) {
    const bounds = GridPlacement.bounds(view.layout?.modules);
    return Object.keys(root.areas).sort().map(screenName => {
      const area = root.areas[screenName];
      return {
        "screen": screenName,
        "scale": GridPlacement.fitScale(bounds, area.width, area.height, OverlayConfig.pageUnit(view, area.unit))
      };
    });
  }

  // --- Pages ---

  function selectedView() {
    return root.localViews?.[root.selectedViewIndex] || null;
  }

  function selectView(index) {
    root.selectedViewIndex = index;
    root.layout.clearSelection();
  }

  // A new Custom page, selected (tool pages are always in config: they're
  // hidden, never added or removed)
  function addView() {
    const taken = root.localViews.map(v => v.name);
    let n = 1;
    while (taken.includes(I18n.tr("Page {0}", n)))
      n++;
    const name = I18n.tr("Page {0}", n);
    root.localViews.push(ConfigManager.withDefaults({
      "id": Utils.newId(Utils.slug(name) || "page", root.localViews),
      "type": "Custom",
      "name": name,
      "layout": {
        "modules": []
      }
    }, "OverlayView"));
    root.editPage(root.localViews.length - 1);
    applyChanges();
  }

  // Inserts a copy of a Custom page after it and selects it
  function duplicateView(index) {
    const view = root.localViews?.[index];
    if (view?.type !== "Custom")
      return;
    const copy = Utils.clone(view);
    copy.name = I18n.tr("{0} (copy)", OverlayConfig.viewLabel(view, index));
    copy.id = Utils.newId(view.id, root.localViews);
    root.localViews.splice(index + 1, 0, copy);
    root.editPage(index + 1);
    applyChanges();
  }

  function removeView(index) {
    if (root.localViews?.[index]?.type !== "Custom")
      return;
    // The selected page stays selected unless it's the one removed
    const selectedView = root.selectedView();
    root.localViews.splice(index, 1);
    const kept = root.localViews.indexOf(selectedView);
    if (kept >= 0)
      root.selectedViewIndex = kept;
    else
      root.selectView(Math.max(0, Math.min(root.selectedViewIndex, root.localViews.length - 1)));
    applyChanges();
  }

  // The selected page stays selected wherever it ends up
  function moveView(from, to) {
    const selectedView = root.selectedView();
    if (GridPlacement.moveTo(root.localViews, from, to) < 0)
      return;
    root.selectedViewIndex = Math.max(0, root.localViews.indexOf(selectedView));
    applyChanges();
  }

  // One of a page's own fields (name, icon, visible), or its double grid
  // ("fineGrid": layout.grid.fine), which rescales the modules' places so
  // they stay put
  function updateViewField(index, key, value) {
    const view = root.localViews?.[index];
    if (!view)
      return;
    if (key === "fineGrid") {
      if (!!view.layout.grid.fine === value)
        return;
      (view.layout.modules ?? []).forEach(module => {
        if (module?.place)
          module.place = GridPlacement.scalePlace(module.place, value);
      });
      view.layout.grid.fine = value;
      // Older snapshots are on the other grid
      if (index === root.selectedViewIndex)
        root.layout.clearHistory();
      applyChanges();
      return;
    }
    if (JSON.stringify(view[key]) === JSON.stringify(value))
      return;
    view[key] = value;
    applyChanges();
  }

  function renameView(index, name) {
    root.updateViewField(index, "name", name);
  }

  // Shown in the navigator (true) or hidden; hidden pages keep their place
  function setViewVisible(index, visible) {
    const view = root.localViews?.[index];
    if (!view || (view.visible !== false) === visible)
      return;
    if (visible)
      delete view.visible;
    else
      view.visible = false;
    applyChanges();
  }

  // --- How a page opens ---

  // Whether `view` is saved under its page key: bar buttons and keybinds
  // are saved by other editors, so they may only open a saved page
  function isSaved(view) {
    const key = OverlayConfig.pageKey(view);
    return key !== "" && (root.savedViews ?? []).some(saved => OverlayConfig.pageKey(saved) === key);
  }

  // Adds a Button that opens the selected page to bar `barIndex`'s `zone`,
  // in the bar editor's draft (saved from there or with Save all), then
  // opens the bar editor on that bar
  function addBarButton(barIndex, zone) {
    const view = root.selectedView();
    if (!root.isSaved(view))
      return;
    BarManager.addWidgetTo(barIndex, zone, {
      "type": "Button",
      "properties": {
        "action": "overlayPage",
        "page": OverlayConfig.pageKey(view),
        "icon": OverlayConfig.pageIcon(view),
        "tooltip": OverlayConfig.viewLabel(view, root.selectedViewIndex)
      }
    });
    ShellManager.openOverlayPage("BarEditor");
  }

  // Adds a keybind that opens the selected page, then opens the keybinds
  // page's editor recording its key
  function addKeybind() {
    const view = root.selectedView();
    if (!root.isSaved(view))
      return;
    KeybindManager.addAndRecord({
      "action": "overlayPage",
      "argument": OverlayConfig.pageKey(view)
    });
  }

  // What a bar widget opens that this editor edits (the other way round
  // from addBarButton: a Button's page or menu, or a widget's menu popout):
  // { kind: "page" | "menu", index, label }, or null
  // A Button's click action first, then a menu popout; one that's gone is
  // passed over
  function openedBy(widget) {
    const props = widget?.type === "Button" ? widget.properties ?? {} : {};
    const menus = root.menus.localMenus ?? EdgeMenusConfig.menus;
    const menuTarget = id => {
      const index = id ? menus.findIndex(menu => menu.id === id) : -1;
      return index < 0 ? null : {
        "kind": "menu",
        "index": index,
        "label": root.menus.menuLabel(menus[index], index)
      };
    };
    const pageTarget = key => {
      const views = root.localViews ?? OverlayConfig.views;
      const index = key ? views.findIndex(view => OverlayConfig.pageKey(view) === key) : -1;
      return index < 0 ? null : {
        "kind": "page",
        "index": index,
        "label": OverlayConfig.viewLabel(views[index], index)
      };
    };
    const click = props.action === "edgeMenu" ? menuTarget(props.menu) : props.action === "overlayPage" ? pageTarget(props.page) : null;
    return click ?? EdgeMenusConfig.menusOpenedBy(widget).map(menuTarget).find(target => target !== null) ?? null;
  }

  // Shows what a bar widget opens in this editor
  function editOpenedBy(widget) {
    root.ensureLoaded();
    root.menus.ensureLoaded();
    const target = root.openedBy(widget);
    if (!target)
      return;
    if (target.kind === "menu")
      root.editMenu(target.index);
    else
      root.editPage(target.index);
    ShellManager.followLink("Layouts");
  }

  // --- Save / reset ---

  // Merged onto the latest real config; stays dirty if rejected
  function saveChanges() {
    if (root.problems.length > 0)
      return false;
    return draft.save();
  }

  function resetChanges() {
    loadConfig();
  }
}
