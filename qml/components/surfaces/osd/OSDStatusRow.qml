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
// ringed (the ring fading in and out) and pops in. A message never shows
// here: it's a card.
// Hovered, a tile takes a faint layer at once and names itself and its
// state; one in
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
        // Only the state glides: hover is the layer below, at once, so
        // moving across the row leaves no tile easing back behind it
        color: tile.lit ? Theme.accent : Qt.alpha(Theme.accent, 0)
        ColorGlide on color {}

        // The hover layer: the ink faintly over the fill, so it shows on
        // any accent (lightening a pale one barely changes it)
        readonly property color hoverTint: Qt.alpha(tile.ink, 0.12)
        Rectangle {
          anchors.fill: parent
          radius: tile.radius
          visible: area.containsMouse
          color: tile.hoverTint
        }

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
          // What the slash parts the glyph in: the lit fill as it shows
          // (hovered too); none on an unlit one, which has no fill
          cutout: !tile.lit ? Qt.alpha(Theme.background, 0) : area.containsMouse ? Qt.tint(tile.color, tile.hoverTint) : tile.color
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

        // The ring round the one that just changed: the foreground, then
        // a gap in the background inside it, so it reads on the accent
        // fill too (borderFocus is the accent in most themes). Fades in
        // and out
        Rectangle {
          anchors.fill: parent
          radius: tile.radius
          color: "transparent"
          border.width: Widget.px(2)
          border.color: Theme.foreground
          opacity: tile.current ? 1 : 0
          Glide on opacity {
            duration: Appearance.animNormal
          }

          Rectangle {
            anchors.fill: parent
            anchors.margins: Widget.px(2)
            radius: Math.max(0, tile.radius - Widget.px(2))
            color: "transparent"
            border.width: Widget.px(2)
            border.color: Theme.background
          }
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
