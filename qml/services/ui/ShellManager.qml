pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.system

/* The shell's signals, link navigation and screen targeting */
QtObject {
  id: root

  signal togglePowerMenu
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

  // The overlay page a link was last followed from (a view type, or ""),
  // or "window:<type>" for a page window's: the navigator offers to go
  // back to it until the user navigates themselves or the overlay closes
  // (OverlayPages keeps it)
  readonly property string linkOrigin: _linkOrigin
  property string _linkOrigin: ""
  // Whether the page switch under way is a link being followed
  readonly property bool followingLink: _followingLink
  property bool _followingLink: false
  // The page window the link under way was followed from, "" for the
  // overlay (PageWindowManager.activeType as it was followed)
  readonly property string linkFromWindow: _linkFromWindow
  property string _linkFromWindow: ""

  // Opens a page as a link from the current one (SettingsLink, a page
  // button), so the navigator offers the way back. From a page window, a
  // page that's in a window of its own is gone to, any other opens in the
  // overlay, whose way back returns to the window
  function followLink(type) {
    _followingLink = true;
    _linkFromWindow = PageWindowManager.activeType;
    openOverlayPage(type);
    _followingLink = false;
    _linkFromWindow = "";
  }

  // Sets or ("") drops the way back (OverlayPages, as it switches pages)
  function setLinkOrigin(type) {
    _linkOrigin = type;
  }

  // Back to the page the last link was followed from
  function followLinkBack() {
    const origin = _linkOrigin;
    _linkOrigin = "";
    if (origin.startsWith("window:")) {
      PageWindowManager.focus(origin.slice("window:".length));
    } else if (origin !== "") {
      showOverlayPage(origin);
    }
  }
  // Opens an OSD by id where it would open for a change (the settings
  // page's Show button)
  signal showOsd(string id)
  // Shows a message card on an OSD (`axiom message`): the OSD of
  // that id (OSDConfig.messageOsd picks it), where it would open for a
  // change; `text` its title, `detail` a faint second line ("" for none),
  // `tone` "warning" for a refusal (refuse()), else ""
  signal osdMessage(string id, string icon, string text, string detail, string tone)

  // Changes the pointer made in axiom's own bar and panels, by kind (an
  // OSD system's mark: "audio", "microphone", "brightness", or a tile's
  // key), when (Date.now()): an OSD doesn't open for them unless
  // OSD.onScreenChanges. Marked by the UI right before it calls a setter,
  // never by a service, so keys (IPC) and automation are never mistaken
  // for a click
  property var _onScreen: ({})

  function onScreen(kind) {
    root._onScreen[kind] = Date.now();
  }

  // Whether a change judged by the mark `kind` is the pointer's own:
  // marked less than `window` ms ago (the OSD system's userWindow; a mark
  // from the future, after a clock change, isn't)
  function fromScreen(kind, window) {
    const at = root._onScreen[kind];
    if (at === undefined)
      return false;
    const elapsed = Date.now() - at;
    return elapsed >= 0 && elapsed < window;
  }

  // A message to the OSD `id` (OSDConfig.messageOsd's) as its card, also
  // filed in the notification history without a popup with
  // OSD.cardsToHistory; with none (no OSD picks Messages) a notification
  // instead
  function _message(id, icon, text, detail) {
    if (id === "") {
      NotificationManager.sendNotification("axiom", text, detail);
      return;
    }
    root.osdMessage(id, icon, text, detail, "");
    if (OSDConfig.cardsToHistory)
      NotificationManager.sendNotification("axiom", text, detail, {
        "silent": true
      });
  }

  // What something just asked for answers once done (the calendar's
  // quick add: "Added …"): its card on the OSD picking Messages, never
  // filed; a toast that isn't kept (transient) where none does
  function confirm(icon, title, detail) {
    root._answer(icon, title, detail, "");
  }

  // The same on the warning colour: what a bind, hot corner or `axiom`
  // command that can't run here says instead of nothing (never filed: it
  // only answers what was just tried). `icon` the base one of what was
  // refused ("nightlight", never "nightlight_off"), `title` what ("Night
  // light"), `detail` why ("Not available here")
  function refuse(icon, title, detail) {
    root._answer(icon, title, detail, "warning");
  }

  function _answer(icon, title, detail, tone) {
    const id = OSDConfig.messageOsd("");
    if (id === "") {
      NotificationManager.sendNotification("axiom", title, detail, {
        "transient": true
      });
      return;
    }
    root.osdMessage(id, icon, title, detail, tone);
  }

  property IpcTarget _osdIpc: IpcTarget {
    target: "osd"

    // What `axiom message` calls (IPC functions take no optional
    // arguments, so it passes all four): `id` "" for the first OSD
    // picking Messages (none: a notification), `detail` "" for no second
    // line
    function message(id: string, icon: string, text: string, detail: string): void {
      root._message(OSDConfig.messageOsd(id), icon, text, detail);
    }

    function show(id: string): void {
      root.showOsd(id);
    }
  }

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

  // Runs an axiom action (the keybind table's ipcActions: "overlayPage"
  // with its page, "lock", …) with its call (toggle, open or close) as its
  // bind would, through the same IPC function in place, or `exec`'s
  // command. ActionsManager.run is the UI's way in (it marks a click first)
  function runAction(action, argument, call) {
    if (action === "exec") {
      CommandManager.runDetached(argument);
      return;
    }
    const ipc = BindActions.ipcCall(KeybindManager.actionTable, action, argument, call);
    if (!ipc) {
      console.warn("[ShellManager] can't run action", action);
      return;
    }
    BackendManager.callLocal(ipc.target, ipc.function, ipc.args);
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
}
