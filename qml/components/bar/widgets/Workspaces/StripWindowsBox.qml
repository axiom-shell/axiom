pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.config
import qs.services.system
import qs.components.methods
import qs.components.bar.look

// A strip workspace's windows in one bar cell (`stripWindows: one`): a box
// in the widget's style and its occupied color, holding every window's app
// icon in strip order (CompositorManager.stripWindows), no limit, along the
// bar. Each icon has a cell's room, the cells' `spacing` apart, so the box covers
// what a box each would. The window focused last shows at full opacity
// with a short line in the active color under it (toward the windows on a
// vertical bar), the rest dimmed. Each icon lights its own room in the
// hover color under the pointer (the box itself never lights); click one
// to focus its window. As a segment of the bar's run (`run`: the widget's
// Background off) the box takes the bar's widget shape, its icons kept
// clear of its caps, cell `chainFirst` of the widget's `chainCount`.
Item {
  id: root

  required property var barConfig
  // How the widget's cells draw on this bar or popout: its size, corners,
  // spacing and colors
  required property CellLook cellLook
  required property int workspaceId
  // The strip's own direction, which orders the windows
  required property bool stripVertical
  // Along the bar's direction, which lays the icons out
  required property bool isVertical
  required property color activeColor
  required property color occupiedColor
  required property color textColor
  property bool clickable: true
  // The widget's (BarWidget.hitArea), which the box reads hover from
  property var hitArea: null
  property bool animated: true
  // Where its box sits among the widget's chained cells, and how many
  // those are
  property int chainFirst: 0
  property int chainCount: 1
  // Across, and each icon's room along it and between them (the widget's
  // `spacing`)
  readonly property real thickness: cellLook.thickness
  readonly property real _iconRoom: cellLook.thickness
  readonly property real _iconSpacing: cellLook.spacing
  // The room it keeps clear of its caps as a segment of the bar's run, its
  // content app icons (CellLook.roomOf), else null
  readonly property var _room: cellLook.roomOf(chainFirst, chainCount, cellLook.iconContent)
  readonly property real _lead: _room?.lead ?? 0
  // Its box's shape as a segment (CellLook.shapeOf), else null, and
  // what it draws past its bounds (BarCells.cellMargins)
  readonly property var _shape: cellLook.shapeOf(chainFirst, chainCount, cellLook.opaque, cellLook.iconContent)
  readonly property var _margins: BarCells.cellMargins(_shape, _shape, isVertical)
  // How far icon `index`'s pointer area reaches past its room, sharing
  // the box: the first back to the box's start, the last on to its end,
  // the rest to the middle of the gaps beside them; across, as the box
  // does. None but the box's own off the bar's run.
  function _slotMargins(index) {
    if (!root._shape)
      return BarCells.cellMargins(null, null, root.isVertical);
    const half = root._iconSpacing / 2;
    const start = index === 0 ? root._lead + (root.isVertical ? root._margins.top : root._margins.left) : half;
    const end = index === root.addresses.length - 1 ? (root._room?.trail ?? 0) + (root.isVertical ? root._margins.bottom : root._margins.right) : half;
    return {
      "left": root.isVertical ? root._margins.left : start,
      "top": root.isVertical ? start : root._margins.top,
      "right": root.isVertical ? root._margins.right : end,
      "bottom": root.isVertical ? end : root._margins.bottom
    };
  }

  readonly property var windows: CompositorManager.stripWindows(root.workspaceId, root.stripVertical)
  // A string, so the icons are only rebuilt when the windows or their
  // order change, not on every compositor event
  readonly property string _key: root.windows.map(w => w.id).join(",")
  readonly property var addresses: root._key === "" ? [] : root._key.split(",")
  readonly property string focused: CompositorManager.lastFocused(root.windows)?.id ?? ""
  readonly property real _along: root.addresses.length > 0 ? root.addresses.length * root._iconRoom + (root.addresses.length - 1) * root._iconSpacing + root._lead + (root._room?.trail ?? 0) : 0

  // Nothing (not even a gap beside it) on an empty workspace
  visible: root.addresses.length > 0
  implicitWidth: root.isVertical ? root.thickness : root._along
  implicitHeight: root.isVertical ? root._along : root.thickness

  // The box: a workspace cell's, without content, unlit (its icons light
  // their own rooms)
  WorkspaceCell {
    id: boxCell
    part: "background"
    lit: false
    barConfig: root.barConfig
    cellLook: root.cellLook
    isActive: false
    look: root.cellLook.colorsOf(root.occupiedColor, root.textColor, "occupied", {})
    thickness: root.thickness
    length: root._along
    shape: root._shape
    hitArea: root.hitArea
    animated: root.animated
  }

  // Clear of its caps
  Grid {
    x: root.isVertical ? 0 : root._lead
    y: root.isVertical ? root._lead : 0
    flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
    rows: root.isVertical ? Math.max(1, root.addresses.length) : 1
    columns: root.isVertical ? 1 : Math.max(1, root.addresses.length)
    spacing: root._iconSpacing

    Repeater {
      model: root.addresses.length

      Item {
        id: slot
        required property int index
        readonly property string address: root.addresses[index] ?? ""
        readonly property var window: root.windows.find(w => w.id === address) ?? null
        readonly property bool isFocused: address === root.focused
        // On the bar, from the widget's hit area (which lies over the
        // icons), asked whether the pointer is in its pointer area;
        // elsewhere, that area itself
        readonly property bool hovered: root.hitArea ? root.hitArea.hovers(slotArea) : slotArea.containsMouse

        width: root.isVertical ? root.thickness : root._iconRoom
        height: root.isVertical ? root._iconRoom : root.thickness

        // Its room lit under the pointer, inset inside the box
        Rectangle {
          readonly property real inset: Math.max(1, Math.round(root.thickness * 0.08))

          anchors.fill: parent
          anchors.margins: inset
          radius: Math.max(0, root.cellLook.radius - inset)
          color: root.cellLook.hoverColor
          opacity: slot.hovered ? 1 : 0

          Behavior on opacity {
            enabled: root.animated
            NumberAnimation {
              duration: Appearance.animFast
              easing.type: Appearance.easing
            }
          }
        }

        Image {
          id: icon
          anchors.centerIn: parent
          width: WorkspaceCells.iconSize(root.thickness)
          height: width
          sourceSize: Qt.size(64, 64)
          source: slot.window ? AppIconManager.resolveWindowIcon(slot.window.appId, slot.window.title) : ""
          opacity: slot.isFocused ? 1 : 0.5

          Behavior on opacity {
            enabled: root.animated
            NumberAnimation {
              duration: Appearance.animFast
              easing.type: Appearance.easing
            }
          }
        }

        // The focused window's mark, in the room between its icon and the
        // box's edge: under it, or on a vertical bar toward the windows
        Rectangle {
          readonly property real size: Math.max(2, Math.round(root.thickness * 0.08))
          readonly property real span: Math.round(icon.width * 0.5)
          readonly property real room: (root.thickness - icon.width) / 2

          visible: slot.isFocused
          radius: size / 2
          color: root.activeColor
          width: root.isVertical ? size : span
          height: root.isVertical ? span : size
          x: root.isVertical ? (root.barConfig.right ? (room - size) / 2 : root.thickness - room + (room - size) / 2) : (parent.width - width) / 2
          y: root.isVertical ? (parent.height - height) / 2 : root.thickness - room + (room - size) / 2
        }

        // Its share of the box as drawn (back under the cell before, out
        // to a tab's edge)
        CellHitArea {
          id: slotArea
          shape: root._shape
          vertical: root.isVertical
          box: boxCell
          margins: root._slotMargins(slot.index)
          enabled: root.clickable
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: CompositorManager.focusWindow(slot.address)
        }
      }
    }
  }
}
