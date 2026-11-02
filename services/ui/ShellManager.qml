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
  // Shows a message card on an OSD (`axiom message`): the OSD of
  // that id (OSDConfig.messageOsd picks it), where it would open for a
  // change; `text` its title, `detail` a faint second line ("" for none),
  // `tone` "warning" for a refusal (refuse()), else ""
  signal osdMessage(string id, string icon, string text, string detail, string tone)

  // Changes the pointer made in axiom's own bar and panels, by kind
  // (OSDItems.onScreenKind's: "audio", "microphone", "brightness", or a
  // status type), when (Date.now()): an OSD doesn't open for them unless
  // OSD.onScreenChanges. Marked by the UI right before it calls a setter,
  // never by a service, so keys (IPC) and automation are never mistaken
  // for a click
  property var _onScreen: ({})

  function onScreen(kind) {
    root._onScreen[kind] = Date.now();
  }

  // Whether a change of a bar or status type is the pointer's own
  function fromScreen(type) {
    const at = root._onScreen[OSDItems.onScreenKind(type)];
    return at !== undefined && OSDItems.fromScreen(type, Date.now() - at);
  }

  // A message to the OSD `id`, also filed in the notification history
  // without a popup with OSD.cardsToHistory (a refusal isn't: it only
  // answers what was just tried)
  function _message(id, icon, text, detail) {
    root.osdMessage(id, icon, text, detail, "");
    if (id !== "" && OSDConfig.cardsToHistory)
      NotificationManager.sendNotification("axiom", text, detail, {
        "silent": true
      });
  }

  // The same on the warning colour: what a bind, hot corner or `axiom`
  // command that can't run here says instead of nothing. `icon` the base
  // one of what was refused ("nightlight", never "nightlight_off"),
  // `title` what ("Night light"), `detail` why ("Not available here")
  function refuse(icon, title, detail) {
    root.osdMessage(OSDConfig.messageOsd(""), icon, title, detail, "warning");
  }

  property IpcTarget _osdIpc: IpcTarget {
    target: "osd"

    // What `axiom message` calls (IPC functions take no optional
    // arguments, so it passes all four): `id` "" for the OSD showing
    // messages, `detail` "" for no second line
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
  // bind would, or `exec`'s command
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
    BackendManager.call("ipc.call", {
      "target": ipc.target,
      "function": ipc.function,
      "args": ipc.args
    }, error => {
      if (error)
        console.warn("[ShellManager]", action, "failed:", error.message);
    });
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
