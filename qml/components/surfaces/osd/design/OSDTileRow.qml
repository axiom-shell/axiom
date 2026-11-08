pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config

// An OSD's status icons: one OSDTile per tile shown (OSDParts.rowTypes),
// in a line along its edge, the one that just changed ringed. Its tiles
// are built once, over every tile the OSD may show (`allTypes`, from
// config); the ones shown follow the live state. A card-only key (a
// message) never shows here.
Item {
  id: root

  // Every tile it may show, in order (ids), the ones shown now
  // (OSDParts.rowTypes), every tile by id (OSDEngine.tileOf's) and each
  // one's English name
  property var allTypes: []
  property var types: []
  property var tiles: ({})
  property var names: ({})
  // The id that just changed, or ""
  property string changed: ""
  // Runs top to bottom (along a left or right edge)
  property bool vertical: false
  // The ids a click runs the action of
  property var toggleable: []

  signal toggled(string type)

  readonly property int tileSize: Widget.px(40)
  // Its largest size across the edge, whatever it shows (OSDHost.maxDepth)
  readonly property real maxDepth: root.tileSize

  // As a string, so an edit elsewhere in the OSD doesn't rebuild the tiles
  readonly property string _allKey: root.allTypes.join(",")

  implicitWidth: line.implicitWidth
  implicitHeight: line.implicitHeight

  GridLayout {
    id: line
    anchors.centerIn: parent
    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: root.vertical ? -1 : 1
    columns: root.vertical ? 1 : -1
    rowSpacing: Widget.spacing
    columnSpacing: Widget.spacing

    // Over the ids from config, not the ones shown: those follow the
    // live state
    Repeater {
      model: root._allKey === "" ? [] : root._allKey.split(",")

      delegate: OSDTile {
        id: tile
        required property string modelData

        visible: root.types.includes(tile.modelData)
        t: root.tiles[tile.modelData] ?? ({})
        name: root.names[tile.modelData] ?? ""
        current: tile.modelData === root.changed
        canToggle: root.toggleable.includes(tile.modelData)
        Layout.preferredWidth: root.tileSize
        Layout.preferredHeight: root.tileSize
        Layout.alignment: Qt.AlignCenter
        onToggled: root.toggled(tile.modelData)
      }
    }
  }
}
