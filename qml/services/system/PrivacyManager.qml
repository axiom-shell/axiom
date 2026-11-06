pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

import qs.config
import qs.services.core

// Which app streams use the camera or share the screen, from active
// PipeWire links (no polling), and the apps holding a camera's device open
// themselves (axiom's `camera.state`, internal/camera: Chromium and
// Electron apps such as Vesktop read V4L2, not PipeWire): the Privacy
// widget's indicators and the OSD's camera and screen sharing statuses. Video comes from a
// `Video/Source` node (a camera, xdg-desktop-portal's screencast) or a
// program's `Stream/Output/Video` (niri's own screencast stream) into an
// app's `Stream/Input/Video`. A camera is a source backed by a device
// (V4L2 or libcamera); any other is a screen share. (A microphone's use is
// AudioManager.micCaptures; axiom's own recording uses screencopy, not
// the portal, so PipeWire never sees it: ScreenshotManager.recording.)
QtObject {
  id: root

  // App input streams (PwNodes) sharing the screen / using a camera, once
  // each. A camera's also lists the apps holding its device open, as
  // objects shaped like a stream's node (id, name, properties: what
  // AudioManager.appName and the Privacy widget's ignore list read)
  readonly property var screenCaptures: root._targets(false)
  readonly property var cameraCaptures: root._targets(true).concat(root._deviceUsers)

  // -- Private --

  // The apps holding a camera's device open (camera.state's users), as
  // nodes: an id by the app ("device:" + its key, never a PipeWire id,
  // and the same while it holds it), its desktop entry's name (its
  // flatpak id's entry, else one found by its process name; read again
  // as the desktop entries load or change)
  readonly property var _deviceUsers: {
    void DesktopEntries.applications.values;
    return root._devices.map(u => {
      const entry = (u.app ? DesktopEntries.byId(u.app) : null) ?? DesktopEntries.heuristicLookup(u.app || u.comm);
      return {
        "id": "device:" + u.key,
        "name": u.comm,
        "properties": {
          "application.name": entry?.name || u.app || u.comm,
          "application.process.binary": u.comm
        }
      };
    });
  }
  // camera.state's users: [{ key, app, comm, pid }]
  property var _devices: []

  function _showDevices(state) {
    root._devices = state.users ?? [];
  }

  function _fetchDevices() {
    BackendManager.call("camera.get", {}, (error, state) => {
      if (!error)
        root._showDevices(state);
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    enabled: !Paths.greeter
    function onGreeted() {
      root._fetchDevices();
    }
  }

  Component.onCompleted: {
    // The login screen's axiom doesn't watch the devices
    if (Paths.greeter)
      return;
    BackendManager.listen("camera.state", state => root._showDevices(state));
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._fetchDevices();
  }

  // Links that may carry video: out of a video source, or between two
  // nodes Quickshell gives no type (it types no video stream, so niri's
  // screencast and the app reading it are both Untracked). Their media
  // class is read once the tracker binds them. A link group's state reads
  // Unlinked until the group is bound, so every candidate is tracked
  readonly property var _videoGroups: Pipewire.linkGroups.values.filter(g => g && g.source && g.target && (g.source.type === PwNodeType.VideoSource || (g.source.type === PwNodeType.Untracked && g.target.type === PwNodeType.Untracked)))
  readonly property var _activeGroups: root._videoGroups.filter(g => g.state === PwLinkState.Active && root._isVideoSource(g.source) && root._isVideoStream(g.target))

  // Binds the link groups (for their state) and the linked nodes (for
  // media.class / application.name)
  property PwObjectTracker _tracker: PwObjectTracker {
    objects: root._videoGroups.concat(...root._videoGroups.map(g => [g.source, g.target]))
  }

  // Quickshell has no type for `Stream/Input/Video`, so a screen or camera
  // consumer is Untracked and `isStream` is false: its media class says
  function _isVideoStream(node) {
    return (node.properties?.["media.class"] ?? "") === "Stream/Input/Video";
  }

  function _isVideoSource(node) {
    if (node.type === PwNodeType.VideoSource)
      return true;
    return (node.properties?.["media.class"] ?? "") === "Stream/Output/Video";
  }

  // A camera's node is a device's (the webcam's: `device.api` v4l2); a
  // screencast's is a stream some program made
  function _isCamera(node) {
    const api = node.properties?.["device.api"] ?? "";
    return api === "v4l2" || api === "libcamera";
  }

  function _targets(camera) {
    const out = [];
    for (const g of root._activeGroups) {
      if (root._isCamera(g.source) === camera && !out.includes(g.target))
        out.push(g.target);
    }
    return out;
  }
}
