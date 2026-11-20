pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.apps
import qs.services.ui
import qs.components.content.parts
import qs.components.content.base

// Screenshots through ScreenshotManager (region, active window or the
// focused screen), saved to the Screenshots section's folder and copied to
// the clipboard. Recording (ScreenshotManager, with wf-recorder) shows only
// when it's installed.
Card {
  id: root

  readonly property bool recording: ScreenshotManager.recording

  // The actions this machine can do, in the card's order; the record tile's
  // icon, label and active state follow `recording`, so a toggle rebuilds nothing
  readonly property var actions: root.properties.actions.filter(a => a === "record" ? ScreenshotManager.hasRecorder : ScreenshotManager.kinds.includes(a))
  readonly property var info: ({
      "region": {
        "icon": "screenshot_region",
        "label": I18n.tr("Region")
      },
      "window": {
        "icon": "wrap_text",
        "label": I18n.tr("Window")
      },
      "screen": {
        "icon": "screenshot_monitor",
        "label": I18n.tr("Screen")
      },
      "record": {
        "icon": root.recording ? "stop" : "fiber_manual_record",
        "label": root.recording ? I18n.tr("Stop") : I18n.tr("Record")
      }
    })

  // Recordings ignore `annotate`. ScreenshotManager clears it at every
  // capture, so it is set after the run, and only on one this click started
  function capture(mode) {
    if (mode === "record") {
      ActionsManager.run("screenRecord");
      return;
    }
    const was = ScreenshotManager.busy;
    ActionsManager.run("screenshot", {
      "argument": mode
    });
    if (!was && ScreenshotManager.busy && root.properties.annotate)
      ScreenshotManager.annotate = true;
  }

  ActionTiles {
    anchors.fill: parent
    anchors.margins: root.pad
    style: "tiles"
    labels: root.properties.labels
    tiles: root.actions.map(m => ({
          "icon": root.info[m].icon,
          "label": root.info[m].label,
          "active": m === "record" && root.recording,
          "tone": "error"
        }))
    onClicked: index => root.capture(root.actions[index])
  }
}
