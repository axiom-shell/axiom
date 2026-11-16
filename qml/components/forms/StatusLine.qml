pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A status line of an intro or a card: its words (wrapping), in `tone`
// (muted, error, …: StyledText's), optionally a StatusChip first (`chip`,
// in `chipTone`) and actions after (buttons, in `actions`). The caller
// translates `text` and `chip`.
RowLayout {
  id: root

  property string text
  // StyledText's tone ("": the role's)
  property string tone: ""
  // A StatusChip's word, shown before the text while set
  property string chip
  // success | warning | error | info | accent | neutral
  property string chipTone: "neutral"
  // Buttons after the text
  default property alias actions: actionRow.data

  spacing: Widget.spacing

  StatusChip {
    visible: root.chip !== ""
    text: root.chip
    tone: root.chipTone
    Layout.alignment: Qt.AlignVCenter
  }

  StyledText {
    visible: root.text !== ""
    text: root.text
    tone: root.tone
    overflow: "wrap"
    Layout.fillWidth: true
  }

  RowLayout {
    id: actionRow
    spacing: Widget.spacing
  }
}
