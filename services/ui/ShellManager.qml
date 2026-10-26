pragma Singleton
import QtQuick

import qs.config
import qs.services.compositor

/* The shell's signals, link navigation and screen targeting */
QtObject {
  signal openPowerMenu
  signal toggleAppLauncher
  signal toggleOverlay
  signal toggleWorkspaceOverlay
  // Switch the overlay to a page by view type or a view's name ("Themes" and
  // "Layouts" for the pinned page), e.g. from a settings link
  signal showOverlayPage(string type)
  // Opens the target overlay on a page (a view type, or a view's name)
  signal openOverlayPage(string type)
  // Closes the overlay wherever it's open
  signal closeOverlay

  // The overlay page a link was last followed from (a view type, or ""):
  // the navigator offers to go back to it until the user navigates
  // themselves or the overlay closes (OverlayPages keeps it)
  readonly property string linkOrigin: _linkOrigin
  property string _linkOrigin: ""
  // Whether the page switch under way is a link being followed
  readonly property bool followingLink: _followingLink
  property bool _followingLink: false

  // Opens a page as a link from the current one (SettingsLink, a page
  // button), so the navigator offers the way back
  function followLink(type) {
    _followingLink = true;
    openOverlayPage(type);
    _followingLink = false;
  }

  // Sets or ("") drops the way back (OverlayPages, as it switches pages)
  function setLinkOrigin(type) {
    _linkOrigin = type;
  }

  // Back to the page the last link was followed from
  function followLinkBack() {
    const origin = _linkOrigin;
    _linkOrigin = "";
    if (origin !== "")
      showOverlayPage(origin);
  }
  // Opens an OSD by id where it would open for a change (the settings
  // page's Show button)
  signal showOsd(string id)

  // Opens the overlay page with the biggest module of the first of `types`
  // any page has, else an edge menu with one (the first of `types` again);
  // false with none
  function openModule(types) {
    for (const type of types) {
      const page = OverlayConfig.pageWithModule(type);
      if (page !== "") {
        openOverlayPage(page);
        return true;
      }
    }
    for (const type of types) {
      const menu = EdgeMenusConfig.menuWithModule(type);
      if (menu) {
        EdgeMenuManager.reveal(menu.id);
        return true;
      }
    }
    return false;
  }

  // A surface's ScreenTarget mode with "inherit" resolved: "primary" |
  // "focused" | "all" | "named" (no target is General's)
  function modeFor(target) {
    const mode = target?.mode ?? "inherit";
    return mode === "inherit" ? General.screen.mode : mode;
  }

  // The screen whose instance of a surface answers a shortcut or IPC call
  // and holds the keyboard: the focused monitor when it opens there or
  // everywhere, else the first it's built on
  function targetFor(target) {
    const resolved = modeFor(target);
    if (resolved === "focused" || resolved === "all")
      return CompositorManager.focusedOutput || General.primaryMonitor;
    return General.screensFor(target)[0]?.name ?? "";
  }

  function isTarget(screen, target) {
    return !!screen && screen.name === targetFor(target);
  }

  // Opens on every monitor at once (SurfaceGroup keeps the instances in step)
  function everywhere(target) {
    return modeFor(target) === "all";
  }

  // Whether a surface opened for its target also shows on `screen`
  function showsOn(screen, target) {
    return !!screen && (everywhere(target) || isTarget(screen, target));
  }

  // The bar windows (BarPanel), for surfaces that attach to a bar without
  // being its popouts (floating edge menus)
  property var barPanels: []

  function registerBar(panel) {
    barPanels = barPanels.filter(p => p !== panel).concat([panel]);
  }

  function unregisterBar(panel) {
    barPanels = barPanels.filter(p => p !== panel);
  }

  // The enabled bar on a screen edge (a Bar.Location), or null
  function barOn(screenName, location) {
    return barPanels.find(p => p.barConfig.enabled && p.barConfig.location === location && p.screen?.name === screenName) ?? null;
  }
}
