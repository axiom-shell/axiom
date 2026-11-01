pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.config
import qs.components.reusable

// An OSD's status icons: one tile per status shown (OSDItems.rowTypes), in
// a line along its edge. A tile is its icon (or short label: a layout's
// code) in a rounded square: on the accent while on, faint while off (a
// mute also struck through: SlashedIcon). The one that just changed is
// ringed and pops in. A message never shows here: it's a card.
// Hovered, a tile lightens and names itself and its state; one in
// `toggleable` is clicked to flip it (`toggled`).
Item {
  id: root

  // Every type it may show, in order (its tiles, built once), the ones
  // shown now (OSDItems.rowTypes), and every status's tile by type
  // (OSDItems.tile)
  property var allTypes: []
  property var types: []
  property var tiles: ({})
  // The type that just changed, or ""
  property string changed: ""
  // Runs top to bottom (along a left or right edge)
  property bool vertical: false
  // The types a click flips
  property var toggleable: []

  signal toggled(string type)

  readonly property int tileSize: Widget.px(40)
  // Its largest size across the edge, whatever it shows (OSDContent.maxDepth)
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

    // Over the types from config, not the ones shown: those follow the
    // live state
    Repeater {
      model: root._allKey === "" ? [] : root._allKey.split(",")

      delegate: Rectangle {
        id: tile
        required property string modelData
        visible: root.types.includes(tile.modelData)
        readonly property var t: root.tiles[tile.modelData] ?? ({})
        readonly property bool current: tile.modelData === root.changed
        readonly property bool canToggle: root.toggleable.includes(tile.modelData)
        // I18n.tr("{0}: on") I18n.tr("{0}: off") I18n.tr("{0}: {1}") I18n.tr("{0}: {1}, muted")
        readonly property string tip: {
          const name = OSDConfig.nameOf(tile.modelData);
          const value = tile.t.name || tile.t.label;
          if (tile.t.name && tile.t.slash)
            return I18n.tr("{0}: {1}, muted", name, value);
          if (value)
            return I18n.tr("{0}: {1}", name, value);
          if (tile.modelData === "powerProfile")
            return name;
          return tile.t.on ? I18n.tr("{0}: on", name) : I18n.tr("{0}: off", name);
        }

        Layout.preferredWidth: root.tileSize
        Layout.preferredHeight: root.tileSize
        Layout.alignment: Qt.AlignCenter
        radius: Widget.radius
        readonly property bool lit: tile.t.on === true
        readonly property color fill: tile.lit ? Theme.accent : Qt.alpha(Theme.backgroundHighlight, 0)
        color: !area.containsMouse ? tile.fill : tile.lit ? Qt.lighter(tile.fill, 1.15) : Theme.backgroundAlt
        ColorGlide on color {}
        border.width: tile.current ? Widget.px(2) : 0
        // The foreground, not borderFocus: that is the accent in most themes
        border.color: Theme.foreground

        // Pops in as it becomes the change
        onCurrentChanged: {
          if (tile.current && Appearance.animations)
            pop.restart();
        }
        NumberAnimation {
          id: pop
          target: tile
          property: "scale"
          from: 0.8
          to: 1
          duration: Appearance.animNormal
          easing.type: Easing.OutBack
        }

        readonly property color ink: tile.lit ? Theme.background : Theme.foreground
        readonly property real inkOpacity: tile.current || tile.lit ? 1 : 0.45

        SlashedIcon {
          anchors.centerIn: parent
          visible: !tile.t.label
          text: tile.t.icon ?? ""
          textSize: Appearance.fontSizeBy(6)
          textColor: tile.ink
          slashed: tile.t.slash === true
          cutout: tile.color
          opacity: tile.inkOpacity
        }

        StyledText {
          anchors.centerIn: parent
          visible: !!tile.t.label
          text: tile.t.label ?? ""
          font.bold: true
          textColor: tile.ink
          opacity: tile.inkOpacity
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: tile.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            if (tile.canToggle)
              root.toggled(tile.modelData);
          }
        }

        LazyLoader {
          active: area.containsMouse
          StyledToolTip {
            target: tile
            text: tile.tip
          }
        }
      }
    }
  }
}
