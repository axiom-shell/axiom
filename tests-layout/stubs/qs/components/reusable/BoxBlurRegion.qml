import QtQuick

import qs.config

// Stand-in for BoxBlurRegion in the layout harness (the real one is a Quickshell
// Region): the same box mapping, so a test reads its x, y, width and height.
QtObject {
  id: root

  required property Item target
  property var moving: null
  property real opacity: 1
  property real alpha: Appearance.surfaceAlpha
  property real threshold: Appearance.blurThreshold
  property real radius: 0

  readonly property rect _at: {
    void root.moving;
    const b = root.target;
    if (!b || !b.visible || b.width <= 0 || b.height <= 0 || root.alpha * root.opacity < root.threshold)
      return Qt.rect(0, 0, 0, 0);
    void [b.x, b.y, b.scale];
    const p = b.mapToItem(null, 0, 0), q = b.mapToItem(null, b.width, b.height);
    return Qt.rect(Math.min(p.x, q.x), Math.min(p.y, q.y), Math.abs(q.x - p.x), Math.abs(q.y - p.y));
  }
  readonly property real x: Math.floor(root._at.x)
  readonly property real y: Math.floor(root._at.y)
  readonly property real width: Math.ceil(root._at.x + root._at.width) - Math.floor(root._at.x)
  readonly property real height: Math.ceil(root._at.y + root._at.height) - Math.floor(root._at.y)
}
