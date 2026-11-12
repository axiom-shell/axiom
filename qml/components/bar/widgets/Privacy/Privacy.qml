pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.services.apps
import qs.config
import qs.components.bar.widgets.base

// Mic / screen share / camera indicators, derived from active Pipewire
// links and the apps holding a camera's device open (no polling). Hidden
// entirely while nothing is capturing.
//   mic:    AudioManager.micCaptures (an app recording from a microphone)
//   screen: PrivacyManager.screenCaptures (a screencast's video linked
//           to a stream), or axiom's own recording (wf-recorder uses
//           screencopy, not the portal, so Pipewire never sees it)
//   camera: PrivacyManager.cameraCaptures (a camera device's video, or an
//           app holding the device open itself, as Vesktop does)
// Drawn one box per indicator (Boxes: One per item), each box is its
// indicator's icon and short name while it's in use.
BarWidget {
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

  // The indicators its settings show (a box of its own shows its one)
  items: ["mic", "screen", "camera"].filter(k => root.properties[{
        "mic": "showMic",
        "screen": "showScreen",
        "camera": "showCamera"
      }[k]])
  readonly property var micUsers: root.shownItems.includes("mic") ? users(AudioManager.micCaptures) : []
  readonly property var screenUsers: root.shownItems.includes("screen") ? users(PrivacyManager.screenCaptures).concat(ScreenshotManager.recording ? [I18n.tr("Screen recording")] : []) : []
  readonly property var cameraUsers: root.shownItems.includes("camera") ? users(PrivacyManager.cameraCaptures) : []

  readonly property var glyphs: [...(micUsers.length ? ["mic"] : []), ...(screenUsers.length ? ["monitor"] : []), ...(cameraUsers.length ? ["camera"] : [])]
  hidden: glyphs.length === 0

  icon: glyphs.join("\n")
  // In a box of its own, its short name, so it splits
  // I18n.tr("Mic") I18n.tr("Screen") I18n.tr("Camera")
  text: root.ownBox ? I18n.tr({
    "mic": "Mic",
    "screen": "Screen",
    "camera": "Camera"
  }[root.shownItems[0]] ?? "") : ""
  showText: root.ownBox

  accentField: "activeColor"

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
