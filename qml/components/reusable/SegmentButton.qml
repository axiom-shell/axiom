pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// One button of a segmented choice (Dark/Light, a wallpaper mode): the
// chosen one reads as the thumb's label; one that can't be chosen is faint.
// Only inside a SegmentRow (a single choice) or SegmentTabs (one entry of
// many): a multi-select is ToggleChips. In a SegmentRow, the row draws the
// track and the thumb (which slides between its buttons) and the button only
// its label; in SegmentTabs (its own wrapping row, no track) it fills itself,
// accent while active.
StyledTextButton {
  id: root

  property bool active: false
  property bool available: true

  readonly property bool inRow: root.parent?.objectName === "segmentTrack"

  // The label's widest case, so a segment never resizes as the choice moves
  // (the active label is Medium, the others Regular)
  TextMetrics {
    id: widest
    font.family: Appearance.fontFamily
    font.pixelSize: Style.typeLabel
    font.weight: Style.weightMedium
    text: root.text
  }

  // The icon's own width (one em for a symbol name)
  TextMetrics {
    id: iconMetrics
    font.family: Appearance.iconFamily
    font.pixelSize: root.textSize
    text: root.iconText
  }

  Layout.fillWidth: true
  Layout.preferredHeight: root.inRow ? -1 : Widget.height
  Layout.fillHeight: root.inRow
  // plus the icon and StyledTextButton's content spacing (`Widget.spacing / 2`) beside the label
  implicitWidth: Math.ceil(widest.advanceWidth) + root.textPadding * 2 + (root.iconText !== "" ? Math.ceil(iconMetrics.advanceWidth) + (root.text !== "" ? Widget.spacing / 2 : 0) : 0)
  enabled: available
  // A segment in a row shares the row's one Tab stop
  tabStop: !root.inRow
  // on the accent thumb: the on-fill hover tints
  ownFill: root.inRow && root.active
  kind: root.inRow ? "text" : root.active ? "primary" : "tonal"
  labelRole: root.inRow && !root.active ? "body" : "label"
  // The else-branch matches StyledTextButton's default for primary/tonal; spelled out because a binding can't fall back to the base default.
  _contentColor: root.inRow ? root._rowInk : Style.toneOn(root.inkScope, "text")

  readonly property color _rowInk: {
    return root.active ? Style.inkAccent.text : Style.inkOf(Style.segmentTrackTone).muted;
  }
}
