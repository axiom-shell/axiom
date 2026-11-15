pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.methods

// A button with a text label and an optional Material Symbols icon, drawn
// from its `kind`, with a state layer for hover and press and an optional
// tooltip. The label is one line and never elided unless `overflow: "line"`.
Surface {
  id: root

  // -- Signals --
  signal clicked

  // -- Public API --
  property alias text: label.text
  // tonal | primary | text | outlined | danger | dangerPrimary
  property string kind: "tonal"
  // A Material Symbols name drawn beside the label (or alone, with no text)
  property string iconText: ""
  // Draw the icon after the label instead of before it
  property bool iconAfter: false
  // A fill of the owner's own colour (set `color` too): hover and press use
  // the tints made for solid fills, as primary does
  property bool ownFill: false
  // The label's and the icon's size
  property real textSize: Style.typeLabel
  property string tooltipText: ""
  // Forwarded to the label: "line" elides it at the button's width
  property alias overflow: label.overflow
  // The label's text role (SegmentButton's inactive segments read `body`)
  property alias labelRole: label.role

  // -- Configurable Appearance --
  property int textPadding: Math.round(Widget.smallPadding * 4 / 3)
  property real borderRadius: Style.radius

  // -- Implementation --
  readonly property bool _filled: root.kind !== "text" && root.kind !== "outlined"
  readonly property var _host: InkHost.find(root.parent)
  readonly property color _fill: {
    switch (root.kind) {
    case "primary":
      return Style.accent;
    case "danger":
      return Style.errorContainer;
    case "dangerPrimary":
      return Style.error;
    default:
      return Style.fillHighest;
    }
  }
  // The label's and the icon's colour; SegmentButton sets it for a segment in a row
  property color _contentColor: Style.toneOn(root.inkScope, root.kind === "text" ? "accent" : "text")

  // No fill of its own: text and outlined buttons read the Surface they sit on
  tone: {
    switch (root.kind) {
    case "primary":
      return "accent";
    case "danger":
      return "errorContainer";
    case "dangerPrimary":
      return "error";
    case "tonal":
      return "highest";
    default:
      return root._host && root._host.tone ? root._host.tone : "surface";
    }
  }
  color: root._filled ? root._fill : "transparent"
  radius: root.borderRadius
  border.width: root.kind === "outlined" ? Style.hairline : 0
  border.color: Style.borderStrong
  implicitWidth: content.implicitWidth + (textPadding * 2)
  implicitHeight: Math.max(content.implicitHeight + (textPadding * 2), Widget.height)
  Layout.alignment: Qt.AlignVCenter
  // A capped button may go under its label, which then elides
  Layout.minimumWidth: root.overflow === "line" ? 0 : root.implicitWidth

  StateLayer {
    hovered: mouseArea.containsMouse
    pressed: mouseArea.pressed
    onAccent: root.ownFill || root.kind === "primary" || root.kind === "dangerPrimary"
    radius: root.radius
  }

  RowLayout {
    id: content
    anchors.centerIn: parent
    width: Math.min(implicitWidth, Math.max(0, root.width - root.textPadding * 2))
    spacing: Widget.spacing / 2
    layoutDirection: root.iconAfter ? Qt.RightToLeft : Qt.LeftToRight

    Loader {
      active: root.iconText !== ""
      visible: active
      sourceComponent: StyledIcon {
        text: root.iconText
        textColor: root._contentColor
        textSize: root.textSize
      }
    }

    StyledLabel {
      id: label
      role: "label"
      visible: text !== ""
      textColor: root._contentColor
      textSize: root.textSize
      Layout.fillWidth: root.overflow === "line"
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  LazyLoader {
    active: mouseArea.containsMouse && root.tooltipText !== ""
    StyledToolTip {
      target: root
      text: root.tooltipText
    }
  }
}
