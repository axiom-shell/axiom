pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// A badge on the overview board, drawn over its cell's windows: a workspace's
// number or name, or a scratchpad's icon and title
Rectangle {
  id: root

  property string text: ""
  // Before the text: a Material Symbols name, drawn as text with `iconPlain`
  // (anything else a user typed); "" for none
  property string icon: ""
  property bool iconPlain: false
  // The badge's color when current (its fill), and for the idle text with
  // `tintText`
  property color tint: Theme.accent
  property bool tintText: false
  // The text elides to fit this; 0 means no limit
  property real maxWidth: 0
  // The monitor's active workspace (or the scratchpad shown)
  property bool current: false
  // The cell's corner radius; the badge sits clear of its border (the
  // thicker, active one) and of the corner's curve
  property real cornerRadius: Widget.radius
  readonly property real _edge: Appearance.borderWidth * 2 + 2
  readonly property color _textColor: root.current ? Theme.background : root.tintText ? root.tint : Theme.foreground
  // Its inset from the cell's corner (placed by OverviewGrid): past the
  // border along the edges, and far enough in that the pill's end circle
  // stays inside the corner's inner arc
  readonly property real margin: {
    const r = height / 2;
    const inner = root.cornerRadius - root._edge;
    const corner = root.cornerRadius - r - (inner - r) / Math.SQRT2;
    return Math.max(root._edge, corner);
  }

  width: Math.max(height, content.implicitWidth + Widget.padding)
  height: Math.max(label.implicitHeight, iconLabel.implicitHeight) + Widget.px(4)
  radius: height / 2
  color: root.current ? root.tint : Qt.alpha(Theme.background, 0.75)

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Widget.px(3)

    StyledIcon {
      id: iconLabel
      visible: root.icon !== "" && !root.iconPlain
      anchors.verticalCenter: parent.verticalCenter
      text: root.icon
      textSize: Appearance.fontSizeBy(-2)
      textColor: root._textColor
    }

    StyledLabel {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      // Plain icon text and the text share one label
      text: root.icon !== "" && root.iconPlain ? root.icon + (root.text !== "" ? " " + root.text : "") : root.text
      textSize: Appearance.fontSizeBy(-2)
      textColor: root._textColor
      font.bold: root.current
      elide: Text.ElideRight
      width: root.maxWidth > 0 ? Math.min(implicitWidth, Math.max(0, root.maxWidth - Widget.padding - (iconLabel.visible ? iconLabel.implicitWidth + content.spacing : 0))) : implicitWidth
    }
  }
}
