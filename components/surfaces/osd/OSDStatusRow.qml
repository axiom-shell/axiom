pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.config
import qs.components.reusable

// An OSD's status icons: one tile per status shown (OSDItems.rowTypes), in
// a line along its edge. A tile is its icon (or short label: a layout's
// code) in a rounded square, filled while on, faint and struck through
// (SlashedIcon) while off; the one that just changed is the accent and
// pops in, its caption (a message's text) beside the line.
// Hovered, a tile lightens and names itself and its state; one in
// `toggleable` is clicked to flip it (`toggled`).
Item {
  id: root

  // The types shown, in order, and every status's tile by type
  // (OSDItems.tile)
  property var types: []
  property var tiles: ({})
  // The type that just changed, or ""
  property string changed: ""
  // Runs top to bottom (along a left or right edge)
  property bool vertical: false
  // It may show a caption (the OSD shows messages)
  property bool hasCaption: false
  // The types a click flips
  property var toggleable: []

  signal toggled(string type)

  readonly property int tileSize: Widget.px(40)
  readonly property int captionWidth: Widget.px(280)
  // Its largest size across the edge, whatever it shows (OSDContent.maxDepth):
  // a tile, and along a left or right edge a caption at its widest
  readonly property real maxDepth: root.vertical && root.hasCaption ? Math.max(root.tileSize, root.captionWidth) : root.tileSize
  readonly property string caption: root.changed !== "" ? (root.tiles[root.changed]?.caption ?? "") : ""

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

    Repeater {
      model: root.types

      delegate: Rectangle {
        id: tile
        required property string modelData
        readonly property var t: root.tiles[tile.modelData] ?? ({})
        readonly property bool current: tile.modelData === root.changed
        readonly property bool canToggle: root.toggleable.includes(tile.modelData)
        // I18n.tr("{0}: on") I18n.tr("{0}: off") I18n.tr("{0}: {1}") I18n.tr("{0}: {1}, muted")
        readonly property string tip: {
          const name = OSDConfig.nameOf(tile.modelData);
          const value = tile.t.caption || tile.t.name || tile.t.label;
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
        readonly property color fill: tile.current ? Theme.accent : tile.t.on ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)
        color: !area.containsMouse ? tile.fill : tile.current ? Qt.lighter(Theme.accent, 1.15) : Theme.backgroundAlt
        ColorGlide on color {}

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

        readonly property color ink: tile.current ? Theme.background : Theme.foreground
        readonly property real inkOpacity: tile.current || tile.t.on ? 1 : 0.45

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

    StyledText {
      visible: root.caption !== ""
      Layout.alignment: Qt.AlignCenter
      Layout.maximumWidth: root.captionWidth
      Layout.leftMargin: root.vertical ? 0 : Widget.spacing
      text: root.caption
      textSize: Appearance.fontSizeLarge
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }
}
