pragma ComponentBehavior: Bound
import QtQuick

// Shows a layout's items in reverse order while `reversed` (a popout
// growing up keeps its controls last, by the bar: Panel.flips). Each item
// is taken out and appended again, last first, so it keeps its Layout
// properties. Only for a layout of plain items: a Repeater directly in it
// would put its rows back in place.
QtObject {
  id: root

  required property Item layout
  property bool reversed: false
  property bool _done: false
  property Item _holding: Item {
    visible: false
  }

  onReversedChanged: root.apply()
  onLayoutChanged: root.apply()
  Component.onCompleted: root.apply()

  function apply() {
    if (!root.layout || root._done === root.reversed)
      return;
    const items = [];
    for (let i = 0; i < root.layout.children.length; i++)
      items.push(root.layout.children[i]);
    for (const item of items)
      item.parent = root._holding;
    for (let i = items.length - 1; i >= 0; i--)
      items[i].parent = root.layout;
    root._done = root.reversed;
  }
}
