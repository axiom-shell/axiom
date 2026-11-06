pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

/*
 * axiom's screen-share picker: the daemon's screenshare.request (a portal
 * asking what to share: xdg-desktop-portal-hyprland's and -wlr's through
 * `axiom screenshare-pick`, niri's through axiom's own ScreenCast portal)
 * shows the picker (ScreenSharePicker) on the focused screen, and the
 * user's choice goes back as screenshare.answer. The daemon closes one
 * whose asker gave up (screenshare.done). A region is dragged in the
 * screenshot picker (ScreenshotManager.pickArea).
 * The hookup (ScreenShareSources.hookupTargets) points the compositor's
 * portal at axiom once; the ScreenSharing settings decide, at each request,
 * whether axiom's picker or the portal's own answers.
 */
Singleton {
  id: root

  // The request shown ({ id, backend, appId, outputs, windows, region }),
  // or null
  readonly property var request: root._request
  // The screen the picker shows on
  readonly property string screenName: root._screenName
  // Picking a region (the picker steps aside meanwhile)
  readonly property bool pickingRegion: root._pickingRegion

  // The portal this compositor shares through (ScreenShareSources.portals),
  // and the hookup that points it at axiom: the binary the daemon runs
  // (in dev mode the dev build, which has the picker the install may not)
  readonly property var portal: ScreenShareSources.portal(CompositorManager.kind)
  readonly property string pickerBinary: BackendManager.dev?.active && BackendManager.dev?.binary ? BackendManager.dev.binary : Paths.axiomBin
  // I18n.tr("Adds the line at the end: Hyprland's portal runs axiom as its share picker.")
  // I18n.tr("Sets the [screencast] chooser: wlroots' portal asks axiom what to share.")
  // I18n.tr("Under niri, screen sharing goes to axiom's own portal; everything else stays with GNOME's.")
  readonly property var hookupTargets: ScreenShareSources.hookupTargets(CompositorManager.kind, root.pickerBinary)

  // Whether the portal backend is installed (and under niri, axiom's own
  // portal file), as checkPortal() last found
  readonly property bool portalInstalled: root._portalInstalled
  readonly property bool axiomPortalInstalled: root._axiomPortalInstalled
  property bool _portalInstalled: false
  property bool _axiomPortalInstalled: false

  // Where xdg-desktop-portal finds .portal files
  function _portalDirs() {
    const dataHome = Quickshell.env("XDG_DATA_HOME") || Paths.homeDirectory + ".local/share";
    const dataDirs = (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":");
    return [dataHome].concat(dataDirs, ["/usr/share"]).map(d => d.replace(/\/?$/, "/") + "xdg-desktop-portal/portals/");
  }

  function _hasPortalFile(name) {
    return !!name && root._portalDirs().some(dir => FileManager.read(dir + name) !== null);
  }

  // Looks for the portal files (the settings card asks as it shows)
  function checkPortal() {
    root._portalInstalled = root._hasPortalFile(root.portal?.portalFile);
    root._axiomPortalInstalled = !root.portal?.axiomPortalFile || root._hasPortalFile(root.portal.axiomPortalFile);
  }

  property var _request: null
  property string _screenName: ""
  property bool _pickingRegion: false
  // A test request's answer goes to the log, not the daemon
  property bool _test: false

  function _show(request) {
    if (Paths.greeter)
      return;
    root._screenName = CompositorManager.focusedOutput || General.primaryMonitor;
    root._pickingRegion = false;
    root._request = request;
  }

  // Shares `choice` ({ kind: "screen", output } | { kind: "window",
  // window: token } | { kind: "region", output, rect: { x, y, w, h } })
  function answer(choice) {
    root._reply({
      "choice": choice
    });
  }

  function cancel() {
    root._reply({
      "cancel": true
    });
  }

  function _reply(answer) {
    const request = root._request;
    if (!request)
      return;
    root._request = null;
    root._pickingRegion = false;
    if (root._test) {
      root._test = false;
      console.info("[ScreenShareManager] test answer:", JSON.stringify(answer));
      return;
    }
    BackendManager.call("screenshare.answer", {
      "id": request.id,
      "choice": answer.choice ?? null,
      "cancel": answer.cancel === true
    }, error => {
      if (error)
        console.warn("[ScreenShareManager] answering:", error.message);
    });
  }

  // Hides the picker to drag a region in the screenshot picker; a cancel
  // there comes back to the picker
  function pickRegion() {
    if (!root._request?.region || root._pickingRegion)
      return;
    root._pickingRegion = true;
    const asked = root._request;
    if (!ScreenshotManager.pickArea((screenName, rect) => {
      if (root._request !== asked)
        return;
      root._pickingRegion = false;
      if (screenName && rect)
        root.answer({
          "kind": "region",
          "output": screenName,
          "rect": {
            "x": Math.round(rect.x),
            "y": Math.round(rect.y),
            "w": Math.round(rect.width),
            "h": Math.round(rect.height)
          }
        });
    }))
      root._pickingRegion = false;
  }

  // Restarts the portal services, so a hookup applied takes effect (a
  // share running ends)
  function restartPortal() {
    const services = ["xdg-desktop-portal.service"].concat((root.portal?.services ?? []).map(s => s + ".service"));
    CommandManager.run(["systemctl", "--user", "restart"].concat(services), (code, stdout, stderr) => {
      if (code !== 0)
        console.warn("[ScreenShareManager] restarting the portal:", stderr.trim());
    });
  }

  // Opens the picker with what the compositor shows now, its answer only
  // logged: to see the picker without a portal
  function openTest() {
    const windows = CompositorManager.windows.map(w => ({
          "token": String(w.id),
          "id": String(w.id),
          "title": w.title,
          "appId": w.appId
        }));
    root._test = true;
    root._show({
      "id": "test",
      "backend": "test",
      "appId": "",
      "outputs": General.outputs.map(s => ({
            "name": s.name
          })),
      "windows": windows,
      "region": CompositorManager.supports.windowGeometry === true
    });
  }

  Component.onCompleted: {
    BackendManager.listen("screenshare.request", request => {
      root._test = false;
      root._show(request);
    });
    BackendManager.listen("screenshare.done", done => {
      if (root._request?.id === done.id) {
        root._request = null;
        root._pickingRegion = false;
      }
    });
  }

  property IpcTarget _ipc: IpcTarget {
    target: "screenshare"

    // Opens the picker with what the compositor shows now, its answer only
    // logged: to see the picker without a portal
    function test(): void {
      root.openTest();
    }

    // Shares what the picker opens on (the focused screen)
    function share(): void {
      const choice = ScreenShareSources.initialChoice(root._request, CompositorManager.focusedOutput);
      if (choice)
        root.answer(choice);
    }

    function cancel(): void {
      root.cancel();
    }
  }
}
