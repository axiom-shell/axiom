pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A faint icon over a line of text, for a module with nothing to show
// ("All caught up", "No paired devices"), with an optional `hint` line and
// an `actionText` button (`triggered`). Centre it in the free space.
ColumnLayout {
  id: root

  property string icon: ""
  property string text: ""
  // One more faint line under the text
  property string hint: ""
  // A text button under it ("" none)
  property string actionText: ""
  // Widest the text may be before it wraps
  property real maxWidth: Widget.textPx(220)
  // The height it has (negative: no limit). Short of room for the text,
  // only the icon shows, sized to fit
  property real availableHeight: -1
  readonly property bool _limited: root.availableHeight >= 0
  readonly property bool _textFits: !root._limited || root.availableHeight >= (root.icon !== "" ? iconMetrics.height + root.spacing : 0) + textLine.implicitHeight + (root.hint !== "" ? root.spacing + hintLine.implicitHeight : 0) + (root.actionText !== "" ? root.spacing + actionButton.implicitHeight : 0)

  signal triggered

  spacing: Widget.spacing / 2

  // The icon's row height at full size (its own height would loop through _textFits)
  FontMetrics {
    id: iconMetrics
    font.family: iconLine.textFamily
    font.pixelSize: Style.iconXl
  }
  StyledIcon {
    id: iconLine
    visible: root.icon !== ""
    Layout.alignment: Qt.AlignHCenter
    text: root.icon
    tone: "faint"
    textSize: root._limited && !root._textFits ? Math.max(Widget.px(8), Math.min(Style.iconXl, root.availableHeight * 0.7)) : Style.iconXl // fitted: the room it's given
  }
  StyledText {
    id: textLine
    visible: root.text !== "" && root._textFits
    Layout.alignment: Qt.AlignHCenter
    Layout.maximumWidth: root.maxWidth
    horizontalAlignment: Text.AlignHCenter
    role: "caption"
    overflow: "wrap"
    text: root.text
  }
  StyledText {
    id: hintLine
    visible: root.hint !== "" && root._textFits
    Layout.alignment: Qt.AlignHCenter
    Layout.maximumWidth: root.maxWidth
    horizontalAlignment: Text.AlignHCenter
    role: "caption"
    tone: "faint"
    text: root.hint
  }
  StyledTextButton {
    id: actionButton
    visible: root.actionText !== "" && root._textFits
    Layout.alignment: Qt.AlignHCenter
    kind: "text"
    text: root.actionText
    onClicked: root.triggered()
  }
}
