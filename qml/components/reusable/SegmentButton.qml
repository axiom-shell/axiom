pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// One button of a segmented choice (Dark/Light, a wallpaper mode): the
// chosen one reads as the thumb's label; one that can't be chosen is faint.
// In a SegmentRow, the row draws the track and the thumb (which slides
// between its buttons) and the button only its label; elsewhere (a
// RowLayout or Flow of toggles) it fills itself, accent while active.
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

  Layout.fillWidth: true
  Layout.preferredHeight: Widget.height
  implicitWidth: Math.ceil(widest.advanceWidth) + root.textPadding * 2
  enabled: available
  kind: root.inRow ? "text" : root.active ? "primary" : "tonal"
  labelRole: root.inRow && !root.active ? "body" : "label"
  backgroundColor: root.inRow ? "transparent" : root._fill
  textColor: root.inRow ? root._rowInk : Style.toneOn(root.inkScope, "text")

  readonly property color _rowInk: {
    if (!root.available)
      return Style.inkOf(Style.segmentTrackTone).faint;
    return root.active ? Style.inkOf(Style.segmentThumbTone).text : Style.inkOf(Style.segmentTrackTone).muted;
  }
}
