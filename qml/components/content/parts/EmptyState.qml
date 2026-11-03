pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A muted icon over a line of text, for a module with nothing to show
// ("All caught up", "No paired devices"). Centre it in the free space.
ColumnLayout {
  id: root

  property string icon: ""
  property string text: ""
  // Widest the text may be before it wraps
  property real maxWidth: Widget.px(220)
  // The height it has (negative: no limit). Short of room for the text,
  // only the icon shows, sized to fit
  property real availableHeight: -1
  readonly property bool _limited: root.availableHeight >= 0
  readonly property bool _textFits: !root._limited || root.availableHeight >= Appearance.fontSize * 2.4 + Widget.spacing / 2 + textLine.implicitHeight

  spacing: Widget.spacing / 2
  opacity: 0.55

  StyledIcon {
    visible: root.icon !== ""
    Layout.alignment: Qt.AlignHCenter
    text: root.icon
    textSize: root._limited && !root._textFits ? Math.max(Widget.px(8), Math.min(Appearance.fontSize * 2, root.availableHeight * 0.7)) : Appearance.fontSize * 2
  }
  StyledText {
    id: textLine
    visible: root.text !== "" && root._textFits
    Layout.alignment: Qt.AlignHCenter
    Layout.maximumWidth: root.maxWidth
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: root.text
    textSize: Appearance.fontSizeBy(-1)
  }
}
