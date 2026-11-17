pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A Flow of equal tiles: as many columns of at least `minTileWidth` as fit
// (never fewer than `minColumns`); tiles take `tileWidth`
Flow {
  id: root

  property real minTileWidth: Appearance.fontSize * 14
  property int minColumns: 1
  // A subtype may bind its own (ChoiceTiles: ChoiceGrid)
  property int columns: Math.max(root.minColumns, Math.floor(root.width / root.minTileWidth))
  readonly property real tileWidth: Math.floor((root.width - root.spacing * (root.columns - 1)) / root.columns)

  spacing: Widget.spacing
}
