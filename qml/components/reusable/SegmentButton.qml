pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// One button of a segmented choice (Dark/Light, a wallpaper mode): the
// chosen one is filled with the accent; one that can't be chosen is
// dimmed. In a SegmentRow, the row draws the track and the accent (which
// slides between its buttons) and the button only its label; elsewhere
// (a RowLayout or Flow of toggles) it fills itself.
StyledTextButton {
  id: root

  property bool active: false
  property bool available: true

  readonly property bool inRow: root.parent?.objectName === "segmentTrack"

  Layout.fillWidth: true
  Layout.preferredHeight: Widget.height
  enabled: available
  opacity: available ? 1 : 0.4
  backgroundColor: inRow ? Qt.alpha(Theme.backgroundAlt, 0) : active ? Theme.accent : Theme.backgroundHighlight
  textColor: active ? Theme.background : Theme.foreground
  hoverColor: inRow ? Qt.alpha(Theme.backgroundAlt, active ? 0 : 0.6) : active ? Theme.accent : Theme.backgroundAlt
  textHoverColor: active ? Theme.background : Theme.foreground

  Glide on opacity {}
}
