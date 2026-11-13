pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config

// The mark at the start of an option row: an accent icon glyph and/or an
// image (an app's icon, by path or URL); takes no room when both are empty
RowLayout {
  id: root

  property string icon: ""
  property string image: ""

  spacing: Widget.spacing
  visible: root.icon !== "" || root.image !== ""

  StyledIcon {
    visible: root.icon !== ""
    text: root.icon
    textColor: Theme.accent
  }

  IconImage {
    visible: root.image !== ""
    source: root.image
    implicitSize: Appearance.fontSizeLarge
    asynchronous: true
  }
}
