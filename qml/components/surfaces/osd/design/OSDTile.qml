pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.reusable

// One status icon of an OSD's row (OSDTileRow): a system's tile
// (OSDEngine.tileOf's) as its icon, or its short label (a layout's code),
// in a rounded square: on the accent while `on` (the fill fading in), its
// icon in the faint text colour while off (a mute also struck through:
// SlashedIcon). The one that just changed is ringed (the ring fading in
// and out) and pops in. Hovered, it takes a state layer over it and names
// itself and its state; with `canToggle` a click runs its action
// (`toggled`). With `highlight` (its system selected in the settings'
// preview) it's outlined in the accent, apart from the ring.
Item {
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
  readonly property bool lit: tile.t.on === true
  // Drawn scaled while it pops in: its glyph and label draw distance field
  // meanwhile, native at rest (TextRender)
  readonly property real contentZoom: tile.scale

  // The on fill, fading in and out with the state
  Surface {
    anchors.fill: parent
    tone: "accent"
    radius: Style.radius
    opacity: tile.lit ? 1 : 0
    Glide on opacity {}
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

  // What its glyph and label draw in: on the accent's on-colour while lit,
  // else the text colour for the one that just changed, the faint one
  readonly property color _ink: tile.lit ? Style.onAccent : tile.current ? Style.text : Style.textFaint

  SlashedIcon {
    anchors.centerIn: parent
    visible: !tile.t.label
    text: tile.t.icon ?? ""
    textSize: Style.iconMd
    textColor: tile._ink
    slashed: tile.t.slash === true
    // What the slash parts the glyph in: the lit fill (the state layer
    // over it needs no colour of its own); none on an unlit one, which has
    // no fill
    cutout: tile.lit ? Style.accent : "transparent"
  }

  StyledLabel {
    anchors.centerIn: parent
    visible: !!tile.t.label
    width: Math.min(implicitWidth, tile.width - Widget.px(4))
    text: tile.t.label ?? ""
    role: "label"
    font.weight: Style.weightStrong
    textSize: Math.max(Style.typeMicro, Math.min(Style.typeLabel, Math.round(tile.size * 0.45))) // fitted: the tile
    horizontalAlignment: Text.AlignHCenter
    textColor: tile._ink
  }

  // The hover and press layer, over the glyph and label (its on-colour
  // tint over the on-colour glyph changes nothing, over the fill and the
  // slash's cutout it composites alike)
  StateLayer {
    radius: Style.radius
    hovered: area.containsMouse
    pressed: area.pressed && tile.canToggle
    onAccent: tile.lit
  }

  // The ring round the one that just changed: the text colour, then a gap
  // in the page colour inside it, so it reads on the accent fill too.
  // Fades in and out
  Rectangle {
    anchors.fill: parent
    radius: Style.radius
    color: "transparent"
    border.width: Widget.px(2)
    border.color: Style.text
    opacity: tile.current ? 1 : 0
    Glide on opacity {
      duration: Appearance.animNormal
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Widget.px(2)
      radius: Math.max(0, Style.radius - Widget.px(2))
      color: "transparent"
      border.width: Widget.px(2)
      border.color: Style.surfacePage
    }
  }

  // The preview's outline: the accent, a line of the page colour inside it
  // so it reads on a lit (accent) tile too
  Rectangle {
    anchors.fill: parent
    visible: tile.highlight
    radius: Style.radius
    color: "transparent"
    border.width: Widget.px(2)
    border.color: Style.accent

    Rectangle {
      anchors.fill: parent
      anchors.margins: Widget.px(2)
      radius: Math.max(0, Style.radius - Widget.px(2))
      color: "transparent"
      border.width: 1
      border.color: Style.surfacePage
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
