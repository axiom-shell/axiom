pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.methods

// A ToolButton showing a Material Symbols icon, drawn from its `kind`, with a
// state layer for hover and press, a focus ring on keyboard focus and an
// optional tooltip.
ToolButton {
  id: root

  // -- Public API --
  property string iconText: ""
  property string tooltipText: ""
  // The tooltip's preferred edges (OverlayPageNavigator's arrows)
  property int tooltipEdges: Edges.Bottom
  // A square of this side that doesn't stretch in layouts
  property int size: Widget.iconButton
  // text (no fill at rest) | tonal | primary | danger (quiet: the error
  // container shows on hover) | dangerPrimary
  property string kind: "text"

  // -- Configurable Appearance --
  property int iconSize: Style.iconSm
  // A content colour: set for a state or data, else the kind's
  property color iconColor: root._ink
  property real borderRadius: Style.radius

  // -- Implementation --
  // A relay for its icon: the walk of the text inside stops here
  readonly property var inkHostAbove: InkHost.find(root.parent)
  readonly property real drawnZoom: TextRender.zoomAt(root.parent)
  readonly property var _scope: root.inkHostAbove ? root.inkHostAbove.inkScope : null
  readonly property bool _dangerOn: root.kind === "danger" && (root.hovered || root.pressed)
  readonly property bool _onFill: root.kind === "primary" || root.kind === "dangerPrimary"
  readonly property color _fill: {
    switch (root.kind) {
    case "tonal":
      return Style.fillHighest;
    case "primary":
      return Style.accent;
    case "dangerPrimary":
      return Style.error;
    default:
      return Tone.cleared(Style.accent); // style-exempt: no fill as the accent at no alpha, so a kind change (RowAction lit) doesn't fade through black
    }
  }
  readonly property color _ink: {
    switch (root.kind) {
    case "tonal":
      return Style.inkHighest.icon;
    case "primary":
      return Style.inkAccent.icon;
    case "dangerPrimary":
      return Style.inkError.icon;
    case "danger":
      return root._dangerOn ? Style.inkErrorContainer.icon : Style.toneOn(root._scope, "muted");
    default:
      return Style.toneOn(root._scope, "text");
    }
  }

  implicitWidth: size
  implicitHeight: size
  Layout.preferredWidth: size
  Layout.preferredHeight: size
  Layout.fillWidth: false
  Layout.fillHeight: false
  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

  padding: 0
  focusPolicy: Qt.TabFocus
  opacity: enabled ? 1.0 : Style.opacityDisabled

  HoverHandler {
    cursorShape: Qt.PointingHandCursor
  }

  LazyLoader {
    active: root.hovered && root.tooltipText !== ""
    StyledToolTip {
      target: root
      text: root.tooltipText
      edges: root.tooltipEdges
    }
  }

  contentItem: StyledIcon {
    text: root.iconText
    textSize: root.iconSize
    textColor: root.iconColor
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    ColorGlide on textColor {}
  }

  background: Rectangle {
    color: root._fill
    radius: root.borderRadius

    ColorGlide on color {}

    // the quiet danger button's hover fill
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: Style.errorContainer
      opacity: root._dangerOn ? 1 : 0

      Glide on opacity {}
    }

    StateLayer {
      hovered: root.hovered
      pressed: root.pressed
      onAccent: root._onFill
    }

    FocusRing {
      shown: root.visualFocus
    }
  }
}
