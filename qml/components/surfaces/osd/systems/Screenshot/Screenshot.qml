pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Screenshots on the OSD: a screenshot taken (ScreenshotManager's
// lastShot: not one opened in the annotator, nor one taken for a caller),
// only ever its card: the picture in place of the icon, what happened (the
// service's own words, already translated), Copied to the clipboard and
// the folder. A click on it opens the picture (ScreenshotWatch's activate)
OSDSystem {
  model: "event"
  onAdd: "card"

  // I18n.tr("Screenshots")
  exposes: [
    {
      "key": "screenshot",
      "part": "card",
      "icon": "screenshot_monitor",
      "label": "Screenshots"
    }
  ]

  // state: { event (lastShot: { path, title, folder }), seq }
  function card(change, state) {
    const e = state.screenshot?.event ?? null;
    if (!e)
      return null;
    return {
      "image": e.path ? "file://" + e.path : "",
      "title": e.title ?? "",
      "role": "Copied to the clipboard",
      "detail": e.folder ?? "",
      "clickable": true
    };
  }
}
