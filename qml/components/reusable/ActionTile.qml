pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config

// An action or toggle tile: an icon well over a label. Hovered (or
// `selected`, for keyboard focus) its well takes the `activeTone` container;
// `active` (a toggle that's on, an action waiting to be confirmed) fills it
// with the `activeTone`, and with a `countdown` a bar along the bottom runs down
// over that many ms. The label shows only where it fits whole (or always,
// with `forceLabel`); otherwise the tile is icon-only with the label as a
// tooltip. With `opens`, a right click or a long press is `opened` (a
// detail to show).
Rectangle {
  id: root

  property string icon: ""
  property string label: ""
  property bool active: false
  // accent | error: the colour an active tile is filled with, and the
  // container its well takes while hovered or selected
  property string activeTone: "accent"
  // Highlighted as if hovered (keyboard selection)
  property bool selected: false
  // Allow the label at all (off: always icon-only)
  property bool showLabel: true
  // Show the label even where it doesn't fit whole (elided)
  property bool forceLabel: false
  // While active, run a bar down over this many ms (0: none)
  property int countdown: 0
  // There's a detail to open: a right click or a long press opens it
  property bool opens: false

  signal clicked
  signal hovered
  signal opened

  // The label fits whole (QuickActions mirrors this for its "auto" names)
  readonly property bool labelFits: labelMetrics.advanceWidth <= root.width - Widget.spacing * 2 && root.height >= Appearance.fontSize * 4.5
  // The fill while active, and the hover / selected outline
  readonly property color _activeColor: root.activeTone === "error" ? Style.error : Style.accent
  readonly property bool hot: root.selected || area.containsMouse
  readonly property string _containerTone: root.activeTone + "Container"
  readonly property color _containerFill: root.activeTone === "error" ? Style.errorContainer : Style.accentContainer
  // Glyph on the well: highest at rest, the container's ink hovered, the
  // fill's ink while active
  readonly property color contentColor: root.active ? Style.inkOf(root.activeTone).icon : root.hot ? Style.inkOf(root._containerTone).icon : Style.inkHighest.icon
  readonly property color labelColor: root.active ? Style.inkOf(root.activeTone).text : root.hot ? Style.inkOf(root._containerTone).text : Style.inkSurface.text
  readonly property color mutedColor: root.active ? Style.inkOf(root.activeTone).muted : root.hot ? Style.inkOf(root._containerTone).muted : Style.inkSurface.muted
  readonly property bool _labelShown: root.showLabel && root.label !== "" && (root.forceLabel || root.labelFits)
  // The well fills most of what the label leaves, never less than an icon
  // (unless the tile itself is smaller)
  readonly property real _wellSize: Math.max(Math.min(Appearance.fontSize * 1.6, Math.min(root.width, root.height) - Widget.px(4)), Math.min(root.width - Widget.spacing * 2, root.height - Widget.spacing * 2 - (root._labelShown ? labelText.implicitHeight + Widget.spacing : 0)) * (root._labelShown ? 0.7 : 0.66))

  radius: Style.radius
  color: root.active ? root._activeColor : Style.fill
  border.color: root.active || root.hot ? root._activeColor : Style.borderSubtle
  border.width: Style.hairline
  clip: true

  ColorGlide on color {}
  ColorGlide on border.color {}

  TextMetrics {
    id: labelMetrics
    text: root.label
    font.family: Appearance.fontFamily
    font.pixelSize: Style.typeLabel
    font.weight: Style.weightMedium
  }

  StateLayer {
    hovered: root.hot
    pressed: area.pressed
    onAccent: root.active
  }

  Column {
    anchors.centerIn: parent
    spacing: Widget.spacing

    // Holds the well's resting size, so the well grows on hover without
    // moving the label. It grows by size, not scale: icons render natively
    // (see StyledIcon), and a scaled native glyph is resampled and blurs
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: root._wellSize
      height: width

      Rectangle {
        id: well
        anchors.centerIn: parent
        width: root._wellSize * (root.hot && !root.active ? 1.06 : 1)
        height: width
        radius: Math.min(Widget.radius * 1.5, width / 2)
        color: root.active ? Style.stateOnAccentHover : root.hot ? root._containerFill : Style.surfaceHighest

        ColorGlide on color {}
        Glide on width {}

        StyledIcon {
          anchors.centerIn: parent
          text: root.icon
          textColor: root.contentColor
          textSize: Math.max(Style.iconXs, well.width * 0.5) // fitted: the glyph is half its well
          fill: root.hot || root.active ? 1 : 0
        }
      }
    }

    StyledText {
      id: labelText
      visible: root._labelShown
      anchors.horizontalCenter: parent.horizontalCenter
      width: root.width - Widget.spacing * 2
      horizontalAlignment: Text.AlignHCenter
      role: "label"
      overflow: "wrap"
      maxLines: 2
      text: root.label
      textColor: root.labelColor
    }
  }

  // Time left while active
  CountdownBar {
    running: root.active
    fillColor: Style.inkOf(root.activeTone).graphic
    duration: root.countdown
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: root.opens ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
    // A long press opened it, so its release isn't a click too
    property bool held: false
    onEntered: root.hovered()
    onPressed: area.held = false
    onPressAndHold: {
      if (!root.opens)
        return;
      area.held = true;
      root.opened();
    }
    onClicked: mouse => {
      if (area.held)
        return;
      if (mouse.button === Qt.RightButton)
        root.opened();
      else
        root.clicked();
    }
  }

  LazyLoader {
    active: area.containsMouse && !root._labelShown && root.label !== ""
    StyledToolTip {
      target: root
      text: root.label
    }
  }
}
