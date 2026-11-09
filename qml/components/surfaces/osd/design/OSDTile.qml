pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.reusable

// One status icon of an OSD's row (OSDTileRow): a system's tile
// (OSDEngine.tileOf's) as its icon, or its short label (a layout's code),
// in a rounded square: on the accent while `on`, faint while off (a mute
// also struck through: SlashedIcon). The one that just changed is ringed
// (the ring fading in and out) and pops in. Hovered, it takes a faint
// layer at once and names itself and its state; with `canToggle` a click
// runs its action (`toggled`). With `highlight` (its system selected in
// the settings' preview) it's outlined in the accent, apart from the ring.
Rectangle {
  id: tile

  // Its tile (OSDEngine.tileOf's): { icon, label, on, slash, name,
  // nameOnly, … }
  property var t: ({})
  // Its name, English (its `exposes` entry's label), translated here
  property string name: ""
  // It just changed: ringed, popping in
  property bool current: false
  // A click runs its action
  property bool canToggle: false
  // Outlined: its system is selected in the settings' preview
  property bool highlight: false
  readonly property int size: Widget.px(40)

  signal toggled

  // `name` a device's, a VPN's or the apps' (its tile's), `label` a
  // layout's; `nameOnly` a tile whose on and off say nothing (the power
  // profile)
  // I18n.tr("{0}: on") I18n.tr("{0}: off") I18n.tr("{0}: {1}") I18n.tr("{0}: {1}, muted")
  readonly property string tip: {
    const name = tile.name !== "" ? I18n.tr(tile.name) : "";
    const value = tile.t.name || tile.t.label;
    if (tile.t.name && tile.t.slash)
      return I18n.tr("{0}: {1}, muted", name, value);
    if (value)
      return I18n.tr("{0}: {1}", name, value);
    if (tile.t.nameOnly === true)
      return name;
    return tile.t.on ? I18n.tr("{0}: on", name) : I18n.tr("{0}: off", name);
  }

  implicitWidth: tile.size
  implicitHeight: tile.size
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

  StyledLabel {
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

  // The preview's outline: the accent, a line of the background inside
  // it so it reads on a lit (accent) tile too
  Rectangle {
    anchors.fill: parent
    visible: tile.highlight
    radius: tile.radius
    color: "transparent"
    border.width: Widget.px(2)
    border.color: Theme.accent

    Rectangle {
      anchors.fill: parent
      anchors.margins: Widget.px(2)
      radius: Math.max(0, tile.radius - Widget.px(2))
      color: "transparent"
      border.width: 1
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
        tile.toggled();
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
