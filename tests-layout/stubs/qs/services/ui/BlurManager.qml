pragma Singleton
import QtQuick

import qs.config

// Stand-in for the shell's BlurManager in the layout harness: a registry of
// BlurShapes, no screens (never paused, never opaque)
QtObject {
  id: root

  property var shapes: []
  property int _lastUid: 0
  property var _byUid: ({})

  function register(shape) {
    if (root.shapes.includes(shape))
      return;
    shape.uid = ++root._lastUid;
    root._byUid[shape.uid] = shape;
    root.shapes = root.shapes.concat([shape]);
  }

  function unregister(shape) {
    if (!root.shapes.includes(shape))
      return;
    delete root._byUid[shape.uid];
    root.shapes = root.shapes.filter(s => s !== shape);
  }

  function shapeOf(uid) {
    return root._byUid[uid] ?? null;
  }

  function fillOn(color, screen) {
    return Style.edgeFill(color, false);
  }
}
