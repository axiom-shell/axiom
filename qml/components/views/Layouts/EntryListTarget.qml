pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A list of rows (EntryListRows as children, each at `y: index * rowStep`)
// that takes drops of its own rows to reorder them: a "list" target of the
// layouts editor's drag layer. A drop is `dropRequested(drag, index)`,
// index counted as if the carried row were still in place.
Item {
  id: root

  required property var dragLayer
  // The payload kind its rows carry
  required property string moveKind
  property int count: 0

  readonly property real rowHeight: Style.listRowHeight
  readonly property real rowStep: root.rowHeight + Widget.spacing / 2
  readonly property string targetKind: "list"
  readonly property bool hovered: root.dragLayer.hoverTarget === root

  signal dropRequested(var drag, int index)

  function takes(drag) {
    return drag.kind === root.moveKind;
  }

  // Before the first row whose middle is below the point
  function indexAt(point) {
    const p = root.dragLayer.mapToItem(root, point.x, point.y);
    for (let i = 0; i < root.count; i++) {
      if (p.y < i * root.rowStep + root.rowHeight / 2)
        return i;
    }
    return root.count;
  }

  Layout.fillWidth: true
  Layout.preferredHeight: Math.max(0, root.count * root.rowStep - Widget.spacing / 2)

  Component.onCompleted: root.dragLayer.registerTarget(root)
  Component.onDestruction: root.dragLayer.unregisterTarget(root)

  // Where the carried row would land
  DropMark {
    visible: root.hovered
    z: 2
    width: root.width
    y: Math.max(0, root.dragLayer.hoverIndex * root.rowStep - Widget.spacing / 4 - height / 2)
  }
}
