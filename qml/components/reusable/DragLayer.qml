pragma ComponentBehavior: Bound
import QtQuick

// An editor area that carries one drag at a time over its content
// (`content`, the default property): the bar editor's (BarDragLayer) and
// the layouts editor's (GridDragLayer). Drop targets
// register themselves; draggables (DragArea with this as `dragLayer`)
// report their pointer. The target under the pointer is the visible one
// that `accepts` the drag, the highest `priority` winning where targets
// overlap; its `indexAt(point)`, if it has one, gives `hoverIndex`.
// A drop over a target is `dropped`.
Item {
  id: root

  default property alias content: contentItem.data

  // The payload being carried, else null
  property var dragging: null
  // The target under the pointer, and the index a drop there inserts at
  property var hoverTarget: null
  property int hoverIndex: -1
  // Hooks: whether `target` takes `drag`, and which of two overlapping
  // targets wins (by default its `dropPriority`, if it has one: a
  // TrashTarget's is above the rest)
  property var accepts: (target, drag) => true
  property var priority: target => target.dropPriority ?? 0

  property var _targets: []

  // A drag began at (x, y) in `item`
  signal started(var payload, Item item, real x, real y)
  // The pointer moved to `point` (in this item)
  signal moved(point point)
  signal dropped(var drag, var target, int index)

  function registerTarget(target) {
    root._targets = root._targets.concat([target]);
  }

  function unregisterTarget(target) {
    root._targets = root._targets.filter(t => t !== target);
    if (root.hoverTarget === target)
      root.hoverTarget = null;
  }

  // Starts carrying `payload`, picked up at (x, y) in `item`
  function begin(payload, item, x, y) {
    root.dragging = payload;
    root.started(payload, item, x, y);
    root.move(item, x, y);
  }

  // The pointer is at (x, y) in `item`
  function move(item, x, y) {
    const p = item.mapToItem(root, x, y);
    root.moved(p);
    let best = null;
    for (const target of root._targets) {
      if (!target.visible || !root.accepts(target, root.dragging))
        continue;
      const q = root.mapToItem(target, p.x, p.y);
      if (q.x < 0 || q.y < 0 || q.x >= target.width || q.y >= target.height)
        continue;
      if (!best || root.priority(target) > root.priority(best))
        best = target;
    }
    root.hoverTarget = best;
    root.hoverIndex = best && best.indexAt ? best.indexAt(p) : -1;
  }

  // Released: a drop, if over a target
  function end() {
    const drag = root.dragging;
    const target = root.hoverTarget;
    const index = root.hoverIndex;
    root.cancel();
    if (drag && target)
      root.dropped(drag, target, index);
  }

  function cancel() {
    root.dragging = null;
    root.hoverTarget = null;
    root.hoverIndex = -1;
  }

  Item {
    id: contentItem
    anchors.fill: parent
  }
}
