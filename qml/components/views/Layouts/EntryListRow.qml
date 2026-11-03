pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable

// A row of an EntryListTarget (`list`): placed by its index, and dragged
// to reorder, carrying { kind (the list's moveKind), index (`entryIndex`),
// icon, label }; faded while it's carried
ListEntryRow {
  id: root

  required property var list
  required property int index
  // What the drag carries as its index: the row's own, unless the list
  // shows a subset (then an index into the whole set)
  property int entryIndex: root.index
  readonly property bool carried: root.list.dragLayer.draggingKind === root.list.moveKind && root.list.dragLayer.dragging.index === root.entryIndex

  width: root.list.width
  height: root.list.rowHeight
  y: root.index * root.list.rowStep
  opacity: root.carried ? 0.3 : 1
  dragArea.dragLayer: root.list.dragLayer
  dragArea.payload: ({
      "kind": root.list.moveKind,
      "index": root.entryIndex,
      "icon": root.icon,
      "label": root.label
    })
}
