pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// A tool page's FieldGroups (and short forms) flowing into newspaper columns
// like a Settings card's rows: as many as the width holds (FlowColumns, a
// column never under Style.columnMin wide), split by ColumnSplit on the
// groups' heights and settled (SettledColumns), their order kept. Children
// are visible `Item`s, each one unit: a hidden one takes no column, none
// spans the area (a full-width row goes above it, in the host's own
// column). It reads only `implicitHeight` and `visible`, so boxed and flat
// groups both work.
Item {
  id: root

  default property alias content: holder.data

  // The gap between groups, down and across (the settings page's card gap)
  property real gap: Style.cardGap
  readonly property int count: FlowColumns.count(root.width, Style.columnTarget, Style.columnMin, Style.columnMax, root.gap)
  // Every child, and of them the visible units in order (a unit's height by
  // index into `units`)
  property var all: []
  property var units: []
  property var heights: []
  readonly property var placed: columns.placed

  implicitHeight: columns.placed.height

  // Re-reads which children show and how tall they are
  function _collect() {
    const next = root.all.filter(child => child.visible);
    root.units = next;
    root.heights = next.map(child => child.implicitHeight);
    columns.relayout();
  }
  function _adopt() {
    root.all = Array.from(holder.children);
    root._collect();
  }

  onWidthChanged: columns.relayout()
  Component.onCompleted: Qt.callLater(root._adopt)
  Connections {
    target: holder
    function onChildrenChanged() {
      Qt.callLater(root._adopt);
    }
  }

  SettledColumns {
    id: columns
    count: root.count
    gap: root.gap
    fill: false
    // None spans the columns
    wide: root.units.map(() => false)
    heights: root.heights
  }

  // The units' own parent (`x`, `y` and `width` of each come from `placed`)
  Item {
    id: holder
    anchors.fill: parent
  }

  // One watcher per child, hidden ones too: a child shown later is heard
  Repeater {
    model: root.all.length

    Item {
      id: slot
      required property int index
      readonly property var unit: root.all[slot.index] ?? null
      readonly property var place: root.placed.cards[root.units.indexOf(slot.unit)] ?? null
      readonly property real columnWidth: (root.width - root.gap * (root.count - 1)) / root.count

      Connections {
        target: slot.unit
        function onImplicitHeightChanged() {
          Qt.callLater(root._collect);
        }
        function onVisibleChanged() {
          Qt.callLater(root._collect);
        }
      }

      Binding {
        target: slot.unit
        property: "x"
        value: slot.place ? Math.round(slot.place.column * (slot.columnWidth + root.gap)) : 0
        when: slot.place !== null
      }
      Binding {
        target: slot.unit
        property: "y"
        value: slot.place ? Math.round(slot.place.y) : 0
        when: slot.place !== null
      }
      Binding {
        target: slot.unit
        property: "width"
        value: Math.round(slot.columnWidth)
        when: slot.place !== null
      }
    }
  }
}
