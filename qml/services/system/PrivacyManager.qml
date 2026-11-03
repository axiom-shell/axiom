pragma Singleton
import QtQuick
import Quickshell.Services.Pipewire

// Which app streams use the camera or share the screen, from active
// PipeWire links (no polling): the Privacy widget's indicators and the
// OSD's camera and screen sharing statuses. Video comes from a
// `Video/Source` node (a camera, xdg-desktop-portal's screencast) or a
// program's `Stream/Output/Video` (niri's own screencast stream) into an
// app's `Stream/Input/Video`. A camera is a source backed by a device
// (V4L2 or libcamera); any other is a screen share. (A microphone's use is
// AudioManager.micCaptures; axiom's own recording uses screencopy, not
// the portal, so PipeWire never sees it: ScreenshotManager.recording.)
QtObject {
  id: root

  // App input streams (PwNodes) sharing the screen / using a camera, once
  // each
  readonly property var screenCaptures: root._targets(false)
  readonly property var cameraCaptures: root._targets(true)

  // -- Private --

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
