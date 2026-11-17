pragma ComponentBehavior: Bound
import QtQuick

// A scaled preview: content drawn at its natural size (`naturalWidth` x
// `naturalHeight`), scaled to fit this frame (at most `maxZoom`, default 1:
// never up; at least `minZoom`, default 0), centred and cut to it. The
// scaled item declares `contentZoom`, so the texts inside draw as under any
// zoom (TextRender.zoomAt). Put the content inside, filling nothing: it is
// `naturalWidth` x `naturalHeight` and anchors fill that.
Item {
  id: root

  // -- Public API --
  property real naturalWidth: 0
  property real naturalHeight: 0
  // The bounds of the zoom: `maxZoom` Infinity lets it scale up, `minZoom`
  // floors it (the fit never goes under it, the content then overflows, cut)
  property real maxZoom: 1
  property real minZoom: 0
  // How far the content is scaled: the fit of the frame's width and (when it
  // has one) height, between `minZoom` and `maxZoom`
  readonly property real zoom: {
    if (root.naturalWidth <= 0 || root.naturalHeight <= 0)
      return 1;
    let fit = root.width > 0 ? root.width / root.naturalWidth : 1;
    if (root.height > 0)
      fit = Math.min(fit, root.height / root.naturalHeight);
    return Math.max(root.minZoom, Math.min(root.maxZoom, fit));
  }
  default property alias content: scaled.data

  // -- Implementation --
  implicitWidth: root.naturalWidth
  implicitHeight: root.naturalHeight
  clip: true

  Item {
    id: scaled
    x: (root.width - width * root.zoom) / 2
    y: (root.height - height * root.zoom) / 2
    width: root.naturalWidth
    height: root.naturalHeight
    scale: root.zoom
    transformOrigin: Item.TopLeft
    readonly property real contentZoom: scaled.scale
  }
}
