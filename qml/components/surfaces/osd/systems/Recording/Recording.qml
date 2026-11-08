pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Screen recording on the OSD: axiom's own recording, one tile, lit and
// unusual while on, hidden with no recorder; either way its icon. A click
// on it only stops a recording running (RecordingWatch reads
// ScreenshotManager)
OSDSystem {
  // I18n.tr("Screen recording")
  exposes: [
    {
      "key": "recording",
      "part": "tile",
      "icon": "screen_record",
      "label": "Screen recording"
    }
  ]

  // state: { available (a recorder found), value (recording) }: the
  // default tile, hidden with no recorder

  // Clickable only while it records, and a click stops it
  function actionOf(key, state) {
    return state?.value === true ? {
      "id": "screenRecord",
      "call": "close"
    } : null;
  }
}
