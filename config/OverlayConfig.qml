pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Overlay: the configured views, plus the card grid's layout constants.
// (Named OverlayConfig because `Overlay` is the module type.)
QtObject {
  // The pages, Overlay.items: [OverlayView], each with its id
  readonly property var views: ConfigManager.live.Overlay.items
  // The overlay's own Module size, in %: its cards are the card size
  // (cardUnitOn) times it, and their content drawn at it (see layoutFor)
  readonly property int moduleScale: ConfigManager.live.Overlay.moduleScale
  // The page switcher's edge, "bottom" | "top", and which tabs show their
  // names: "auto" (all while they fit) | "current" | "icons"
  readonly property string navigator: ConfigManager.live.Overlay.navigator
  readonly property string navigatorLabels: ConfigManager.live.Overlay.navigatorLabels
  // "top" | "bottom" (the edge it slides in from) | "fade"
  readonly property string animation: ConfigManager.live.Overlay.animation
  readonly property bool showBackdrop: ConfigManager.live.Overlay.showBackdrop
  // 0-1 opacity of the backdrop
  readonly property real backdrop: ConfigManager.live.Overlay.backdrop / 100
  // The ScreenTarget it opens on (see General.screensFor)
  readonly property var screen: ConfigManager.live.Overlay.screen
  readonly property bool closeOnEscape: ConfigManager.live.Overlay.closeOnEscape
  readonly property bool closeOnOutsideClick: ConfigManager.live.Overlay.closeOnOutsideClick

  // The pages that aren't in config, after the configured ones: the
  // layouts editor (overlay pages and edge menus), which can't be removed.
  // Labels: I18n.tr("Layouts")
  readonly property var pinnedPages: [
    {
      "type": "Layouts",
      "icon": "dashboard_customize",
      "label": "Layouts"
    }
  ]

  // What the overlay editor offers, read from the schema's oneOfs so new
  // module/view types show up there automatically
  function _oneOfTypes(definition) {
    const schema = ConfigManager.configSchema;
    return (schema?.definitions?.[definition]?.oneOf ?? []).map(option => {
      const def = schema.definitions[option.$ref.replace("#/definitions/", "")];
      const type = def?.properties?.type;
      if (!type?.const)
        return null;
      return {
        "type": type.const,
        "label": type.description || type.const,
        "propertiesSchema": def.properties?.properties?.properties ?? null,
        // Its options shown first, in order (their `x-order`)
        "propertiesOrder": def.properties?.properties?.["x-order"] ?? [],
        // The size a module is added at ([w, h] in grid units, four to a
        // card; `x-defaultSize`), null when not declared
        "defaultSize": def["x-defaultSize"] ?? null,
        // The least a drop into a gap shrinks it to (`x-minSize`), null
        // when not declared
        "minSize": def["x-minSize"] ?? null,
        // A tool page (`x-tool`), shown apart from the user's own pages
        "tool": def["x-tool"] === true,
        // The compositor capability a page needs to be shown (`x-needs`,
        // a CompositorManager.supports key), "" for none
        "needs": def["x-needs"] ?? "",
        // Material Symbols name (`x-icon`)
        "icon": def["x-icon"] ?? "extension",
        // Its group in the module library (`x-libraryGroup`)
        "group": def["x-libraryGroup"] ?? "",
        // Where a module may be placed (`x-hosts`): "overlay", "edgeMenu",
        // "desktop" when left out; "lockscreen" and "greeter" only for
        // modules that list them
        "hosts": def["x-hosts"] ?? ["overlay", "edgeMenu", "desktop"],
        // Part of every grid on its hosts (`x-required`): never removed,
        // duplicated or offered in the library
        "required": def["x-required"] === true,
        // Takes typing (`x-keyboard`): a host that otherwise keeps the
        // keyboard away (the desktop) takes it on a click while it shows one
        "keyboard": def["x-keyboard"] === true,
        // The property shown on its layouts editor tile (`x-canvasDetail`),
        // and the color property filling it (`x-canvasFill`), else ""
        "canvasDetail": def["x-canvasDetail"] ?? "",
        "canvasFill": def["x-canvasFill"] ?? "",
        // Where its feature is set (`x-link`), shown in the layouts
        // editor's inspector; undefined for none
        "link": def["x-link"]
      };
    }).filter(t => t !== null);
  }
  readonly property var availableModuleTypes: _oneOfTypes("OverlayModule")
  // The groups the editors' libraries sort bar widgets and modules into
  // (the schema's `x-libraryGroups`), in order
  readonly property var libraryGroups: ConfigManager.configSchema?.["x-libraryGroups"] ?? []
  // A Custom page's own fields (name, icon, layout), for the layouts editor
  readonly property var customViewSchema: ConfigManager.configSchema.definitions.CustomOverlayView.properties
  readonly property var availableViewTypes: _oneOfTypes("OverlayView")
  // The module types a host's library offers: "overlay" pages,
  // "edgeMenu"s or the "lockscreen" (required ones are always there)
  function modulesFor(host) {
    return availableModuleTypes.filter(t => t.hosts.includes(host) && !t.required);
  }
  // The required module types on a host
  function requiredFor(host) {
    return availableModuleTypes.filter(t => t.hosts.includes(host) && t.required).map(t => t.type);
  }
  function isRequired(type) {
    return moduleInfo(type)?.required ?? false;
  }
  function allowedIn(type, host) {
    const info = moduleInfo(type);
    return !info || info.hosts.includes(host);
  }

  function moduleInfo(type) {
    return availableModuleTypes.find(t => t.type === type) ?? null;
  }
  function viewInfo(type) {
    return availableViewTypes.find(t => t.type === type) ?? null;
  }
  // How a page is named and drawn in the page navigator and the overlay
  // editor: a Custom page by its name (or its place), others by type
  // (i18n: keys from the schema's view labels)
  function viewLabel(view, index) {
    if (view?.type === "Custom")
      return view.name || I18n.tr("Page {0}", index + 1);
    const label = viewInfo(view?.type)?.label ?? view?.type ?? "";
    return I18n.tr(label);
  }
  // What opens a page by name (`openOverlayPage`, a bar Button or bind's
  // `overlayPage` action): a Custom page's name, other pages' type; "" for
  // a Custom page with no name
  function pageKey(view) {
    return view?.type === "Custom" ? view.name ?? "" : view?.type ?? "";
  }
  function viewIcon(type) {
    return pinnedPages.find(page => page.type === type)?.icon ?? viewInfo(type)?.icon ?? "dashboard";
  }
  // A page's icon: a Custom page's own, else its type's
  function pageIcon(view) {
    return (view?.type === "Custom" && view.icon) || viewIcon(view?.type);
  }
  // Whether the overlay has a page of this type to go to (a link's): the
  // pinned pages always, others while they're in Overlay.views and shown
  function hasPage(type) {
    return pinnedPages.some(page => page.type === type) || views.some(view => view.type === type && view.visible !== false);
  }
  function isTool(type) {
    return viewInfo(type)?.tool ?? false;
  }

  // The page to open for a module type (what openOverlayPage takes): the
  // named Custom page where it's biggest, "" when no page has it
  function pageWithModule(type) {
    let best = "";
    let bestArea = 0;
    (views ?? []).forEach(view => {
      if (view?.type !== "Custom" || !view.name || view.visible === false)
        return;
      (view.layout?.modules ?? []).forEach(module => {
        const area = module?.type === type ? module.place.w * module.place.h : 0;
        if (area > bestArea) {
          best = view.name;
          bestArea = area;
        }
      });
    });
    return best;
  }

  // Card grid layout (see GridPlacement for the geometry). Card radius/border
  // follow Appearance so the overlay matches the shell.
  readonly property int cardSpacing: GridPlacement.cardSpacing
  // The inner padding a module lays its content out within (Card/Panel
  // `pad`): none when bare, less in a quarter slot (Widget's density)
  function cardPad(compact, bare) {
    return bare ? 0 : compact ? Widget.cardPadding * 0.75 : Widget.cardPadding * 1.5;
  }
  // The overlay box's padding around a page (OverlayPages), at the
  // Interface scale: the page inside it is scaled, the box isn't
  readonly property int boxPadding: Widget.px(cardSpacing)
  // The page switcher's height (OverlayPageNavigator), and the room it
  // takes off the pages' area with the gaps around it (OverlayPanel)
  readonly property int navigatorHeight: Math.round(Widget.height * 1.5)
  readonly property int navigatorRoom: navigatorHeight + Widget.padding * 4
  // The overlay's cards on `screen` in `width` × `height` px of room (the
  // page area less its margin and the box's padding): the card size there
  // times the overlay's Module size, content drawn at that Module size,
  // two cards high at most. { drawn, unit, zoom }, see
  // GridPlacement.overlayLayout
  function layoutFor(screen, width, height) {
    const card = cardUnitOn(screen?.width ?? width, screen?.height ?? height) * moduleScale / 100;
    return GridPlacement.overlayLayout(height, card, GridPlacement.zoomOf(moduleScale / 100));
  }
  // The card size (px) every module grid on a `width` × `height` screen
  // starts from: two cards fill its short side (GridPlacement.baseCard)
  // at the card size (Widget.cardSize). The overlay, edge menus, the
  // desktop, the lock screen and the greeter scale it by their own Module
  // size, so on one monitor they all agree, turned either way
  function cardUnitOn(width, height) {
    return GridPlacement.baseCard(width, height) * Widget.cardSize / 100;
  }

  // A screen layout's (a desktop item's, the lock screen's, the
  // greeter's) `modules` on `screen` in a `width` × `height` px room (its
  // room inside the bars and border): the units that fit there at its
  // card size (cardUnitOn times its Module size, its units split in two
  // each way with grid.fine), each module kept to its nearest edge from the grid it was
  // placed on (`grid.columns` × `grid.rows`), content drawn at its Module size.
  // GridPlacement.screenArrangement's { cols, rows, unit, gap, zoom,
  // places, shrunk }, plus `margin`, the px left all round the grid
  // reads: Desktop.items.moduleScale, Desktop.items.grid, Lockscreen.layout.moduleScale, Lockscreen.layout.grid, Greeter.layout.moduleScale, Greeter.layout.grid
  function screenArrangement(layout, modules, screen, width, height) {
    if (!layout)
      return {
        "cols": 0,
        "rows": 0,
        "unit": 0,
        "gap": cardSpacing,
        "places": [],
        "shrunk": false,
        "zoom": 1,
        "margin": cardSpacing
      };
    const card = cardUnitOn(screen?.width ?? width, screen?.height ?? height) * layout.moduleScale / 100;
    const places = (modules ?? []).map(module => module?.place ?? null);
    const arranged = GridPlacement.screenArrangement(places, GridPlacement.screenGrid(layout.grid), card, width, height, cardSpacing, layout.grid.fine, GridPlacement.zoomOf(layout.moduleScale / 100));
    arranged.margin = cardSpacing;
    return arranged;
  }

  // The card size a Custom page's modules are laid out at on an overlay
  // whose cards are `unit` px: a double grid's (layout.grid.fine) has twice
  // the units across (GridPlacement.fineUnit)
  function pageUnit(view, unit) {
    return view?.layout?.grid?.fine ? GridPlacement.fineUnit(unit) : unit;
  }

  function slotShape(rect) {
    return GridPlacement.slotShape(rect);
  }

  // The size [w, h] a module is added at: its declared one, else a card.
  // Modules take any size (each lays itself out for its slot), so this is
  // only a starting point
  function defaultSize(type) {
    return moduleInfo(type)?.defaultSize ?? [4, 4];
  }

  // The least [w, h] a module dropped into a gap is shrunk to fit it: its
  // declared one, else half its default size. Like the default, only a
  // starting point: it can still be resized smaller
  function minSize(type) {
    return moduleInfo(type)?.minSize ?? defaultSize(type).map(n => Math.max(1, Math.ceil(n / 2)));
  }
}
