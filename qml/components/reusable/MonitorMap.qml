pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// Monitors where they stand, read-only: a `delegate` per entry of `model`
// (given `modelData` and `index`), placed over its rect in `rects` (layout
// pixels, by index: x, y, width and height are set here), the whole layout
// fitted in the item and centred, `margin` inside each side
Item {
  id: root

  // { x, y, width, height } per model entry, in layout (logical) pixels
  property var rects: []
  property var model: []
  property Component delegate: null
  property real margin: 0

  // Layout pixels to the item's (MonitorLayout.fit)
  readonly property var view: MonitorLayout.fit(root.rects, root.width, root.height, root.margin)

  function _placed(index) {
    const rect = root.rects[index];
    return rect ? MonitorLayout.place(rect, root.view) : {
      "x": 0,
      "y": 0,
      "width": 0,
      "height": 0
    };
  }

  Repeater {
    model: root.model
    delegate: root.delegate

    onItemAdded: (index, item) => {
      item.x = Qt.binding(() => root._placed(index).x);
      item.y = Qt.binding(() => root._placed(index).y);
      item.width = Qt.binding(() => root._placed(index).width);
      item.height = Qt.binding(() => root._placed(index).height);
    }
  }
}
