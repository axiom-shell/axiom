pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config

// The mark at the start of an option row: a muted icon glyph (on the current
// option, the selected row's colour) and/or an image (an app's icon, by path
// or URL); takes no room when both are empty
RowLayout {
  id: root

  property string icon: ""
  property string image: ""
  // The row is the field's current value
  property bool current: false

  spacing: Widget.spacing
  visible: root.icon !== "" || root.image !== ""

  StyledIcon {
    visible: root.icon !== ""
    text: root.icon
    size: "md"
    textColor: root.current ? Style.onAccentContainer : Style.textMuted
  }

  IconImage {
    visible: root.image !== ""
    source: root.image
    implicitSize: Style.iconMd
    asynchronous: true
  }
}
