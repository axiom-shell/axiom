pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.services.apps
import qs.config
import qs.components.bar.widgets.base

// Mic / screen share / camera indicators, derived from active Pipewire
// links (no polling). Hidden entirely while nothing is capturing.
//   mic:    AudioManager.micCaptures (an app recording from a microphone)
//   screen: PrivacyManager.screenCaptures (a screencast's video linked
//           to a stream), or axiom's own recording (wf-recorder uses
//           screencopy, not the portal, so Pipewire never sees it)
//   camera: PrivacyManager.cameraCaptures (a camera device's video)
BarIconWidget {
  id: root

  readonly property var ignoredApps: properties.ignoreApps.map(a => a.trim().toLowerCase()).filter(a => a !== "")

  function ignored(node) {
    const names = [node.name, node.properties?.["application.name"], node.properties?.["application.process.binary"]];
    return names.some(n => n && root.ignoredApps.includes(n.toLowerCase()));
  }
  // Unique app names of the streams, past the ignored ones
  function users(nodes) {
    return [...new Set(nodes.filter(n => !root.ignored(n)).map(n => AudioManager.appName(n)))];
  }

  readonly property var micUsers: properties.showMic ? users(AudioManager.micCaptures) : []
  readonly property var screenUsers: properties.showScreen ? users(PrivacyManager.screenCaptures).concat(ScreenshotManager.recording ? [I18n.tr("Screen recording")] : []) : []
  readonly property var cameraUsers: properties.showCamera ? users(PrivacyManager.cameraCaptures) : []

  readonly property var glyphs: [...(micUsers.length ? ["mic"] : []), ...(screenUsers.length ? ["monitor"] : []), ...(cameraUsers.length ? ["camera"] : [])]
  hidden: glyphs.length === 0

  icon: glyphs.join(isVertical ? "\n" : " ")
  showText: false

  accentColor: Theme.resolveColor(properties.activeColor)

  clickable: true
  onClicked: {
    const lines = [];
    if (root.micUsers.length)
      lines.push(I18n.tr("Microphone: {0}", root.micUsers.join(", ")));
    if (root.screenUsers.length)
      lines.push(I18n.tr("Screen: {0}", root.screenUsers.join(", ")));
    if (root.cameraUsers.length)
      lines.push(I18n.tr("Camera: {0}", root.cameraUsers.join(", ")));
    // An answer: a toast that isn't kept
    NotificationManager.sendNotification("axiom", I18n.tr("Privacy"), lines.join("\n"), {
      "transient": true
    });
  }
}
