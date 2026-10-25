pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire

import qs.services.system
import qs.services.apps
import qs.config
import qs.components.bar.widgets.base

// Mic / screen share / camera indicators, derived from active Pipewire
// links (no polling). Hidden entirely while nothing is capturing.
//   mic:    AudioManager.micCaptures (an app recording from a microphone)
//   screen: a video source from xdg-desktop-portal linked to a stream, or
//           axiom's own recording (wf-recorder uses screencopy, not the
//           portal, so Pipewire never sees it)
//   camera: any other video source linked to a stream
BarIconWidget {
  id: root

  readonly property var ignoredApps: properties.ignoreApps.map(a => a.trim().toLowerCase()).filter(a => a !== "")

  // Links out of a video source (mic use comes from Audio). A link group's
  // state reads Unlinked until the group is bound, so all are tracked.
  readonly property var videoGroups: Pipewire.linkGroups.values.filter(g => g && g.source?.type === PwNodeType.VideoSource && g.target)
  readonly property var activeGroups: videoGroups.filter(g => g.state === PwLinkState.Active)

  function appName(node) {
    return node.properties?.["application.name"] || node.nickname || node.name || I18n.tr("Unknown");
  }
  function ignored(node) {
    const names = [node.name, node.properties?.["application.name"], node.properties?.["application.process.binary"]];
    return names.some(n => n && root.ignoredApps.includes(n.toLowerCase()));
  }
  // Quickshell has no type for `Stream/Input/Video`, so a screen/camera
  // consumer is Untracked and `isStream` is false; read the media class.
  function isVideoStream(node) {
    return (node.properties?.["media.class"] ?? "") === "Stream/Input/Video";
  }
  function isPortal(node) {
    return (node.name || "").startsWith("xdg-desktop-portal");
  }
  // Unique app names capturing from sources matching `sourceTest`
  function users(sourceTest, targetTest) {
    const names = activeGroups.filter(g => sourceTest(g.source) && targetTest(g.target) && !ignored(g.target)).map(g => appName(g.target));
    return [...new Set(names)];
  }

  readonly property var micUsers: properties.showMic ? [...new Set(AudioManager.micCaptures.filter(n => !ignored(n)).map(n => appName(n)))] : []
  readonly property var screenUsers: properties.showScreen ? users(s => s.type === PwNodeType.VideoSource && isPortal(s), t => isVideoStream(t)).concat(ScreenshotManager.recording ? [I18n.tr("Screen recording")] : []) : []
  readonly property var cameraUsers: properties.showCamera ? users(s => s.type === PwNodeType.VideoSource && !isPortal(s), t => isVideoStream(t)) : []

  readonly property var glyphs: [...(micUsers.length ? ["mic"] : []), ...(screenUsers.length ? ["monitor"] : []), ...(cameraUsers.length ? ["camera"] : [])]
  hidden: glyphs.length === 0

  icon: glyphs.join(isVertical ? "\n" : " ")
  showText: false

  accentColor: Theme.resolveColor(properties.activeColor)

  // Binds the link groups (for their state) and the linked nodes (for
  // media.class / application.name)
  PwObjectTracker {
    objects: root.videoGroups.concat(...root.videoGroups.map(g => [g.source, g.target]))
  }

  clickable: true
  onClicked: {
    const lines = [];
    if (root.micUsers.length)
      lines.push(I18n.tr("Microphone: {0}", root.micUsers.join(", ")));
    if (root.screenUsers.length)
      lines.push(I18n.tr("Screen: {0}", root.screenUsers.join(", ")));
    if (root.cameraUsers.length)
      lines.push(I18n.tr("Camera: {0}", root.cameraUsers.join(", ")));
    NotificationManager.sendNotification("axiom", I18n.tr("Privacy"), lines.join("\n"));
  }
}
