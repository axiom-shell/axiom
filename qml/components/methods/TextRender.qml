pragma Singleton
import QtQuick

// How text is rasterised: native (hinted, on whole device pixels) at rest,
// distance field where an ancestor zooms it. Called in a binding, so it
// re-runs on reparent.
//
// Both walks stop at a publisher (a Surface's drawnZoom, a relay's inkHostAbove
// and drawnZoom), so a text walks only to the nearest one; the publisher's own
// binding re-runs on a reparent or zoom change above it.
QtObject {
  id: root

  // The product of `contentZoom` over `start` and its visual parents (1 with
  // none): how far the text is drawn scaled
  function zoomAt(start) {
    let zoom = 1;
    for (let item = start; item; item = item.parent) {
      if ("drawnZoom" in item)
        return zoom * item.drawnZoom;
      if ("contentZoom" in item)
        zoom *= item.contentZoom;
    }
    return zoom;
  }

  // Native rendering at rest (within 1 %) or for a filled symbol, which the
  // distance-field renderer draws as blotches; else distance field
  function typeFor(zoom, symbol, fill) {
    return Math.abs(zoom - 1) <= 0.01 || (symbol && fill) ? Text.NativeRendering : Text.QtRendering;
  }
}
