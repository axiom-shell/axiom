pragma ComponentBehavior: Bound
import Quickshell
import QtQuick

import qs.config

// One box as a blur region (BackgroundEffect.blurRegion, where the
// compositor blurs only what a window asks: supports.blurRegion), in its
// window's coordinates, its corners rounded as the box's (a Rectangle's
// `radius`; set `radius` for another). A Region's own
// `item` is read again only when that item moves itself, so the box is
// mapped here, again whenever `moving` changes: whatever else moves it
// (a parent sliding, a transform), and as it scales. Empty while there's
// no box, it's hidden, or its fill is drawn under the blur threshold
// (`alpha` × `opacity`: the pixel's alpha, as Hyprland's ignore_alpha
// compares it).
Region {
  id: root

  required property Item target
  // What moves the box besides its own geometry (a slide's offset)
  property var moving: null
  // How opaque it's drawn now (a fade), and under what it isn't blurred:
  // the blur threshold, or nearly nothing for a dim (a backdrop)
  property real opacity: 1
  // The fill's own alpha: the surface opacity, or a dim's color
  property real alpha: Appearance.surfaceAlpha
  property real threshold: Appearance.blurThreshold

  radius: (root.target as Rectangle)?.radius ?? 0

  readonly property rect _at: {
    void root.moving;
    const b = root.target;
    if (!b || !b.visible || b.width <= 0 || b.height <= 0 || root.alpha * root.opacity < root.threshold)
      return Qt.rect(0, 0, 0, 0);
    // (each read so a change maps it again)
    void [b.x, b.y, b.scale];
    // Both corners, so a scale (an opening box) counts
    const p = b.mapToItem(null, 0, 0), q = b.mapToItem(null, b.width, b.height);
    return Qt.rect(Math.min(p.x, q.x), Math.min(p.y, q.y), Math.abs(q.x - p.x), Math.abs(q.y - p.y));
  }
  x: Math.floor(root._at.x)
  y: Math.floor(root._at.y)
  width: Math.ceil(root._at.x + root._at.width) - Math.floor(root._at.x)
  height: Math.ceil(root._at.y + root._at.height) - Math.floor(root._at.y)
}
